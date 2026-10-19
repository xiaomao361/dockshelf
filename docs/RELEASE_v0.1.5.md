# v0.1.5 发布回执

日期：2026-10-19（Asia/Shanghai）。用户明确授权发布 GitHub Release。

- 版本：0.1.5（2026101901），Apple Silicon arm64 / macOS 14+
- 仓库：`xiaomao361/dockshelf`，分支 `codex/m0-probe`
- 目标标签：`v0.1.5`
- 正式产物目录：`.build/releases/v0.1.5/`
- 当前源码与已验证本地测试包的 33 个构建输入指纹一致，三组隔离回归和 Debug/Release 构建凭据见 [优化计划](OPTIMIZATION_2026-10-19.md)。
- 本地测试包的 Developer ID 签名和镜像完整性见 [本地打包回执](PACKAGE_v0.1.5.md)，它仍是未公证的独立测试产物。

## 分发凭据

- 文件：`DockShelf-0.1.5-macos-arm64.dmg`，1,071,939 bytes
- SHA-256：`ceecae5bb5b14bd41b6ffa8116f477045c87d2074d27b47fa73c937a7561278c`
- 签名：Developer ID Application: zhou wei（`A5L4GGX82X`），timestamp；App 启用 hardened runtime
- 公证 profile：`claracore-notary`，凭据由本机钥匙串管理，不写入仓库
- App 公证：`535a3fb3-8237-4462-9c6b-47f145562b58`（Accepted）
- DMG 公证：`1b8d4179-0c1d-4d94-b10b-e58cdf50b750`（Accepted）
- App/DMG 票据附加、票据验证、strict 签名及 Gatekeeper 检查均通过，来源为 `Notarized Developer ID`
- 镜像校验及非交互只读挂载通过，挂载 App 的七个文件与签名/公证 staging 逐一匹配；原本地测试 App 的六个文件保持不变，新增的是公证票据
- `Applications` 链接和安装说明正确，挂载卷已卸载；机器回执见产物目录 `package-verification.json`

## 发布状态

正式分发检查通过，准备提交源码、推送 `v0.1.5` 标签及上传 GitHub Release；公开下载复验完成后补充记录。

没有安装、启动或操作产品 UI；用户授权发布不等于真实拖放、GUI 或辅助功能验收通过。
