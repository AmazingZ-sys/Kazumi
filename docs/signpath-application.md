# SignPath Foundation 申请资料留档

资料日期：2026-10-19。**据维护者反馈，本 fork 的申请因项目影响力不足被拒。** 此状态来自维护者说明，本文不代表独立核验过的审核结论，也不表示获得 SignPath 授权。上游的服务授权不适用于本 fork。

本 fork 当前改用固定自签名 Authenticode 证书，为新 Windows 构建生成 EXE 安装程序和便携 ZIP；首次托管 CI 签名验证仍待完成。自签名不提供公共 CA 信任，也不保证消除 Windows 或 SmartScreen 提示。配置与密钥复用见[打包文档](packaging.md#windows)。已发布的 `2.3.12` 仍是历史未签名 ZIP，不因新流水线而变成签名发布。

下文保留原申请资料与将来获批后的接入参考，**不是当前正在执行的签名方案**。若未来重新申请，应重新核对官方申请表、条款及集成文档。

## 申请入口与适用范围

使用 [SignPath Foundation 开源项目申请表](https://signpath.org/apply)，申请开源项目的免费代码签名服务和 Foundation 证书。上游 [Kazumi 已列入 Foundation 项目](https://signpath.org/projects/kazumi/)，对应仓库是 `Predidit/Kazumi`，不包含本 fork 的授权。

原申请目标是对 Windows 自己构建的 `kazumi.exe` 做 Authenticode 签名，并将其装回完整便携 ZIP。若将来覆盖当前双格式产物，还需包含完成打包的 EXE 安装程序。ZIP 本身不是 Authenticode 签名对象；Android、iOS 和 macOS 的平台签名不由这次申请解决。

## 原申请步骤（重新申请时参考）

1. **准备公开资料。** 确保包含 fork 功能和最新文档的代码已推送至默认分支 `main`，仓库首页能展示一致的源码、fork 差异、隐私和 [Code signing policy](../README.md#code-signing-policy)。历史发布的构建证据使用对应 tag（本次为 `2.3.12`），便于核对实际源码；本地修改不会自动出现在 GitHub。
2. **检查申请条件。** 阅读 [Foundation 条件](https://signpath.org/terms)，确认项目及依赖许可、维护与发布状态；为 GitHub 和后续 SignPath 访问启用多因素认证，确定提交、审阅和签名批准人员。正式签名须人工批准且可追溯到源码。修改上游软件的 fork 还须保留可见 fork 关系，上游有签名构建，拟签名发布分支基于上游通常签名的分支，并履行对修改的审阅要求；申请时应说明这些来源关系。
3. **打开申请表。** 按下方资料填写。姓名、邮箱、组织和使用情况由维护者填写真实信息；阅读条款及个人数据处理同意项后自行决定提交，营销订阅是可选项。
4. **提供发布与构建证据。** 附上 `2.3.12` Release 和成功 Actions 链接；明确它是新 fork，并说明相对上游的修改。`Reputation` 是必填项，不能把上游的星标、下载量或签名资格当作本 fork 的成绩。
5. **等待并处理审核反馈。** 账户邀请、补充资料及配置安排以 SignPath 邮件为准。能提交申请不代表一定获批；官方会评估可核验的项目声誉。[申请条件与审核原则](https://signpath.org/terms)
6. **获批后配置并接入。** 按文末清单提供组织 / 项目 / 策略标识，在 GitHub 配置 Secret，随后修改工作流，验证签名后再发布新版本。

## 表单填写资料

以下是原先根据[官方申请表](https://signpath.org/apply)整理的字段资料，保留供参考；重新申请时以届时表单为准。建议项目显示名区分上游；它是申请名称建议，不表示已经修改 Windows 文件中的 ProductName。

| 字段 | 建议填写内容 |
| --- | --- |
| Project Name * | `Kazumi (AmazingZ-sys Fork)` |
| Repository URL * | `https://github.com/AmazingZ-sys/Kazumi` |
| Homepage URL * | `https://github.com/AmazingZ-sys/Kazumi`，不要填写上游 `kazumi.app` |
| Download URL | `https://github.com/AmazingZ-sys/Kazumi/releases` |
| Privacy Policy URL | `https://github.com/AmazingZ-sys/Kazumi#隐私政策` |
| Wikipedia URL (optional) | 留空；不借用其他项目的条目 |
| Tagline * | 使用下方英文文案 |
| Category * | 当前分类没有 Video / Multimedia，可选 `Other` |
| Description * | 使用下方英文文案 |
| Reputation * | 使用下方事实说明，后续补充本 fork 自己的真实使用证据 |
| Maintainer Type | 选择个人 / 独立维护者对应选项；以实际维护方式为准 |
| Build System * | 选择 GitHub Actions 对应选项 |
| First Name * / Last Name * | 维护者本人的姓名，用于创建 SignPath 账户 |
| Email * | 维护者常用、可收取账户邀请和审核通知的邮箱 |
| Company Name | 无对应组织或公司可留空 |
| Primary Discovery Channel * | 如从上游得知，选择 GitHub / 开源项目对应项，以当前菜单为准 |
| Please specify the exact source (optional) | `Predidit/Kazumi code signing policy: https://github.com/Predidit/Kazumi`（仅在符合实际情况时填写） |

### Tagline

```text
An independently maintained Kazumi fork with drama search and HTTP-based TVBox source configuration support.
```

### Description

```text
Kazumi (AmazingZ-sys Fork) is an independently maintained fork of Predidit/Kazumi, a Flutter-based application for watching anime and managing custom video-source rules. This fork extends the application with drama, movie and variety-show search, a built-in Olevod rule, and local management of compatible HTTP-based TVBox source configurations. It retains the upstream playback features and publishes its own builds and application updates from AmazingZ-sys/Kazumi. The source code is licensed under GPL-3.0. We are applying for Windows code signing for binaries built from this fork's public source repository.
```

### Reputation

```text
This is a new, independently maintained fork and it does not yet have broad independent adoption. Please assess it on its own public source history and releases.

Repository and fork relationship:
https://github.com/AmazingZ-sys/Kazumi

Published release 2.3.12, including a Windows x64 portable ZIP and SHA256SUMS:
https://github.com/AmazingZ-sys/Kazumi/releases/tag/2.3.12

Successful GitHub-hosted build and release workflow for that tag:
https://github.com/AmazingZ-sys/Kazumi/actions/runs/39208951179

Build workflow:
https://github.com/AmazingZ-sys/Kazumi/blob/2.3.12/.github/workflows/release.yaml

For upstream context only, Predidit/Kazumi is already listed by SignPath Foundation:
https://signpath.org/projects/kazumi/

The upstream project's reputation and signing authorization do not belong to this fork. This application requests separate evaluation and authorization for AmazingZ-sys/Kazumi.
```

这段提供的是可核验的构建与维护记录，不能替代实际用户认可。若已有本 fork 的讨论、使用反馈或下载统计，可另补链接；没有则保持上述说明。

## 原申请对应的技术信息

以下构建资料对应历史 `2.3.12`，当前自签名流程见打包文档与新工作流。

| 项目 | 申请时记录 |
| --- | --- |
| 维护者 | GitHub `AmazingZ-sys`：`https://github.com/AmazingZ-sys` |
| 上游 / 可见 fork | `Predidit/Kazumi`；GitHub API 确认本仓库为其 fork |
| 源码许可证 | 仓库根目录 [LICENSE](../LICENSE)，GPL-3.0 |
| 基准版本 | 本 fork `2.3.12+20312`，基于上游 `2.3.9`，并合入截至上游 `4effe14e` 的后续代码 |
| 已发布产物 | `Kazumi_2.3.12+20312_windows_x64.zip`，历史版本保持未签名 |
| 对应源码 | tag `2.3.12`，commit `75460859c7e2da07112af8fe7dc67bf7f80a1d0a` |
| 构建配置 | `.github/workflows/release.yaml`，Windows job 使用 GitHub 托管的 `windows-latest` |
| 历史构建入口 | `scripts/package.py --platform windows --windows-format zip`；新流水线使用 `--windows-format both` 并自签名 |
| 拟签名对象 | 此 fork 从源码编译的 `kazumi.exe`；第三方 DLL 保留原签名 / 原状，具体范围交由 artifact configuration 审核 |
| 维护与审批角色 | 建议由 `AmazingZ-sys` 作为初始提交和签名批准人员；审阅成员按实际团队填写，并由 SignPath 确认角色设置 |

申请时还应如实提供图标、字体及第三方库的许可信息。README 已注明图标为另行授权资源，不应把仓库内所有资源都描述为 GPL；授权是否覆盖 fork 分发及是否符合服务条件，请随材料交由审核确认。

## 下载页与签名策略声明

原申请材料包含以下历史未签名版本声明，供核对 `2.3.12` 时参考，不应用来描述当前自签名流水线：

```text
Code signing policy: The historical Windows ZIP published for AmazingZ-sys/Kazumi 2.3.12 is unsigned. The maintainer reports that this fork's SignPath application was declined due to insufficient project reputation. No SignPath approval or integration is claimed; the upstream project's authorization does not apply to this fork. New builds use this fork's self-signed Authenticode certificate, which does not provide public CA trust.

https://github.com/AmazingZ-sys/Kazumi#code-signing-policy
```

仅在将来获批并实际接入后，再按届时[官方签名策略要求](https://signpath.org/terms)添加服务归属、实际团队角色和隐私说明；在 README 与下载 / 发布页使用 `Code signing policy` 标题或链接。以下服务署名只供该情形参考，当前不能用于声称本 fork 获得服务：

```text
Free code signing provided by SignPath.io, certificate by SignPath Foundation.
```

## 将来获批后的接入参考

下列标识由 SignPath 后台确定，不要使用上游配置，也不要预先编造值：

| 信息 | 配置位置 / 用途 |
| --- | --- |
| Organization ID | SignPath 组织 ID，供 workflow 的 `organization-id` 使用 |
| Project slug | 本 fork 的项目标识，供 `project-slug` 使用 |
| Signing policy slug | 获批的签名策略标识，供 `signing-policy-slug` 使用 |
| Artifact configuration slug | 定义 ZIP 内的路径、允许签名的文件及元数据约束；使用后台实际值 |
| API token | 具备提交权限的 CI 身份 token，存入仓库 Actions Secret `SIGNPATH_API_TOKEN`；不要写进源码或聊天 |
| GitHub 集成 | 按后台指引关联本 fork 与 GitHub Trusted Build System；如要求安装 SignPath GitHub App，只授权所需仓库 |

接入后的发布顺序应为：GitHub 托管 runner 构建 → 上传未签名 Actions artifact → 提交签名请求 → 人工批准 → 下载签名后的文件 → 校验 Authenticode → 用签名后的内容生成最终 ZIP 与 `SHA256SUMS` → 发布 Release。

具体改动注意：

- 当前已使用 `actions/upload-artifact@v4`。需给上传步骤添加 `id`，把输出的 `artifact-id` 传给签名 action；当前官方集成示例使用 `signpath/github-action-submit-signing-request@v3`。[GitHub 集成文档](https://docs.signpath.io/trusted-build-systems/github)
- 上传 action 默认会加一层 ZIP，当前发布文件本身也是 ZIP。artifact configuration 必须匹配实际嵌套层级，或改为上传待签名的 Windows 目录；不要笼统签署所有第三方 DLL。
- 检查并修正 `windows/runner/Runner.rc` 的元数据：目前 `CompanyName` / Copyright 仍含 `com.example` 占位，`ProductName` 为 `kazumi`；签名配置应与最终 fork 名称、版本和文件路径一致。
- 旧版工作流自动发布未签名 Windows ZIP，当前已改为固定自签名方案。若将来接入 SignPath，必须等待该服务签名成功再计算校验和与发布，并为人工批准设置合适的等待时间；签名失败时不应误发为服务已签名版本。
- 在 Windows 用 `Get-AuthenticodeSignature` 核对 `kazumi.exe` 的状态与预期证书，并测试最终 ZIP；签名不会替代运行库 / WebView2 依赖，也不要据此承诺不会出现系统提示。

本文保留申请记录与未来接入参考；当前发布工作流使用本 fork 的固定自签名证书，没有集成 SignPath。
