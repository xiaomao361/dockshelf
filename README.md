# 搁这儿

“搁这儿”是一个 macOS 菜单栏文件暂存工具：把待会儿要用的文件主动拖进搁板，需要时再拖到 Finder、浏览器、聊天或邮件应用。

## 产品形态

- 只做 macOS，不以跨平台代码复用为目标。
- 没有普通主窗口和可见 Dock 图标，只有菜单栏入口与临时浮动搁板。
- 点击图标管理文件；有内容时悬停图标可展开；面板关闭时把文件拖到图标会自动展开。
- 文件与文件夹拖入后只保存原位置引用，不复制、移动或上传内容。
- 最多保存 20 项；固定项跨重启保留，普通项退出清空；容量不足时替换最早的未固定项并允许撤销。
- 不记录剪贴板历史，不做搜索、分类、同步或资料库。

## 当前状态

macOS 原生核心交互闭环已经可用，并在本轮由用户确认整体效果和功能可用。当前实现包括菜单栏拖入唤出、文件夹支持、固定持久化、容量替换与撤销、悬停取出、水平滚动、原生玻璃材质、菜单栏选中反馈、自适应面板锚点，以及同源的状态栏 icon / App icon / Logo。

这不等于完整发布验收已经完成。浏览器、聊天/邮件、特殊路径、失效引用和多显示器仍需针对同一候选构建执行正式矩阵。

- 实现与验收边界：[`docs/NATIVE_M0.md`](docs/NATIVE_M0.md)
- 视觉决策：[`docs/DESIGN_DIRECTION.md`](docs/DESIGN_DIRECTION.md)
- 品牌资产：[`docs/brand/`](docs/brand/README.md)
- 跨窗口续接：[`HANDOFF.md`](HANDOFF.md)
- Flutter 历史归档：[`archive/flutter-m0-probe/`](archive/flutter-m0-probe/ARCHIVE.md)

## 技术栈

- Swift
- AppKit：`NSStatusItem`、`NSPanel`、系统拖放与应用生命周期
- SwiftUI：搁板内容与交互状态
- macOS 26 使用 `NSGlassEffectView`；macOS 14–15 降级到 `NSVisualEffectView`

项目当前没有第三方运行时依赖。

## 构建与运行

```bash
cd /Volumes/E61/Developer/Workspaces/dockshelf

xcodebuild \
  -project DockShelf.xcodeproj \
  -scheme DockShelf \
  -configuration Debug \
  -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build

open -n '.build/DerivedData/Build/Products/Debug/搁这儿.app'
```

调试时需要启动后立即显示搁板，可追加：

```bash
open -n '.build/DerivedData/Build/Products/Debug/搁这儿.app' --args --show-shelf
```

当前尚未完成 Developer ID 签名、公证、安装包或对外发布。
