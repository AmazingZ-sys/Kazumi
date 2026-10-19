<div align=center>

<h1>Kazumi · AmazingZ-sys Fork</h1>

<img src="assets/images/logo/logo_rounded.png" width=200></img>

<a href="https://github.com/AmazingZ-sys/Kazumi/releases/latest"><img src="https://img.shields.io/github/v/release/AmazingZ-sys/Kazumi?style=for-the-badge&label=Fork%20Release"></img></a>

<img src="https://img.shields.io/badge/Flutter-03A9F4?style=for-the-badge&logo=flutter&logoColor=white"></img>
<img src="https://img.shields.io/badge/Dart-00B4AB?style=for-the-badge&logo=Dart&logoColor=white"></img>

<p>基于 Flutter 的自定义规则番剧与影视播放器。在上游 Kazumi 的番剧体验上，增加剧集搜索、欧乐影院规则和影视仓 / TVBox 配置管理。</p>
</div>

本仓库是由 [AmazingZ-sys](https://github.com/AmazingZ-sys) 独立维护的 [Kazumi fork](https://github.com/AmazingZ-sys/Kazumi)，基于 [Predidit/Kazumi](https://github.com/Predidit/Kazumi)，沿用 GPL-3.0 许可证。上游提供番剧功能与播放器基础，本 fork 维护影视扩展及自己的发布流程。

请从[本 fork 的 Releases](https://github.com/AmazingZ-sys/Kazumi/releases/latest) 下载；本 fork 的发布包默认跟随本仓库检查应用更新。上游发布渠道、签名和社区认可不代表本 fork。

Actions 构建 Android APK、需重新签名侧载的 iOS IPA、macOS DMG，以及 Windows x64 EXE 安装程序和便携 ZIP。Windows 流水线使用本 fork 的固定自签名证书进行 Authenticode 签名，已于 2026-10-19 通过[四平台构建与 Windows 签名验证](https://github.com/AmazingZ-sys/Kazumi/actions/runs/39227772221)；自签名不保证 Windows 公共信任或消除 SmartScreen 提示。本次输出为 Actions Artifacts，未发布新 Release；已发布的 `2.3.12` 仍是历史未签名 ZIP。发布与签名说明见[打包文档](docs/packaging.md#github-actions-构建与发布)。

## 与上游项目的区别

以下功能对照以本 fork 的 `2.3.12` 发布版为基准：基于上游 `2.3.9`，并合入截至 `4effe14e` 的后续代码，不代表上游此后的功能范围；Windows 签名行另注明新流水线状态。

| 项目 | 上游 Predidit/Kazumi | 本 fork AmazingZ-sys/Kazumi |
| --- | --- | --- |
| 主要用途 | 基于自定义规则的番剧采集、追番与播放 | 保留番剧功能，增加电视剧、电影和综艺的来源搜索 |
| 剧集搜索 | 番剧搜索入口 | 新增「搜索电视剧」入口，使用非番剧规则搜索，按来源展示结果并接入现有播放器 |
| 欧乐影院 | 未内置本 fork 的欧乐规则 | 内置欧乐影院 XPath 规则，可在规则管理中查看和编辑 |
| 影视仓 / TVBox 配置 | 未包含本 fork 的配置管理功能 | 支持 URL / JSON 导入、预览、多配置管理、刷新及来源编辑，配置保存在本地 |
| 应用更新 | 跟随上游发布渠道 | 默认查询本仓库 GitHub Releases，按实际平台附件提供更新；自建时可通过 `UPDATE_REPOSITORY` 覆盖 |
| 打包与发布 | 上游自己的构建和签名流程 | 提供本地打包脚本和独立四平台 Actions；数字 tag 校验后发布安装包及 `SHA256SUMS` |
| Windows 签名 | 上游使用 SignPath 服务 | `2.3.12` 为未签名 ZIP；新流水线使用本 fork 固定自签名证书，生成 EXE 安装程序与便携 ZIP，不使用 SignPath |

TVBox 兼容范围限于 `type: 0 / 1 / 2 / 4` 的 HTTP(S) 采集接口；不支持 `type: 3` 的 JAR / JavaScript / Python Spider、多仓列表和加密配置。这里的 TVBox 指配置兼容，当前没有新增 Android TV / 遥控器专属适配。来源能否搜索和播放取决于接口与网络环境，详见[兼容范围](docs/tvbox-sources.md)。

番剧目录、弹幕、Anime4K 超分、DLNA 投屏、跨设备同步、一起看及番剧下载等能力继承自上游；规则商店目前也继续使用上游 [KazumiRules](https://github.com/Predidit/KazumiRules)。感谢上游作者和贡献者。

## 支持平台

- Android 10 及以上
- Windows 10 及以上 (x64；`2.3.12` 提供 ZIP，新流水线生成 EXE 安装程序与 ZIP)
- macOS 12 及以上
- iOS 15 及以上 (需要重新签名后[侧载](https://kazumi.app/docs/misc/how-to-install-in-ios))
- Linux (继承上游的实验性支持，当前 fork Actions 不构建或发布 Linux 包)

HarmonyOS 与 Web 可参考上游生态中的独立社区分支 [ErBWs/Kazumi](https://github.com/ErBWs/Kazumi/releases/latest) 和 [KazumiWeb](https://github.com/0Chencc/KazumiWeb/releases/latest)；这些项目独立维护，不是本 fork 的发布目标，也不保证包含这里的影视扩展。

## 屏幕截图

<table>
  <tr>
    <td><img alt="homepage" src="static/screenshot/img_1.png"></td>
    <td><img alt="timetable" src="static/screenshot/img_2.png"></td>
    <td><img alt="details" src="static/screenshot/img_3.png"></td>
  <tr>
  <tr>
    <td><img alt="selection-page" src="static/screenshot/img_4.png"></td>
    <td><img alt="rules-mange" src="static/screenshot/img_5.png"></td>
    <td><img alt="rules-edit" src="static/screenshot/img_6.png"></td>
  <tr>
</table>

## 功能 / 开发计划

- [X]  规则编辑器
- [X]  番剧目录
- [X]  番剧搜索
- [X]  剧集搜索 (电视剧、电影、综艺)
- [X]  欧乐影院规则
- [X]  影视仓 / TVBox 配置导入
- [X]  影视来源与配置管理
- [X]  番剧时间表
- [X]  番剧字幕
- [X]  分集播放
- [X]  视频播放器
- [X]  多视频源支持
- [X]  规则分享
- [X]  硬件加速
- [X]  高刷适配
- [X]  追番列表
- [X]  番剧弹幕
- [X]  在线更新
- [X]  历史记录
- [X]  倍速播放
- [X]  配色方案
- [X]  跨设备同步
- [X]  无线投屏 (DLNA)
- [X]  外部播放器播放
- [X]  超分辨率
- [X]  一起看
- [X]  番剧下载
- [ ]  番剧更新提醒
- [ ]  还有更多 (/・ω・＼)

### 剧集搜索与影视仓配置

本分支新增独立的剧集搜索入口。在搜索页点击「搜索电视剧」，即可使用已安装的非番剧规则搜索电视剧、电影或综艺；结果按来源展示，点击结果获取播放线路与剧集列表，并使用现有播放器观看。内置「欧乐影院」规则，支持通过规则管理查看和编辑。

在「剧集搜索」右上角或「设置 → 规则管理」打开「影视仓配置」：

- **导入配置**：填写 HTTP(S) 配置地址或直接粘贴 JSON，预览识别结果后保存；支持包含 `sites` 的配置、单个站点对象和站点数组，也可通过「一键导入远端配置」获取预设地址的配置。
- **管理来源**：多个配置可以共存，导入的兼容来源参与剧集搜索并保存在本地，重启后仍可使用。可以刷新、编辑或删除配置，也可以在规则管理中单独编辑或删除来源。
- **保留自定义设置**：刷新配置会保留单独修改或删除的来源；重新编辑并保存整个配置会重置这些单独调整。远端读取或保存失败时保留原有配置，启动时不自动联网刷新。

支持标准 XML 采集接口 (`type: 0`)、标准 JSON 采集接口 (`type: 1 / 2`) 和兼容的远程 HTTP 接口 (`type: 4`)。不支持 `type: 3` 的 JAR / JavaScript / Python Spider、多仓列表或加密配置。导入预览检查配置格式，实际搜索和播放取决于来源接口及网络环境。

详细格式、兼容范围及远端配置地址的设置方式见 [影视仓 / TVBox 配置说明](docs/tvbox-sources.md)。

## 本地打包

使用 `python3 scripts/package.py`（Windows 使用 `py -3 scripts/package.py`）打包当前系统支持的平台。支持 Android APK、iOS IPA、macOS DMG 和 Windows EXE/ZIP，可通过 `--platform` 选择平台、`--output` 指定导出目录；macOS 默认导出到 Downloads，Windows 默认导出到桌面。Windows 建议使用 `--platform windows --windows-format both` 同时导出两种格式；配置自签名凭据时还需要 PowerShell 7 (`pwsh`)。环境准备、固定密钥复用和参数示例见 [本地打包与导出](docs/packaging.md)。

## 下载

通过本页面 [Releases](https://github.com/AmazingZ-sys/Kazumi/releases/latest) 选项卡下载：

<a href="https://github.com/AmazingZ-sys/Kazumi/releases">
  <img src="static/svg/get_it_on_github.svg" alt="Get it on Github" width="200"/>
</a>

| 平台 | 本 fork 的发布包 | 安装与签名说明 |
| --- | --- | --- |
| Android | `.apk` | 使用本 fork 固定签名。与上游应用包名相同、签名不同，切换前请备份数据并卸载原版本 |
| iOS | `_no_sign.ipa` | 使用自己的证书 / 描述文件重新签名后侧载 |
| macOS | `.dmg` | 应用使用 ad-hoc 签名，尚未进行 Apple 公证 |
| Windows | 新流水线：`_windows_x64_setup.exe`、`_windows_x64.zip` | 使用本 fork 固定自签名证书，2026-10-19 已通过 CI 与下载后签名验证，产物见上方 Actions 链接；可能仍有系统信任提示。历史 `2.3.12` Release ZIP 未签名。ZIP 须完整解压后运行 `kazumi.exe`，保留 DLL 和 data 目录 |

每个正式版本附带 `SHA256SUMS` 供下载校验。Windows 签名状态见 [Code signing policy](#code-signing-policy)。

### 上游与社区下载渠道

以下 F-Droid、Flathub 和 AUR 入口沿用自上游文档，**不提供本 fork 的发布包**。要使用这里新增的影视功能，请使用上方本仓库 Releases。

#### Android（上游）

<a href="https://f-droid.org/packages/com.predidit.kazumi">
  <img src="https://fdroid.gitlab.io/artwork/badge/get-it-on-zh-hans.svg"
  alt="Get it on F-Droid" width="200">
</a>

#### GNU/Linux（上游 / 社区）

<a href="https://flathub.org/apps/io.github.Predidit.Kazumi">
  <img src="https://flathub.org/api/badge?svg&locale=zh-Hans" alt="Get it on Flathub" width="175"/>
</a>

##### Arch Linux

可以从 [AUR](http://aur.archlinux.org) 安装。

```bash
[yay/paru] -S kazumi # 从源码构建
[yay/paru] -S kazumi-bin # 二进制包
```

## 贡献

本 fork 的影视扩展与打包问题可通过[本仓库 Pull Requests](https://github.com/AmazingZ-sys/Kazumi/pulls) 提交改进。通用番剧规则可向上游 [KazumiRules](https://github.com/Predidit/KazumiRules) 贡献；规则中可自行决定是否署名，编写方法见[上游规则开发文档](https://kazumi.app/docs/rules/develop-rules)。

## Q&A

<details>
<summary>使用者 Q&A</summary>

#### Q: 为什么少数番剧中有广告？

A: 本项目未插入任何广告。广告来自视频源, 请不要相信广告中的任何内容, 并尽量选择没有广告的视频源观看。

#### Q: 为什么我启用超分辨率功能后播放卡顿？

A: 超分辨率功能对 GPU 性能要求较高, 如果没有在高性能独立显卡上运行 Kazumi, 尽量选择效率档而非质量档。对低分辨率视频源而非高分辨率视频源使用超分也可以降低性能消耗。

#### Q: 为什么播放视频时内存占用较高？

A: 本程序在视频播放时, 会尽可能多地缓存视频到内存, 以提供较好的观看体验。如果您的内存较为紧张, 可以在播放设置选项卡启用低内存模式, 这将限制缓存。

#### Q: 为什么少数番剧无法通过外部播放器观看？

A: 部分视频源的番剧使用了反盗链措施, 这可以被 Kazumi 解决, 但无法被外部播放器解决。

#### Q: 为什么下载的 Linux 版本缺少图标和托盘功能？

A: 使用 .deb 版本进行安装, tar.gz 版本仅为方便二次打包, 这一格式先天缺乏图标和托盘功能支持。

</details>

<details>
<summary>规则编写者 Q&A</summary>

#### Q: 为什么我的自定义规则无法实现检索？

A: 目前我们对 `Xpath` 语法的支持并不完整, 我们目前只支持以 `//` 开头的选择器。建议参照我们给出的示例规则构建自定义规则。

#### Q: 为什么我的自定义规则可以实现检索, 但不能实现观看？

A: 尝试关闭自定义规则的使用内置播放器选项, 这将尝试使用 `webview` 进行播放, 提高兼容性。但在内置播放器可用时, 建议启用内置播放器, 以获得更加流畅并带有弹幕的观看体验。

</details>

<details>
<summary>开发者 Q&A</summary>

#### Q: 我在尝试自行编译该项目, 但编译没有成功。

A: 本项目编译需要良好的网络环境, 除了由 Google 托管的 Flutter 相关依赖外, 本项目同样依赖托管在 MavenCentral/Github/SourceForge 上的资源。如果您位于中国大陆, 可能需要设置恰当的镜像地址。

</details>

## 开发

欢迎您提交 PR！在开始之前, 请阅读 [贡献指引](static/doc/CONTRIBUTING.md) 以了解我们对 PR 和 AI 参与辅助开发的规定。

## 美术资源

本项目图标来自 [Yuquanaaa](https://www.pixiv.net/users/66219277) 发表在 [Pixiv](https://www.pixiv.net/artworks/116666979) 上的作品。

此图标由其原作者 [Yuquanaaa](https://www.pixiv.net/users/66219277) 拥有版权。我们已获得原作者的授权和许可, 可以在本项目中使用这一图标。这一图标不是自由使用的, 未经原作者明确授权, 任何人不得擅自使用、复制、修改或分发这一图标。

本项目内嵌字体为 [Mi Sans](https://hyperos.mi.com/font/zh/details/sc/) 字体, 由 [Xiaomi](https://www.mi.com/index.html) 开发和拥有版权。

## 免责声明

本项目基于 GNU 通用公共许可证第 3 版（GPL-3.0）授权。我们不对其适用性、可靠性或准确性作出任何明示或暗示的保证。在法律允许的最大范围内, 作者和贡献者不承担任何因使用本软件而产生的直接、间接、偶然、特殊或后果性的损害赔偿责任。

使用本项目需遵守所在地法律法规, 不得进行任何侵犯第三方知识产权的行为。因使用本项目而产生的数据和缓存应在24小时内清除, 超出 24 小时的使用需获得相关权利人的授权。

## 隐私政策

我们不收集任何用户数据, 不使用任何遥测组件。

## Code signing policy

本 fork 维护与发布：[AmazingZ-sys](https://github.com/AmazingZ-sys)。隐私说明见[隐私政策](#隐私政策)。

- Android 正式发布使用本 fork 的固定签名。
- Windows 新流水线使用本 fork 的固定自签名代码签名证书，签署 `kazumi.exe` 和完成打包的 EXE 安装程序，再验证安装程序及 ZIP 内的程序。2026-10-19 的[成功构建](https://github.com/AmazingZ-sys/Kazumi/actions/runs/39227772221)已完成托管 runner 与下载后的本地签名校验，临时 runner 信任已清理；产物为 Actions Artifacts，已发布的 `2.3.12` Release ZIP 保持未签名。
- 公共证书及 SHA256 指纹保存在 [certificates](certificates/)，私钥和密码在仓库外安全备份，后续构建复用同一密钥。自签名不等于公共 CA 信任，也不保证消除 Windows 或 SmartScreen 提示。
- 据维护者反馈，本 fork 的 SignPath 申请因项目影响力不足被拒；本仓库没有 SignPath 授权，上游授权不适用于本 fork。

当前签名配置见[打包文档](docs/packaging.md#windows)；原申请材料保留于 [SignPath 申请资料留档](docs/signpath-application.md)，仅供将来参考。

## 上游赞助致谢

以下为上游项目的赞助与服务致谢，不代表本 fork 获得了相同服务。

| ![signpath](https://signpath.org/assets/favicon-50x50.png)                                                                                                                      | 上游项目的 Windows 签名由 [SignPath.io](https://about.signpath.io/) 和 [SignPath Foundation](https://signpath.org/) 提供；本 fork 尚未获得该服务。 |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| <img src="https://kilo.ai/favicon/favicon.svg" width="50">                                                                                                                      | **Automatic PR review provided by [Kilo Code](https://kilo.ai/), sponsored by the [Kilo OSS Program](https://kilo.ai/oss)**                   |
| <a href="https://m.do.co/c/0062035db3e4"><img src="https://opensource.nyc3.cdn.digitaloceanspaces.com/attribution/assets/SVG/DO_Logo_icon_blue.svg" width="50" height="50"></a> | **Cloud infrastructure is supported by [DigitalOcean](https://m.do.co/c/0062035db3e4)**                                                       |

## 致谢

特别感谢 [XpathSelector](https://github.com/simonkimi/xpath_selector) 这个优秀的项目是本项目的基石。

特别感谢 [弹弹play](https://www.dandanplay.com/) 本项目使用了 弹弹play开放平台 以提供弹幕交互。

特别感谢 [Bangumi](https://bangumi.tv/) 本项目使用了 Bangumi 开放 API 以提供番剧元数据。

特别感谢 [Anime4K](https://github.com/bloc97/Anime4K) 本项目使用 Anime4K 进行实时超分。

特别感谢 [SyncPlay](https://github.com/Syncplay/syncplay) 本项目使用 SyncPlay 协议并通过 SyncPlay 公共服务器实现一起看功能。

特别感谢 [所有贡献者](https://github.com/Predidit/Kazumi/graphs/contributors) 本项目因为你们变得更好。

特别感谢 [trace.moe](https://trace.moe) 本项目使用了 trace.moe 提供的图片识别番剧功能。

感谢 [media-kit](https://github.com/media-kit/media-kit) 本项目跨平台媒体播放能力来自 media-kit。

感谢 [avbuild](https://github.com/wang-bin/avbuild) 本项目使用了来自 avbuild 的树外补丁实现非标准视频流播放。

感谢 [hive](https://github.com/isar/hive) 本项目持久化储存能力来自 hive。
