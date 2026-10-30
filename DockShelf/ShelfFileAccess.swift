import Foundation

/// Injectable only for isolated regression fixtures. Live calls use Foundation's
/// read-only security scope; a path string never creates an authorization grant.
struct ShelfAccessOperations {
    var start: (URL) -> Bool
    var stop: (URL) -> Void
    var bookmark: (URL) throws -> Data
    var resolve: (Data) throws -> (url: URL, stale: Bool)

    static let live = ShelfAccessOperations(
        start: { $0.startAccessingSecurityScopedResource() },
        stop: { $0.stopAccessingSecurityScopedResource() },
        bookmark: { try $0.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                       includingResourceValuesForKeys: nil, relativeTo: nil) },
        resolve: {
            var stale = false
            let url = try URL(resolvingBookmarkData: $0,
                              options: [.withSecurityScope, .withoutUI, .withoutMounting],
                              relativeTo: nil, bookmarkDataIsStale: &stale)
            return (url, stale)
        }
    )
}

/// Shared by current items and the one undo snapshot. The final reference releases
/// the matching grant, including when a replacement is undone or discarded.
final class ShelfFileAccess: @unchecked Sendable {
    enum State: Equatable {
        case ready, needsAuthorization, locationChanged, bookmarkUnavailable

        var message: String? {
            switch self {
            case .ready: nil
            case .needsAuthorization: "访问权限未恢复：可选择所在文件夹批量恢复，或单独选择原文件"
            case .locationChanged: "原位置已改变：请移除旧引用，再从新位置拖入"
            case .bookmarkUnavailable: "未能保存长期访问权限，请选择所在文件夹恢复后重试"
            }
        }
    }

    let url: URL
    private let operations: ShelfAccessOperations
    private let started: Bool
    private let parentAccess: ShelfFileAccess?
    private(set) var bookmark: Data?
    private(set) var state: State
    var canReadCurrentSession: Bool { state == .ready || state == .bookmarkUnavailable }

    init(url: URL, operations: ShelfAccessOperations = .live, retaining parentAccess: ShelfFileAccess? = nil) {
        // Keep the original URL carrying the drag grant, rather than reconstructing it.
        self.url = url
        self.parentAccess = parentAccess
        self.operations = operations
        self.started = operations.start(url)
        self.state = .ready
    }

    private init(path: String, bookmark: Data?, state: State, operations: ShelfAccessOperations) {
        self.url = URL(fileURLWithPath: path)
        self.parentAccess = nil
        self.bookmark = bookmark
        self.state = state
        self.operations = operations
        self.started = false
    }

    static func restore(path: String, bookmark: Data?, operations: ShelfAccessOperations) -> ShelfFileAccess {
        guard let bookmark else {
            return ShelfFileAccess(path: path, bookmark: nil, state: .needsAuthorization, operations: operations)
        }
        do {
            let resolved = try operations.resolve(bookmark)
            guard resolved.url.standardizedFileURL.path == path else {
                // Bookmarks can follow moves. The product continues to identify the
                // original path, so never export a silently relocated file.
                return ShelfFileAccess(path: path, bookmark: bookmark, state: .locationChanged, operations: operations)
            }
            let access = ShelfFileAccess(url: resolved.url, operations: operations)
            access.bookmark = bookmark
            if !access.started {
                access.state = .needsAuthorization
            } else if resolved.stale {
                access.prepareBookmark()
            }
            return access
        } catch {
            return ShelfFileAccess(path: path, bookmark: bookmark, state: .needsAuthorization, operations: operations)
        }
    }

    @discardableResult
    func prepareBookmark() -> Bool {
        guard state == .ready || state == .bookmarkUnavailable else { return false }
        do {
            bookmark = try operations.bookmark(url)
            state = .ready
            return true
        } catch {
            state = .bookmarkUnavailable
            return false
        }
    }

    deinit {
        if started { operations.stop(url) }
    }
}

enum ShelfFileAvailability: Equatable, Sendable {
    case available, unavailable, accessDenied

    var message: String? {
        switch self {
        case .available: nil
        case .unavailable: "原位置暂不可用，请检查文件、外置卷或云盘后重试"
        case .accessDenied: "无法访问，可在恢复提示中选择所在文件夹重新授权"
        }
    }

    static func inspect(_ url: URL) -> ShelfFileAvailability {
        do {
            return try url.checkResourceIsReachable() ? .available : .unavailable
        } catch {
            let error = error as NSError
            if (error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoPermissionError)
                || (error.domain == NSPOSIXErrorDomain && [1, 13].contains(error.code)) {
                return .accessDenied
            }
            return .unavailable
        }
    }
}

struct ShelfPreparedReference: @unchecked Sendable {
    let access: ShelfFileAccess?
    let availability: ShelfFileAvailability
}


struct ShelfFolderRecovery {
    let urls: [URL]
    let prepared: [ShelfPreparedReference]
    let issues: [ShelfImportIssue]

    static func contains(_ path: URL, in folder: URL) -> Bool {
        let parent = folder.standardizedFileURL.pathComponents
        return path.standardizedFileURL.pathComponents.starts(with: parent)
    }

    static func prepare(paths: [String], folders: [ShelfFileAccess], operations: ShelfAccessOperations) -> Self {
        guard !paths.isEmpty else { return Self(urls: [], prepared: [], issues: []) }
        let ordered = folders.sorted { $0.url.pathComponents.count > $1.url.pathComponents.count }
        var urls: [URL] = []
        var prepared: [ShelfPreparedReference] = []
        var issues: [ShelfImportIssue] = []
        var matchedFolders = Set<String>()
        for path in paths {
            let url = URL(fileURLWithPath: path)
            guard let parent = ordered.first(where: { contains(url, in: $0.url) }) else { continue }
            matchedFolders.insert(parent.url.standardizedFileURL.path)
            // A lexical child that resolves outside the selected tree must not
            // inherit that folder's authority (e.g. a symlink to another volume).
            guard contains(url.resolvingSymlinksInPath(), in: parent.url.resolvingSymlinksInPath()) else {
                issues.append(ShelfImportIssue(url: url, reason: .outsideSelectedFolder))
                continue
            }
            let access = url.standardizedFileURL.path == parent.url.standardizedFileURL.path
                ? parent : ShelfFileAccess(url: url, operations: operations, retaining: parent)
            urls.append(url)
            prepared.append(ShelfPreparedReference(access: access, availability: ShelfFileAvailability.inspect(url)))
        }
        for parent in ordered where !matchedFolders.contains(parent.url.standardizedFileURL.path) {
            // An ancestor selected together with a more specific matching folder
            // is redundant, rather than an unrelated-folder error.
            if !paths.contains(where: { contains(URL(fileURLWithPath: $0), in: parent.url) }) {
                issues.append(ShelfImportIssue(url: parent.url, reason: .folderDoesNotContainReferences))
            }
        }
        return Self(urls: urls, prepared: prepared, issues: issues)
    }
}
