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
    @State private var showsClearAllConfirmation = false
    @State private var inspectedItemID: String?
    @State private var scrollItemID: String?

    var body: some View {
        ZStack(alignment: .bottom) {
            shelfContent
                .opacity(showsDropPrompt ? 0.08 : 1)

            if showsDropPrompt {
                dropPrompt
                    .transition(.opacity)
            } else if let feedback = transientFeedback {
                feedbackBanner(feedback)
                    .transition(feedbackTransition)
            }

            if !store.items.isEmpty {
                countPill
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
                    .transition(.opacity)
            }

            // Feedback owns the footer; keep the inspected file identifiable in the header.
            if transientFeedback != nil && !showsDropPrompt,
               let item = store.items.first(where: { $0.id == inspectedItemID }) {
                Text(item.displayName)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, 16)
                    .padding(.trailing, 72)
                    .padding(.top, 5)
                    .allowsHitTesting(false)
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
            Button("移除全部临时引用") {
                store.clearTemporaryItems()
            }
            .disabled(!store.items.contains { !$0.isPinned })

            Button("移除全部引用…", role: .destructive) {
                showsClearAllConfirmation = true
            }
            .disabled(store.items.isEmpty)
        }
        .confirmationDialog(
            "移除全部引用？",
            isPresented: $showsClearAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("移除全部引用", role: .destructive) {
                store.clearAll()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("固定和临时引用都会从搁板移除，但不会删除原文件。")
        }
        .onHover { interaction.panelHoverChanged?($0) }
        .task(id: interaction.isPanelVisible) {
            guard interaction.isPanelVisible else { return }
            refreshDate = Date()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(2)) }
                catch { return }
                refreshDate = Date()
            }
        }
        .onChange(of: store.canUndoReplacement) { _, canUndo in
            if !canUndo, case .replaced = interaction.phase {
                interaction.dismissFeedback()
            }
        }
        .onChange(of: interaction.isPanelVisible) { _, visible in
            if !visible { inspectedItemID = nil }
        }
        .onChange(of: interaction.phase) { _, _ in
            announceFeedback()
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: interaction.phase)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: store.items.map(\.id))
        .accessibilityIdentifier("shelf-panel")
    }

    @ViewBuilder
    private var shelfContent: some View {
        if store.items.isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: true) {
                    LazyHStack(spacing: DockShelfMetrics.itemSpacing) {
                        ForEach(store.items) { item in
                            ShelfItemTile(
                                item: item,
                                refreshDate: refreshDate,
                                interaction: interaction,
                                inspect: { isInspecting in
                                    if isInspecting { inspectedItemID = item.id }
                                    else if inspectedItemID == item.id { inspectedItemID = nil }
                                },
                                togglePinned: { store.togglePinned(item) },
                                remove: { store.remove(item) }
                            )
                            .id(item.id)
                            .transition(reduceMotion ? .opacity : .asymmetric(
                                insertion: .opacity.combined(with: .offset(y: -4)),
                                removal: .opacity
                            ))
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, DockShelfMetrics.horizontalPadding)
                    .padding(.top, 24)
                    .padding(.bottom, 38)
                }
                .scrollPosition(id: $scrollItemID, anchor: .leading)
                .background(HorizontalScrollWheelBridge())
                .onAppear {
                    if let newestID = store.items.last?.id {
                        proxy.scrollTo(newestID, anchor: .trailing)
                    }
                }
                .onChange(of: store.items.map(\.id)) { oldIDs, newIDs in
                    guard let newestID = newIDs.last, !oldIDs.contains(newestID) else { return }
                    // Wait for the newly appended tile to enter the scroll layout.
                    DispatchQueue.main.async { proxy.scrollTo(newestID, anchor: .trailing) }
                }
                .overlay(alignment: .bottom) {
                    if transientFeedback == nil && !showsDropPrompt {
                        shelfFooter(proxy: proxy)
                    }
                }
            }
        }
    }

    private func shelfFooter(proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 6) {
            if store.items.count > 5 {
                pageButton("向左翻动", symbol: "chevron.left") { scrollPage(-1, proxy: proxy) }
            }

            Group {
                if let item = store.items.first(where: { $0.id == inspectedItemID }) {
                    VStack(spacing: 1) {
                        Text(item.displayName)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.primary)
                        Text(item.url.deletingLastPathComponent().path)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(item.url.path)
                    .accessibilityElement(children: .combine)
                } else if store.items.count > 5 {
                    Text("左右翻动或滚动查看更多")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("拖到需要的位置 · 固定后重启仍保留")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)

            if store.items.count > 5 {
                pageButton("向右翻动", symbol: "chevron.right") { scrollPage(1, proxy: proxy) }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .padding(.bottom, 1)
    }

    private func pageButton(_ label: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(label)
        .accessibilityLabel(label)
    }

    private func scrollPage(_ direction: Int, proxy: ScrollViewProxy) {
        let index = store.items.firstIndex { $0.id == scrollItemID } ?? 0
        let target = min(max(0, index + direction * 5), store.items.count - 1)
        guard store.items.indices.contains(target) else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) {
            proxy.scrollTo(store.items[target].id, anchor: .leading)
        }
    }

    private var emptyState: some View {
        HStack(spacing: 15) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(emptyStateColor)
                .frame(width: 46, height: 46)
                .background(emptyStateColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(emptyStateTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(interaction.phase == .receivingInvalid ? DockShelfTheme.invalid : Color.primary)
                Text(emptyStateSubtitle)
                    .font(.system(size: 13, weight: .regular))
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
            .frame(height: 16)
            .background(.regularMaterial, in: Capsule(style: .continuous))
            .accessibilityLabel("搁板中有 \(store.items.count) 个项目，最多 \(ShelfStore.maximumItemCount) 个")
    }

    private var dropPrompt: some View {
        HStack(spacing: 15) {
            Image(systemName: dropPromptSymbol)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(dropPromptColor)
                .frame(width: 46, height: 46)
                .background(dropPromptColor.opacity(0.11), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(dropPromptTitle)
                    .font(.system(size: 16, weight: .semibold))
                Text(dropPromptSubtitle)
                    .font(.system(size: 13, weight: .regular))
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
            .frame(maxWidth: .infinity, alignment: .leading)

            if hasImportIssues {
                Button {
                    interaction.isShowingDetails.toggle()
                } label: {
                    Image(systemName: "info.circle")
                        .frame(width: 24, height: 28)
                }
                .buttonStyle(.borderless)
                .help("查看未加入项目")
                .accessibilityLabel("查看未加入项目及原因")
                .popover(isPresented: $interaction.isShowingDetails, arrowEdge: .bottom) {
                    ShelfImportIssuesView(issues: store.lastImportIssues)
                }
            }

            if feedback.canUndo && store.canUndoReplacement {
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
            .frame(minHeight: feedback.subtitle == nil ? 28 : 36)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(feedback.color.opacity(0.24), lineWidth: 1)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 2)
            .accessibilityElement(children: .contain)
    }

    private var showsDropPrompt: Bool {
        interaction.phase == .receivingValid
            || interaction.phase == .receivingInvalid
            || interaction.phase == .returningShelfItem
    }

    private var feedbackTransition: AnyTransition {
        if reduceMotion { return .opacity }
        if interaction.phase == .success {
            return .opacity.combined(with: .offset(y: -6))
        }
        return .opacity.combined(with: .offset(y: 3))
    }

    private var transientFeedback: FeedbackContent? {
        switch interaction.phase {
        case .success:
            FeedbackContent(title: "已搁好 \(interaction.lastAddedCount) 项", symbol: "checkmark", color: DockShelfTheme.accent)
        case .invalid:
            FeedbackContent(
                title: "未能加入项目",
                subtitle: "请确认本地文件可访问，再拖入重试",
                symbol: "xmark",
                color: DockShelfTheme.invalid,
                canDismiss: true
            )
        case let .replaced(count):
            FeedbackContent(
                title: "已替换 \(count) 个较早文件",
                symbol: "arrow.triangle.2.circlepath",
                color: DockShelfTheme.warning,
                canUndo: true,
                canDismiss: true
            )
        case let .partial(added, removed, duplicates, failed):
            FeedbackContent(
                title: removed > 0 ? "已加入 \(added) 项，替换 \(removed) 项" : (added > 0 ? "已加入 \(added) 项" : "没有加入新项目"),
                subtitle: [
                    duplicates > 0 ? "\(duplicates) 项重复" : nil,
                    failed > 0 ? "\(failed) 项无法读取" : nil
                ].compactMap { $0 }.joined(separator: " · "),
                symbol: "exclamationmark.circle",
                color: DockShelfTheme.warning,
                canUndo: removed > 0,
                canDismiss: true
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

    private var hasImportIssues: Bool {
        guard !store.lastImportIssues.isEmpty else { return false }
        switch interaction.phase {
        case .invalid: return true
        case let .partial(_, _, _, failed): return failed > 0
        default: return false
        }
    }

    private func announceFeedback() {
        guard interaction.isPanelVisible, let feedback = transientFeedback,
              interaction.phase != .exporting else { return }
        let message = [feedback.title, feedback.subtitle].compactMap { $0 }.joined(separator: "，")
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.medium.rawValue]
        )
    }

    private var panelBorder: Color {
        switch interaction.phase {
        case .idle, .exporting:
            DockShelfTheme.border
        case .receivingValid, .success, .restored:
            DockShelfTheme.accent
        case .receivingInvalid, .invalid:
            DockShelfTheme.invalid
        case .returningShelfItem, .replaced, .partial, .duplicate, .tooMany, .insufficientReplaceable:
            DockShelfTheme.warning
        }
    }

    private var emptyStateColor: Color {
        switch interaction.phase {
        case .idle, .partial, .returningShelfItem, .exporting, .duplicate, .tooMany, .insufficientReplaceable:
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
            if store.items.count >= ShelfStore.maximumItemCount {
                store.items.allSatisfy(\.isPinned)
                    ? "固定项已满，新项目需先腾出位置"
                    : "已满，加入新项目可能替换较早的临时引用"
            } else {
                "只添加引用，内容仍在原位置"
            }
        }
    }

    private var emptyStateTitle: String {
        interaction.phase == .success ? "已搁好" : "把文件或文件夹先搁这儿"
    }

    private var emptyStateSubtitle: String {
        interaction.phase == .success ? "需要时再拖出去" : "原文件不会移动，需要时再拖出去"
    }
}

private struct ShelfImportIssuesView: View {
    let issues: [ShelfImportIssue]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("未加入的项目")
                .font(.headline)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(issues) { issue in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(issue.displayName)
                                .font(.callout.weight(.medium))
                                .lineLimit(2)
                            Text(issue.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let url = issue.url {
                                Text(url.path)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: min(240, CGFloat(issues.count) * 82))
            Text("详情仅留在本机，原文件不会被修改。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 320)
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
    private enum FocusTarget: Hashable {
        case tile
        case pin
        case remove
    }

    let item: ShelfItem
    let refreshDate: Date
    @ObservedObject var interaction: ShelfInteractionState
    let inspect: (Bool) -> Void
    let togglePinned: () -> Void
    let remove: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    @State private var fileExists = true
    @State private var fileIcon: NSImage?
    @FocusState private var focusTarget: FocusTarget?

    var body: some View {
        let exists = fileExists
        let showsControls = isHovered || focusTarget != nil
        let isEmphasized = isHovered || focusTarget != nil
        let tile = VStack(spacing: 5) {
            Image(nsImage: fileIcon ?? NSImage())
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: DockShelfMetrics.iconSize, height: DockShelfMetrics.iconSize)
                .opacity(exists ? 1 : 0.42)
                .accessibilityHidden(true)

            Text(item.displayName)
                .font(.caption.weight(.medium))
                .foregroundStyle(exists ? .primary : .secondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 24, alignment: .top)
                .opacity(showsControls ? 0 : 1)
                .accessibilityHidden(showsControls)
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
        .frame(width: DockShelfMetrics.itemWidth, height: DockShelfMetrics.itemHeight, alignment: .top)
        .background(
            DockShelfTheme.itemBackground.opacity(isEmphasized ? 0.86 : 0.64),
            in: RoundedRectangle(cornerRadius: DockShelfMetrics.itemRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DockShelfMetrics.itemRadius, style: .continuous)
                .strokeBorder(
                    exists
                        ? (isEmphasized ? DockShelfTheme.accent.opacity(0.68) : DockShelfTheme.border)
                        : DockShelfTheme.invalid,
                    lineWidth: isEmphasized ? 1.5 : 1
                )
        }
        .overlay(alignment: .bottom) {
            HStack(spacing: 4) {
                Button(action: togglePinned) {
                    Image(systemName: item.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .foregroundStyle(item.isPinned ? DockShelfTheme.accent : Color.secondary)
                .help(item.isPinned ? "取消固定" : "固定并在重启后保留")
                .accessibilityLabel(item.isPinned ? "取消固定 \(item.displayName)" : "固定 \(item.displayName)")
                .focused($focusTarget, equals: .pin)

                Button(action: remove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .foregroundStyle(.secondary)
                .help("移除引用")
                .accessibilityLabel("移除 \(item.displayName)")
                .focused($focusTarget, equals: .remove)
            }
            .buttonStyle(.plain)
            .symbolRenderingMode(.hierarchical)
            .opacity(showsControls ? 1 : 0)
            .accessibilityHidden(!showsControls)
            .allowsHitTesting(showsControls)
        }
        .overlay(alignment: .topLeading) {
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DockShelfTheme.accent)
                    .padding(5)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
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
        .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
        .help(exists ? item.url.path : "原文件已移动、删除或暂不可访问\n\(item.url.path)")
        .contentShape(RoundedRectangle(cornerRadius: DockShelfMetrics.itemRadius, style: .continuous))
        .focusable()
        .focused($focusTarget, equals: .tile)
        .contextMenu {
            Button("在 Finder 中显示") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
            .disabled(!exists)
            Divider()
            Button(item.isPinned ? "取消固定" : "固定") {
                togglePinned()
            }
            Button("移除引用", role: .destructive) {
                remove()
            }
        }
        .onAppear { refreshFileMetadata() }
        .onChange(of: refreshDate) { _, _ in refreshFileMetadata() }
        .onHover { isHovered = $0 }
        .onChange(of: isHovered) { _, _ in inspect(isHovered || focusTarget != nil) }
        .onChange(of: focusTarget) { _, _ in inspect(isHovered || focusTarget != nil) }
        .onDisappear { inspect(false) }
        .animation(
            reduceMotion
                ? nil
                : .easeOut(duration: 0.12),
            value: isEmphasized
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(item.displayName)，\(item.url.deletingLastPathComponent().path)")
        .accessibilityValue(item.isPinned ? "已固定" : "临时文件")
        .accessibilityHint(
            exists
                ? "按住并拖动到其他窗口"
                : "原文件已移动、删除或暂不可访问"
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

    private func refreshFileMetadata() {
        let exists = item.exists
        if fileIcon == nil || exists != fileExists {
            fileIcon = NSWorkspace.shared.icon(forFile: item.url.path)
        }
        fileExists = exists
    }
}
