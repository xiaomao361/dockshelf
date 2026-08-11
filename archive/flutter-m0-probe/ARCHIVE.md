# Flutter M0 探针归档

归档日期：2026-08-11

## 归档原因

项目已决定只做 macOS 原生菜单栏应用，不再以 Flutter 作为实现技术栈。Flutter 探针保留为技术选型证据，不继续扩建，也未删除。

## 内容

- `source/`：原 Flutter 工程源码、macOS Runner、依赖锁定文件和当时使用的 `.gitignore`。
- `evidence/DRAG_DROP_PROBE.md`：复现、隔离和上游竞态证据。
- 生成缓存：`/Volumes/E61/Developer/Archives/dockshelf/flutter-m0-probe-2026-08-11/generated/`。

归档前的源码与证据共 102 个文件、521,888 字节；同卷移动后按文件数和总字节复核一致。生成缓存约 1.8 GB，已移出项目工作树。

关键文件 SHA-256：

- `source/pubspec.yaml`：`75b48f80150badc5d14d44c7aa53baca07f7617c93dccb3545fc730c92fdc4bb`
- `source/pubspec.lock`：`eec1dc86666923183ea4afec567f9cd2d19bb8211440dc5cda76963cdf0bc3a7`
- `source/lib/main.dart`：`4b491012be5abf7fef4c7b30c395ea07dbfdfdee0139cbdcf6ed10e498a993d8`
- `source/macos/Runner/AppDelegate.swift`：`ce9dbe45a57c59e85519da50a26c471615b9c8cdd85a8f4a39d2e480e62a4af4`
- `source/macos/Runner/Info.plist`：`6c38e08d15defc8a7ae5503628bc2bd0dd58251bc128443fbbc954d7bcf31cab`
