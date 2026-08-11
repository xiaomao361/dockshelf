# 搁这儿

“搁这儿”是一款原生 macOS 菜单栏文件搁板。把待会儿要用的文件或文件夹拖到菜单栏图标，需要时再从搁板拖到 Finder、浏览器、聊天或邮件应用。

它只保存原位置的引用，不复制、移动、上传或修改文件内容。

## 系统要求

- Apple Silicon Mac（arm64）
- macOS 14 Sonoma 或更高版本

v0.1.0 不支持 Intel Mac、Windows 或 Mac App Store 安装。

## 安装

1. 从 [Releases](https://github.com/xiaomao361/dockshelf/releases) 下载最新 DMG。
2. 打开 DMG，把“搁这儿”拖入“应用程序”。
3. 从“应用程序”启动“搁这儿”；启动后它只显示在菜单栏，不显示 Dock 图标。

发布版使用 Developer ID 签名并经过 Apple 公证。更新版本时重新下载 DMG，并用新版应用替换旧版即可。

## 使用

- 将文件或文件夹拖到菜单栏图标，搁板会自动展开并接收引用。
- 点击菜单栏图标可以显示或收起搁板；有内容时悬停 300 ms 也会展开。
- 从搁板把项目拖到需要的位置；原文件仍留在原处。
- 搁板最多保存 20 项。固定项会在应用重启后恢复，普通项退出应用后清空。
- 容量不足时会替换最早加入的未固定项，并提供一次撤销机会。
- 原文件被移动或删除后，引用会显示为失效；应用不会自动寻找新位置。

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
- [品牌资产](docs/brand/README.md)
- [v0.1.0 发布说明](docs/RELEASE_NOTES_v0.1.0.md)

## 授权

Copyright © 2026 Zhou Wei. All rights reserved. 当前仓库公开仅用于查看和问题反馈，未授予复制、修改或再分发源码与品牌资产的许可。详见 [LICENSE](LICENSE)。
