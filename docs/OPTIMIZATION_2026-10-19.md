# v0.1.5 交互与界面优化计划

日期：2026-10-19（Asia/Shanghai）

## 目标与范围

基于 v0.1.4 的源码审查，改善拖放会话稳定性、文件辨认、容量预期与结果反馈。保持原生 macOS 菜单栏形态、420 × 146 pt 面板、20 项上限、只保存原文件引用、固定保护与最早临时项替换规则。

目标版本：**0.1.5（2026101901）**，已正式发布。初始优化后，用户先授权本地打包，再明确授权正式 Release。App/DMG 双层签名、公证、Gatekeeper、GitHub 上传与公开下载复验均已通过，见 [发布回执](RELEASE_v0.1.5.md)。安装和 UI 操作仍由用户执行。

## 实施顺序

1. 修复取消新拖入后旧替换/部分失败反馈及撤销入口丢失；保护自动展开会话，鼠标仍按住时不因离开菜单栏图标而收起；整理重复菜单入口及拖出兜底。
2. 利用底栏显示悬停或聚焦文件的完整名称与所在目录；提供横向翻动按钮；让管理按钮与文件图标拖动区域分开。
3. 拖入时保留容量，预告可能替换临时引用或没有可替换位置；不在悬停检测中读取文件路径，不预判去重后的准确结果。
4. 为实际导入失败保留本机内存详情；已知失败展示文件名和原因，无法识别的项目明确标为未知；保持部分失败、全失败和成功可区分。
5. 显示成功加入数量并补充辅助播报；局部新增/移除过渡遵循减少动态效果，维持 160 ms 进入、110 ms 退出、120 ms 悬停与 350 ms 成功收起。
6. 同步版本、README、设计说明、自动展开说明与交接文档；完成隔离回归及 Debug/Release 构建。

## 验证标准

- 取消新拖入能恢复旧替换和部分失败反馈；真正完成新导入后展示新结果。
- 自动会话的状态栏拖离不会安排提前收起，成功导入的完成计时仍独立工作。
- 失败详情不降低失败计数、不把未知转成成功、不记录私人路径或内容到日志；成功导入清理旧失败详情。
- 原有容量、去重、固定持久化、替换、撤销顺序、自身拖入拒绝与源文件不变回归通过。
- Debug 和 Release 构建通过；产物版本与构建号正确。
- 真实拖放、卡片命中、长文件名、横向翻动、深浅色、减少动态效果及 VoiceOver 由用户操作验收；自动化结果不替代该层。

## 实施回执

已完成上述六步本地实现，版本配置的 Debug/Release 均为 **0.1.5（2026101901）**。

- `ShelfInteractionState.swift` / `ShelfPanelController.swift`：取消新拖入恢复旧反馈；自动会话状态栏拖离保护；独立拖出兜底；新拖入、新结果、撤销、返回及拖出显式关闭旧详情。
- `StatusBarController.swift`：合并动态显示/收起菜单，并接入相同的失败详情数据。
- `ShelfStore.swift` / `ShelfImport.swift`：保留失败详情，不改变原有加入结果、计数或容量规则；未知身份不猜测文件名，不读取文件内容，不持久化失败详情。
- `ShelfView.swift`：底栏文件辨认、反馈期间顶部名称、左右翻动、图标与下方管理按钮分区、容量预告、失败详情弹层、成功数量及辅助播报、遵循减少动态效果的局部过渡。
- 同步 README、权威交接、默认目录的交接入口、设计说明、自动展开说明及 v0.1.5 版本说明。保留历史 v0.1.4 正式分发记录。

### 非交互验证结果

| 检查 | 结果与范围 |
| --- | --- |
| `ShelfStoreSmoke` | 通过：容量、去重、固定持久化、最早临时项替换、精确撤销、拒绝边界与文件夹 |
| `ShelfInteractionSmoke` | 通过：两入口取消恢复、真正新结果覆盖、部分/失败与加入数量区分、详情生命周期、重置、导出状态及源文件不变 |
| `ShelfRefinementSmoke` | 通过：原生 NSURL 顺序、已知/未知失败、失败计数不重复、成功清理详情、自身拖入拒绝、计时及自动检测 |
| Debug / Release | 均 `BUILD SUCCEEDED`，`CODE_SIGNING_ALLOWED=NO`；未启动构建产物 |
| 产物 Info.plist | Debug/Release 均核对为 0.1.5 / 2026101901，最低 macOS 14.0，`LSUIElement=true` |
| `git diff --check` | 通过 |
| 集成源码复核 | 修正反馈占用底栏时悬停名称消失，以及旧详情状态可能遗留的问题；未发现新增路径日志或失败转成功 |

原生粘贴板测试仍出现 `sandbox_extension_consume` 环境提示，但测试通过；这不证明真实 Finder 或其他应用的拖放权限与事件行为已经验收。构建仅有未依赖 AppIntents 的元数据提取提示，没有阻止构建。

### 可复跑检查

从实际仓库根目录执行，三个脚本使用独立临时文件及 UserDefaults suite，不读取真实固定项：

```bash
xcrun swiftc -target arm64-apple-macos14.0 -parse-as-library \
  DockShelf/ShelfStore.swift scripts/ShelfStoreSmoke.swift \
  -o /tmp/dockshelf-store-smoke
/tmp/dockshelf-store-smoke

xcrun swiftc -target arm64-apple-macos14.0 -parse-as-library \
  DockShelf/ShelfStore.swift DockShelf/ShelfInteractionState.swift \
  scripts/ShelfInteractionSmoke.swift -o /tmp/dockshelf-interaction-smoke
/tmp/dockshelf-interaction-smoke

xcrun swiftc -target arm64-apple-macos14.0 -parse-as-library \
  DockShelf/ShelfStore.swift DockShelf/ShelfInteractionState.swift \
  DockShelf/ShelfImport.swift DockShelf/ShelfView.swift DockShelf/DockShelfTheme.swift \
  DockShelf/ShelfShortcut.swift DockShelf/ShelfDragMonitor.swift \
  scripts/ShelfRefinementSmoke.swift -o /tmp/dockshelf-refinement-smoke
/tmp/dockshelf-refinement-smoke
```

构建命令沿用 `HANDOFF.md`。原始未签名构建为 `.build/DerivedData/Build/Products/Release/搁这儿.app`；正式公证 DMG 为 `.build/releases/v0.1.5/DockShelf-0.1.5-macos-arm64.dmg`，早先未公证本地试用包另行保留。

### 待用户人工验收

1. 满 20 项触发替换后，再拖入但取消；原来的反馈和撤销仍可操作。
2. 自动展开后经过菜单栏图标，再拖到面板外保持按住超过 0.45 秒；窗口继续保留，松开或成功加入后按既有规则收起。
3. 长文件名、同名文件、固定项和失效项：检查底栏/顶部名称、图标拖动、下方管理按钮及原路径提示。
4. 六至二十项时检查左右按钮、触控板、鼠标滚轮和新增项目定位。
5. 失败详情打开、关闭，再开始新拖入、取消或返回；反馈/撤销保留，外部点击仍能正常收起。
6. 深浅色、复杂壁纸、减少动态效果、减少透明度、键盘焦点及 VoiceOver 的结果播报。

后续已按用户授权完成源码提交推送、正式 App/DMG 签名、公证、票据附加、Gatekeeper、镜像及只读挂载文件比对、GitHub Release 与公开下载复验，详见 [发布回执](RELEASE_v0.1.5.md)。没有进行安装或 UI 操作；真实体验验收保持独立。
