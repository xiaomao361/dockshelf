# DockShelf / 搁这儿 项目交接

更新时间：2026-08-11（Asia/Shanghai）

## 当前结论

“搁这儿”已经完成一个可日常使用的 macOS 原生菜单栏版本。本阶段已收口核心拖放、20 项容量、固定持久化、自动替换与撤销、文件夹支持、错误恢复、状态栏命中区，以及统一的状态栏 icon / App icon / Logo。

当前最远验证层是：**Debug/Release 构建、隔离模型冒烟测试、资源编译、真实进程启动、真实菜单栏 18 pt 视觉检查，以及用户对核心交互的人工体验**。

这不等于正式发布完成。尚未进行 Developer ID 签名、公证、安装包、自动更新或对外发布。

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
- 尚未对浏览器、全部聊天/邮件应用、特殊路径、多显示器和辅助功能组合做正式逐项发布验收；
- 尚未签名、公证或验证 Gatekeeper，构建成功不能推导为可分发版本。

## 下一步建议

若继续自用发布，下一阶段只做一个小闭环：确定版本号与安装位置，使用 Developer ID 签名、公证，然后在隔离目录验证安装、首次启动、重启恢复和 Gatekeeper。不要同时扩展新产品功能。

## 不要做

- 不恢复 Flutter 或优先考虑 Windows；
- 不扩成剪贴板历史、文件管理器、搜索分类或云同步；
- 不删除 Flutter 归档、Figma 文件或品牌源资产；
- 不把本阶段构建与人工体验表述成已签名、已发布或已通过完整业务验收。
