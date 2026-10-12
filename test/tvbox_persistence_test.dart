import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/plugins/tvbox_source_api.dart';
import 'package:logger/logger.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

String config({String api = 'https://media.test/api', String key = 'one'}) =>
    jsonEncode({
      'sites': [
        {'key': key, 'name': '视频', 'type': 1, 'api': api},
      ],
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late PathProviderPlatform previousPaths;
  late Level previousLogLevel;

  setUp(() async {
    previousLogLevel = Logger.level;
    Logger.level = Level.off;
    directory = await Directory.systemTemp.createTemp('kazumi_tvbox_');
    previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(directory.path);
  });
  tearDown(() async {
    PathProviderPlatform.instance = previousPaths;
    Logger.level = previousLogLevel;
    await directory.delete(recursive: true);
  });

  test(
    'remote import fetches the default URL and survives offline restart',
    () async {
      final requested = <String>[];
      final controller = PluginsController(
        tvBoxConfigLoader: (url) async {
          requested.add(url);
          return config();
        },
      );
      await controller.init();
      await controller.fetchRemoteTvBoxConfig();
      expect(requested, [TvBoxSourceApi.configUrl]);
      final subscription = controller.tvBoxSubscriptions.single;
      expect(subscription.input, TvBoxSourceApi.configUrl);
      final restored = PluginsController(
        tvBoxConfigLoader: (_) async {
          fail('Startup must use the locally imported snapshot');
        },
      );
      await restored.init();
      expect(restored.tvBoxSubscriptions.single.id, subscription.id);
      expect(
        restored.pluginList.where((p) => p.subscriptionId == subscription.id),
        hasLength(1),
      );
    },
  );

  test(
    'concurrent remote imports reuse a manually added subscription',
    () async {
      final controller = PluginsController(
        tvBoxConfigLoader: (_) async => config(),
        pluginJsonWriter: (_) async {},
      );
      await controller.saveTvBoxConfig(
        name: '自定义订阅名',
        input: TvBoxSourceApi.configUrl,
      );
      final id = controller.tvBoxSubscriptions.single.id;
      await Future.wait([
        controller.fetchRemoteTvBoxConfig(),
        controller.fetchRemoteTvBoxConfig(),
      ]);
      expect(controller.tvBoxSubscriptions, hasLength(1));
      expect(controller.tvBoxSubscriptions.single.id, id);
      expect(controller.tvBoxSubscriptions.single.name, '自定义订阅名');
      expect(controller.pluginList, hasLength(1));
    },
  );

  test(
    'remote updates preserve local edits and deletions, failures preserve disk',
    () async {
      var response = jsonEncode({
        'sites': [
          {'key': 'one', 'name': '一', 'type': 1, 'api': 'https://one.test/api'},
          {'key': 'two', 'name': '二', 'type': 1, 'api': 'https://two.test/api'},
        ],
      });
      final controller = PluginsController(
        tvBoxConfigLoader: (_) async => response,
      );
      await controller.init();
      await controller.fetchRemoteTvBoxConfig();
      final id = controller.tvBoxSubscriptions.single.id;
      final owned = controller.pluginList
          .where((p) => p.subscriptionId == id)
          .toList();
      await controller.updatePlugin(
        Plugin.fromJson(owned.first.toJson())..referer = 'https://local.test/',
      );
      await controller.removePlugin(owned.last);
      await controller.fetchRemoteTvBoxConfig();
      expect(
        controller.pluginList.where((p) => p.subscriptionId == id),
        hasLength(1),
      );
      expect(
        controller.pluginList
            .singleWhere((p) => p.subscriptionId == id)
            .referer,
        'https://local.test/',
      );
      final file = File('${directory.path}/plugins/v2/plugins.json');
      final before = file.readAsStringSync();
      for (final invalid in ['<html>404</html>', '{"sites":[]}']) {
        response = invalid;
        await expectLater(
          controller.fetchRemoteTvBoxConfig(),
          throwsA(isA<FormatException>()),
        );
        expect(file.readAsStringSync(), before);
      }
    },
  );

  test(
    'custom endpoint is fetched and invalid endpoint does not mutate',
    () async {
      final requested = <String>[];
      final controller = PluginsController(
        tvBoxConfigLoader: (url) async {
          requested.add(url);
          return config();
        },
        pluginJsonWriter: (_) async {},
      );
      await controller.fetchRemoteTvBoxConfig(
        url: ' https://custom.test/kazumi.json ',
      );
      expect(requested, ['https://custom.test/kazumi.json']);
      for (final invalid in ['', 'file:///tmp/config.json', '{"sites":[]}']) {
        await expectLater(
          controller.fetchRemoteTvBoxConfig(url: invalid),
          throwsA(isA<FormatException>()),
        );
      }
      expect(requested, hasLength(1));
      expect(controller.tvBoxSubscriptions, hasLength(1));
    },
  );

  test(
    'configuration and generated sources survive a fresh controller',
    () async {
      final controller = PluginsController(
        tvBoxConfigLoader: (_) async => config(),
      );
      await controller.init();
      await controller.saveTvBoxConfig(
        name: '我的配置',
        input: 'https://config.test/box.json',
      );
      final subscription = controller.tvBoxSubscriptions.single;
      final source = controller.pluginList.singleWhere(
        (p) => p.subscriptionId == subscription.id,
      );
      expect(source.type, 'tv');

      final restored = PluginsController(
        tvBoxConfigLoader: (_) async => throw StateError('offline'),
      );
      await restored.init();
      expect(
        restored.tvBoxSubscriptions.single.input,
        'https://config.test/box.json',
      );
      expect(restored.tvBoxSubscriptions.single.snapshot, config());
      expect(
        restored.pluginList
            .singleWhere((p) => p.subscriptionId == subscription.id)
            .name,
        source.name,
      );
      expect(
        restored.pluginList
            .singleWhere((p) => p.subscriptionId == subscription.id)
            .tvBoxSite!
            .api,
        'https://media.test/api',
      );
    },
  );

  test('edit replaces owned sources and delete survives restart', () async {
    final controller = PluginsController();
    await controller.init();
    final unrelated = Plugin.fromTemplate()..name = '保留的规则';
    await controller.updatePlugin(unrelated);
    await controller.saveTvBoxConfig(name: '配置', input: config());
    final id = controller.tvBoxSubscriptions.single.id;
    await controller.saveTvBoxConfig(
      id: id,
      name: '新名称',
      input: config(api: 'https://new.test/api', key: 'two'),
    );
    expect(controller.tvBoxSubscriptions.single.name, '新名称');
    expect(
      controller.pluginList.where((p) => p.subscriptionId == id),
      hasLength(1),
    );
    expect(
      controller.pluginList
          .singleWhere((p) => p.subscriptionId == id)
          .tvBoxSite!
          .api,
      'https://new.test/api',
    );
    await controller.removeTvBoxConfig(id);
    final restored = PluginsController();
    await restored.init();
    expect(restored.tvBoxSubscriptions, isEmpty);
    expect(restored.pluginList.where((p) => p.subscriptionId == id), isEmpty);
    expect(
      restored.pluginList.where((p) => p.name == unrelated.name),
      hasLength(1),
    );
  });

  test(
    'failed remote refresh preserves last successful config and rules',
    () async {
      var response = config();
      final controller = PluginsController(
        tvBoxConfigLoader: (_) async => response,
      );
      await controller.init();
      await controller.saveTvBoxConfig(
        name: '配置',
        input: 'https://config.test/box',
      );
      final id = controller.tvBoxSubscriptions.single.id;
      final before = File(
        '${directory.path}/plugins/v2/plugins.json',
      ).readAsStringSync();
      response = '<html>not a configuration</html>';
      await expectLater(
        controller.refreshTvBoxConfig(id),
        throwsA(isA<FormatException>()),
      );
      expect(controller.tvBoxSubscriptions.single.snapshot, config());
      expect(
        File('${directory.path}/plugins/v2/plugins.json').readAsStringSync(),
        before,
      );
    },
  );

  test('failed write rolls back rules and configuration together', () async {
    var failWrite = false;
    final controller = PluginsController(
      pluginJsonWriter: (_) async {
        if (failWrite) throw const FileSystemException('disk full');
      },
      errorReporter: (_, _, _) {},
    );
    await controller.init();
    await controller.saveTvBoxConfig(name: '配置', input: config());
    final id = controller.tvBoxSubscriptions.single.id;
    failWrite = true;
    await expectLater(
      controller.removeTvBoxConfig(id),
      throwsA(isA<FileSystemException>()),
    );
    expect(controller.tvBoxSubscriptions.single.id, id);
    expect(
      controller.pluginList.where((p) => p.subscriptionId == id),
      hasLength(1),
    );
    await expectLater(
      controller.saveTvBoxConfig(
        id: id,
        name: '新名称',
        input: config(key: 'two'),
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(controller.tvBoxSubscriptions.single.name, '配置');
    expect(
      controller.pluginList
          .singleWhere((p) => p.subscriptionId == id)
          .tvBoxSite!
          .key,
      'one',
    );
  });

  test(
    'same source names from separate configurations remain independent',
    () async {
      final controller = PluginsController();
      await controller.init();
      await controller.updatePlugin(Plugin.fromTemplate()..name = '配置 · 视频');
      await controller.saveTvBoxConfig(name: '配置', input: config());
      await controller.saveTvBoxConfig(
        name: '配置',
        input: config(api: 'https://second.test/api'),
      );
      final ids = controller.tvBoxSubscriptions.map((s) => s.id).toList();
      final owned = controller.pluginList
          .where((p) => p.subscriptionId != null)
          .toList();
      expect(owned, hasLength(2));
      expect(
        controller.pluginList.map((p) => p.name.toLowerCase()).toSet().length,
        controller.pluginList.length,
      );
      await controller.removeTvBoxConfig(ids.first);
      expect(
        controller.pluginList.where((p) => p.subscriptionId == ids.last),
        hasLength(1),
      );
      expect(
        controller.pluginList.where((p) => p.name == '配置 · 视频'),
        hasLength(1),
      );
    },
  );

  test('refresh retains local edits and deletions across restart', () async {
    var response = jsonEncode({
      'sites': [
        {'key': 'one', 'name': '一', 'type': 1, 'api': 'https://one.test/api'},
        {'key': 'two', 'name': '二', 'type': 1, 'api': 'https://two.test/api'},
      ],
    });
    final controller = PluginsController(
      tvBoxConfigLoader: (_) async => response,
    );
    await controller.init();
    await controller.saveTvBoxConfig(
      name: '配置',
      input: 'https://config.test/box',
    );
    final id = controller.tvBoxSubscriptions.single.id;
    final owned = controller.pluginList
        .where((p) => p.subscriptionId == id)
        .toList();
    final edited = Plugin.fromJson(owned.first.toJson())
      ..referer = 'https://custom.test/';
    await controller.updatePlugin(edited);
    await controller.removePlugin(owned.last);
    final restored = PluginsController(
      tvBoxConfigLoader: (_) async => response,
    );
    await restored.init();
    response = jsonEncode({
      'sites': [
        {
          'key': 'one',
          'name': '一改名',
          'type': 1,
          'api': 'https://new-one.test/api',
        },
        {'key': 'two', 'name': '二', 'type': 1, 'api': 'https://two.test/api'},
        {
          'key': 'three',
          'name': '三',
          'type': 1,
          'api': 'https://three.test/api',
        },
      ],
    });
    await restored.refreshTvBoxConfig(id);
    final refreshed = restored.pluginList
        .where((p) => p.subscriptionId == id)
        .toList();
    expect(refreshed.map((p) => p.tvBoxSite!.key), ['one', 'three']);
    expect(refreshed.first.referer, 'https://custom.test/');
    expect(refreshed.first.name, edited.name);
    await restored.refreshTvBoxConfig(id);
    expect(
      restored.pluginList.where((p) => p.subscriptionId == id),
      hasLength(2),
    );
  });

  test(
    'a configuration without compatible sources cannot erase installed ones',
    () async {
      final controller = PluginsController();
      await controller.init();
      await controller.saveTvBoxConfig(name: '配置', input: config());
      final id = controller.tvBoxSubscriptions.single.id;
      await expectLater(
        controller.saveTvBoxConfig(id: id, name: '配置', input: '{"sites":[]}'),
        throwsA(isA<FormatException>()),
      );
      expect(
        controller.pluginList.where((p) => p.subscriptionId == id),
        hasLength(1),
      );
    },
  );
}

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}
