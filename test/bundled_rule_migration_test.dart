import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:logger/logger.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late PathProviderPlatform originalPaths;
  late File pluginsFile;
  late Level originalLogLevel;

  setUp(() async {
    originalLogLevel = Logger.level;
    Logger.level = Level.off;
    directory = await Directory.systemTemp.createTemp('kazumi_rule_migration_');
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TestPaths(directory.path);
    pluginsFile = File('${directory.path}/plugins/v2/plugins.json');
    await pluginsFile.parent.create(recursive: true);
  });

  tearDown(() async {
    PathProviderPlatform.instance = originalPaths;
    Logger.level = originalLogLevel;
    await directory.delete(recursive: true);
  });

  Map<String, dynamic> legacyOlevod() {
    final rule =
        jsonDecode(File('assets/plugins/olevod.json').readAsStringSync())
            as Map<String, dynamic>;
    return rule
      ..['version'] = '1.0'
      ..['searchName'] = '//h4/a/text()[last()]';
  }

  test(
    'startup repairs persisted Olevod while preserving custom settings',
    () async {
      final oldRule = legacyOlevod()
        ..['userAgent'] = 'custom-agent'
        ..['referer'] = 'https://example.com/'
        ..['chapterRoads'] = '//ul[@id="custom"]';
      await pluginsFile.writeAsString(jsonEncode([oldRule]));

      final controller = PluginsController();
      await controller.init();
      final installed = controller.pluginList.singleWhere(
        (plugin) => plugin.name == '欧乐影院',
      );
      expect(installed.version, '1.0.1');
      expect(installed.searchName, '//h4/a/@title');
      expect(installed.userAgent, 'custom-agent');
      expect(installed.referer, 'https://example.com/');
      expect(installed.chapterRoads, '//ul[@id="custom"]');

      final persisted = (jsonDecode(await pluginsFile.readAsString()) as List)
          .singleWhere((rule) => rule['name'] == '欧乐影院');
      expect(persisted['searchName'], '//h4/a/@title');
      await controller.init();
      expect(
        controller.pluginList.where((p) => p.name == '欧乐影院'),
        hasLength(1),
      );
    },
  );

  for (final field in ['version', 'baseURL', 'searchURL', 'searchName']) {
    test('preserves an Olevod rule with a customized $field', () async {
      final rule = legacyOlevod()..[field] = 'custom-value';
      await pluginsFile.writeAsString(jsonEncode([rule]));
      final controller = PluginsController();
      await controller.init();
      final installed = controller.pluginList.singleWhere(
        (plugin) => plugin.name == '欧乐影院',
      );
      expect(installed.toJson()[field], 'custom-value');
      expect(installed.version, rule['version']);
      expect(installed.searchName, rule['searchName']);
    });
  }

  test('preserves customized older anime rules', () async {
    // Historical installed rules must survive even after their bundled assets
    // are removed upstream.
    final rule = <String, dynamic>{
      'api': '5',
      'type': 'anime',
      'name': 'DM84',
      'version': '0',
      'baseURL': 'https://dmbus.cc/',
      'searchURL': 'https://dmbus.cc/s----------.html?wd=@keyword',
      'searchList': '//div/div[3]/ul/li',
      'searchName': '//a[@id="custom"]',
      'searchResult': '//div/a[2]',
      'chapterRoads': '//div/div[4]/div/ul',
      'chapterResult': '//li/a',
    };
    await pluginsFile.writeAsString(jsonEncode([rule]));
    final controller = PluginsController();
    await controller.init();
    final installed = controller.pluginList.singleWhere(
      (p) => p.name == 'DM84',
    );
    expect(installed.version, '0');
    expect(installed.searchName, '//a[@id="custom"]');
  });
}

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}
