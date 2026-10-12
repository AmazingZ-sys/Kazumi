import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/pages/plugin_editor/rule_dialogs.dart';
import 'package:kazumi/pages/plugin_editor/tvbox_config_page.dart';
import 'package:kazumi/pages/plugin_editor/tvbox_source_editor_page.dart';
import 'package:kazumi/pages/search/drama_search_page.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/plugins/tvbox_source_api.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:logger/logger.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

String _config(String name, {bool includeUnsupported = false}) => jsonEncode({
  'sites': [
    {'key': name, 'name': name, 'type': 1, 'api': 'https://media.test/api'},
    if (includeUnsupported)
      {'key': 'spider', 'name': '爬虫来源', 'type': 3, 'api': 'csp_Test'},
  ],
});

Future<void> _mount(WidgetTester tester, Widget page) async {
  await tester.pumpWidget(
    MaterialApp(navigatorObservers: [KazumiDialog.observer], home: page),
  );
  await tester.pumpAndSettle();
}

Future<void> _openEditor(WidgetTester tester) async {
  await tester.tap(find.text('添加配置'));
  await tester.pumpAndSettle();
}

Future<void> _fillEditor(WidgetTester tester, String name, String input) async {
  await tester.ensureVisible(find.byKey(const ValueKey('tvbox-name')));
  await tester.enterText(find.byKey(const ValueKey('tvbox-name')), name);
  await tester.ensureVisible(find.byKey(const ValueKey('tvbox-input')));
  await tester.enterText(find.byKey(const ValueKey('tvbox-input')), input);
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late PathProviderPlatform originalPaths;
  late Level originalLogLevel;

  setUpAll(() async {
    originalLogLevel = Logger.level;
    Logger.level = Level.off;
    directory = await Directory.systemTemp.createTemp('kazumi_tvbox_ui_');
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TestPaths(directory.path);
    Hive.init(directory.path);
    await GStorage.init();
  });

  tearDownAll(() async {
    await Hive.close();
    PathProviderPlatform.instance = originalPaths;
    Logger.level = originalLogLevel;
    await directory.delete(recursive: true);
  });

  testWidgets(
    'one click fetches remote config and repeated import updates it',
    (tester) async {
      final requests = <String>[];
      final controller = PluginsController(
        tvBoxConfigLoader: (url) async {
          requests.add(url);
          return _config('远端来源');
        },
        pluginJsonWriter: (_) async {},
      );
      await _mount(tester, TvBoxConfigPage(controller: controller));
      await tester.tap(find.text('一键导入远端配置'));
      await tester.pumpAndSettle();
      expect(requests, [TvBoxSourceApi.configUrl]);
      expect(controller.tvBoxSubscriptions, hasLength(1));
      expect(find.textContaining('已导入 1 个来源'), findsOneWidget);
      await tester.tap(find.text('一键导入远端配置'));
      await tester.pumpAndSettle();
      expect(controller.tvBoxSubscriptions, hasLength(1));
      expect(requests, hasLength(2));
    },
  );

  testWidgets('remote fetch disables actions and explains failure with retry', (
    tester,
  ) async {
    final response = Completer<String>();
    final controller = PluginsController(
      tvBoxConfigLoader: (_) => response.future,
      pluginJsonWriter: (_) async {},
    );
    await _mount(tester, TvBoxConfigPage(controller: controller));
    await tester.tap(find.text('一键导入远端配置'));
    await tester.pump();
    expect(find.text('正在获取远端配置'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '添加配置'))
          .onPressed,
      isNull,
    );
    response.completeError(const SocketException('offline'));
    await tester.pumpAndSettle();
    expect(find.textContaining('远端配置导入失败'), findsOneWidget);
    expect(find.textContaining('已部署'), findsOneWidget);
    expect(find.text('一键导入远端配置'), findsOneWidget);
    expect(controller.tvBoxSubscriptions, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('source edits retain ownership and playback settings', (
    tester,
  ) async {
    final controller = PluginsController(
      pluginJsonWriter: (_) async {},
      errorReporter: (_, _, _) {},
    );
    await controller.saveTvBoxConfig(name: '配置', input: _config('原始来源'));
    final original = controller.pluginList.single
      ..adBlocker = true
      ..referer = 'https://player.test/';
    await _mount(
      tester,
      TvBoxSourceEditorPage(controller: controller, plugin: original),
    );
    await tester.enterText(
      find.byKey(const ValueKey('tvbox-source-name')),
      '自定义名称',
    );
    await tester.enterText(
      find.byKey(const ValueKey('tvbox-source-json')),
      jsonEncode({
        'key': '原始来源',
        'name': '原始来源',
        'type': 1,
        'api': 'https://changed.test/api',
      }),
    );
    await tester.tap(find.text('保存来源'));
    await tester.pumpAndSettle();
    expect(controller.pluginList, hasLength(1));
    final updated = controller.pluginList.single;
    expect(updated.name, '自定义名称');
    expect(updated.subscriptionId, original.subscriptionId);
    expect(updated.tvBoxSite!.api, 'https://changed.test/api');
    expect(updated.adBlocker, isTrue);
    expect(updated.referer, 'https://player.test/');
  });

  testWidgets('source editor prevents changing source identity', (
    tester,
  ) async {
    final controller = PluginsController(pluginJsonWriter: (_) async {});
    await controller.saveTvBoxConfig(name: '配置', input: _config('原始来源'));
    final original = controller.pluginList.single;
    await _mount(
      tester,
      TvBoxSourceEditorPage(controller: controller, plugin: original),
    );
    await tester.enterText(
      find.byKey(const ValueKey('tvbox-source-json')),
      jsonEncode({
        'key': '其他来源',
        'name': '其他来源',
        'type': 1,
        'api': 'https://changed.test/api',
      }),
    );
    await tester.tap(find.text('保存来源'));
    await tester.pumpAndSettle();
    expect(find.textContaining('不能修改'), findsOneWidget);
    expect(controller.pluginList.single, same(original));
  });

  testWidgets('failed save keeps name and input available for retry', (
    tester,
  ) async {
    var failWrite = true;
    final controller = PluginsController(
      pluginJsonWriter: (_) async {
        if (failWrite) throw StateError('storage unavailable');
      },
      errorReporter: (_, _, _) {},
    );
    await _mount(tester, TvBoxConfigPage(controller: controller));
    await _openEditor(tester);
    final input = _config('电影来源');
    await _fillEditor(tester, '保留输入', input);
    await tester.ensureVisible(find.text('保存配置'));
    await tester.tap(find.text('保存配置'));
    await tester.pumpAndSettle();
    expect(find.textContaining('内容已保留'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('tvbox-input')))
          .controller!
          .text,
      input,
    );
    expect(controller.tvBoxSubscriptions, isEmpty);

    failWrite = false;
    await tester.tap(find.text('保存配置'));
    await tester.pumpAndSettle();
    expect(find.text('保留输入'), findsOneWidget);
    expect(controller.tvBoxSubscriptions, hasLength(1));
  });

  testWidgets('refresh failure leaves saved sources visible', (tester) async {
    var failLoad = false;
    final controller = PluginsController(
      tvBoxConfigLoader: (_) async {
        if (failLoad) throw const FormatException('地址返回的是网页，不是配置');
        return _config('电影来源');
      },
      pluginJsonWriter: (_) async {},
      errorReporter: (_, _, _) {},
    );
    await controller.saveTvBoxConfig(
      name: '远程配置',
      input: 'https://config.test',
    );
    await _mount(tester, TvBoxConfigPage(controller: controller));
    failLoad = true;
    await tester.tap(find.byTooltip('刷新 远程配置'));
    await tester.pumpAndSettle();
    expect(find.textContaining('不是配置'), findsOneWidget);
    expect(find.text('远程配置'), findsOneWidget);
    expect(controller.pluginList, hasLength(1));
  });

  testWidgets('pending preview tolerates editor disposal', (tester) async {
    final response = Completer<String>();
    final controller = PluginsController(
      tvBoxConfigLoader: (_) => response.future,
      pluginJsonWriter: (_) async {},
      errorReporter: (_, _, _) {},
    );
    await _mount(tester, TvBoxConfigPage(controller: controller));
    await _openEditor(tester);
    await _fillEditor(tester, '远程配置', 'https://config.test');
    await tester.tap(find.text('预览来源'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    response.complete(_config('电影来源'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('drama search reacts to installed source changes', (
    tester,
  ) async {
    final controller = PluginsController(pluginJsonWriter: (_) async {});
    await _mount(tester, DramaSearchPage(pluginsController: controller));
    expect(find.text('还没有安装剧集规则'), findsOneWidget);
    expect(find.byTooltip('影视仓配置'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '添加影视仓配置'), findsOneWidget);
    await controller.updatePlugin(
      Plugin.fromTemplate()
        ..name = '剧集来源'
        ..type = 'tv',
    );
    await tester.pumpAndSettle();
    expect(find.text('还没有安装剧集规则'), findsNothing);
    expect(find.text('搜索电视剧、电影或综艺'), findsNWidgets(2));
  });

  testWidgets('add rules offers TVBox configuration management', (
    tester,
  ) async {
    await _mount(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showRuleAddDialog(context),
            child: const Text('打开'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('影视仓配置'), findsOneWidget);
  });
}

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}
