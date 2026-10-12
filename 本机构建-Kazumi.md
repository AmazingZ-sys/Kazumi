# Kazumi 本机构建说明

检查日期：2026-10-09。目录：`/Users/zhix/Documents/project/Kazumi`；分支：`feat/drama-olevod`。

## 本轮实际验证

- `flutter build macos --release --no-pub` 成功，生成 `build/macos/Build/Products/Release/Kazumi.app`（126.0 MB）。主程序与 App.framework 包含 x86_64、arm64，`codesign --verify --deep --strict` 通过。
- 已启动该 macOS Release 应用，进程持续运行，系统日志显示 Metal 渲染初始化；未做视频源、播放、登录或付费/签名 API 的完整功能验收。
- `pod install` 成功；`flutter doctor -v` 的 Android toolchain 为通过状态。
- `flutter test --no-pub --reporter expanded`：211 项测试全部通过。
- `flutter analyze --no-pub --no-fatal-infos --fatal-warnings`：退出码 0，无 error/warning，保留 18 条 info 级提示。
- 已生成 `build/macos/Kazumi-macos-local.zip`（约 53 MB），保留 `.app` 目录结构。
- Android Debug APK 构建成功，`build/app/outputs/flutter-apk/app-debug.apk`（约 136 MB），含 ARMv7、ARM64、x86_64；APK 签名验证通过。
- Android Emulator 的 `-accel-check` 通过，使用现有 `Pixel_Tablet` Android 14 x86_64 模拟器成功安装并显示 Kazumi 主界面；复查 `am start -W` 返回 `Status: ok`。模拟器首次冷启动出现过 System UI 无响应，选择等待后恢复。在线番剧列表暂未加载成功，不能将其计为在线功能验收通过。

构建、测试、分析和 doctor 日志保存在 `/Users/zhix/Library/Application Support/Codex/Kazumi-build/logs/`。

## 已配置的环境

| 工具 | 本机版本 / 路径 |
| --- | --- |
| Flutter / Dart | 3.47.6 / 3.13.5；`/Users/zhix/Library/flutter/bin` |
| Android SDK | `/Users/zhix/Library/Android/sdk`；Platform 36、Build Tools 36.0.0、NDK 28.2.13676358；许可证已接受 |
| JDK | 17.0.9；Flutter 已配置使用 `/Users/zhix/Library/Java/JavaVirtualMachines/jbr-17.0.9/Contents/Home` |
| Xcode | 26.1.1；`/Applications/Xcode.app/Contents/Developer` |
| CocoaPods | 1.16.2；`/Users/zhix/.gem/ruby/3.3.0/bin/pod`，使用 Homebrew Ruby 3.3 |
| CMake / Ninja | 4.4.4 / 1.13.2；`/Users/zhix/Library/Python/3.9/bin` |
| 主机 | Intel x86_64，macOS 26.2 |

`.zprofile`、`.zshrc`、`.bashrc` 已加入上述工具路径和 Android SDK 变量。重新打开终端，或执行 `exec zsh -l`，让新路径生效。IDE 若已启动，需要重新打开，并确认 Flutter SDK 路径指向 `/Users/zhix/Library/flutter`。

`.zshrc` 原有 `proxy_on` 函数的 `no_proxy` 已补入 `::1`，避免 IPv6 loopback 被送入代理；交互式新终端已验证生效。

```sh
cd /Users/zhix/Documents/project/Kazumi
flutter --version
dart --version
pod --version
flutter doctor -v
flutter pub get
flutter test
```

Flutter 固定在仓库要求的 3.47.6 tag，因此 doctor 的未知 channel 提示不等于版本不匹配。不要为消除提示而直接升级到其他 Flutter 版本。

## macOS

当前 Flutter 引擎要求最低 macOS 12.0。已将 `macos/Podfile` 和 `macos/Runner.xcodeproj/project.pbxproj` 中三处最低版本由 10.15 改为 12.0；产物不再面向 macOS 10.15/11。CocoaPods 依赖已安装成功。

```sh
# 开发调试
flutter run -d macos

# Release 应用
flutter build macos --release

# 打开已构建的应用
open build/macos/Build/Products/Release/Kazumi.app
```

Intel 主机仍可使用这版 Flutter。Debug 默认构建宿主 x86_64，Release 默认尝试 Universal；实际原生依赖架构需要检查最终产物。当前项目使用本地 ad-hoc 签名，向其他用户正式分发时需要另做 Developer ID 签名和公证。

## Android

没有连接的 Android 真机；已有 Android 14 的 `Pixel_Tablet` x86_64 模拟器配置，可以从 Android Studio Device Manager 启动，或执行：

```sh
flutter emulators --launch Pixel_Tablet
flutter devices
flutter run -d <上一步显示的设备ID>

# 本地安装测试
flutter build apk --debug

# 按 CPU 架构生成 Release APK
flutter build apk --release --split-per-abi
```

Flutter APK 的通常输出目录是 `build/app/outputs/flutter-apk/`；直接 Gradle 构建还可在 `build/app/outputs/apk/` 找到产物。当前 `android/app/build.gradle` 的 release 使用 debug keystore，适合本地测试。正式发布必须配置自己的 keystore 和 release signingConfig；本地测试包与官方包签名不同，可能无法直接覆盖安装。

本次遇到的 TLS 错误发生在 Gradle 下载 Google/Maven 依赖时。用户级 Gradle 配置和系统代理均指向 `127.0.0.1:7890`，只取消 shell 的代理变量不足以保证 Java 直连。已经验证临时镜像配置加显式清空 Java 代理参数可以完成 Gradle 配置阶段；用户原来的全局 Gradle 代理设置已恢复。

本机专用入口保存在用户目录，仅对当前 Kazumi Gradle 进程启用国内 Maven/Flutter 镜像并清空 Java 代理属性，保留官方仓库；不修改全局 Gradle 配置：

```sh
bash "$HOME/Library/Application Support/Codex/Kazumi-build/android-build.sh" debug
bash "$HOME/Library/Application Support/Codex/Kazumi-build/android-build.sh" release
```

镜像配置是同目录的 `maven.init.gradle`，仅匹配本 checkout，排除 Flutter SDK 的 included build。若移动仓库或更换 JDK，需更新这两个文件内的绝对路径。

Gradle 8.14.5 / AGP 8.11.1 / Kotlin 2.2.21 会被 Flutter 提示即将停止支持。它们目前是仓库锁定的组合；不要仅为消除警告而分别升级版本。

## iOS

本轮未验证 iOS 构建。当前 Flutter 最低 iOS 15.0，仓库还写 13.0；执行 iOS 构建前需将 Xcode 工程及 Podfile 最低目标同步到 15.0（Flutter 自带迁移可能自动完成，需检查 diff）。iOS 引擎缓存也需要更新：

```sh
flutter precache --ios
flutter build ios --release --no-codesign
```

`--no-codesign` 产物不能直接安装到普通真机。用 Xcode 打开 `ios/Runner.xcworkspace`，选择自己的开发团队、唯一 Bundle ID，连接并信任 iPhone、开启开发者模式，再执行真机运行或签名归档。不要把开发者凭据写进仓库。

本机尚无 iOS 模拟器 runtime。Xcode 26.1.1 的官方元数据提供 iOS 26.1 Universal runtime，包含 x86_64，下载约 10.33 GB；Intel 主机必须选择 Universal，不能选 arm64-only：

```sh
xcodebuild -downloadPlatform iOS -buildVersion 26.1 -architectureVariant universal
open -a Simulator
flutter devices
```

安装 runtime 后，还需在 Xcode 的 Devices and Simulators 中创建对应模拟器设备。此下载未在本轮自动执行。

## 构建凭据与在线功能

四个 `dart-define` 可省略以验证编译和启动，但相关在线功能可能受限：`DANDANAPI_APPID` / `DANDANAPI_KEY` 用于弹弹 Play 搜索、匹配、弹幕；`KAZUMI_APPID` / `KAZUMI_KEY` 用于 Bangumi 镜像的搜索、评论签名。项目默认启用 Bangumi 镜像；可在设置中切换直连/ECH 来避开该镜像签名路径。

有自己的授权凭据时，按仓库 CI 的方式传入环境变量，不要将真实值提交到 Git：

```sh
flutter build macos --release \
  --dart-define=DANDANAPI_APPID="$DANDANAPI_APPID" \
  --dart-define=DANDANAPI_KEY="$DANDANAPI_KEY" \
  --dart-define=KAZUMI_APPID="$KAZUMI_APPID" \
  --dart-define=KAZUMI_KEY="$KAZUMI_KEY"
```

Android / iOS 同样使用这四个参数。构建成功不代表凭据、视频源或所有在线功能已验证。

## 其他平台与限制

- Windows 桌面包需在 Windows 上构建，Linux 桌面包需在 Linux 上构建，可用对应 VM 或 CI。
- `web/` 虽然存在模板，但应用入口使用 `dart:io`，不能据此认定项目支持 Web。
- Homebrew 因本机 Command Line Tools 较旧未能安装新工具，CMake/Ninja 已改用用户目录安装；Xcode 构建使用完整 Xcode 内的工具链。后续 Homebrew 维护时再更新与系统匹配的 CLT。

参考：[Flutter 平台支持](https://docs.flutter.dev/reference/supported-platforms)、[Apple 安装 Xcode 组件](https://developer.apple.com/documentation/xcode/downloading-and-installing-additional-xcode-components)。
