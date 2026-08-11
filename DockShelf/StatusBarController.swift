import AppKit

@MainActor
final class StatusBarController: NSObject {
    private static let statusItemHitWidth: CGFloat = 32

    private let statusItem: NSStatusItem
    private let store = ShelfStore()
    private let panelController: ShelfPanelController
    private lazy var contextMenu = makeContextMenu()
    private var interactionView: StatusItemInteractionView?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: Self.statusItemHitWidth)
        panelController = ShelfPanelController(store: store)
        super.init()

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

    @objc private func handleAccessibleStatusItemAction() {
        guard let button = statusItem.button else { return }
        panelController.toggleManual(relativeTo: button)
    }

    @objc private func showShelf() {
        guard let button = statusItem.button else { return }
        panelController.showManual(relativeTo: button)
    }

    @objc private func clearTemporaryShelf() {
        store.clearTemporaryItems()
    }

    @objc private func clearAllShelf() {
        store.clearAll()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()

        let showItem = NSMenuItem(title: "显示搁板", action: #selector(showShelf), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)

        let clearTemporaryItem = NSMenuItem(
            title: "清空临时文件",
            action: #selector(clearTemporaryShelf),
            keyEquivalent: ""
        )
        clearTemporaryItem.target = self
        menu.addItem(clearTemporaryItem)

        let clearAllItem = NSMenuItem(
            title: "清空全部引用",
            action: #selector(clearAllShelf),
            keyEquivalent: ""
        )
        clearAllItem.target = self
        menu.addItem(clearAllItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出搁这儿", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        return menu
    }

    private func showContextMenu(relativeTo button: NSStatusBarButton) {
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

    func statusItemInteractionView(_ view: StatusItemInteractionView, received urls: [URL]) -> Bool {
        return panelController.receiveStatusDrop(urls)
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
    func statusItemInteractionView(_ view: StatusItemInteractionView, received urls: [URL]) -> Bool
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
        let isValid = !validItemURLs(from: sender.draggingPasteboard).isEmpty
        delegate?.statusItemInteractionView(self, dragEnteredWithValidItems: isValid)
        return isValid ? .copy : []
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let isValid = !validItemURLs(from: sender.draggingPasteboard).isEmpty
        delegate?.statusItemInteractionView(self, dragUpdatedWithValidItems: isValid)
        return isValid ? .copy : []
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        delegate?.statusItemInteractionViewDragExited(self)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let urls = validItemURLs(from: sender.draggingPasteboard)
        guard !urls.isEmpty else { return false }
        return delegate?.statusItemInteractionView(self, received: urls) ?? false
    }

    private func validItemURLs(from pasteboard: NSPasteboard) -> [URL] {
        let values = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [NSURL] ?? []

        return values.compactMap { value in
            let url = value as URL
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return url
        }
    }
}
