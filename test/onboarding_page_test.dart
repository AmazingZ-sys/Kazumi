import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/pages/my/my_controller.dart';
import 'package:kazumi/pages/onboarding/onboarding_page.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/update/startup_update_check.dart';
import 'package:logger/logger.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

Future<void> _mountRulesStep(
  WidgetTester tester, {
  required String sourceType,
}) async {
  final controller = PluginsController(catalogLoader: () async => []);
  controller.pluginList.add(
    Plugin.fromJson({
      'name': sourceType == 'tv' ? '欧乐' : '番剧来源',
      'type': sourceType,
    }),
  );
  final module = createModule(
    register: (routes) => routes
      ..route(
        '/',
        child: (_, _) => OnboardingPage(
          pluginsController: controller,
          myController: _FakeMyController(),
        ),
      )
      ..route(
        '/home',
        child: (_, _) => const Scaffold(body: Text('startup destination')),
      ),
  );
  await tester.pumpWidget(
    ModularApp(
      module: module,
      navigatorObservers: [KazumiDialog.observer],
      defaultTransition: TransitionType.none,
      child: Builder(
        builder: (context) => MaterialApp.router(
          routerConfig: ModularApp.routerConfigOf(context),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('同意并继续'));
  await tester.pumpAndSettle();
  for (var i = 0; i < (Platform.isAndroid ? 2 : 1); i++) {
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
  }
}

Future<void> _finish(WidgetTester tester) async {
  await _tapWithStorage(tester, '开始使用');
}

Future<void> _tapWithStorage(WidgetTester tester, String label) async {
  await tester.runAsync(() async {
    await tester.tap(find.text(label));
    await Hive.box('setting').flush();
  });
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late PathProviderPlatform originalPaths;
  late Level originalLogLevel;

  setUpAll(() async {
    originalLogLevel = Logger.level;
    Logger.level = Level.off;
    directory = await Directory.systemTemp.createTemp('kazumi_onboarding_ui_');
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TestPaths(directory.path);
    Hive.init(directory.path);
    await GStorage.init();
  });

  setUp(() async {
    await GStorage.putSetting(SettingsKeys.onboardingCompleted, false);
    await GStorage.putSetting(SettingsKeys.autoUpdate, false);
    await GStorage.putSetting(SettingsKeys.defaultStartupPage, '/home');
  });

  tearDownAll(() async {
    // Finishing schedules a delayed check in the real IO zone above.
    await Future<void>.delayed(startupUpdateCheckDelay);
    await Hive.close();
    PathProviderPlatform.instance = originalPaths;
    Logger.level = originalLogLevel;
    await directory.delete(recursive: true);
  });

  testWidgets('TV-only sources require an explicit choice before finishing', (
    tester,
  ) async {
    await _mountRulesStep(tester, sourceType: 'tv');
    await _finish(tester);

    expect(find.text('暂不添加番剧来源？'), findsOneWidget);
    expect(GStorage.getSetting(SettingsKeys.onboardingCompleted), isFalse);
    expect(find.text('startup destination'), findsNothing);

    await tester.tap(find.text('返回添加'));
    await tester.pumpAndSettle();

    expect(find.text('暂不添加番剧来源？'), findsNothing);
    expect(find.text('开始使用'), findsOneWidget);
    expect(GStorage.getSetting(SettingsKeys.onboardingCompleted), isFalse);

    await _finish(tester);
    await _tapWithStorage(tester, '仍然继续');

    expect(GStorage.getSetting(SettingsKeys.onboardingCompleted), isTrue);
    expect(find.text('startup destination'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('anime sources complete onboarding without a skip dialog', (
    tester,
  ) async {
    await _mountRulesStep(tester, sourceType: 'anime');
    await _finish(tester);

    expect(find.byType(AlertDialog), findsNothing);
    expect(GStorage.getSetting(SettingsKeys.onboardingCompleted), isTrue);
    expect(find.text('startup destination'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _FakeMyController extends Fake implements MyController {}

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}
