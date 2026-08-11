import AppKit
import SwiftUI
import UniformTypeIdentifiers

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
                feedbackPill(feedback)
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
            if !store.items.isEmpty {
                Button("清空搁板", role: .destructive) { store.clear() }
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
                            interaction: interaction
                        ) {
                            store.remove(item)
                        }
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
            .accessibilityLabel("搁板中有 \(store.items.count) 个文件，最多 \(ShelfStore.maximumItemCount) 个")
    }

    private var dropPrompt: some View {
        HStack(spacing: 14) {
            Image(systemName: interaction.phase == .receivingInvalid ? "xmark" : "arrow.down")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(dropPromptColor)
                .frame(width: 42, height: 42)
                .background(dropPromptColor.opacity(0.11), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(interaction.phase == .receivingInvalid ? "这里只接受文件" : "松手放到搁板")
                    .font(.subheadline.weight(.semibold))
                Text(interaction.phase == .receivingInvalid ? "文件夹或不支持的项目不会加入" : "只添加引用，文件仍在原位置")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 28)
        .padding(.bottom, 14)
    }

    private func feedbackPill(_ feedback: (title: String, symbol: String, color: Color)) -> some View {
        Label(feedback.title, systemImage: feedback.symbol)
            .font(.caption.weight(.medium))
            .foregroundStyle(feedback.color)
            .padding(.horizontal, 11)
            .frame(height: 28)
            .background(.regularMaterial, in: Capsule(style: .continuous))
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(feedback.color.opacity(0.24), lineWidth: 1)
            }
            .padding(.bottom, 27)
    }

    private var showsDropPrompt: Bool {
        interaction.phase == .receivingValid || interaction.phase == .receivingInvalid
    }

    private var transientFeedback: (title: String, symbol: String, color: Color)? {
        switch interaction.phase {
        case .success:
            ("已放好", "checkmark", DockShelfTheme.accent)
        case .exporting:
            ("拖到需要的位置", "arrow.up.forward", Color.secondary)
        default:
            nil
        }
    }

    private var panelBorder: Color {
        switch interaction.phase {
        case .idle, .exporting:
            DockShelfTheme.border
        case .receivingValid, .success:
            DockShelfTheme.accent
        case .receivingInvalid:
            DockShelfTheme.invalid
        }
    }

    private var emptyStateColor: Color {
        switch interaction.phase {
        case .idle, .exporting:
            .secondary
        case .receivingValid, .success:
            DockShelfTheme.accent
        case .receivingInvalid:
            DockShelfTheme.invalid
        }
    }

    private var dropPromptColor: Color {
        interaction.phase == .receivingInvalid ? DockShelfTheme.invalid : DockShelfTheme.accent
    }

    private var emptyStateTitle: String {
        interaction.phase == .success ? "已放好" : "把文件搁到这里"
    }

    private var emptyStateSubtitle: String {
        interaction.phase == .success ? "需要时再拖出去" : "文件仍留在原位置"
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
        private var globalEventMonitor: Any?

        func install(for view: NSView) {
            hostView = view
            localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) {
                [weak self] event in
                guard let self else { return event }
                return self.route(event) ? nil : event
            }

            globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) {
                [weak self] event in
                DispatchQueue.main.async {
                    _ = self?.route(event)
                }
            }
        }

        @discardableResult
        private func route(_ event: NSEvent) -> Bool {
            guard let hostView,
                  let window = hostView.window else { return false }

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
            if let globalEventMonitor {
                NSEvent.removeMonitor(globalEventMonitor)
                self.globalEventMonitor = nil
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
        .accessibilityHint(exists ? "按住并拖动到其他窗口" : "原文件已失效")

        if exists {
            tile.onDrag {
                interaction.beginExport()
                return NSItemProvider(contentsOf: item.url)
                    ?? NSItemProvider(object: item.url as NSURL)
            }
        } else {
            tile
        }
    }
}

private struct FileDropDelegate: DropDelegate {
    let store: ShelfStore
    let interaction: ShelfInteractionState

    func validateDrop(info: DropInfo) -> Bool { true }

    func dropEntered(info: DropInfo) {
        interaction.panelDropEntered(
            isValid: info.hasItemsConforming(to: [UTType.fileURL.identifier])
        )
    }

    func dropExited(info: DropInfo) {
        interaction.panelDropExited()
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let isValid = info.hasItemsConforming(to: [UTType.fileURL.identifier])
        return DropProposal(operation: isValid ? .copy : .cancel)
    }

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: [UTType.fileURL.identifier])
        guard !providers.isEmpty else {
            interaction.finishDrop(addedItems: false)
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
                let addedCount = store.add(resolvedURLs)
                interaction.finishDrop(addedItems: addedCount > 0)
            }
        }
        return true
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
