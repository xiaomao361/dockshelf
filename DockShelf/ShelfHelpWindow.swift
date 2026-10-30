import AppKit
import SwiftUI

/// One auxiliary window shared by the menu and the shelf's help button.
/// It is created only when requested, and reused after closing.
@MainActor
final class ShelfHelpWindowController: NSWindowController {
    init(shortcut: ShelfShortcut) {
        let panel = ShelfHelpPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 540),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.shortcut = shortcut
        panel.title = "帮助与关于搁这儿"
        panel.identifier = NSUserInterfaceItemIdentifier("DockShelf.HelpAbout")
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = false
        panel.hidesOnDeactivate = false
        panel.contentMinSize = NSSize(width: 400, height: 360)
        panel.contentView = NSHostingView(rootView: ShelfHelpView(info: .live, shortcut: shortcut) { [weak panel] in panel?.close() })
        panel.center()
        super.init(window: panel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init()") }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

private final class ShelfHelpPanel: NSPanel {
    var shortcut: ShelfShortcut?

    override func close() {
        shortcut?.cancelRecording()
        super.close()
    }
    override func resignKey() {
        shortcut?.cancelRecording()
        super.resignKey()
    }
    override func cancelOperation(_ sender: Any?) {
        if shortcut?.isRecording == true { shortcut?.cancelRecording() }
        else { close() }
    }
    override func sendEvent(_ event: NSEvent) {
        if captureShortcut(event) { return }
        super.sendEvent(event)
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if captureShortcut(event) { return true }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers == .command, event.charactersIgnoringModifiers == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
    // Scoped to this panel while the user explicitly arms the recorder.
    // No event tap, global keyboard monitor, or accessibility permission.
    private func captureShortcut(_ event: NSEvent) -> Bool {
        guard let shortcut, shortcut.isRecording, event.type == .keyDown else { return false }
        guard !event.isARepeat else { return true }
        if event.keyCode == 53 { shortcut.cancelRecording() }
        else if let binding = ShelfShortcutBinding.capture(event) { shortcut.apply(binding) }
        else { shortcut.rejectRecording() }
        return true
    }
}

private struct ShelfHelpInformation {
    let versionDescription: String
    let copyright: String?
    let icon: NSImage?

    static var live: Self {
        let bundle = Bundle.main
        let description: String
        if let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            if let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String {
                description = "版本 \(version)（\(build)）"
            } else { description = "版本 \(version)" }
        } else { description = "版本信息暂不可用" }
        return Self(versionDescription: description,
                    copyright: bundle.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String,
                    icon: NSImage(named: NSImage.applicationIconName))
    }

#if DEBUG
    static var preview: Self {
        Self(versionDescription: "版本 0.1.5（2026102105）",
             copyright: "Copyright © 2026 Zhou Wei. All rights reserved.",
             icon: NSImage(named: "AppIcon"))
    }
#endif
}

private struct ShelfHelpView: View {
    let info: ShelfHelpInformation
    let close: () -> Void
    @ObservedObject var shortcut: ShelfShortcut
    @State private var privacyExpanded: Bool

    init(info: ShelfHelpInformation, shortcut: ShelfShortcut, privacyExpanded: Bool = false, close: @escaping () -> Void) {
        self.info = info
        self.shortcut = shortcut
        self.close = close
        _privacyExpanded = State(initialValue: privacyExpanded)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    appIdentity
                    Divider()
                    usage
                    Divider()
                    DisclosureGroup("隐私与本地存储", isExpanded: $privacyExpanded) {
                        privacy
                            .padding(.top, 10)
                    }
                    .font(.body.weight(.medium))
                    .accessibilityIdentifier("help-privacy-disclosure")
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                Link("反馈问题", destination: URL(string: "https://github.com/xiaomao361/dockshelf/issues")!)
                    .help("在默认浏览器中打开 GitHub Issues")
                    .accessibilityHint("在默认浏览器中打开 GitHub Issues")
                Spacer()
                Button("关闭", action: closeOrCancelRecording)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 400, minHeight: 360)
        .onExitCommand(perform: closeOrCancelRecording)
        .accessibilityIdentifier("help-about-window")
    }

    private var appIdentity: some View {
        HStack(spacing: 16) {
            if let image = info.icon {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("搁这儿")
                    .font(.system(size: 23, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(info.versionDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if let copyright = info.copyright {
                    Text(copyright)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var usage: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("先搁好，需要时再拖走")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            instruction("拖入", detail: "拖到菜单栏图标，或放入自动展开的搁板。")
            instruction("取用", detail: "把卡片图标拖到 Finder、上传区或其他应用。")
            instruction("固定", detail: "临时引用退出清空；点图钉固定，重启仍保留。")
            Text("最多 \(ShelfStore.maximumItemCount) 项，满时替换最早未固定项，可撤销。\n固定项受保护，移除引用不会删除原文件。")
                .font(.callout)
                .foregroundStyle(.secondary)
            shortcutEditor

        }
    }

    private func closeOrCancelRecording() {
        if shortcut.isRecording { shortcut.cancelRecording() }
        else { close() }
    }

    private var shortcutEditor: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text("打开搁板")
                Button {
                    if shortcut.isRecording { shortcut.cancelRecording() }
                    else { shortcut.beginRecording() }
                } label: {
                    Text(shortcut.isRecording ? "请按组合键…" : shortcut.configuration.display)
                        .font(.callout.monospaced())
                }
                .accessibilityLabel(shortcut.isRecording ? "取消录入快捷键" : "修改打开搁板快捷键，" + shortcut.configuration.accessibilityLabel)
                .help(shortcut.isRecording ? "按 Esc 取消" : "点击后按新的组合键")
                .accessibilityIdentifier("shelf-shortcut-recorder")
                Spacer(minLength: 0)
            }
            HStack(spacing: 14) {
                if shortcut.isRecording {
                    Button("取消录入", action: shortcut.cancelRecording)
                } else {
                    Button("恢复默认") { shortcut.apply(.standard) }
                        .disabled(shortcut.configuration == .standard && !shortcut.hasProblem)
                    if shortcut.hasProblem {
                        Button("重试启用", action: shortcut.retryRegistration)
                    }
                }
            }
            .buttonStyle(.link)
            Text(shortcut.statusText)
                .font(.caption)
                .foregroundStyle(shortcut.hasProblem && !shortcut.isRecording ? Color.orange : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("shelf-shortcut-status")
        }
        .font(.callout)
    }

    private func instruction(_ title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.callout.weight(.medium))
                .fixedSize(horizontal: true, vertical: false)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private var privacy: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("快捷键可自行修改，组合保存在本机。只在点击修改后接收本窗口的组合键，离开窗口即结束录入；不监听其他应用的普通键入。")
            Text("只在本机保存引用与偏好。固定项还保存用于重启访问的只读书签；不会复制、移动或修改原文件。")
            Text("无账号、遥测、后台网络请求或云同步。拖给其他应用后，由目标应用处理文件。反馈问题会在你选择后通过浏览器打开 GitHub。")
            Text("导入失败详情只在当前会话显示，不写入诊断日志。固定记录的迁移与恢复副本留在本机；移除当前引用不会清除这些副本。")
            Text("文件换了位置时，移除旧引用后从新位置拖入；权限未恢复时，可在恢复提示中选择所在文件夹批量恢复，无需逐个选择源文件。")
            Text("导出备份包含固定引用、顺序、加入时间和已有访问书签，不包含原文件或临时项。重新导入时会尝试恢复权限；失效部分可按所在文件夹批量恢复。备份留在本机应用目录，包含私人路径和授权信息，请妥善保管；跨Mac或不同用户不保证授权可复用。")
        }
        .font(.callout)
        .fontWeight(.regular)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }
}

#if DEBUG
@MainActor
private final class PreviewShortcutDriver: ShelfShortcutDriver {
    var action: (() -> Void)?
    func register(_ binding: ShelfShortcutBinding) -> Int32 { 0 }
    func unregister() -> Int32 { 0 }
}
@MainActor
private func previewShortcut() -> ShelfShortcut {
    ShelfShortcut(storage: ShelfShortcutStorage(load: { .standard }, save: { _ in }),
                  driver: PreviewShortcutDriver(), action: {})
}

#Preview("帮助与关于") {
    ShelfHelpView(info: .preview, shortcut: previewShortcut(), close: {})
        .frame(width: 460, height: 540)
}

#Preview("展开隐私说明") {
    ShelfHelpView(info: .preview, shortcut: previewShortcut(), privacyExpanded: true, close: {})
        .frame(width: 460, height: 540)
}
#endif
