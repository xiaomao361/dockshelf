# macOS M0 跨应用拖放探针记录

更新日期：2026-08-11

## 当前结论

M0 **尚未通过**。

启动阻塞已定位为 `irondash_engine_context` 在 macOS 上的初始化竞态，并通过 `FLTEnableMergedPlatformUIThread=false` 临时绕过。实际探针的 Debug 与 Release 构建都能稳定启动，但真实跨应用拖入和拖出尚未完成人工验收，因此不能进入 MVP。

## 环境

- macOS 26.6.1，Apple Silicon（arm64）
- Xcode 26.6
- Flutter 3.44.8 stable，Dart 3.12.2
- CocoaPods 1.17.0
- `super_drag_and_drop 0.9.1`
- `super_native_extensions 0.9.1`
- `irondash_engine_context 0.5.5`

## 隔离矩阵

| 用例 | 结果 | 证据 |
| --- | --- | --- |
| 实际探针，默认线程配置 | 崩溃 | `EXC_BAD_ACCESS / SIGSEGV`，地址 `0x8`；栈为 `objc_loadWeakRetained → getFlutterView → DropManager` |
| 纯 Flutter macOS 工程 | 通过 | 构建成功并稳定运行 15 秒 |
| 仅加入依赖、不挂载 `DropRegion` | 通过 | 构建成功并稳定运行 15 秒 |
| 首帧立即挂载 `DropRegion` | 崩溃 | 约 1.4 秒内复现相同调用栈 |
| 延迟 100 ms 或等待首帧栅格化后挂载 | 通过 | 两种用例均稳定运行 15 秒 |
| 立即挂载并设置 `FLTEnableMergedPlatformUIThread=false` | 通过 | 稳定运行 15 秒 |
| 实际探针 Debug | 通过启动层 | 构建成功并稳定运行 20 秒，无新崩溃报告 |
| 实际探针 Release | 通过启动层 | 构建成功并稳定运行 20 秒，无新崩溃报告 |

## 根因证据

本地依赖 `irondash_engine_context 0.5.5` 在插件注册时用 `dispatch_async` 延后登记 engine context，但 `getFlutterView` 随后直接解引用 context，没有空值防护。合并 UI/Platform 线程时，首帧立即创建 `DropRegion` 可以先于登记任务执行，从而读到空 context。

本次原始崩溃报告：

- `/Users/zhouwei/Library/Logs/DiagnosticReports/搁这儿-2026-08-11-082228.ips`
- `/Users/zhouwei/Library/Logs/DiagnosticReports/搁这儿-2026-08-11-082233.ips`
- `/Users/zhouwei/Library/Logs/DiagnosticReports/dockshelf_plugin_smoke-2026-08-11-082750.ips`

上游已有相同问题和修复尝试：

- [irondash #81：macOS engine context 初始化竞态](https://github.com/irondash/irondash/issues/81)
- [super_native_extensions #570：相同 `getFlutterView` 崩溃栈](https://github.com/superlistapp/super_native_extensions/issues/570)
- [irondash #86：尚未合并且当前冲突的修复 PR](https://github.com/irondash/irondash/pull/86)

因此，现有证据支持“插件初始化竞态被 Flutter 默认合并线程拓扑暴露”，不支持把它定性为 Xcode 26 或 Flutter 3.44 的引擎回归。

## 当前工程变更

`macos/Runner/Info.plist` 增加：

```xml
<key>FLTEnableMergedPlatformUIThread</key>
<false/>
```

这是启动探针的临时兼容配置，不是长期产品修复。Flutter 已在跟踪移除非合并线程拓扑的计划（[flutter/flutter #181874](https://github.com/flutter/flutter/issues/181874)），后续仍需选择：等待或集成上游竞态修复，或改走原生/Qt 路线。

## 已完成验证

- `plutil -lint macos/Runner/Info.plist`
- `flutter analyze`
- `flutter test`（1 个测试通过）
- `flutter build macos --debug`
- Debug 应用稳定启动 20 秒
- `flutter build macos --release`
- Release 应用稳定启动 20 秒
- Debug/Release 产物的 `Info.plist` 均包含 `FLTEnableMergedPlatformUIThread=false`

## 待人工完成的 M0 验收

- 从 Finder 拖入单个文件并显示正确路径；
- 从 Finder 一次拖入多个文件；
- 将同一文件从窗口拖回 Finder；
- 拖到浏览器真实上传区；
- 拖到一个真实聊天或邮件应用；
- 验证中文、空格和 `#` 等特殊字符路径；
- 源文件删除或移动后，窗口给出明确失效状态；
- 确认探针只保存文件引用，不复制、移动或上传文件内容。

完成上述真实路径前，不进入 MVP。若全部通过，Flutter 路线只能“有条件继续”，并必须先确定上游修复策略；若任一核心跨应用路径失败，则停止 Flutter 正式开发，评估原生或 Qt。
