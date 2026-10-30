import AppKit
import SwiftUI
import QuickLookThumbnailing

private struct FeedbackContent {
    let title: String
    var subtitle: String? = nil
    let symbol: String
    let color: Color
    var canUndo = false
    var canDismiss = false
}

struct ShelfView: View {
    @ObservedObject var store: ShelfStore
    @ObservedObject var interaction: ShelfInteractionState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var showsRecovery = false
    @State private var showsRestoreConfirmation = false
    @State private var showsClearAllConfirmation = false
    @State private var inspectedItemID: String?
    @State private var scrollItemID: String?
    @State private var shelfUnfolded = false

    var body: some View {
        ZStack(alignment: .bottom) {
            FoldingShelfMaterial(unfolded: shelfUnfolded, reduceMotion: reduceMotion, receiving: interaction.phase == .receivingValid)
                .padding(.horizontal, 12)
                .frame(height: 22)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 92)

            if interaction.phase == .receivingValid {
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(colors: [DockShelfTheme.accent.opacity(0.025), DockShelfTheme.accent.opacity(0.12)], startPoint: .top, endPoint: .bottom))
                    .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(DockShelfTheme.accent.opacity(0.32), style: StrokeStyle(lineWidth: 1, dash: [4, 4])) }
                    .frame(height: 110)
                    .padding(.horizontal, 12)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 10)
                    .allowsHitTesting(false)
            }

            shelfContent
                .opacity(showsDropPrompt ? 0.45 : 1)

            if showsDropPrompt {
                dropPrompt
                    .transition(.opacity)
            } else if let feedback = transientFeedback {
                feedbackBanner(feedback)
                    .transition(feedbackTransition)
            }

            if transientFeedback == nil && !showsDropPrompt,
               let item = store.items.first(where: { $0.id == inspectedItemID }) {
                ShelfHoverName(name: item.displayName)
                    .padding(.bottom, 8)
                    .transition(.opacity)
            }

            if store.persistenceProblem != nil || store.accessWarning != nil || store.items.contains(where: { $0.access?.state != .ready }) {
                Button {
                    showsRecovery = true
                } label: {
                    Label(recoveryLabel, systemImage: "exclamationmark.circle")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
                .padding(.leading, 12)
                .padding(.top, 3)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .popover(isPresented: $showsRecovery) { recoveryDetails }
            }


        }
        .frame(width: DockShelfMetrics.panelSize.width, height: DockShelfMetrics.panelSize.height)
        .contentShape(RoundedRectangle(cornerRadius: DockShelfMetrics.panelRadius, style: .continuous))
        .contextMenu {
            Button("帮助与关于…") { interaction.helpRequested?() }
            Divider()
            Button("移除全部临时引用") {
                store.clearTemporaryItems()
            }
            .disabled(!store.items.contains { !$0.isPinned })

            Button("移除全部引用…", role: .destructive) {
                showsClearAllConfirmation = true
            }
            .disabled(store.items.isEmpty || !store.canModifyPinnedReferences)
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
        .onAppear { updateShelfFold(interaction.isPanelVisible) }
        .onChange(of: interaction.isPanelVisible) { _, visible in updateShelfFold(visible) }
        .onChange(of: showsRecovery) { _, visible in interaction.isShowingRecovery = visible }
        .onChange(of: interaction.isPanelVisible) { _, visible in
            if !visible { showsRecovery = false }
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
        .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: inspectedItemID)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: interaction.phase)
        .animation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.88), value: store.items.map(\.id))
        .accessibilityIdentifier("shelf-panel")
    }

    private func updateShelfFold(_ visible: Bool) {
        withAnimation(reduceMotion ? nil : .smooth(duration: visible ? ShelfMotion.unfold : ShelfMotion.fold)) { shelfUnfolded = visible }
    }

    @ViewBuilder
    private var shelfContent: some View {
        if store.items.isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: DockShelfMetrics.itemSpacing) {
                            ForEach(store.items) { item in
                                ShelfItemTile(
                                    item: item,
                                    canModifyPinnedReferences: store.canModifyPinnedReferences,
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
                                    insertion: .opacity.combined(with: .offset(y: -18)),
                                    removal: .opacity
                                ))
                            }
                        }
                        .scrollTargetLayout()
                        .padding(.horizontal, DockShelfMetrics.horizontalPadding)
                        .frame(minWidth: DockShelfMetrics.panelSize.width, alignment: store.items.count <= 5 ? .center : .leading)
                        .padding(.top, DockShelfMetrics.tileTop)
                        .padding(.bottom, 4)
                    }
                    .frame(height: DockShelfMetrics.contentHeight)
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
                    HStack {
                        if store.items.count > 5 && transientFeedback == nil && !showsDropPrompt {
                            pageButton("向左翻动", symbol: "chevron.left") { scrollPage(-1, proxy: proxy) }
                            Spacer(minLength: 0)
                            pageButton("向右翻动", symbol: "chevron.right") { scrollPage(1, proxy: proxy) }
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(height: DockShelfMetrics.footerHeight)
                }

            }
        }
    }

    private func pageButton(_ label: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .frame(width: DockShelfMetrics.footerButtonSize, height: DockShelfMetrics.footerButtonSize)
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
        Image(systemName: "arrow.down")
            .font(.system(size: 18, weight: .light))
            .foregroundStyle(.secondary)
            .frame(width: 38, height: 38)
            .background(.regularMaterial, in: Circle())
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 44)
            .help(emptyStateSubtitle)
            .accessibilityLabel(emptyStateTitle)
    }

    private var dropPrompt: some View {
        Label(dropPromptTitle, systemImage: dropPromptSymbol)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(dropPromptColor)
            .padding(.horizontal, 13).padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 45)
            .accessibilityHint(dropPromptSubtitle)
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

    private var recoveryLabel: String {
        if store.persistenceProblem == .saveFailed { return "固定更改未保存" }
        if store.persistenceProblem != nil { return "固定记录需恢复" }
        if store.accessWarning != nil { return "未能固定" }
        return "需要重新授权"
    }

    private var recoveryDetails: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("固定与访问恢复").font(.headline)
            if let problem = store.persistenceProblem {
                Text(problem.message).font(.callout)
                Button(problem == .saveFailed ? "重试保存或读取" : "重试读取") { store.retryPersistence() }
                if store.canRestoreBackup {
                    Button("恢复上一次备份…") { showsRestoreConfirmation = true }
                        .confirmationDialog("恢复上一次固定记录？", isPresented: $showsRestoreConfirmation) {
                            Button("恢复备份") { store.restorePinnedBackup() }
                            Button("取消", role: .cancel) {}
                        } message: {
                            Text("当前无法读取的记录会保留副本。备份之后的固定更改可能不在备份中。")
                        }
                }
            }
            if let warning = store.accessWarning {
                Text(warning).font(.callout)
                Button("知道了") { store.dismissAccessWarning() }
            }
            if store.items.contains(where: { $0.access?.state != .ready }) {
                Text("备份中的部分访问权限未恢复。选择所在文件夹，即可一起恢复其中记录的项目，无需逐个选文件。")
                    .font(.caption)
                Button("选择所在文件夹，批量恢复…") {
                    requestReauthorization(store.items.filter { $0.access?.state != .ready }.map(\.id), usingFolders: true)
                }
                .disabled(store.pendingImportCount > 0 || !store.canModifyPinnedReferences)
                .accessibilityHint("选择一个或多个所在文件夹，只恢复已记录的项目")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(store.items.filter { $0.access?.state != .ready }) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.displayName).font(.callout.weight(.medium))
                            Text(item.access?.state.message ?? "请在恢复提示中选择所在文件夹授权").font(.caption)
                            Text(item.url.path).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                            HStack {
                                Button("单独选择文件…") { requestReauthorization([item.id]) }
                                    .disabled(store.pendingImportCount > 0 || !store.canModifyPinnedReferences)
                                    .accessibilityLabel("为\(item.displayName)选择原文件授权")
                                Button("移除引用") { store.remove(item) }
                            }
                        }.accessibilityElement(children: .contain)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 190)
            Text("固定记录和原文件不会因读取失败而清空。授权后保留原顺序、加入时间与固定状态。")
                .font(.caption).foregroundStyle(.secondary)
            Button("关闭") { showsRecovery = false }.keyboardShortcut(.cancelAction)
        }.padding(16).frame(width: 330)
    }

    private func requestReauthorization(_ ids: [String], usingFolders: Bool = false) {
        showsRecovery = false
        if usingFolders { interaction.folderReauthorizationRequested?(ids) }
        else { interaction.reauthorizationRequested?(ids) }
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
        case .processing:
            FeedbackContent(title: "正在检查文件引用…", subtitle: "外置卷或云盘暂不可用时可能需要等待", symbol: "hourglass", color: .secondary)
        case let .reauthorized(count):
            FeedbackContent(title: "已重新授权 \(count) 项", symbol: "checkmark", color: DockShelfTheme.accent, canDismiss: true)
        case .success:
            nil
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
                    , store.lastReauthorizedCount > 0 ? "\(store.lastReauthorizedCount) 项重新授权" : nil
                ].compactMap { $0 }.joined(separator: " · "),
                symbol: "exclamationmark.circle",
                color: DockShelfTheme.warning,
                canUndo: removed > 0,
                canDismiss: true
            )
        case .duplicate:
            FeedbackContent(
                title: store.lastReauthorizedCount > 0 ? "已重新授权 \(store.lastReauthorizedCount) 项，其余项目已存在" : "项目已经在搁板里",
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
            nil
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
        guard interaction.isPanelVisible else { return }
        let message: String
        if interaction.phase == .success {
            message = "已搁好 \(interaction.lastAddedCount) 项"
        } else if let feedback = transientFeedback, interaction.phase != .exporting {
            message = [feedback.title, feedback.subtitle].compactMap { $0 }.joined(separator: "，")
        } else { return }
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.medium.rawValue]
        )
    }

    private var panelBorder: Color {
        switch interaction.phase {
        case .idle, .processing, .exporting:
            DockShelfTheme.border
        case .receivingValid, .success, .reauthorized, .restored:
            DockShelfTheme.accent
        case .receivingInvalid, .invalid:
            DockShelfTheme.invalid
        case .returningShelfItem, .replaced, .partial, .duplicate, .tooMany, .insufficientReplaceable:
            DockShelfTheme.warning
        }
    }

    private var emptyStateColor: Color {
        switch interaction.phase {
        case .idle, .processing, .partial, .returningShelfItem, .exporting, .duplicate, .tooMany, .insufficientReplaceable:
            .secondary
        case .receivingValid, .success, .reauthorized, .replaced, .restored:
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
            "整块区域均可放入"
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
        if store.persistenceProblem == .saveFailed { return "固定更改尚未保存" }
        if store.persistenceProblem != nil { return "固定记录暂时无法读取" }
        return interaction.phase == .success ? "已搁好" : "把文件或文件夹先搁这儿"
    }

    private var emptyStateSubtitle: String {
        if store.persistenceProblem != nil { return "原记录已保留 · 点左上角提示处理\n临时引用仍可拖入使用" }
        return interaction.phase == .success ? "需要时再拖出去" : "拖入后需要时再拖出 · 点图钉固定\n临时项退出即清空，原文件不会移动"
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
    let canModifyPinnedReferences: Bool
    @ObservedObject var interaction: ShelfInteractionState
    let inspect: (Bool) -> Void
    let togglePinned: () -> Void
    let remove: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    @State private var fileExists = false
    @State private var hasCheckedAvailability = false
    @State private var availabilityMessage: String? = "正在检查原位置"
    @State private var fileIcon: NSImage?
    @State private var previewImage: NSImage?
    @State private var isDirectory = false
    @State private var isDragging = false
    @State private var hasLanded = false
    @FocusState private var focusTarget: FocusTarget?

    var body: some View {
        let exists = fileExists
        let showsControls = isHovered || focusTarget != nil
        let isEmphasized = isHovered || focusTarget != nil
        let tile = VStack(spacing: 0) {
            draggableFileIcon
                .frame(height: 78, alignment: .bottom)
        }
        .padding(.horizontal, 4)
        .frame(width: DockShelfMetrics.itemWidth, height: DockShelfMetrics.itemHeight, alignment: .top)
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
                .disabled(!canModifyPinnedReferences)

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
                .disabled(item.isPinned && !canModifyPinnedReferences)
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
            if !exists && hasCheckedAvailability {
                Circle()
                    .fill(DockShelfTheme.invalid)
                    .frame(width: 9, height: 9)
                    .padding(6)
                    .accessibilityHidden(true)
            }
        }
        .offset(y: hasLanded || reduceMotion ? 0 : -16)
        .opacity(hasLanded || reduceMotion ? 1 : 0)
        .task(id: interaction.isPanelVisible) {
            guard interaction.isPanelVisible else { isDragging = false; return }
            withAnimation(reduceMotion ? nil : .spring(response: ShelfMotion.settle, dampingFraction: 0.92)) { hasLanded = true }
        }
        .help(itemHelp)
        .contentShape(RoundedRectangle(cornerRadius: DockShelfMetrics.itemRadius, style: .continuous))
        .focusable()
        .focusEffectDisabled()
        .focused($focusTarget, equals: .tile)
        .contextMenu {
            Button("在 Finder 中显示") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
            .disabled(!exists)
            Divider()
            Button(item.isPinned ? "取消固定" : "固定") {
                togglePinned()
            }.disabled(!canModifyPinnedReferences)
            Button("移除引用", role: .destructive) {
                remove()
            }.disabled(item.isPinned && !canModifyPinnedReferences)
        }
        .task(id: refreshIdentity) { await refreshMetadataWhileVisible() }
        .onHover { isHovered = $0 }
        .task(id: inspectionIdentity) {
            guard interaction.isPanelVisible, !isDragging, isHovered || focusTarget != nil else {
                inspect(false); return
            }
            guard await ShelfHoverTiming.ready(keyboardFocused: focusTarget != nil),
                  !Task.isCancelled else { return }
            inspect(true)
        }
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
                : availabilityMessage ?? "请在恢复提示中选择所在文件夹授权"
        )
        .accessibilityAction(named: item.isPinned ? "取消固定" : "固定") {
            togglePinned()
        }
        .accessibilityAction(named: "移除引用") {
            remove()
        }

        tile
    }

    private var artworkKind: ShelfArtworkKind { ShelfArtworkKind(url: item.url, isDirectory: isDirectory) }

    @MainActor private var dragImage: NSImage {
        let renderer = ImageRenderer(content: ShelfFileArtwork(kind: artworkKind, preview: previewImage).frame(width: 64, height: 78))
        renderer.scale = 2
        return renderer.nsImage ?? fileIcon ?? NSImage()
    }

    private var draggableFileIcon: some View {
        ShelfFileObject(kind: artworkKind, preview: previewImage,
            lifted: isHovered && !reduceMotion,
            opacity: fileExists || !hasCheckedAvailability ? (isDragging ? 0.16 : 1) : 0.42,
            dragging: isDragging,
            hitLayer: Group {
                if fileExists {
                    ShelfNativeFileDrag(item: item, image: dragImage,
                        began: { isDragging = true; interaction.beginExport() },
                        ended: { accepted in
                            withAnimation(reduceMotion ? nil : .smooth(duration: 0.18)) { isDragging = false }
                            interaction.exportEnded?(accepted)
                        })
                }
            })
            .accessibilityLabel("拖动 \(item.displayName)")
    }

    private var inspectionIdentity: String {
        "\(interaction.isPanelVisible)-\(isHovered)-\(focusTarget != nil)-\(isDragging)"
    }

    private var refreshIdentity: String {
        let identity = item.access.map { String(describing: ObjectIdentifier($0)) } ?? "none"
        return "\(identity)-\(interaction.isPanelVisible)"
    }

    private var itemHelp: String {
        fileExists ? item.url.path : "\(availabilityMessage ?? "请在恢复提示中选择所在文件夹授权")\n\(item.url.path)"
    }

    @MainActor
    private func refreshMetadataWhileVisible() async {
        guard interaction.isPanelVisible else { return }
        while !Task.isCancelled {
            let access = item.access
            let url = item.url
            let previousIcon = fileIcon
            let previousExists = fileExists
            let canRead = access?.canReadCurrentSession == true
            let accessMessage = access?.state.message
            let metadata = await Task.detached(priority: .utility) { () -> ShelfTileMetadata in
                _ = access // Retain the scope; mutable access state is read only on the UI actor.
                let status = canRead ? ShelfFileAvailability.inspect(access?.url ?? url) : .accessDenied
                let icon = status == .available && (previousIcon == nil || !previousExists)
                    ? NSWorkspace.shared.icon(forFile: (access?.url ?? url).path) : previousIcon
                return ShelfTileMetadata(status: status, icon: icon, isDirectory: (try? (access?.url ?? url).resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true)
            }.value
            guard !Task.isCancelled else { return }
            hasCheckedAvailability = true
            fileExists = metadata.status == .available
            isDirectory = metadata.isDirectory
            availabilityMessage = accessMessage ?? metadata.status.message
            if let icon = metadata.icon { fileIcon = icon }
            if fileExists && artworkKind.supportsPreview && (previousIcon == nil || !previousExists) {
                // Publish availability first: a slow preview must not block dragging.
                let request = QLThumbnailGenerator.Request(fileAt: access?.url ?? url,
                    size: CGSize(width: 112, height: 112), scale: 2, representationTypes: .all)
                let preview: NSImage? = await withCheckedContinuation { continuation in
                    QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                        continuation.resume(returning: representation?.nsImage)
                    }
                }
                guard !Task.isCancelled else { return }
                // Unsupported previews keep the file icon and the real availability result.
                if let preview { previewImage = preview }
            }
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
        }
    }

}

private struct ShelfTileMetadata: @unchecked Sendable {
    let status: ShelfFileAvailability
    let icon: NSImage?
    let isDirectory: Bool
}


/// AppKit owns pointer tracking and cancelled-drag snapback; the source retains only a reference.
private struct ShelfNativeFileDrag: NSViewRepresentable {
    let item: ShelfItem
    let image: NSImage
    let began: () -> Void
    let ended: (Bool) -> Void

    func makeNSView(context: Context) -> FileDragView { FileDragView() }
    func updateNSView(_ view: FileDragView, context: Context) {
        view.item = item; view.image = image; view.began = began; view.ended = ended
    }

    final class FileDragView: NSView, NSDraggingSource {
        var item: ShelfItem?
        var image = NSImage()
        var began: (() -> Void)?
        var ended: ((Bool) -> Void)?
        private var downEvent: NSEvent?
        private var retainedAccess: ShelfFileAccess?

        override func mouseDown(with event: NSEvent) { downEvent = event }
        override func mouseUp(with event: NSEvent) { downEvent = nil }
        override func mouseDragged(with event: NSEvent) {
            guard let downEvent, let item,
                  hypot(event.locationInWindow.x - downEvent.locationInWindow.x,
                        event.locationInWindow.y - downEvent.locationInWindow.y) > 4 else { return }
            self.downEvent = nil
            retainedAccess = item.access
            let writer = NSPasteboardItem()
            writer.setString((item.access?.url ?? item.url).absoluteString, forType: .fileURL)
            writer.setString(item.id, forType: ShelfImport.sourceType)
            let draggingItem = NSDraggingItem(pasteboardWriter: writer)
            draggingItem.setDraggingFrame(NSRect(x: 0, y: 0, width: 64, height: 78), contents: image)
            let session = beginDraggingSession(with: [draggingItem], event: event, source: self)
            session.animatesToStartingPositionsOnCancelOrFail = true
            session.draggingFormation = .none
            began?()
        }
        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            retainedAccess = nil
            ended?(!operation.isEmpty)
        }
        func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
    }
}
