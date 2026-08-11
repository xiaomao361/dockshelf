import AppKit
import SwiftUI
import UniformTypeIdentifiers

private struct FeedbackContent {
    let title: String
    var subtitle: String? = nil
    let symbol: String
    let color: Color
    var canUndo = false
    var canDismiss = false
}

private extension UTType {
    static let dockShelfItem = UTType(exportedAs: "com.claracore.dockshelf.shelf-item")
}

struct ShelfView: View {
    @ObservedObject var store: ShelfStore
    @ObservedObject var interaction: ShelfInteractionState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var refreshDate = Date()

    private let refreshTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack(alignment: .bottom) {
            shelfContent
                .opacity(showsDropPrompt ? 0.08 : 1)

            if showsDropPrompt {
                dropPrompt
                    .transition(.opacity)
            } else if let feedback = transientFeedback {
                feedbackBanner(feedback)
                    .transition(.opacity.combined(with: .offset(y: 3)))
            }

            if !store.items.isEmpty && !showsDropPrompt {
                countPill
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(8)
                    .transition(.opacity)
            }
        }
        .frame(width: DockShelfMetrics.panelSize.width, height: DockShelfMetrics.panelSize.height)
        .background {
            NativePopoverMaterial()
        }
        .clipShape(RoundedRectangle(cornerRadius: DockShelfMetrics.panelRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DockShelfMetrics.panelRadius, style: .continuous)
                .strokeBorder(panelBorder, lineWidth: interaction.phase == .idle ? 1 : 1.5)
        }
        .contentShape(RoundedRectangle(cornerRadius: DockShelfMetrics.panelRadius, style: .continuous))
        .contextMenu {
            if store.items.contains(where: { !$0.isPinned }) {
                Button("清空临时文件") { store.clearTemporaryItems() }
            }
            if !store.items.isEmpty {
                Button("清空全部引用", role: .destructive) { store.clearAll() }
            }
        }
        .onDrop(
            of: [UTType.fileURL.identifier, UTType.item.identifier],
            delegate: FileDropDelegate(store: store, interaction: interaction)
        )
        .onHover { interaction.panelHoverChanged?($0) }
        .onReceive(refreshTimer) { refreshDate = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: interaction.phase)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: store.items.map(\.id))
        .accessibilityIdentifier("shelf-panel")
    }

    @ViewBuilder
    private var shelfContent: some View {
        if store.items.isEmpty {
            emptyState
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: DockShelfMetrics.itemSpacing) {
                    ForEach(store.items) { item in
                        ShelfItemTile(
                            item: item,
                            refreshDate: refreshDate,
                            interaction: interaction,
                            togglePinned: { store.togglePinned(item) },
                            remove: { store.remove(item) }
                        )
                        .transition(.opacity.combined(with: .offset(y: 3)))
                    }
                }
                .padding(.horizontal, DockShelfMetrics.horizontalPadding)
                .padding(.top, 18)
                .padding(.bottom, 34)
            }
            .background(HorizontalScrollWheelBridge())
        }
    }

    private var emptyState: some View {
        HStack(spacing: 14) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(emptyStateColor)
                .frame(width: 42, height: 42)
                .background(emptyStateColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(emptyStateTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(interaction.phase == .receivingInvalid ? DockShelfTheme.invalid : Color.primary)
                Text(emptyStateSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 28)
        .padding(.bottom, 14)
        .accessibilityElement(children: .combine)
    }

    private var countPill: some View {
        Text("\(store.items.count)/\(ShelfStore.maximumItemCount)")
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(.regularMaterial, in: Capsule(style: .continuous))
            .accessibilityLabel("搁板中有 \(store.items.count) 个项目，最多 \(ShelfStore.maximumItemCount) 个")
    }

    private var dropPrompt: some View {
        HStack(spacing: 14) {
            Image(systemName: dropPromptSymbol)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(dropPromptColor)
                .frame(width: 42, height: 42)
                .background(dropPromptColor.opacity(0.11), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(dropPromptTitle)
                    .font(.subheadline.weight(.semibold))
                Text(dropPromptSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 28)
        .padding(.bottom, 14)
    }

    private func feedbackBanner(_ feedback: FeedbackContent) -> some View {
        HStack(spacing: 8) {
            Image(systemName: feedback.symbol)
                .foregroundStyle(feedback.color)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(feedback.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(feedback.color)
                if let subtitle = feedback.subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if feedback.canUndo {
                Button("撤销") {
                    if store.undoLastReplacement() {
                        interaction.showReplacementRestored()
                    }
                }
                .buttonStyle(.borderless)
                .font(.caption.weight(.semibold))
                .accessibilityHint("恢复替换前的文件和排列顺序")
            }

            if feedback.canDismiss {
                Button("返回") {
                    interaction.dismissFeedback()
                }
                .buttonStyle(.borderless)
                .font(.caption.weight(.semibold))
                .keyboardShortcut(.cancelAction)
                .accessibilityHint("关闭提示并返回搁板")
            }
        }
            .padding(.horizontal, 12)
            .frame(minHeight: feedback.subtitle == nil ? 30 : 40)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(feedback.color.opacity(0.24), lineWidth: 1)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 22)
            .accessibilityElement(children: .contain)
    }

    private var showsDropPrompt: Bool {
        interaction.phase == .receivingValid
            || interaction.phase == .receivingInvalid
            || interaction.phase == .returningShelfItem
    }

    private var transientFeedback: FeedbackContent? {
        switch interaction.phase {
        case .success:
            FeedbackContent(title: "已放好", symbol: "checkmark", color: DockShelfTheme.accent)
        case .invalid:
            FeedbackContent(
                title: "这里只接受文件或文件夹",
                subtitle: "其他内容不会加入",
                symbol: "xmark",
                color: DockShelfTheme.invalid,
                canDismiss: true
            )
        case let .replaced(count):
            FeedbackContent(
                title: "已替换 \(count) 个较早文件",
                symbol: "arrow.triangle.2.circlepath",
                color: DockShelfTheme.warning,
                canUndo: true
            )
        case .duplicate:
            FeedbackContent(
                title: "项目已经在搁板里",
                symbol: "doc.on.doc",
                color: DockShelfTheme.warning,
                canDismiss: true
            )
        case let .tooMany(limit):
            FeedbackContent(
                title: "一次最多放入 \(limit) 个项目",
                symbol: "exclamationmark.triangle",
                color: DockShelfTheme.warning,
                canDismiss: true
            )
        case let .insufficientReplaceable(required, available):
            FeedbackContent(
                title: "还需要 \(required - available) 个临时位置",
                subtitle: "取消固定或移除文件后再试",
                symbol: "pin.fill",
                color: DockShelfTheme.warning,
                canDismiss: true
            )
        case .restored:
            FeedbackContent(
                title: "已恢复替换前的文件",
                symbol: "arrow.uturn.backward",
                color: DockShelfTheme.accent
            )
        case .exporting:
            FeedbackContent(title: "拖到需要的位置", symbol: "arrow.up.forward", color: .secondary)
        default:
            nil
        }
    }

    private var panelBorder: Color {
        switch interaction.phase {
        case .idle, .exporting:
            DockShelfTheme.border
        case .receivingValid, .success, .restored:
            DockShelfTheme.accent
        case .receivingInvalid, .invalid:
            DockShelfTheme.invalid
        case .returningShelfItem, .replaced, .duplicate, .tooMany, .insufficientReplaceable:
            DockShelfTheme.warning
        }
    }

    private var emptyStateColor: Color {
        switch interaction.phase {
        case .idle, .returningShelfItem, .exporting, .duplicate, .tooMany, .insufficientReplaceable:
            .secondary
        case .receivingValid, .success, .replaced, .restored:
            DockShelfTheme.accent
        case .receivingInvalid, .invalid:
            DockShelfTheme.invalid
        }
    }

    private var dropPromptColor: Color {
        switch interaction.phase {
        case .receivingInvalid:
            DockShelfTheme.invalid
        case .returningShelfItem:
            DockShelfTheme.warning
        default:
            DockShelfTheme.accent
        }
    }

    private var dropPromptSymbol: String {
        interaction.phase == .receivingValid ? "arrow.down" : "xmark"
    }

    private var dropPromptTitle: String {
        switch interaction.phase {
        case .receivingInvalid:
            "这里只接受文件或文件夹"
        case .returningShelfItem:
            "项目已经在搁板里"
        default:
            "松手放到搁板"
        }
    }

    private var dropPromptSubtitle: String {
        switch interaction.phase {
        case .receivingInvalid:
            "其他内容不会加入"
        case .returningShelfItem:
            "请拖到搁板外使用"
        default:
            "只添加引用，内容仍在原位置"
        }
    }

    private var emptyStateTitle: String {
        interaction.phase == .success ? "已放好" : "把文件或文件夹搁到这里"
    }

    private var emptyStateSubtitle: String {
        interaction.phase == .success ? "需要时再拖出去" : "内容仍留在原位置"
    }
}

private struct NativePopoverMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        if #available(macOS 26.0, *) {
            let view = NSGlassEffectView()
            view.style = .regular
            view.cornerRadius = DockShelfMetrics.panelRadius
            return view
        }

        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = false
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private struct HorizontalScrollWheelBridge: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.install(for: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.hostView = nsView
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    final class Coordinator {
        weak var hostView: NSView?
        private var localEventMonitor: Any?

        func install(for view: NSView) {
            hostView = view
            localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) {
                [weak self] event in
                guard let self else { return event }
                return self.route(event) ? nil : event
            }
        }

        @discardableResult
        private func route(_ event: NSEvent) -> Bool {
            guard let hostView,
                  let window = hostView.window,
                  window.isVisible else { return false }

            let locationInWindow = event.window === window
                ? event.locationInWindow
                : window.convertPoint(fromScreen: NSEvent.mouseLocation)

            guard let scrollView = horizontalScrollView(
                at: locationInWindow,
                inside: window
            ) else { return false }

            let verticalDelta = event.scrollingDeltaY
            guard abs(verticalDelta) > abs(event.scrollingDeltaX),
                  abs(verticalDelta) > 0.01 else { return false }

            let clipView = scrollView.contentView
            let documentWidth = max(
                scrollView.documentView?.frame.width ?? 0,
                scrollView.documentView?.bounds.width ?? 0
            )
            let maximumX = max(0, documentWidth - clipView.bounds.width)
            guard maximumX > 0 else { return false }

            let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 32
            let proposedX = min(
                maximumX,
                max(0, clipView.bounds.origin.x - verticalDelta * multiplier)
            )
            guard abs(proposedX - clipView.bounds.origin.x) > 0.01 else {
                return false
            }

            clipView.scroll(to: NSPoint(x: proposedX, y: clipView.bounds.origin.y))
            scrollView.reflectScrolledClipView(clipView)
#if DEBUG
            NSLog(
                "Shelf wheel mapped vertical=%0.2f to horizontal=%0.2f/%0.2f",
                verticalDelta,
                proposedX,
                maximumX
            )
#endif
            return true
        }

        private func horizontalScrollView(
            at locationInWindow: NSPoint,
            inside window: NSWindow
        ) -> NSScrollView? {
            guard let rootView = window.contentView else { return nil }

            var candidates: [NSScrollView] = []
            collectScrollViews(in: rootView, into: &candidates)

            return candidates
                .filter { scrollView in
                    let localPoint = scrollView.convert(locationInWindow, from: nil)
                    guard scrollView.bounds.contains(localPoint) else { return false }

                    let documentWidth = max(
                        scrollView.documentView?.frame.width ?? 0,
                        scrollView.documentView?.bounds.width ?? 0
                    )
                    return documentWidth > scrollView.contentView.bounds.width + 1
                }
                .min { $0.bounds.width < $1.bounds.width }
        }

        private func collectScrollViews(
            in view: NSView,
            into result: inout [NSScrollView]
        ) {
            if let scrollView = view as? NSScrollView {
                result.append(scrollView)
            }
            for subview in view.subviews {
                collectScrollViews(in: subview, into: &result)
            }
        }

        func removeMonitor() {
            if let localEventMonitor {
                NSEvent.removeMonitor(localEventMonitor)
                self.localEventMonitor = nil
            }
        }

        deinit {
            removeMonitor()
        }
    }
}

private struct ShelfItemTile: View {
    let item: ShelfItem
    let refreshDate: Date
    @ObservedObject var interaction: ShelfInteractionState
    let togglePinned: () -> Void
    let remove: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        let exists = item.exists
        let _ = refreshDate
        let tile = VStack(spacing: 7) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: DockShelfMetrics.iconSize, height: DockShelfMetrics.iconSize)
                .opacity(exists ? 1 : 0.42)
                .accessibilityHidden(true)

            Text(item.displayName)
                .font(.caption2.weight(.medium))
                .foregroundStyle(exists ? .primary : .secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 24, alignment: .top)
        }
        .padding(.horizontal, 4)
        .padding(.top, 10)
        .frame(width: DockShelfMetrics.itemWidth, height: DockShelfMetrics.itemHeight, alignment: .top)
        .background(
            DockShelfTheme.itemBackground.opacity(isHovered ? 0.86 : 0.64),
            in: RoundedRectangle(cornerRadius: DockShelfMetrics.itemRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DockShelfMetrics.itemRadius, style: .continuous)
                .strokeBorder(
                    exists
                        ? (isHovered ? DockShelfTheme.accent.opacity(0.68) : DockShelfTheme.border)
                        : DockShelfTheme.invalid,
                    lineWidth: isHovered ? 1.5 : 1
                )
        }
        .overlay(alignment: .topTrailing) {
            if isHovered {
                Button(action: remove) {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .offset(x: 3, y: -3)
                .help("移除引用")
                .accessibilityLabel("移除 \(item.displayName)")
                .transition(.opacity)
            }
        }
        .overlay(alignment: .topLeading) {
            if item.isPinned || isHovered {
                Button(action: togglePinned) {
                    Image(systemName: item.isPinned ? "pin.fill" : "pin")
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(item.isPinned ? DockShelfTheme.accent : Color.secondary)
                .offset(x: -3, y: -3)
                .help(item.isPinned ? "取消固定" : "固定并在重启后保留")
                .accessibilityLabel(
                    item.isPinned
                        ? "取消固定 \(item.displayName)"
                        : "固定 \(item.displayName)"
                )
                .transition(.opacity)
            }
        }
        .overlay(alignment: .topTrailing) {
            if !exists {
                Circle()
                    .fill(DockShelfTheme.invalid)
                    .frame(width: 9, height: 9)
                    .padding(6)
                    .accessibilityHidden(true)
            }
        }
        .shadow(color: .black.opacity(isHovered ? 0.16 : 0.05), radius: isHovered ? 8 : 3, y: isHovered ? 4 : 1)
        .scaleEffect(reduceMotion || !isHovered ? 1 : 1.018)
        .offset(y: reduceMotion || !isHovered ? 0 : -1)
        .contentShape(RoundedRectangle(cornerRadius: DockShelfMetrics.itemRadius, style: .continuous))
        .contextMenu {
            Button(item.isPinned ? "取消固定" : "固定") {
                togglePinned()
            }
            Button("移除引用", role: .destructive) {
                remove()
            }
        }
        .onHover { isHovered = $0 }
        .animation(
            reduceMotion
                ? nil
                : .interactiveSpring(
                    response: 0.22,
                    dampingFraction: 0.86,
                    blendDuration: 0.08
                ),
            value: isHovered
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(item.displayName)
        .accessibilityValue(item.isPinned ? "已固定" : "临时文件")
        .accessibilityHint(
            exists
                ? "按住并拖动到其他窗口"
                : "原文件已失效"
        )
        .accessibilityAction(named: item.isPinned ? "取消固定" : "固定") {
            togglePinned()
        }
        .accessibilityAction(named: "移除引用") {
            remove()
        }

        if exists {
            tile.onDrag {
                interaction.beginExport()
                let provider = NSItemProvider(contentsOf: item.url)
                    ?? NSItemProvider(object: item.url as NSURL)
                provider.registerDataRepresentation(
                    forTypeIdentifier: UTType.dockShelfItem.identifier,
                    visibility: .ownProcess
                ) { completion in
                    completion(Data(item.id.utf8), nil)
                    return nil
                }
                return provider
            }
        } else {
            tile
        }
    }
}

private struct FileDropDelegate: DropDelegate {
    let store: ShelfStore
    let interaction: ShelfInteractionState

    func validateDrop(info: DropInfo) -> Bool {
        !isShelfItemDrag(info)
    }

    func dropEntered(info: DropInfo) {
        if isShelfItemDrag(info) {
            interaction.showReturningShelfItem()
            return
        }
        interaction.panelDropEntered(
            isValid: info.hasItemsConforming(to: [UTType.fileURL.identifier])
        )
    }

    func dropExited(info: DropInfo) {
        if interaction.phase == .returningShelfItem {
            interaction.resumeExport()
            return
        }
        interaction.panelDropExited()
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        if isShelfItemDrag(info) {
            return DropProposal(operation: .cancel)
        }
        let isValid = info.hasItemsConforming(to: [UTType.fileURL.identifier])
        return DropProposal(operation: isValid ? .copy : .cancel)
    }

    func performDrop(info: DropInfo) -> Bool {
        if isShelfItemDrag(info) {
            interaction.resumeExport()
            return false
        }
        let providers = info.itemProviders(for: [UTType.fileURL.identifier])
        guard !providers.isEmpty else {
            interaction.finishDrop(result: .invalid)
            return false
        }

        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let url = Self.fileURL(from: item) {
                    lock.lock()
                    urls.append(url)
                    lock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            let resolvedURLs = urls
            Task { @MainActor in
                interaction.finishDrop(result: store.add(resolvedURLs))
            }
        }
        return true
    }

    private func isShelfItemDrag(_ info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.dockShelfItem.identifier])
    }

    private static func fileURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL { return url }
        if let url = item as? NSURL { return url as URL }
        if let data = item as? Data {
            let value = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: "\0")))
            return URL(string: value)
        }
        if let value = item as? String { return URL(string: value) }
        return nil
    }
}
