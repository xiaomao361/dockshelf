# v0.1.4 发布回执

- 版本：0.1.4（2026091504），Apple Silicon arm64 / macOS 14+
- 发布目标：https://github.com/xiaomao361/dockshelf/releases/tag/v0.1.4
- 分支：`codex/m0-probe`
- 文件：`DockShelf-0.1.4-macos-arm64.dmg`，1211882 bytes
- SHA-256：`14885e82d633f402a84d0078223a0f06474782b88c2337f0b35fc1f7b863c926`
- 签名：Developer ID Application: zhou wei (A5L4GGX82X)，hardened runtime + timestamp
- App 公证：`32038886-87e1-411d-82bd-95816dd1b302`（Accepted）
- DMG 公证：`d764f6de-85d7-4c72-b7aa-8afb1bfc28b9`（Accepted）
- App/DMG stapling、签名和 Gatekeeper 校验通过。
- 镜像校验与只读挂载通过；挂载 App 与 staging 全部 7 个文件散列一致，版本与 Applications 链接正确。
- Release 构建、ShelfStoreSmoke、ShelfRefinementSmoke 和 diff 检查通过。测试粘贴板输出 sandbox_extension_consume 环境提示，未把它当成真实 Finder 权限验收。

## 回归与边界

HCT-2026-09-08-01：混合失败保留 partial，全失败保留 invalid；独立计时验证悬停不能取消成功收起，新会话取消旧任务。HCT-2026-09-08-02：原生 URL 导入保留顺序、文件夹、去重、容量与撤销语义，测试源文件内容不变。未发现本轮新增的结果含义歧义。

用户已确认方向并授权公开发布。本轮没有驱动 UI 或安装应用；构建、公证和自动化验证不替代所有系统版本及长期真实交互验收。

## 公开发布复验

v0.1.4 已作为正式 Latest Release 发布，附 DMG 与 SHA256SUMS.txt。标签提交：`5c85a92514011c68d83f33b5b6788996727f62d6`。公开下载的 DMG 与本地正式包逐字节一致，签名与公证票据再次验证通过。GitHub 资产 digest 与上述 SHA-256 一致。
