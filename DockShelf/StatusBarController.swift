import AppKit
import UniformTypeIdentifiers

@MainActor
final class StatusBarController: NSObject {
    private static let statusItemHitWidth: CGFloat = 32

    private let statusItem: NSStatusItem
    private let store = ShelfStore()
    private let panelController: ShelfPanelController
    private var helpWindowController: ShelfHelpWindowController?
    private var shortcut: ShelfShortcut?
    private var dragMonitor: ShelfDragMonitor?
    private static let automaticDragKey = "DockShelf.automaticFileDrag"
    private var automaticDragEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.automaticDragKey) as? Bool ?? true
    }
    private var interactionView: StatusItemInteractionView?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var screenObserver: NSObjectProtocol?
    private var isExportingReferences = false
    private var isChoosingAccess = false

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: Self.statusItemHitWidth)
        panelController = ShelfPanelController(store: store)
        super.init()
        panelController.folderReauthorizationRequested = { [weak self] in self?.chooseOriginalFilesForAccess($0, usingFolders: true) }
        panelController.reauthorizationRequested = { [weak self] in self?.chooseOriginalFilesForAccess($0) }
        panelController.helpRequested = { [weak self] in self?.showHelpAndAbout() }

        guard let button = statusItem.button else { return }
        button.image = makeStatusItemImage()
        button.toolTip = "搁这儿"
        button.target = self
        button.action = #selector(handleAccessibleStatusItemAction)
        button.sendAction(on: .leftMouseUp)
        button.setAccessibilityLabel("搁这儿")
        button.setAccessibilityHelp("打开临时文件搁板")

        let interactionView = StatusItemInteractionView(frame: button.bounds)
        interactionView.autoresizingMask = [.width, .height]
        interactionView.delegate = self
        interactionView.setAccessibilityElement(false)
        button.addSubview(interactionView)
        self.interactionView = interactionView
        dragMonitor = ShelfDragMonitor(onStart: { [weak self] in
            guard let self, !self.isChoosingAccess, let button = self.statusItem.button else { return }
            self.panelController.showForAutomaticDrag(relativeTo: button)
        }, onEnd: { [weak self] in self?.panelController.automaticDragEnded() })
        if automaticDragEnabled { dragMonitor?.start() }
        shortcut = ShelfShortcut { [weak self] in self?.showShelfUsingShortcut() }
        updateStatusTooltip()
        observeLifecycle()
        if shortcut?.isRegistered != true {
            NSLog("Shelf shortcut registration failed: %d", shortcut?.registrationStatus ?? -1)
        }

#if DEBUG
        NSLog("DockShelf status item initialized; showShelf=%@", CommandLine.arguments.contains("--show-shelf") ? "true" : "false")
#endif
        if CommandLine.arguments.contains("--show-shelf") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self, weak button] in
                guard let self, let button else { return }
                self.panelController.showManual(relativeTo: button)
            }
        }
    }

    private func observeLifecycle() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.dragMonitor?.stop()
                self?.panelController.close()
            }
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.automaticDragEnabled { self.dragMonitor?.start() }
                self.updateStatusTooltip()
            }
        })
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.panelController.close() }
        }
    }

    func canTerminate() -> Bool {
        guard store.persistenceProblem == .saveFailed || store.pendingImportCount > 0 || isExportingReferences else { return true }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = isExportingReferences ? "仍在导出固定记录" : (store.pendingImportCount > 0 ? "仍在检查文件引用" : "固定更改尚未保存")
        alert.informativeText = "退出会放弃尚未完成的检查、导出或未保存的固定更改。原文件不会被修改。"
        alert.addButton(withTitle: "返回搁板")
        alert.addButton(withTitle: "仍然退出")
        if store.persistenceProblem == .saveFailed { alert.addButton(withTitle: "重试保存") }
        let response = alert.runModal()
        if response == .alertSecondButtonReturn { return true }
        if response == .alertThirdButtonReturn { store.retryPersistence() }
        if let button = statusItem.button { panelController.showManual(relativeTo: button) }
        return false
    }

    func stop() {
        dragMonitor?.stop()
        shortcut?.stop()
        shortcut = nil
        panelController.close()
        helpWindowController?.close()
        helpWindowController = nil
        store.releaseAllAccess()
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers.removeAll()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
    }

    @objc private func handleAccessibleStatusItemAction() {
        guard let button = statusItem.button else { return }
        panelController.toggleManual(relativeTo: button)
    }

    @objc private func showShelfUsingShortcut() {
        guard !isChoosingAccess else { return }
        guard let button = statusItem.button else { return }
        panelController.showUsingShortcut(relativeTo: button)
    }

    @objc private func toggleAutomaticDrag() {
        let enable = dragMonitor?.isMonitoring != true
        UserDefaults.standard.set(enable, forKey: Self.automaticDragKey)
        if enable { dragMonitor?.start() } else { dragMonitor?.stop() }
        updateStatusTooltip()
    }

    private func updateStatusTooltip() {
        if dragMonitor?.isMonitoring == true {
            statusItem.button?.toolTip = "搁这儿 · 拖动文件时自动展开"
        } else if automaticDragEnabled {
            statusItem.button?.toolTip = "搁这儿 · 自动展开不可用，可点击打开"
        } else {
            statusItem.button?.toolTip = "搁这儿 · 点击打开"
        }
    }

    @objc private func clearTemporaryShelf() {
        store.clearTemporaryItems()
    }

    @objc private func clearAllShelf() {
        guard !store.items.isEmpty else { return }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "移除全部引用？"
        alert.informativeText = "固定和临时引用都会从搁板移除，但不会删除原文件。"
        alert.addButton(withTitle: "移除全部引用")
        alert.addButton(withTitle: "取消")

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.clearAll()
    }

    @objc private func exportPinnedReferences() {
        guard !isExportingReferences else { return }
        panelController.close()
        let document: ShelfReferenceExport
        do { document = try store.exportPinnedReferences() }
        catch {
            let alert = NSAlert()
            alert.messageText = "未导出固定记录"
            alert.informativeText = error as? ShelfReferenceExportProblem == .tooLarge
                ? "备份超过可导入的大小限制，未生成备份。当前记录没有改变。"
                : "请先固定项目；若固定记录无法读取，请先处理恢复提示。当前记录没有改变。"
            alert.addButton(withTitle: "关闭")
            alert.runModal()
            return
        }
        isExportingReferences = true
        Task { @MainActor in
            let result = await Task.detached(priority: .userInitiated) { () -> Result<URL, Error> in
                Result {
                    let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                        .appendingPathComponent("com.claracore.dockshelf/Exports", isDirectory: true)
                    return try document.write(to: directory)
                }
            }.value
            isExportingReferences = false
            let alert = NSAlert()
            switch result {
            case let .success(url):
                alert.messageText = "已导出 \(document.count) 项固定引用"
                let note = document.includesUnsavedChanges ? "这份导出包含当前尚未保存的固定更改。\n\n" : ""
                alert.informativeText = note + "记录已生成到本机应用导出目录。可在 Finder 中复制到你要保管的位置。\n\n备份包含路径、顺序、加入时间和已有访问书签（\(document.bookmarkCount) 项），不包含原文件或临时项。重新导入时自动尝试恢复权限；不能恢复的部分可选择所在文件夹批量处理。书签主要用于同一Mac、同一用户及同一应用恢复；备份含私人路径和授权信息，请妥善保管。"
                alert.addButton(withTitle: "在 Finder 中显示")
                alert.addButton(withTitle: "关闭")
                alert.addButton(withTitle: "复制导出文件路径")
                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } else if response == .alertThirdButtonReturn {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.path, forType: .string)
                }
            case .failure:
                alert.messageText = "未导出固定记录"
                alert.informativeText = "无法写入或核对应用的导出文件，请确认本机存储可用后重试。当前搁板和原文件没有改变。"
                alert.addButton(withTitle: "关闭")
                alert.runModal()
            }
        }
    }

    private func chooseOriginalFilesForAccess(_ requestedIDs: [String], usingFolders: Bool = false) {
        guard !isChoosingAccess, store.pendingImportCount == 0, store.canModifyPinnedReferences else { return }
        let targetIDs = Set(requestedIDs).intersection(store.items.map(\.id))
        guard !targetIDs.isEmpty else { return }
        panelController.close()
        isChoosingAccess = true
        let picker = NSOpenPanel()
        picker.title = usingFolders ? "选择所在文件夹，批量恢复" : "为引用重新授权"
        picker.prompt = usingFolders ? "恢复文件夹内的记录" : "授权"
        picker.canChooseFiles = !usingFolders
        picker.canChooseDirectories = true
        picker.treatsFilePackagesAsDirectories = false
        picker.allowsMultipleSelection = targetIDs.count > 1
        if usingFolders {
            // Start near the recorded locations, rather than unrelated Downloads.
            // Suggesting a directory never grants access; the user confirms it.
            let parents = targetIDs.map { URL(fileURLWithPath: $0).deletingLastPathComponent() }
            if var common = parents.first {
                while common.path != "/" && !parents.allSatisfy({ ShelfFolderRecovery.contains($0, in: common) }) {
                    common.deleteLastPathComponent()
                }
                if common.path != "/" { picker.directoryURL = common }
            }
            picker.message = "选择这些文件所在的文件夹，即可批量恢复其中的记录，不必逐个选文件。可选择多个文件夹；只恢复已记录的项目，不会加入其他文件。"
        } else if let path = targetIDs.first {
            picker.directoryURL = URL(fileURLWithPath: path).deletingLastPathComponent()
            picker.message = "选择原位置的文件或文件夹：\n\(path)\n其他位置的同名文件不会替换它。"
        }
        NSApp.activate(ignoringOtherApps: true)
        picker.begin { [weak self] response in
            guard let self else { return }
            guard response == .OK else {
                self.isChoosingAccess = false
                if let button = self.statusItem.button { self.panelController.showManual(relativeTo: button) }
                return
            }
            // Retain the original user-selected URL grants at the picker boundary.
            let completion: @MainActor (ShelfStore.AddResult) -> Void = { [weak self] _ in
                guard let self else { return }
                self.isChoosingAccess = false
                let restored = self.store.lastReauthorizedCount
                let remaining = self.store.items.filter { targetIDs.contains($0.id) && $0.access?.state != .ready }.count
                let issues = self.store.lastImportIssues
                let alert = NSAlert()
                let saved = self.store.persistenceProblem == nil
                alert.messageText = restored > 0 ? (saved ? "已为 \(restored) 项引用授权" : "已授权 \(restored) 项，但固定更改尚未保存") : "没有新增授权"
                var details = ["原顺序、加入时间与固定状态保持不变；没有加入或替换其他文件。"]
                if remaining > 0 { details.append("仍有 \(remaining) 项未恢复；可继续选择它们所在的文件夹，或检查原文件是否仍在原位置。") }
                if !saved { details.append("请在恢复提示中重试保存；当前授权尚不能确认重启后保留。") }
                if !issues.isEmpty {
                    details.append(issues.map { "\($0.displayName)：\($0.message)" }.joined(separator: "\n"))
                }
                alert.informativeText = details.joined(separator: "\n\n")
                alert.addButton(withTitle: "返回搁板")
                alert.runModal()
                if let button = self.statusItem.button { self.panelController.showManual(relativeTo: button) }
            }
            if usingFolders {
                self.store.enqueueFolderReauthorization(picker.urls, targetIDs: targetIDs, completion: completion)
            } else {
                self.store.enqueueImport(picker.urls, failedCount: 0, issues: [], reauthorizing: targetIDs, completion: completion)
            }
        }
    }

    @objc private func importPinnedReferences() {
        panelController.close()
        let picker = NSOpenPanel()
        picker.title = "导入固定记录"
        picker.message = "选择搁这儿导出的 JSON 或旧版偏好 plist。仅合并固定引用，不覆盖当前项目；会自动尝试恢复备份中的访问权限；失效部分可选择所在文件夹批量恢复。"
        picker.allowedContentTypes = [.json, .propertyList]
        picker.canChooseDirectories = false
        picker.allowsMultipleSelection = false
        picker.begin { [weak self] response in
            guard response == .OK, let url = picker.url else { return }
            Task { @MainActor [weak self] in
                let result = await Task.detached(priority: .userInitiated) { () -> Result<Data, Error> in
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    return Result {
                        let handle = try FileHandle(forReadingFrom: url)
                        defer { try? handle.close() }
                        let data = try handle.read(upToCount: 2_000_001) ?? Data()
                        guard data.count <= 2_000_000 else { throw ShelfPersistenceProblem.unreadable }
                        return data
                    }
                }.value
                guard let self else { return }
                let alert = NSAlert()
                var authorizationIDs: [String] = []
                do {
                    let count = try self.store.importPinnedReferences(result.get())
                    let restored = self.store.lastImportedRestoredCount
                    authorizationIDs = self.store.items.filter { $0.access?.state != .ready }.map(\.id)
                    alert.messageText = count > 0 ? "已导入 \(count) 项固定记录" : (restored > 0 ? "已恢复 \(restored) 项访问权限" : "备份中的项目已在搁板里")
                    var details = ["原有引用的排列和加入时间保持不变，没有重复加入。"]
                    if restored > 0 { details.append("已用备份中的访问书签恢复 \(restored) 项权限。") }
                    if !authorizationIDs.isEmpty {
                        details.append("搁板还有 \(authorizationIDs.count) 项权限未恢复。选择所在文件夹即可一起处理其中的记录，不必逐个选文件；旧版仅含路径的备份也可这样恢复。")
                        alert.addButton(withTitle: "选择所在文件夹，批量恢复…")
                    }
                    alert.informativeText = details.joined(separator: "\n\n")
                } catch {
                    alert.messageText = "未导入固定记录"
                    let reason: String
                    switch error as? ShelfPersistenceProblem {
                    case .recoveryNeedsSpace:
                        reason = "可用位置不足，请先移除部分临时引用，再重新导入。"
                    case .importConflict:
                        reason = "记录与现有临时项重叠，请先固定或移除相应临时引用，再导入。"
                    case .saveFailed:
                        reason = "未能保存导入结果，请确认本机存储可用后重试。"
                    case .unreadable:
                        reason = "所选记录或现有固定记录无法读取。请确认文件格式有效；若搁板显示恢复提示，请先处理。"
                    case nil:
                        reason = "请确认选择的记录文件可读取。"
                    }
                    alert.informativeText = "当前搁板未改变。\(reason)\n记录需格式有效、没有重复路径且最多 20 项。"
                }
                alert.addButton(withTitle: "返回搁板")
                let response = alert.runModal()
                if !authorizationIDs.isEmpty, response == .alertFirstButtonReturn {
                    self.chooseOriginalFilesForAccess(authorizationIDs, usingFolders: true)
                    return
                }
                if let button = self.statusItem.button { self.panelController.showManual(relativeTo: button) }
            }
        }
    }

    @objc private func showHelpAndAbout() {
        panelController.close()
        guard let shortcut else { return }
        if helpWindowController == nil { helpWindowController = ShelfHelpWindowController(shortcut: shortcut) }
        helpWindowController?.present()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let shortcutAvailable = shortcut?.isRegistered == true
        let showTitle = panelController.isVisible ? "收起搁板" : "显示搁板"
        let shortcutDescription = shortcut?.activeConfiguration?.display ?? "快捷键不可用"
        // Display the registered physical combination without adding a second
        // AppKit key-equivalent handler for the same global hotkey.
        let showItem = NSMenuItem(
            title: shortcutAvailable ? "\(showTitle)（\(shortcutDescription)）" : "\(showTitle)（快捷键不可用）",
            action: #selector(showShelfUsingShortcut), keyEquivalent: ""
        )
        showItem.target = self
        menu.addItem(showItem)
        let automaticItem = NSMenuItem(
            title: automaticDragEnabled && dragMonitor?.isMonitoring != true ? "自动展开不可用（点击重试）" : "拖动文件时自动展开",
            action: #selector(toggleAutomaticDrag), keyEquivalent: ""
        )
        automaticItem.target = self
        automaticItem.state = dragMonitor?.isMonitoring == true ? .on : .off
        menu.addItem(automaticItem)


        let clearTemporaryItem = NSMenuItem(
            title: "移除全部临时引用",
            action: #selector(clearTemporaryShelf),
            keyEquivalent: ""
        )
        clearTemporaryItem.target = self
        clearTemporaryItem.isEnabled = store.items.contains { !$0.isPinned }
        menu.addItem(clearTemporaryItem)

        let clearAllItem = NSMenuItem(
            title: "移除全部引用…",
            action: #selector(clearAllShelf),
            keyEquivalent: ""
        )
        clearAllItem.target = self
        clearAllItem.isEnabled = !store.items.isEmpty && store.canModifyPinnedReferences
        menu.addItem(clearAllItem)

        menu.addItem(.separator())
        let importItem = NSMenuItem(title: "导入固定记录…", action: #selector(importPinnedReferences), keyEquivalent: "")
        importItem.target = self
        importItem.isEnabled = store.canModifyPinnedReferences
        menu.addItem(importItem)
        let exportItem = NSMenuItem(title: "导出固定记录…", action: #selector(exportPinnedReferences), keyEquivalent: "")
        exportItem.target = self
        exportItem.isEnabled = store.canExportPinnedReferences && !isExportingReferences
        menu.addItem(exportItem)
        menu.addItem(.separator())
        let helpItem = NSMenuItem(title: "帮助与关于…", action: #selector(showHelpAndAbout), keyEquivalent: "")
        helpItem.target = self
        menu.addItem(helpItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出搁这儿", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        return menu
    }

    private func showContextMenu(relativeTo button: NSStatusBarButton) {
        let contextMenu = makeContextMenu()
        button.highlight(true)
        button.isHighlighted = true
        button.cell?.isHighlighted = true
        button.needsDisplay = true
        contextMenu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: button.bounds.height + 4),
            in: button
        )
        button.highlight(false)
        button.isHighlighted = false
        button.cell?.isHighlighted = false
        button.needsDisplay = true
    }

    private func makeStatusItemImage() -> NSImage? {
        if let image = NSImage(named: NSImage.Name("MenuBarTemplateIcon")) {
            image.isTemplate = true
            image.size = NSSize(width: 18, height: 18)
            image.accessibilityDescription = "搁这儿"
            return image
        }

        return NSImage(
            systemSymbolName: "square.stack.3d.up",
            accessibilityDescription: "搁这儿"
        )
    }
}

extension StatusBarController: StatusItemInteractionViewDelegate {
    func statusItemInteractionViewDidLeftClick(_ view: StatusItemInteractionView) {
        guard let button = statusItem.button else { return }
        panelController.toggleManual(relativeTo: button)
    }

    func statusItemInteractionViewDidRightClick(_ view: StatusItemInteractionView) {
        guard let button = statusItem.button else { return }
        showContextMenu(relativeTo: button)
    }

    func statusItemInteractionView(_ view: StatusItemInteractionView, hoverChanged isHovering: Bool) {
        guard let button = statusItem.button else { return }
        panelController.statusHoverChanged(isHovering, relativeTo: button)
    }

    func statusItemInteractionView(_ view: StatusItemInteractionView, dragEnteredWithValidItems isValid: Bool) {
        guard let button = statusItem.button else { return }
        panelController.statusDragEntered(relativeTo: button, isValid: isValid)
    }

    func statusItemInteractionView(_ view: StatusItemInteractionView, dragUpdatedWithValidItems isValid: Bool) {
        panelController.statusDragUpdated(isValid: isValid)
    }

    func statusItemInteractionViewDragExited(_ view: StatusItemInteractionView) {
        panelController.statusDragExited()
    }

    func statusItemInteractionView(_ view: StatusItemInteractionView, received batch: ShelfImport.Batch) -> Bool {
        return panelController.receiveStatusDrop(batch)
    }
}

@MainActor
protocol StatusItemInteractionViewDelegate: AnyObject {
    func statusItemInteractionViewDidLeftClick(_ view: StatusItemInteractionView)
    func statusItemInteractionViewDidRightClick(_ view: StatusItemInteractionView)
    func statusItemInteractionView(_ view: StatusItemInteractionView, hoverChanged isHovering: Bool)
    func statusItemInteractionView(_ view: StatusItemInteractionView, dragEnteredWithValidItems isValid: Bool)
    func statusItemInteractionView(_ view: StatusItemInteractionView, dragUpdatedWithValidItems isValid: Bool)
    func statusItemInteractionViewDragExited(_ view: StatusItemInteractionView)
    func statusItemInteractionView(_ view: StatusItemInteractionView, received batch: ShelfImport.Batch) -> Bool
}

@MainActor
final class StatusItemInteractionView: NSView {
    weak var delegate: StatusItemInteractionViewDelegate?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
        addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self
            )
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseUp(with event: NSEvent) {
        delegate?.statusItemInteractionViewDidLeftClick(self)
    }

    override func rightMouseUp(with event: NSEvent) {
        delegate?.statusItemInteractionViewDidRightClick(self)
    }

    override func mouseEntered(with event: NSEvent) {
        delegate?.statusItemInteractionView(self, hoverChanged: true)
    }

    override func mouseExited(with event: NSEvent) {
        delegate?.statusItemInteractionView(self, hoverChanged: false)
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let isValid = ShelfImport.accepts(sender.draggingPasteboard)
        delegate?.statusItemInteractionView(self, dragEnteredWithValidItems: isValid)
        return isValid ? .copy : []
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let isValid = ShelfImport.accepts(sender.draggingPasteboard)
        delegate?.statusItemInteractionView(self, dragUpdatedWithValidItems: isValid)
        return isValid ? .copy : []
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        delegate?.statusItemInteractionViewDragExited(self)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard ShelfImport.accepts(sender.draggingPasteboard) else { return false }
        let batch = ShelfImport.read(sender.draggingPasteboard)
        return delegate?.statusItemInteractionView(self, received: batch) ?? false
    }

}
