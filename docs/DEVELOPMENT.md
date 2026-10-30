# 构建与分发

## 环境

- Apple Silicon Mac，macOS 14+
- 含 macOS SDK 的 Xcode、Command Line Tools
- Swift、Python 3、Bash

工程没有第三方运行时包依赖。构建缓存与产物存放在已忽略的 `.build/`。

## 本地构建

```bash
xcodebuild -project DockShelf.xcodeproj \
  -scheme DockShelf-AppStore -configuration AppStoreDebug \
  -derivedDataPath .build/DerivedData build
```

本地编译可用 `CODE_SIGNING_ALLOWED=NO` 检查源码；实际运行与分发需匹配签名和沙盒权限。正式商店使用 `DockShelf-AppStore` scheme、`AppStoreRelease` 配置；普通 `Debug` / `Release` 保留独立分发通道的配置。

## 自动检查

```bash
bash scripts/validate.sh
xcrun swiftc -target arm64-apple-macos14.0 -parse-as-library \
  DockShelf/DockShelfTheme.swift scripts/ShelfAppearanceSmoke.swift \
  -o .build/appearance-check
.build/appearance-check .build/appearance
```

前者执行六组隔离回归；后者检查布局间距、悬停取消及焦点策略，并输出组件离屏图。测试使用独立偏好域和临时文件，不更改个人固定记录。完整范围见 [测试说明](TESTING.md)。

## 商店归档

```bash
xcodebuild -project DockShelf.xcodeproj \
  -scheme DockShelf-AppStore -configuration AppStoreRelease \
  -derivedDataPath .build/StoreRelease \
  -archivePath .build/DockShelf.xcarchive \
  CODE_SIGN_IDENTITY='Apple Development' \
  DEBUG_INFORMATION_FORMAT=dwarf-with-dsym \
  -allowProvisioningUpdates archive
```

版本号与构建号来自工程中的商店配置。上传前核对归档内实际版本、正式 Bundle ID、签名 Team、架构、最低系统版本、权限、隐私清单及 dSYM UUID。

`scripts/build-app-store-candidate.sh` 用于本地候选的多配置构建和归档验证，不上传。`verify-candidate.py` 支持 `--version` 和 `--build` 指定期望值。

App Store 上传、Apple 构建处理、最终送审与公开发布是独立阶段。商店签名使用本机已配置的账户；不要把证书私钥、API 密钥、账号令牌或分发日志加入仓库。
