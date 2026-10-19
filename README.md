# 搁这儿

“搁这儿”是一款原生 macOS 菜单栏文件搁板。拖起待会儿要用的文件或文件夹，放进自动展开的搁板，需要时再从搁板拖到 Finder、浏览器、聊天或邮件应用。

它只保存原位置的引用，不复制、移动、上传或修改文件内容。

当前版本：**0.1.5（2026101901）**。交互与界面改进见 [版本说明](docs/RELEASE_NOTES_v0.1.5.md) 和 [实施计划](docs/OPTIMIZATION_2026-10-19.md)。正式 App/DMG 已完成 Developer ID 签名与 Apple 公证，GitHub 发布准备与验证见 [发布回执](docs/RELEASE_v0.1.5.md)。

## 系统要求

- Apple Silicon Mac（arm64）
- macOS 14 Sonoma 或更高版本

当前版本不支持 Intel Mac、Windows 或 Mac App Store 安装。

## 安装

1. 从 [Releases](https://github.com/xiaomao361/dockshelf/releases) 下载最新 DMG。
2. 打开 DMG，把“搁这儿”拖入“应用程序”。
3. 从“应用程序”启动“搁这儿”；启动后它只显示在菜单栏，不显示 Dock 图标。

发布版使用 Developer ID 签名并经过 Apple 公证。更新版本时重新下载 DMG，并用新版应用替换旧版即可。

## 使用

- 默认开启自动展开：拖起文件后，搁板固定在菜单栏图标下方出现，移进去松手即可；成功放入约 0.35 秒后收起，鼠标停留不会取消收起。菜单栏右键可关闭“拖动文件时自动展开”；Control–Option–空格保留为备用入口。

- 将文件或文件夹拖到菜单栏图标，搁板会自动展开并接收引用。
- 点击菜单栏图标可以显示或收起搁板；有内容时悬停 300 ms 也会展开。
- 从搁板把项目拖到需要的位置；原文件仍留在原处。
- 搁板最多保存 20 项。固定项会在应用重启后恢复，普通项退出应用后清空。
- 容量不足时会替换最早加入的未固定项，并提供一次撤销机会。
- 原文件被移动或删除后，引用会显示为失效；应用不会自动寻找新位置。

0.1.5 增加以下操作反馈：

- 悬停或键盘聚焦卡片时，底部显示文件名称及所在目录；反馈占用底栏时，顶部继续显示文件名称。完整路径仍可通过悬停提示查看。固定与移除按钮位于卡片下方，图标区域用于拖动。
- 超过五项时可用底部左右按钮翻动，触控板横向滚动与鼠标滚轮继续可用。
- 拖入时保留容量，已满时说明可能替换临时引用或需要腾出固定位置；准确结果在放入后显示。
- 未能读取的项目可从反馈右侧的信息按钮查看原因。已知失效路径显示名称和路径；原生拖拽未提供可靠身份时明确显示“无法识别的项目”。详情只保留在本机内存，不写入日志或偏好设置。
- 取消另一次拖入会恢复之前的可操作反馈与撤销入口；成功显示加入数量，并发出辅助播报请求。

## 隐私

“搁这儿”没有网络请求、账号、云同步、遥测或崩溃上报。固定项的本地绝对路径保存在当前 Mac 的应用偏好设置中。详情见 [PRIVACY.md](PRIVACY.md)。

## 问题反馈

请通过 [GitHub Issues](https://github.com/xiaomao361/dockshelf/issues) 反馈问题，并附上 macOS 版本、Mac 芯片型号和复现步骤。不要提交包含私人文件路径、文件名或文件内容的截图和日志。

## 本地构建

```bash
xcodebuild \
  -project DockShelf.xcodeproj \
  -scheme DockShelf \
  -configuration Debug \
  -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

技术实现与历史记录见：

- [原生实现与验收边界](docs/NATIVE_M0.md)
- [视觉决策](docs/DESIGN_DIRECTION.md)
- [v0.1.5 优化计划与验证](docs/OPTIMIZATION_2026-10-19.md)
- [v0.1.5 版本说明](docs/RELEASE_NOTES_v0.1.5.md)
- [v0.1.5 签名、公证与发布回执](docs/RELEASE_v0.1.5.md)
- [品牌资产](docs/brand/README.md)
- [v0.1.4 发布说明](docs/RELEASE_NOTES_v0.1.4.md)

## 授权

Copyright © 2026 Zhou Wei. All rights reserved. 当前仓库公开仅用于查看和问题反馈，未授予复制、修改或再分发源码与品牌资产的许可。详见 [LICENSE](LICENSE)。
