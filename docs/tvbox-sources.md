# 影视仓 / TVBox 配置

在「剧集搜索」右上角或「设置 → 规则管理」打开「影视仓配置」。添加配置名称和 HTTP(S) 配置地址，也可以直接粘贴 JSON。先预览识别结果，再保存。导入后的来源参与剧集搜索，重启应用仍保留。

## 一键获取自己的远端配置

在「影视仓配置」点击 **一键导入远端配置**，会获取 `tvbox-source-api` 自动筛选的 `kazumi.json`，保存为本地订阅「远端精选影视仓」，并立即导入剧集搜索来源。再次点击会更新同一地址的订阅，保留你单独修改或删除的来源；如果已经手动添加过相同地址，会复用该订阅和名称。

默认地址：`https://amazingz-sys.github.io/tvbox-source-api/kazumi.json`。

该地址需要先按照 **tvbox-source-api 项目的 README** 启用 GitHub Actions / Pages，并成功发布一次。地址尚未部署、网络失败、返回内容不兼容或没有可用来源时，会显示错误并保留已有本地配置。应用启动只读本地快照，不会自动联网拉取。

`tvbox-source-api` 是独立项目，负责发现上游、递归展开仓库、检测 HTTP 来源和发布 JSON；本项目只获取已生成的 `kazumi.json`。`warehouse.json` 是提供给支持多仓的 TVBox/影视仓客户端的列表，不要作为本项目的一键导入地址。

如果部署到其他账号或域名，可直接「添加配置」填入新地址，也可在构建时修改一键按钮的默认地址：

```bash
flutter run -d macos \
  --dart-define=TVBOX_SOURCE_API_URL=https://your-host.example/kazumi.json
```

同样的 `--dart-define` 参数适用于 `flutter build apk` / `flutter build macos`。对应常量为 `lib/plugins/tvbox_source_api.dart`。服务端筛选检查的是配置可读取、搜索 API 返回结构兼容，不保证每部影片均可播放，也不代表当前设备的网络一定可达。

开发时可用服务端实际生成的文件验证两端格式兼容：

```bash
TVBOX_GENERATED_CONFIG=/Users/zhix/Documents/project/tvbox-source-api/public/kazumi.json \
  flutter test --no-pub test/tvbox_source_api_contract_test.dart
```

## 手动导入格式

支持以下输入：包含 `sites` 的配置对象、单个站点对象、站点数组。允许 JSON 注释和尾逗号。每个站点至少需要 `key`、`name`、`type`、`api`。

```json
{
  "sites": [
    {
      "key": "my-source",
      "name": "我的影视源",
      "type": 1,
      "api": "https://your-server.example/api.php/provide/vod/",
      "searchable": 1
    }
  ]
}
```

示例域名仅用于展示格式，需要替换为你实际使用的接口。

| 类型 | 支持范围 |
| --- | --- |
| 0 | 标准 XML 采集接口 |
| 1 / 2 | 标准 JSON 采集接口，`vod_id`、`vod_name`、`vod_play_from`、`vod_play_url` |
| 4 | 远程 HTTP 接口，选中剧集时请求播放地址，支持直链与网页嗅探 |
| 3 | 不支持 JAR / JavaScript / Python Spider，导入时显示原因 |

自定义执行脚本、多仓列表、加密配置、需要特殊解析运行时的站点不会当作普通 API 安装。站点是否可访问、内容是否可播放取决于接口本身；预览只检查配置格式，不测试每个站点的网络可用性。

## 后续维护

- **添加配置**：多个配置可以共存，同名来源自动分配不同的显示名。
- **刷新**：重新读取地址；保留在规则管理中单独编辑或删除的来源。远程读取、解析或保存失败会保留上次成功的配置。
- **编辑配置**：修改名称、地址或 JSON 并重新保存，会用新配置重新生成关联来源，并重置这些来源的单独修改与删除记录。
- **修改单个来源**：在规则管理点开该来源，编辑显示名称及站点 JSON。站点 `key` 保持不变。
- **删除**：可以在规则管理只删除单个来源，也可以在配置管理删除配置及其全部关联来源。

配置名称、地址/原始 JSON、上次成功导入内容及关联规则保存在应用支持目录的 `plugins/v2/plugins.json`。应用启动只读取本地保存结果，不自动访问配置地址。配置与规则作为同一份快照写入；无配置时保留原有规则数组格式，有配置时使用带版本号的对象格式，仍可读取旧数组文件。请勿将新格式文件交给旧版应用覆盖写入。
