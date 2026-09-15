# 2026-09-15 交互与视觉精修候选

## 后续兼容修订

用户安装 0.1.1 后反馈持续导入失败及 macOS 27 顶边触发 Mission Control。以下异步导入实现和测试记录为 0.1.1 历史；当前候选已改为原生 NSHostingView 接收拖放并通过 NSPasteboard 读取 NSURL，增加 Control–Option–空格鼠标旁唤出。最新边界见 `MACOS27_COMPATIBILITY.md`。

## 0.1.1 结果与边界

在现有 Swift + AppKit + SwiftUI 实现上精修，保留原生材质、420 × 146 pt 浮层、20 项上限、只保存引用、固定保护和最早临时项替换规则。保留本轮开始前已有的五个文件修改；全部变更目前仅在本地工作树中，未提交、安装、签名、公证或发布。

## 已实现

- 导入：成功、重复、无法读取分别计数；混合批次进入可辨认的 `partial` 状态，保留有效文件。全失败不会显示成功。面板导入保留非文件提供者作为失败项；状态栏入口不再提前过滤失效文件路径。
- 顺序：按提供者原始索引收集，避免异步回调先后改变文件次序。提供者 10 秒未返回计入失败，后续回调不能再次加入。
- 撤销：按钮绑定模型快照可用性；固定、移除和清空使旧快照失效时，不再留下可点击的无效撤销。部分成功的替换也可以撤销并恢复精确顺序。
- 监听：注册外部点击或拖出结束监听前移除已有监听，避免覆盖旧句柄。状态栏菜单显式禁用自动启用，保留空列表禁用状态。
- 文件辨认：两行中间截断保留文件名首尾，悬停完整路径；右键增加“在 Finder 中显示”。失效提示提供可能原因和原路径，红点避开移除按钮。
- 列表：新增项自动滚入视野；超过五项显示左右滚动提示，启用原生滚动条。
- 视觉：24 pt 顶部区域、84 pt 卡片、38 pt 底部区域；42 pt 系统文件图标。反馈贴近底部独立区域；悬停仅增强背景和边框，不再缩放/抬升/增强阴影。
- 刷新：仅面板可见时每两秒检查路径状态，图标在卡片出现或路径可用性变化时获取。没有测量网络卷性能，不宣称已消除慢卷阻塞。

## 自动验证

- Debug / Release：`BUILD SUCCEEDED`，`CODE_SIGNING_ALLOWED=NO`。
- 原有 `ShelfStoreSmoke`：通过，覆盖容量、去重、固定持久化、最早临时项替换、精确撤销、文件夹与拒绝边界。
- 新增 `ShelfRefinementSmoke`：通过，覆盖混合成功/失败/重复、全失败、下游 partial 状态、部分替换撤销、固定与移除后的撤销可用性、固定容量整批拒绝、回调乱序、晚到回调、真实 NSItemProvider 加载错误/非文件输入/超时、中文空格特殊字符路径及 22 个源文件内容不变。
- `git diff --check`：通过。
- 本机 Xcode 报告 CoreDevice/CoreSimulator 组件版本不匹配及未依赖 AppIntents 的元数据提示；没有阻止本次 macOS Debug/Release 构建。本轮没有安装或修理这些系统组件。

测试使用独立临时目录与 UserDefaults suite，不读取实际固定项。复跑：

```bash
xcrun swiftc -target arm64-apple-macos14.0 -parse-as-library \
  DockShelf/ShelfStore.swift scripts/ShelfStoreSmoke.swift \
  -o /tmp/dockshelf-store-smoke-bin
/tmp/dockshelf-store-smoke-bin

xcrun swiftc -target arm64-apple-macos14.0 -parse-as-library \
  DockShelf/ShelfStore.swift DockShelf/ShelfInteractionState.swift \
  DockShelf/ShelfImport.swift DockShelf/ShelfView.swift \
  DockShelf/DockShelfTheme.swift DockShelf/ShelfShortcut.swift \
  DockShelf/ShelfDragMonitor.swift \
  scripts/ShelfRefinementSmoke.swift \
  -o /tmp/dockshelf-refinement-smoke
/tmp/dockshelf-refinement-smoke
```

## Data Correctness Trials

- `HCT-2026-09-08-01`：审查时发现提供者错误和失效路径被静默丢弃。新增测试确认部分失败进入 `partial`，全失败进入 `invalid`，超时和晚到回调不会成为成功或重复追加。有效项仍可独立使用。
- `HCT-2026-09-08-02`：依据现有产品规则及本轮精修授权，保留只引用、标准化路径去重、20 项、固定保护和整批容量拒绝。改动的是结果可见性与源顺序保留；测试覆盖混合批次、容量边界及撤销后的完整顺序。两项试行仍属本次证据，不代表长期可靠性已确认。

## 待用户人工验收

候选构建：`.build/DerivedData/Build/Products/Release/搁这儿.app`（未签名开发构建）。本轮未启动应用或驱动任何 UI。

1. 拖入超过五个文件，检查最新项目进入视野；鼠标滚轮和触控板可以访问全部内容。
2. 两个同名文件和长文件名：检查完整路径提示、扩展名辨认、Finder 定位，以及失效项目提示。
3. 满容量替换后执行撤销；再次替换后固定/移除一项，检查没有失效撤销按钮。
4. 检查部分导入提示与完整成功提示的区别；重复文件、文件夹、Finder/浏览器/聊天应用双向拖放需真实验收。
5. 深浅色下检查文件名与反馈不重叠、容量角标、键盘聚焦与按钮可达性、减少动态效果。
6. 多次展开、触发拒绝提示、点击外部收起；实际监听生命周期和窗口交互目前只有代码检查与构建证据。

人工通过后再根据用户授权决定安装、提交或发布；本轮没有扩大到快捷键、开机启动、自动更新或重做品牌。

## 后续测试包回执（2026-09-15）

用户随后授权构建可安装版本。已通过构建参数生成 0.1.1（2026091501），源码版本配置未变；App 和 DMG 均完成 Developer ID 签名。此本机测试包未做 Apple 公证或公开发布，未替用户安装/启动。

- 产物：`.build/releases/0.1.1-2026091501/DockShelf-0.1.1-2026091501-macos-arm64.dmg`
- 大小：1,206,712 bytes；Apple Silicon，macOS 14+。
- SHA-256：`04a6230137e57814a9f6238f504c943975c069171124db297eff1577d04dd442`
- 验证：Release 构建通过；App/DMG 签名验证通过；磁盘镜像校验通过；只读挂载后 App 的 6 个文件散列与打包源一致，版本、bundle ID 和 Applications 链接正确。验证卷已卸载。
- 安装：先固定需要保留的条目，退出旧版；打开 DMG，将“搁这儿”拖到 Applications 并替换，然后手动启动。
