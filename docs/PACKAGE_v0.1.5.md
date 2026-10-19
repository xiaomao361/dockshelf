# v0.1.5 本地安装包回执

日期：2026-10-19（Asia/Shanghai）。本文仅记录早先“供本人安装试用”的本地打包阶段。用户随后已授权正式发布，正式包另完成公证，见 [发布回执](RELEASE_v0.1.5.md)；本地测试产物及原始散列保留不变。

## 产物

- 版本：**0.1.5（2026101901）**
- 文件：`.build/releases/0.1.5-2026101901/DockShelf-0.1.5-2026101901-macos-arm64.dmg`
- 大小：1,069,887 bytes
- SHA-256：`478aedbb6eecf6a8ecd6c250f2fdd4da0d3bdb7e384d88dd30b3290988f2a682`
- 校验文件：同目录 `SHA256SUMS.txt`
- 范围：Apple Silicon arm64，macOS 14+
- Bundle ID：`com.claracore.dockshelf`，与旧版一致，固定引用继续使用原有偏好设置。

## 签名和验证

- 从当前未提交优化源码重新执行 Release 构建，`BUILD SUCCEEDED`；源码输入指纹保存在同目录 `source-manifest.json`，打包后复核一致。
- App 和 DMG 均使用 `Developer ID Application: zhou wei (A5L4GGX82X)` 签名，包含 timestamp；App 启用 hardened runtime。
- App 的 deep/strict 签名与 DMG strict 签名验证通过；另由独立只读审查复核身份、Team ID、runtime、timestamp、版本及架构。
- `hdiutil verify` 通过；以只读、`nobrowse`、`noautoopen` 方式挂载，没有打开 Finder 或启动应用。
- 挂载 App 的相对文件列表与签名 staging 一致，六个文件的大小和 SHA-256 逐一一致。
- `Applications -> /Applications` 正确，包内 `安装说明.txt` 与打包源一致，挂载卷已卸载。
- 机器可读回执位于同目录 `package-verification.json`。

DMG 首次请求 timestamp 时服务暂不可用；重试后签名及 timestamp 验证通过，没有改成无 timestamp 的降级包。

## 安装

1. 若需保留旧版临时条目，请先固定；临时条目退出时清空。
2. 从菜单栏退出旧版“搁这儿”。
3. 打开 DMG，将“搁这儿”拖入 Applications，替换旧版。
4. 从“应用程序”手动启动；应用只显示在菜单栏。

## 验证边界

本文所指本地测试包已签名、未做 Apple 公证，不作为后续正式分发产物。没有代用户安装、启动或进行真实交互验收。人工验收清单见 [优化计划](OPTIMIZATION_2026-10-19.md)，后续提交、公证及发布状态以 [发布回执](RELEASE_v0.1.5.md) 为准。
