# 本地打包与导出

`scripts/package.py` 使用 Python 3.9+ 标准库调用本机 Flutter，统一生成 Release 安装包，无需安装 Python 第三方依赖。脚本可从任意工作目录调用，自动定位项目根目录。以下示例在项目根目录执行。

## 快速开始

macOS：构建 Android APK、未签名 IPA 和 macOS DMG，导出至 `~/Downloads/Kazumi_<版本>_<时间>_<唯一标识>/`：

```bash
python3 scripts/package.py
```

Windows PowerShell：构建 Android APK 和 Windows x64 EXE 安装程序，导出至系统桌面的独立子目录（支持 OneDrive 重定向桌面）：

```powershell
py -3 scripts/package.py
```

选择平台、指定目录：

```bash
python3 scripts/package.py --platform android,macos --output "/Volumes/Storage/Kazumi Packages"
python3 scripts/package.py --platform ipa
python3 scripts/package.py --platform android --split-per-abi
```

```powershell
py -3 scripts/package.py --platform windows --output "D:\安装包"
py -3 scripts/package.py --platform windows --windows-format zip
```

仅查看构建计划，不执行构建、不创建目录：

```bash
python3 scripts/package.py --dry-run
python3 scripts/package.py --help
```

## 平台及环境

| 目标 | 可以运行脚本的系统 | 输出 | 额外要求 |
| --- | --- | --- | --- |
| `android` | macOS / Windows / Linux | 通用 `.apk`；可按 ABI 拆包 | Android SDK、JDK，接受 Android SDK licenses |
| `ipa`（也支持 `ios`） | macOS | 默认 `_no_sign.ipa`，可签名导出 | Xcode 和项目所需 Apple 平台依赖 |
| `macos` | macOS | `.dmg`，含 App 与 Applications 快捷方式 | Xcode，系统自带 ditto/hdiutil |
| `windows` | Windows | 默认 x64 `_setup.exe`；可选便携 `.zip` | Visual Studio C++ 桌面开发工具、Windows SDK；EXE 还需要 Inno Setup 6.3+ |

先安装符合 `pubspec.yaml` 要求的 Flutter SDK，运行 `flutter doctor -v` 检查目标平台环境。本项目 CI 还安装了 CMake 和 Ninja；遇到原生插件构建缺少这些工具时需安装并加入 PATH。

`all` 是默认值，表示**当前宿主系统支持的目标**：Mac 为 Android、IPA、macOS；Windows 为 Android、Windows；Linux 仅 Android（默认导出至 `~/Downloads`）。显式选择不兼容平台会在构建前报错。此脚本不远程调用其他机器；要获得四个平台的包，需要分别在 Mac 和 Windows 上运行。

可通过 `--flutter "/path/to/flutter"` 或环境变量 `FLUTTER_BIN` 选择 SDK。Windows 可指定 `flutter.bat` 路径。默认先执行一次 `flutter pub get`；已有可用依赖时可加 `--skip-pub-get`。

## 签名与安装

### Android

Release 优先使用环境变量 `KAZUMI_ANDROID_KEYSTORE`（keystore 路径）、`KAZUMI_ANDROID_KEYSTORE_PASSWORD`、`KAZUMI_ANDROID_KEY_ALIAS`、`KAZUMI_ANDROID_KEY_PASSWORD` 配置固定签名。四项必须同时提供；本地开发不提供时回退到 debug keystore，仅适合测试。脚本不会生成或修改签名凭据。后续覆盖升级必须沿用同一签名并提高版本号。默认生成通用 APK，`--split-per-abi` 生成 armeabi-v7a、arm64-v8a、x86_64 三份 APK。

### iOS

默认沿用仓库 CI 的侧载流程：`flutter build ios --release --no-codesign`，把 App 放入 `Payload/Runner.app`，对嵌入框架做 ad-hoc 签名后生成 `_no_sign.ipa`。该文件**需要通过侧载工具重新签名后安装**，不能直接当作已签名分发包使用。

已配置开发者团队、证书和描述文件时，可使用 Xcode 导出的 ExportOptions.plist：

```bash
python3 scripts/package.py --platform ipa --export-options-plist "/path/to/ExportOptions.plist"
```

此时执行 `flutter build ipa --release --export-options-plist=...`，只导出本次新生成的 IPA。ExportOptions.plist 的导出方式及证书必须匹配当前项目。参见 [Flutter iOS 发布文档](https://docs.flutter.dev/deployment/ios)。

### macOS

生成可拖入 Applications 安装的 DMG；沿用项目现有 App 签名设置，脚本不额外做 Developer ID 签名或公证。向其他用户公开分发时应单独完成对应签名与公证流程。

### Windows

默认通过 [Inno Setup](https://jrsoftware.org/isinfo.php) 生成 EXE 安装程序，包含完整 Release 目录，支持卸载、开始菜单快捷方式和可选桌面快捷方式，安装至当前用户目录。脚本不会自动下载 Inno Setup 或申请管理员权限。

支持自动查找 PATH 和常见安装目录，也可以指定编译器：

```powershell
py -3 scripts/package.py -p windows --iscc "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
```

`--windows-format zip` 不需要 Inno Setup；解压整个 ZIP 后运行 `kazumi.exe`，必须保留同目录 DLL 和 data 资源。安装程序及 ZIP 均未额外进行代码签名，目标电脑还需要应用依赖的 Microsoft Visual C++ x64 运行库及 WebView2 Runtime；脚本不捆绑这两个运行库。参见 [Flutter Windows 构建与分发文档](https://docs.flutter.dev/platform-integration/windows/building)。

## 构建配置与结果

需要编译期配置时可传入文件，路径中的空格需用引号包裹：

```bash
python3 scripts/package.py -p android --dart-define-from-file "/path/to/config.json"
```

也会沿用 CI 使用的 `DANDANAPI_APPID`、`DANDANAPI_KEY`、`KAZUMI_APPID`、`KAZUMI_KEY` 和 `UPDATE_REPOSITORY` 环境变量（仅传入已设置的项）。`UPDATE_REPOSITORY` 默认为 `AmazingZ-sys/Kazumi`，决定应用的 GitHub 更新仓库；Actions 自动使用当前仓库。脚本打印命令时隐藏这些值。避免将私有配置文件提交到仓库。

输出文件包含 `pubspec.yaml` 中的版本号。每次在导出目录内新建唯一子目录，已有安装包不会被覆盖。各平台依次构建；某个平台失败会继续尝试其余已选择的平台，最后汇总失败平台并返回退出码 1，已成功导出的文件保留。工具缺失、参数错误或依赖下载失败会直接退出。全部成功返回 0；手动中断返回 130。

## 脚本验证

```bash
python3 -m unittest discover -s scripts/tests -v
```

测试覆盖宿主选择、默认目录、构建失败、产物缺失、ZIP 内容和 IPA Payload/符号链接等行为；测试中的 Flutter 调用使用模拟替身。它们不代替在真实 SDK 和证书环境下完整构建及安装验证。

## GitHub Actions 构建与发布

`Fork packages and releases` 工作流在 `feat/drama-olevod`、`main` 分支推送时，以及手动运行时，执行测试与分析并产出 Android APK、iOS IPA、macOS DMG、Windows x64 ZIP。产物在 Actions 运行页的 Artifacts 下载；普通分支构建不创建 Release。每次运行前，请确认选择的是包含 fork 定制功能的分支。

正式发布时，先修改 `pubspec.yaml` 的版本并提交，再推送不含 `v` 前缀、与构建版本完全相同的数字 tag。例如 `version: 2.3.11+20311` 对应 tag `2.3.11`。工作流验证 tag 与版本一致，全部测试及四平台构建成功后发布当前仓库的 stable Release，并附带 `SHA256SUMS`。不要重写已经公开发布的 tag。

Android 正式发布需要以下仓库 Actions Secrets；keystore 和密码必须另行安全备份，不能提交到 Git：

| Secret | 内容 |
| --- | --- |
| `KAZUMI_ANDROID_KEYSTORE_BASE64` | 固定 JKS keystore 的 Base64 内容 |
| `KAZUMI_ANDROID_KEYSTORE_PASSWORD` | keystore 密码 |
| `KAZUMI_ANDROID_KEY_ALIAS` | 签名 key 的 alias |
| `KAZUMI_ANDROID_KEY_PASSWORD` | 签名 key 的密码 |

分支构建未配置签名时可生成 debug 签名 APK，正式 tag 发布则必须配置完整签名。API 服务凭据按需配置为同名 Secrets；缺失时部分弹幕或服务功能不可用，但不应阻止编译。

Windows 首版仅提供未签名便携 ZIP，解压整个目录后运行 `kazumi.exe`。未接入上游 SignPath，也不生成 MSIX。iOS IPA 必须重新签名侧载；macOS DMG 暂未添加 Developer ID 签名和公证。

应用只查询 `https://api.github.com/repos/<UPDATE_REPOSITORY>/releases/latest`，使用当前 Release 实际提供的平台附件。没有发布版本时按无更新处理；网络与权限错误仍报告失败。下载保留 SHA256 校验。此 fork 没有自己的更新镜像，因此默认使用 GitHub 下载，不再使用上游的版本元数据或镜像安装包。iOS 更新打开此 fork 的 Release 页面，安装需要自行重新签名。
