# DockShelf / 搁这儿 项目交接

更新时间：2026-09-15（Asia/Shanghai）

## 最新续接：v0.1.4 发布收口

用户确认本轮方向，并授权收口、签名和 GitHub Release。源码版本固定为 0.1.4（2026091504），正式 Release 已发布并完成公开下载复验，发布说明见 `docs/RELEASE_NOTES_v0.1.4.md`，签名与分发证据见 `docs/RELEASE_v0.1.4.md`。此前 0.1.1–0.1.4 候选回执是历史记录；正式分发包位于 `.build/releases/v0.1.4/`。

## 本次功能：0.1.4 定位与收起修正

自动拖拽和备用快捷键均固定在菜单栏图标下方展开。成功放入后约 0.35 秒开始收起，悬停不会再取消完成计时；取消拖拽在释放鼠标后收起。部分失败和替换撤销保留反馈。独立计时回归与 Debug 构建通过，真实交互待用户安装验收。详见 `docs/AUTOMATIC_DRAG.md`。

## 历史 0.1.3：拖动文件自动展开

用户明确要求简化为拖起文件即自动弹出。0.1.3（2026091503）候选默认开启自动展开：以鼠标按下起点、拖拽粘贴板新所有者/文件类型、8 pt 位移与 120 ms 防抖识别文件拖拽，在鼠标旁仅展开一次，不激活来源应用、不追随光标；松开后自动收起，实际接收结果保留原反馈与撤销。右键可关闭；全局快捷键降为备用。详见 `docs/AUTOMATIC_DRAG.md`，真实系统事件与 Finder 拖放仍待用户验收。

## 前次续接：macOS 27 兼容候选

用户安装 0.1.1 后报告真实拖入失败及屏幕顶边 Mission Control 冲突。本轮把面板与状态栏收件统一为 AppKit/NSPasteboard 原始 NSURL 路径；移除面板的 SwiftUI DropInfo/NSItemProvider 转换及异步超时实现。新增 Control–Option–空格，在鼠标旁展开面板并保持拖拽来源应用。当时安装候选版本为 0.1.2（2026091502），详见 `docs/MACOS27_COMPATIBILITY.md`。未证明失败的唯一根因，也未完成用户真实拖放验收。

## 前次续接：2026-09-15 精修候选

用户授权在现有原生方向上整体精修。当前工作树包含旧有五个文件修改及本轮修复，尚未提交、安装或发布。新候选内容和验收边界以 `docs/REFINEMENT_2026-09-15.md` 为准；下面的签名、公证和人工通过记录仅对应历史 v0.1.0。

本轮已实现：明确的部分导入结果、异步顺序与超时、撤销按钮同步、监听清理、完整路径与 Finder 入口、列表滚动定位、底部反馈独立布局、克制悬停效果、仅可见时刷新和图标缓存。

## v0.1.0 历史结论

“搁这儿”已经完成一个可日常使用的 macOS 原生菜单栏版本。本阶段已收口核心拖放、20 项容量、固定持久化、自动替换与撤销、文件夹支持、错误恢复、状态栏命中区，以及统一的状态栏 icon / App icon / Logo。

当前最远验证层是：**Debug/Release 构建、隔离模型冒烟测试、资源编译、真实进程启动、真实菜单栏 18 pt 视觉检查，以及用户对核心交互的人工体验**。

v0.1.0 已完成 Developer ID 签名、App 与 DMG 双层公证、stapling、Gatekeeper 验证、GitHub Release 发布和公开下载复验。自动更新与 Mac App Store 仍不在本版本范围内。

## v0.1.0 发布回执

```text
Release：https://github.com/xiaomao361/dockshelf/releases/tag/v0.1.0
Tag commit：510398f1e6e3d74e69f39e1da0fe90e489bbd552
产物：DockShelf-0.1.0-macos-arm64.dmg
SHA-256：b9d46788370780382319141930aa9cd3f1e55a2a79bc496fbdfe8e6f3ab13c08
App 公证：ba1bdc9b-be33-4639-859b-17f9abb5a3e0（Accepted）
DMG 公证：eefccd7a-3531-4e86-abac-5b61b54f90a6（Accepted）
范围：Apple Silicon arm64，macOS 14+
```

## 权威位置

```text
源码仓库：/Volumes/E61/Developer/Workspaces/dockshelf
远端：git@github.com:xiaomao361/dockshelf.git
当前分支：codex/m0-probe
Figma：https://www.figma.com/design/OcZQnKy9TeNDES4stN49Fp
```

Codex 默认目录 `/Users/zhouwei/Documents/ClaraCore/apps/dockshelf` 是主 worktree/资料入口，不是当前原生源码工作区。任何代码操作前先进入外置盘仓库并重新核对分支、远端与工作树。

## 产品边界

- 仅做 macOS 菜单栏工具，没有普通主窗口和可见 Dock 图标；
- 保存本地文件或文件夹的引用，不复制、移动、上传或修改原内容；
- 不做剪贴板历史、搜索分类、云同步、资料库或跨平台扩展；
- 技术栈为 Swift + AppKit + SwiftUI，无第三方运行时依赖；
- Flutter 技术探针已停止并归档在 `archive/flutter-m0-probe/`。

## 已确认行为

### 引用与容量

- 接收现存的本地文件和文件夹，同一标准化路径去重；
- 搁板最多 20 项；
- 普通项仅当前会话保留；
- 固定项写入 `UserDefaults` 的 `DockShelf.pinnedItems.v1`，退出和重启后恢复；
- 超出 20 项时替换最早加入的未固定项；
- 固定项不参与自动替换；未固定项不足时整批拒绝；
- 自动替换保留一次完整快照，可恢复替换前的顺序与内容；
- 固定、移除、清空和替换均只修改引用，不触碰原文件。

### 拖放与面板

- 文件或文件夹拖到状态栏图标时，即使面板关闭也会立即展开；
- 状态栏图标为 18 pt，拖拽、悬停和点击命中宽度为 32 pt；
- 有内容时悬停 300 ms 展开；点击图标显示或收起；右键提供显示、清空和退出；
- 搁板内项目拖回自身会通过本进程来源标记拒绝，不产生文件夹临时副本或重复引用；
- 拖出结束后自动收起；手动打开时支持点击外部或 Esc 收起；
- 重复、无效、单批过多和固定项不足均有明确提示与“返回”；
- 面板固定为 420 × 146 pt，优先靠近图标左侧锚定，右侧空间不足时切换方向；
- 文件列表横向排列，触控板横向滚动，鼠标纵向滚轮映射为横向滚动。

### 品牌与视觉

- 状态栏 icon、App icon 和 Logo 共用“一张卡片刚刚落在搁板上”的 A2 骨架；
- 状态栏使用单色 Template Icon，面板打开时保持系统选中态；
- App icon 使用矿物青、乳白、石墨和接触点琥珀色，并提供 16–1024 px 完整槽位；
- 中文“搁这儿”为主 Logo；彩色、单色、独立 Mark 与 App icon 母版位于 `docs/brand/`；
- 面板继续使用系统字体、系统颜色、系统文件图标与原生玻璃材质，不把品牌色扩散到整个界面。

## 关键文件

- `DockShelf/StatusBarController.swift`：状态栏入口、点击/悬停/拖入与右键菜单；
- `DockShelf/ShelfPanelController.swift`：面板会话、定位、收起、选中态与动画；
- `DockShelf/ShelfInteractionState.swift`：拖放、反馈、替换和导出状态；
- `DockShelf/ShelfView.swift`：横向列表、文件卡片、固定、错误返回和拖放提供者；
- `DockShelf/ShelfStore.swift`：容量、去重、固定持久化、替换与撤销；
- `DockShelf/Assets.xcassets/`：生产状态栏图标与 AppIcon；
- `docs/brand/`：可复用品牌矢量源文件与颜色规则；
- `scripts/ShelfStoreSmoke.swift`：隔离的核心模型冒烟测试；
- `docs/NATIVE_M0.md`：实现与验收边界；
- `docs/DESIGN_DIRECTION.md`：生产视觉决策。

## 构建、测试与启动

```bash
cd /Volumes/E61/Developer/Workspaces/dockshelf

xcodebuild \
  -project DockShelf.xcodeproj \
  -scheme DockShelf \
  -configuration Debug \
  -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build

xcodebuild \
  -project DockShelf.xcodeproj \
  -scheme DockShelf \
  -configuration Release \
  -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build

xcrun swiftc -parse-as-library \
  DockShelf/ShelfStore.swift \
  scripts/ShelfStoreSmoke.swift \
  -o /tmp/dockshelf-store-smoke-bin

/tmp/dockshelf-store-smoke-bin

open -n '.build/DerivedData/Build/Products/Debug/搁这儿.app'
```

## 本阶段验证结果

- Debug 和 Release 构建通过；
- `ShelfStore smoke passed`：覆盖 20 项、同路径去重、固定、最早未固定替换、撤销顺序、重启恢复、全固定拒绝、超大批次拒绝和文件夹；
- Asset Catalog 无槽位错误，`Assets.car` 含 16、32、64、128、256、512、1024 px AppIcon；
- 构建产物包含 `AppIcon.icns`，`Info.plist` 含 `CFBundleIconName=AppIcon` 与 `LSUIElement=true`；
- 新状态栏 Template Icon 已在真实菜单栏 18 pt 下检查，轮廓清楚且不再形成原来的手势联想；
- 新版应用进程可以正常启动。

## 仍需注意

- 用户固定的是路径引用；原文件被移动或删除后会显示失效，不自动追踪新位置；
- 只持久化固定项，普通项退出即清空是产品决策，不是数据丢失 Bug；
- Logo 当前使用系统苹方字标；若未来用于跨平台官网、商店宣传或印刷，再决定是否轮廓化或定制字形；
- 尚未对全部浏览器、聊天/邮件应用、特殊路径、多显示器和辅助功能组合做正式逐项矩阵验收；
- v0.1.0 没有自动更新、开机启动、Intel Mac 或 Mac App Store 版本；
- 当前公开下载验证证明产物完整、签名、公证与 Gatekeeper 通过，不代表长期用户使用验收。

## 下一步建议

先观察 v0.1.0 的真实使用反馈。只有出现稳定需求时，再单独评估开机启动、自动更新或 Mac App Store 沙盒版本；不要同时扩展新产品功能。

## 不要做

- 不恢复 Flutter 或优先考虑 Windows；
- 不扩成剪贴板历史、文件管理器、搜索分类或云同步；
- 不删除 Flutter 归档、Figma 文件或品牌源资产；
- 不把已签名、已公证和已发布表述成已通过长期用户验收或 Mac App Store 审核。
