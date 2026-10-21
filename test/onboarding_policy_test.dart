import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/pages/onboarding/onboarding_policy.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:logger/logger.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late PathProviderPlatform originalPaths;
  late Level originalLogLevel;

  setUp(() async {
    originalLogLevel = Logger.level;
    Logger.level = Level.off;
    directory = await Directory.systemTemp.createTemp('kazumi_onboarding_');
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TestPaths(directory.path);
  });

  tearDown(() async {
    PathProviderPlatform.instance = originalPaths;
    Logger.level = originalLogLevel;
    await directory.delete(recursive: true);
  });

  Plugin rule(String type) => Plugin.fromJson({'name': type, 'type': type});

  test(
    'fresh install still needs onboarding after loading bundled TV rules',
    () async {
      final controller = PluginsController();
      await controller.init();

      expect(controller.pluginList.map((p) => p.name), contains('欧乐影院'));
      expect(hasAnimeSources(controller.pluginList), isFalse);
      expect(
        shouldShowOnboarding(completed: false, plugins: controller.pluginList),
        isTrue,
      );
    },
  );

  test(
    'affected TV-only install still needs onboarding on the next launch',
    () async {
      final firstLaunch = PluginsController();
      await firstLaunch.init();
      final nextLaunch = PluginsController();
      await nextLaunch.init();

      expect(nextLaunch.pluginList.map((p) => p.name), contains('欧乐影院'));
      expect(
        shouldShowOnboarding(completed: false, plugins: nextLaunch.pluginList),
        isTrue,
      );
    },
  );

  test(
    'legacy anime rules skip onboarding without a completion flag',
    () async {
      final pluginsFile = File('${directory.path}/plugins/v2/plugins.json');
      await pluginsFile.parent.create(recursive: true);
      await pluginsFile.writeAsString(
        jsonEncode([
          {'name': 'Legacy anime rule'},
        ]),
      );
      final controller = PluginsController();
      await controller.init();

      expect(hasAnimeSources(controller.pluginList), isTrue);
      expect(
        shouldShowOnboarding(completed: false, plugins: controller.pluginList),
        isFalse,
      );
    },
  );

  test('no installed rules requires onboarding', () {
    expect(shouldShowOnboarding(completed: false, plugins: []), isTrue);
  });

  test('TV and TVBox rules do not satisfy anime source onboarding', () {
    final plugins = [rule('tv'), rule('movie'), rule('tvbox')];
    expect(hasAnimeSources(plugins), isFalse);
    expect(shouldShowOnboarding(completed: false, plugins: plugins), isTrue);
  });

  test('anime type normalization matches drama search classification', () {
    final plugins = [rule('tv'), rule(' Anime ')];
    expect(hasAnimeSources(plugins), isTrue);
    expect(shouldShowOnboarding(completed: false, plugins: plugins), isFalse);
  });

  test('explicitly completed onboarding respects skipping anime rules', () {
    expect(shouldShowOnboarding(completed: true, plugins: []), isFalse);
    expect(
      shouldShowOnboarding(completed: true, plugins: [rule('tv')]),
      isFalse,
    );
  });
}

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}
