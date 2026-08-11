# DockShelf 跨窗口交接

更新时间：2026-08-11（Asia/Shanghai）

## 下一窗口先做什么

从当前已确认的 macOS 原生版本继续，不再重启 Flutter 或视觉方向探索。先针对同一个候选构建完成一轮精简的人工验收矩阵；通过后再制作可长期自用的本地应用。

## 权威位置

```text
源码仓库：/Volumes/E61/Developer/Workspaces/dockshelf
远端：git@github.com:xiaomao361/dockshelf.git
当前开发分支：codex/m0-probe
Figma：https://www.figma.com/design/OcZQnKy9TeNDES4stN49Fp
```

Codex 默认目录 `/Users/zhouwei/Documents/ClaraCore/apps/dockshelf` 是主 worktree/资料入口，不是当前原生源码工作区。开始任何代码操作前先 `cd` 到上述外置盘路径，并重新核对分支和工作树。

## 当前状态

- 产品只做 macOS 菜单栏形态，没有普通主窗口和 Dock 图标。
- 技术栈为 Swift + AppKit + SwiftUI，无第三方运行时依赖。
- Flutter 探针已停止并完整归档到 `archive/flutter-m0-probe/`。
- 核心交互闭环已经可用，用户确认整体功能和最终视觉效果良好。
- 当前最远验证层：Debug/Release 构建、本地进程启动、核心交互人工体验。
- 尚未签名、公证、制作安装包或发布。

## 已确认的产品与设计决策

- 只保存原文件引用，不复制、移动或上传内容。
- 当前只接收文件，不接收文件夹；同一路径去重，最多 20 项，退出后清空。
- 文件拖到菜单栏图标时，即使面板关闭也会自动展开接收界面。
- 拖入完成后面板自动收起；有内容时悬停图标可展开并向外拖出。
- 文件列表横向排列，鼠标纵向滚轮映射为横向滚动。
- 使用系统文件图标、系统字体、系统语义色和原生毛玻璃。
- 唯一继续使用的定制视觉资产是 A · Ledge Tabs 菜单栏 Template Icon。
- 面板打开时图标保持系统选中态；面板优先靠左锚定，空间不足时靠右。
- 面板尺寸 420 × 146 pt，与菜单栏的计算间距为 12 pt。
- 不恢复 Figma 暖黄配色、装饰性承托横线或大面板方向。

## 关键源码

- `DockShelf/StatusBarController.swift`：菜单栏图标、点击/悬停/拖入入口和右键菜单。
- `DockShelf/ShelfPanelController.swift`：面板会话状态、定位、选中态、收起时机和进出场动画。
- `DockShelf/ShelfView.swift`：玻璃材质、横向列表、滚轮映射、文件卡片和拖放反馈。
- `DockShelf/ShelfStore.swift`：20 项内存引用、去重、移除和清空。
- `docs/NATIVE_M0.md`：实现与验收边界。
- `docs/DESIGN_DIRECTION.md`：最终生产视觉决策。

## 构建与启动

```bash
cd /Volumes/E61/Developer/Workspaces/dockshelf

xcodebuild \
  -project DockShelf.xcodeproj \
  -scheme DockShelf \
  -configuration Debug \
  -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build

open -n '.build/DerivedData/Build/Products/Debug/搁这儿.app' --args --show-shelf
```

## 下一轮验收

最小矩阵：

1. Finder 单文件和多文件拖入；
2. 面板关闭时拖到图标、放入后自动收起；
3. 悬停展开后拖回 Finder；
4. 拖到浏览器上传区和一个真实聊天或邮件应用；
5. 20 项时鼠标滚轮与触控板滚动；
6. 中文/空格路径、删除源文件后的失效状态；
7. 浅色/深色、减少动态效果和多显示器位置。

验收时只记录真实结果，不因构建成功推导跨应用行为。若矩阵通过，下一步是决定本地安装形态、Bundle 版本、Developer ID 签名与公证；它们都不在本次收口范围内。

## 不要做

- 不恢复 Flutter 或优先考虑 Windows。
- 不把产品扩成剪贴板历史、文件管理器、搜索分类或云同步工具。
- 不在未验证当前候选构建前继续大改视觉。
- 不删除 Flutter 归档、Figma 文件或现有设计资产。
