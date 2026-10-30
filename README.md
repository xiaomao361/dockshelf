# 搁这儿 · DockShelf

原生 macOS 菜单栏文件搁板。把待会儿要用的文件或文件夹放在手边，需要时再拖到 Finder、浏览器上传区或其他应用。

搁板只保存引用，不复制、移动、删除或上传原文件。

[Mac App Store](https://apps.apple.com/cn/app/id6825144885) · [产品介绍](https://xiaomao361.github.io/dockshelf/) · [使用帮助](https://xiaomao361.github.io/dockshelf/support/) · [版本记录](CHANGELOG.md)

## 功能

- 拖起文件时自动展开，也可通过菜单栏图标或全局快捷键打开。
- 临时引用退出即清空；固定引用通过只读安全作用域书签恢复访问。
- 最多容纳 20 项。容量不足时替换最早加入的临时项，并提供撤销；固定项不会自动替换。
- 文件类型图标、照片与 PDF 内容预览、悬停文件名、横向滚动和翻页。
- 固定记录备份、导入和按所在文件夹批量恢复访问。
- 本地存储，无账号、遥测、广告跟踪或云同步。

源码版本为 **1.1（2026103001）**，商店构建已上传，尚未确认公开发布；商店可下载版本以商店页面为准。1.1 包含软触质感的翻折搁板、分类文件图标和拖拽交互改进。历史独立安装包位于 [GitHub Releases](https://github.com/xiaomao361/dockshelf/releases)。

## 系统要求

- Apple Silicon Mac（arm64）
- macOS 14 或更高版本

## 使用

1. 启动后在屏幕顶部菜单栏找到搁这儿；应用没有普通主窗口或 Dock 图标。
2. 从 Finder 拖入文件或文件夹，放到菜单栏图标或展开的搁板区域。
3. 从搁板上的文件图像拖到目标应用继续使用。
4. 在 1.1 中，悬停文件可查看名称并显示固定、移除按钮；超过五项时可滚动或使用底部两侧箭头。

默认快捷键为 **Control–Option–空格**。右键菜单栏图标，进入“帮助与关于…”可修改快捷键。关闭“拖动文件时自动展开”后，仍可用菜单栏与快捷键打开。

移除引用不会删除原文件。文件移动后需移除旧引用并从新位置重新拖入；外置卷未连接或授权失效时，可使用恢复入口。备份包含私人路径和访问书签，请勿公开分享。详情见 [隐私政策](PRIVACY.md)。

## 开发

应用使用 Swift、SwiftUI 与 AppKit，无第三方运行时依赖。

```bash
xcodebuild -project DockShelf.xcodeproj \
  -scheme DockShelf-AppStore -configuration AppStoreDebug \
  -derivedDataPath .build/DerivedData build
bash scripts/validate.sh
```

- [架构与数据模型](docs/ARCHITECTURE.md)
- [构建与分发](docs/DEVELOPMENT.md)
- [测试与交互验证](docs/TESTING.md)
- [GitHub Pages](docs/GITHUB_PAGES.md)
- [品牌资源](docs/brand/README.md)

## 反馈与许可

通过 [GitHub Issues](https://github.com/xiaomao361/dockshelf/issues) 提交问题，附上应用版本、macOS 版本和复现步骤。截图及日志请先移除私人文件名、路径和访问书签。

源码、二进制及品牌资源的使用条件见 [LICENSE](LICENSE)。Copyright © 2026 Zhou Wei.
