import Foundation
import Combine

struct ShelfItem: Identifiable, Hashable {
    let url: URL
    let addedAt: Date
    var isPinned: Bool
    var access: ShelfFileAccess? = nil

    var id: String { url.path }
    var displayName: String { url.lastPathComponent }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.url == rhs.url && lhs.addedAt == rhs.addedAt && lhs.isPinned == rhs.isPinned
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(url); hasher.combine(addedAt); hasher.combine(isPinned)
    }
}

/// Local, in-memory recovery details. These never enter persistence or diagnostics.
struct ShelfImportIssue: Identifiable, Equatable {
    enum Reason: Equatable {
        case unavailable
        case authorization
        case accessDenied
        case folderDoesNotContainReferences
        case outsideSelectedFolder
        case notRequestedReference
        case notLocalFile
        case unknown
    }

    let id: String
    let url: URL?
    let reason: Reason

    init(id: String = UUID().uuidString, url: URL? = nil, reason: Reason) {
        self.id = id
        self.url = url
        self.reason = reason
    }

    var displayName: String {
        guard let url, !url.lastPathComponent.isEmpty else { return "无法识别的项目" }
        return url.lastPathComponent
    }

    var message: String {
        switch reason {
        case .authorization:
            "无法保存长期访问权限，请选择所在文件夹恢复，或单独选择原文件"
        case .accessDenied:
            "无法读取所选文件，请检查访问权限后重新授权"
        case .folderDoesNotContainReferences:
            "该文件夹不包含待恢复记录，请选择它们所在的文件夹"
        case .outsideSelectedFolder:
            "此路径的链接指向所选文件夹以外，未恢复；请选择目标所在的文件夹或单独授权"
        case .notRequestedReference:
            "所选文件与待授权引用的原路径不一致，未替换或加入"
        case .unavailable:
            "原文件已移动、删除或暂不可访问"
        case .notLocalFile:
            "这里只接受本地文件或文件夹"
        case .unknown:
            "无法读取原始文件引用，请从来源重新拖入"
        }
    }
}

@MainActor
final class ShelfStore: ObservableObject {
    enum AddResult: Equatable {
        case reauthorized(count: Int)
        case added(count: Int)
        case replaced(addedCount: Int, removedCount: Int)
        case partial(addedCount: Int, removedCount: Int, duplicateCount: Int, failedCount: Int)
        case duplicate
        case invalid
        case tooMany(limit: Int)
        case insufficientReplaceable(required: Int, available: Int)

        var accepted: Bool {
            switch self {
            case .added, .replaced, .reauthorized:
                true
            case let .partial(addedCount, _, _, _):
                addedCount > 0
            case .duplicate, .invalid, .tooMany, .insufficientReplaceable:
                false
            }
        }
    }

    static let maximumItemCount = 20

    @Published private(set) var pendingImportCount = 0
    private var importTask: Task<Void, Never>?
    private var importGeneration = 0
    @Published private(set) var items: [ShelfItem]
    @Published private(set) var lastImportIssues: [ShelfImportIssue] = []

    @Published private(set) var persistenceProblem: ShelfPersistenceProblem?
    @Published private(set) var accessWarning: String?
    @Published private(set) var lastReauthorizedCount = 0
    @Published private(set) var lastImportedRestoredCount = 0
    private let persistence: ShelfPersistence
    private let accessOperations: ShelfAccessOperations
    private var needsLoadRecovery = false
    @Published private var replacementUndoSnapshot: [ShelfItem]?

    var canModifyPinnedReferences: Bool { !needsLoadRecovery }
    var canExportPinnedReferences: Bool { !needsLoadRecovery && items.contains(where: \.isPinned) }
    var canUndoReplacement: Bool { replacementUndoSnapshot != nil }
    var canRestoreBackup: Bool { persistence.hasBackup && needsLoadRecovery }

    init(defaults: UserDefaults = .standard,
         accessOperations: ShelfAccessOperations = .live,
         persistence: ShelfPersistence? = nil) {
        self.persistence = persistence ?? ShelfPersistence(defaults: defaults)
        self.accessOperations = accessOperations
        self.items = []
        reloadPinnedItems()
    }

    @discardableResult
    func add(
        _ urls: [URL],
        failedCount: Int = 0,
        issues: [ShelfImportIssue] = [],
        prepared: [ShelfPreparedReference]? = nil,
        reauthorizing targetIDs: Set<String>? = nil
    ) -> AddResult {
        accessWarning = nil
        lastReauthorizedCount = 0
        var invalidCount = max(0, failedCount)
        // Details describe the receiver's failures; they must never add to or
        // reduce its authoritative count. Unidentified entries remain explicit.
        var importIssues = Array(issues.prefix(max(0, failedCount)))
        if importIssues.count < failedCount {
            importIssues.append(contentsOf: (importIssues.count..<failedCount).map { _ in
                ShelfImportIssue(reason: .unknown)
            })
        }
        defer { lastImportIssues = importIssues }
        var duplicateCount = 0
        var incomingPaths = Set<String>()
        let existingPaths = Set(items.map(\.url.path))
        var incoming: [(url: URL, access: ShelfFileAccess)] = []
        var reauthorized: [(index: Int, access: ShelfFileAccess)] = []

        for (offset, candidate) in urls.enumerated() {
            guard candidate.isFileURL else {
                invalidCount += 1
                importIssues.append(ShelfImportIssue(reason: .notLocalFile))
                continue
            }
            let url = candidate.standardizedFileURL
            // A recovery picker may only renew explicitly requested identities.
            // Recheck the current shelf after queued work; never re-add removed
            // references or treat a same-name file at another path as a match.
            if let targetIDs, !targetIDs.contains(url.path) || !existingPaths.contains(url.path) {
                invalidCount += 1
                importIssues.append(ShelfImportIssue(url: url, reason: .notRequestedReference))
                continue
            }
            let preflight = prepared?[offset]
            let access = preflight?.access ?? ShelfFileAccess(url: candidate, operations: accessOperations)
            let availability = preflight?.availability ?? ShelfFileAvailability.inspect(candidate)
            guard availability == .available else {
                invalidCount += 1
                importIssues.append(ShelfImportIssue(url: url, reason: availability == .accessDenied ? .accessDenied : .unavailable))
                continue
            }
            guard incomingPaths.insert(url.path).inserted else {
                duplicateCount += 1
                continue
            }
            if existingPaths.contains(url.path) {
                if let index = items.firstIndex(where: { $0.id == url.path }),
                   items[index].access?.state != .ready {
                    if !items[index].isPinned || access.prepareBookmark() {
                        reauthorized.append((index, access))
                    } else {
                        invalidCount += 1
                        importIssues.append(ShelfImportIssue(url: url, reason: .authorization))
                    }
                } else {
                    duplicateCount += 1
                }
                continue
            }
            incoming.append((url, access))
        }

        func commitReauthorization() {
            // Regrant only changes access to the same identity, not order, date or pin state.
            for entry in reauthorized {
                let id = items[entry.index].id
                items[entry.index].access = entry.access
                if let index = replacementUndoSnapshot?.firstIndex(where: { $0.id == id }) {
                    replacementUndoSnapshot?[index].access = entry.access
                }
            }
            lastReauthorizedCount = reauthorized.count
            if !reauthorized.isEmpty { persistPinnedItems() }
        }

        guard !incoming.isEmpty else {
            commitReauthorization()
            if !reauthorized.isEmpty && invalidCount == 0 && duplicateCount == 0 {
                return .reauthorized(count: reauthorized.count)
            }
            if invalidCount > 0 && (duplicateCount > 0 || !reauthorized.isEmpty) {
                return .partial(addedCount: 0, removedCount: 0, duplicateCount: duplicateCount, failedCount: invalidCount)
            }
            return duplicateCount > 0 ? .duplicate : .invalid
        }
        guard incoming.count <= Self.maximumItemCount else {
            return .tooMany(limit: Self.maximumItemCount)
        }

        let requiredReplacementCount = max(
            0,
            items.count + incoming.count - Self.maximumItemCount
        )
        let replaceableItems = items.filter { !$0.isPinned }
        guard replaceableItems.count >= requiredReplacementCount else {
            return .insufficientReplaceable(
                required: requiredReplacementCount,
                available: replaceableItems.count
            )
        }

        commitReauthorization()
        clearReplacementUndo()
        let previousItems = items

        if requiredReplacementCount > 0 {
            let replacedIDs = Set(
                replaceableItems.prefix(requiredReplacementCount).map(\.id)
            )
            items.removeAll { replacedIDs.contains($0.id) }
        }

        items.append(contentsOf: incoming.map {
            ShelfItem(url: $0.url, addedAt: Date(), isPinned: false, access: $0.access)
        })

        if requiredReplacementCount > 0 {
            replacementUndoSnapshot = previousItems
        }

        if invalidCount > 0 || duplicateCount > 0 {
            return .partial(
                addedCount: incoming.count,
                removedCount: requiredReplacementCount,
                duplicateCount: duplicateCount,
                failedCount: invalidCount
            )
        }
        if requiredReplacementCount > 0 {
            return .replaced(
                addedCount: incoming.count,
                removedCount: requiredReplacementCount
            )
        }

        return .added(count: incoming.count)
    }

    /// Native drop receivers acknowledge queuing, then present the actual result.
    /// File probes run off the UI actor; serial commit preserves drop order/capacity.
    func enqueueImport(_ urls: [URL], failedCount: Int, issues: [ShelfImportIssue],
                       reauthorizing targetIDs: Set<String>? = nil,
                       completion: @escaping @MainActor (AddResult) -> Void) {
        pendingImportCount += 1
        let previous = importTask
        let generation = importGeneration
        // Consume/retain the original drag grants before the native receiver
        // returns. A later queued file probe must not depend on the source drag
        // session still being alive.
        let captured = urls.map { $0.isFileURL ? ShelfFileAccess(url: $0, operations: accessOperations) : nil }
        importTask = Task { @MainActor [weak self] in
            await previous?.value
            guard !Task.isCancelled, self?.importGeneration == generation else { return }
            let prepared = await Task.detached(priority: .userInitiated) {
                zip(urls, captured).map { candidate, access -> ShelfPreparedReference in
                    let availability = candidate.isFileURL ? ShelfFileAvailability.inspect(candidate) : .unavailable
                    return ShelfPreparedReference(access: access, availability: availability)
                }
            }.value
            guard let self, !Task.isCancelled, self.importGeneration == generation else { return }
            let result = self.add(urls, failedCount: failedCount, issues: issues, prepared: prepared, reauthorizing: targetIDs)
            self.pendingImportCount -= 1
            completion(result)
        }
    }

    /// One explicit folder selection restores only known reference paths inside
    /// it. Never enumerate folders, search by filename, or append new items.
    func enqueueFolderReauthorization(_ folders: [URL], targetIDs: Set<String>,
                                     completion: @escaping @MainActor (AddResult) -> Void) {
        pendingImportCount += 1
        let previous = importTask
        let generation = importGeneration
        let captured = folders.filter(\.isFileURL).map { ShelfFileAccess(url: $0, operations: accessOperations) }
        let paths = items.filter { targetIDs.contains($0.id) && $0.access?.state != .ready }.map(\.id)
        let operations = accessOperations
        importTask = Task { @MainActor [weak self] in
            await previous?.value
            guard !Task.isCancelled, self?.importGeneration == generation else { return }
            let batch = await Task.detached(priority: .userInitiated) {
                ShelfFolderRecovery.prepare(paths: paths, folders: captured, operations: operations)
            }.value
            guard let self, !Task.isCancelled, self.importGeneration == generation else { return }
            let result = self.add(batch.urls, failedCount: batch.issues.count, issues: batch.issues,
                                  prepared: batch.prepared, reauthorizing: targetIDs)
            self.pendingImportCount -= 1
            completion(result)
        }
    }

    func togglePinned(_ item: ShelfItem) {
        guard !needsLoadRecovery else { return }
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        accessWarning = nil
        if !items[index].isPinned {
            guard items[index].access?.prepareBookmark() == true else {
                accessWarning = "未固定：无法保存长期访问权限。请在恢复提示中选择所在文件夹恢复，再重试。"
                return
            }
        }
        clearReplacementUndo()
        items[index].isPinned.toggle()
        persistPinnedItems()
    }

    func remove(_ item: ShelfItem) {
        guard !needsLoadRecovery || !item.isPinned else { return }
        clearReplacementUndo()
        items.removeAll { $0.id == item.id }
        if item.isPinned { persistPinnedItems() }
    }

    func clearTemporaryItems() {
        clearReplacementUndo()
        items.removeAll { !$0.isPinned }
    }

    func clearAll() {
        guard !needsLoadRecovery else { clearTemporaryItems(); return }
        clearReplacementUndo()
        items.removeAll()
        persistPinnedItems()
    }

    @discardableResult
    func undoLastReplacement() -> Bool {
        guard let replacementUndoSnapshot else { return false }
        items = replacementUndoSnapshot
        clearReplacementUndo()
        return true
    }

    /// A backup of references and their existing app-scoped access bookmarks.
    /// It contains no original file bytes. Restore validates every grant.
    func exportPinnedReferences() throws -> ShelfReferenceExport {
        guard !needsLoadRecovery else { throw ShelfPersistenceProblem.unreadable }
        let records = items.filter(\.isPinned).map {
            ShelfPinnedRecord(path: $0.id, addedAt: $0.addedAt, bookmark: $0.access?.bookmark)
        }
        guard !records.isEmpty else { throw ShelfReferenceExportProblem.noPinnedItems }
        return ShelfReferenceExport(data: try persistence.encodeExport(records), count: records.count,
                                    includesUnsavedChanges: persistenceProblem == .saveFailed,
                                    bookmarkCount: records.filter { $0.bookmark != nil }.count)
    }

    /// Merge references explicitly selected by the user. Never replace current
    /// identities, discard unavailable entries or infer grants from their paths.
    @discardableResult
    func importPinnedReferences(_ data: Data) throws -> Int {
        lastImportedRestoredCount = 0
        guard !needsLoadRecovery else { throw ShelfPersistenceProblem.unreadable }
        let records = try persistence.decodeImport(data)
        let importedIDs = Set(records.map(\.path))
        guard !items.contains(where: { !$0.isPinned && importedIDs.contains($0.id) }) else {
            throw ShelfPersistenceProblem.importConflict
        }
        let knownIDs = Set(items.map(\.id))
        let incoming = records.filter { !knownIDs.contains($0.path) }
        guard items.count + incoming.count <= Self.maximumItemCount else {
            throw ShelfPersistenceProblem.recoveryNeedsSpace
        }
        var candidate = items
        var restoredAccess: [String: ShelfFileAccess] = [:]
        for record in records {
            if let index = candidate.firstIndex(where: { $0.id == record.path }) {
                // Keep existing metadata and working access; a backup can repair
                // pending access without forcing remove/re-import of the record.
                guard candidate[index].access?.state != .ready, record.bookmark != nil else { continue }
                let access = ShelfFileAccess.restore(path: record.path, bookmark: record.bookmark, operations: accessOperations)
                if access.canReadCurrentSession {
                    candidate[index].access = access
                    restoredAccess[record.path] = access
                }
            } else {
                let access = ShelfFileAccess.restore(path: record.path, bookmark: record.bookmark, operations: accessOperations)
                candidate.append(ShelfItem(url: URL(fileURLWithPath: record.path), addedAt: record.addedAt, isPinned: true, access: access))
                if access.canReadCurrentSession { restoredAccess[record.path] = access }
            }
        }
        guard !incoming.isEmpty || !restoredAccess.isEmpty else { return 0 }
        try persistence.preserveImportedBytes(data)
        // Save first: a failed import cannot publish access/metadata as committed.
        try persistence.save(candidate.filter(\.isPinned).map {
            ShelfPinnedRecord(path: $0.id, addedAt: $0.addedAt, bookmark: $0.access?.bookmark)
        })
        if !incoming.isEmpty { clearReplacementUndo() }
        else {
            for (id, access) in restoredAccess {
                if let index = replacementUndoSnapshot?.firstIndex(where: { $0.id == id }) {
                    replacementUndoSnapshot?[index].access = access
                }
            }
        }
        items = candidate
        persistenceProblem = nil
        lastImportedRestoredCount = restoredAccess.count
        return incoming.count
    }

    func retryPersistence() {
        if needsLoadRecovery { reloadPinnedItems() }
        else { persistPinnedItems() }
    }

    func restorePinnedBackup() {
        guard needsLoadRecovery else { return }
        do {
            try persistence.restoreBackup()
            reloadPinnedItems()
        } catch { persistenceProblem = .unreadable }
    }

    func dismissAccessWarning() { accessWarning = nil }

    /// Called only on termination. Current entries and undo share grant ownership.
    func releaseAllAccess() {
        importGeneration += 1
        importTask?.cancel()
        importTask = nil
        pendingImportCount = 0
        replacementUndoSnapshot = nil
        items.removeAll()
    }

    private func clearReplacementUndo() { replacementUndoSnapshot = nil }

    private func persistPinnedItems() {
        guard !needsLoadRecovery else { return }
        do {
            try persistence.save(items.filter(\.isPinned).map {
                ShelfPinnedRecord(path: $0.id, addedAt: $0.addedAt, bookmark: $0.access?.bookmark)
            })
            persistenceProblem = nil
        } catch {
            persistenceProblem = (error as? ShelfPersistenceProblem) ?? .saveFailed
            if persistenceProblem == .unreadable { needsLoadRecovery = true }
        }
    }

    private func reloadPinnedItems() {
        do {
            let loaded = try persistence.load()
            let pinned = loaded.records.map {
                ShelfItem(url: URL(fileURLWithPath: $0.path), addedAt: $0.addedAt, isPinned: true,
                          access: ShelfFileAccess.restore(path: $0.path, bookmark: $0.bookmark, operations: accessOperations))
            }
            let pinnedIDs = Set(pinned.map(\.id))
            let temporary = items.filter { !$0.isPinned && !pinnedIDs.contains($0.id) }
            guard pinned.count + temporary.count <= Self.maximumItemCount else {
                needsLoadRecovery = true
                persistenceProblem = .recoveryNeedsSpace
                return
            }
            clearReplacementUndo()
            items = pinned + temporary
            needsLoadRecovery = false
            persistenceProblem = nil
            if zip(pinned, loaded.records).contains(where: { $0.0.access?.bookmark != $0.1.bookmark }) {
                persistPinnedItems()
            }
        } catch {
            needsLoadRecovery = true
            persistenceProblem = (error as? ShelfPersistenceProblem) ?? .unreadable
        }
    }
}
