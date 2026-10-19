import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodCall, MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/dialog/update_available_dialog.dart';
import 'package:kazumi/bean/settings/settings_dropdown_tile.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/request/core/network_exception.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/update/auto_updater.dart';
import 'package:kazumi/services/update/update_download_source.dart';
import 'package:kazumi/services/update/update_downloader.dart';
import 'package:logger/logger.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

const _repository = String.fromEnvironment(
  'UPDATE_REPOSITORY',
  defaultValue: 'AmazingZ-sys/Kazumi',
);
const _releaseApi = 'https://api.github.com/repos/$_repository/releases/latest';
const _releasePage = 'https://github.com/$_repository/releases/latest';

Map<String, dynamic> _asset(String name, {bool mirror = false}) => {
  'name': name,
  'browser_download_url':
      'https://github.com/$_repository/releases/download/999.0.0/$name',
  if (mirror) 'mirror_download_url': 'https://mirror.example/$name',
  'digest': 'sha256:${'a' * 64}',
};

Map<String, dynamic> _release({
  String version = '999.0.0',
  List<dynamic> assets = const [],
}) => {
  'tag_name': version,
  'body': 'Fork release',
  'html_url': _releasePage,
  'published_at': '2026-10-19T00:00:00Z',
  'assets': assets,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late PathProviderPlatform originalPaths;
  late _RecordingAdapter adapter;

  setUpAll(() async {
    Logger.level = Level.off;
    directory = await Directory.systemTemp.createTemp('kazumi_fork_update_');
    originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TestPaths(directory.path);
    Hive.init(directory.path);
    await GStorage.init();
  });

  setUp(() {
    DioFactory.reset();
    adapter = _RecordingAdapter();
    DioFactory.downloadDio.httpClientAdapter.close();
    DioFactory.downloadDio.httpClientAdapter = adapter;
  });

  tearDownAll(() async {
    DioFactory.reset();
    await Hive.close();
    PathProviderPlatform.instance = originalPaths;
    await directory.delete(recursive: true);
  });

  test('release endpoint is the configured fork GitHub API', () {
    expect(ApiEndpoints.latestApp, _releaseApi);
  });

  test(
    'requests fork metadata once and preserves direct GitHub assets',
    () async {
      final asset = _asset('Kazumi_android_999.0.0.apk');
      adapter.respond = (_) => _response(200, _release(assets: [asset]));

      final update = await AutoUpdater().checkForUpdates();

      expect(adapter.requests.single.uri.toString(), _releaseApi);
      expect(update!.version, '999.0.0');
      expect(update.assets, [asset]);
      expect(
        getUpdateDownloadUrlFromAsset(
          update.assets.single,
          UpdateDownloadSource.github,
        ),
        asset['browser_download_url'],
      );
      expect(getUpdateFileHashFromAsset(update.assets.single), 'a' * 64);
    },
  );

  test(
    'no fork releases (404) means no update and makes no fallback request',
    () async {
      adapter.respond = (_) => _response(404, {'message': 'Not Found'});

      expect(await AutoUpdater().checkForUpdates(), isNull);
      expect(adapter.requests.single.uri.toString(), _releaseApi);
    },
  );

  for (final status in [403, 500]) {
    test(
      'fork API $status remains an error without a fallback request',
      () async {
        adapter.respond = (_) => _response(status, {'message': 'failure'});

        await expectLater(
          AutoUpdater().checkForUpdates(),
          throwsA(
            isA<NetworkException>().having(
              (error) => error.statusCode,
              'status',
              status,
            ),
          ),
        );
        expect(adapter.requests.single.uri.toString(), _releaseApi);
      },
    );
  }

  test('equal version does not request an update', () async {
    adapter.respond = (_) =>
        _response(200, _release(version: ApiEndpoints.version));
    expect(await AutoUpdater().checkForUpdates(), isNull);
  });

  test('accepts a v prefix at the release metadata boundary', () async {
    adapter.respond = (_) => _response(200, _release(version: 'v999.0.0'));
    expect((await AutoUpdater().checkForUpdates())!.version, 'v999.0.0');
  });

  test(
    'missing platform assets do not advertise an unavailable installer',
    () async {
      adapter.respond = (_) => _response(200, _release());

      final update = (await AutoUpdater().checkForUpdates())!;

      expect(update.availableInstallationTypes, isEmpty);
      expect(update.recommendedInstallationType, InstallationType.unknown);
      expect(update.recommendedInstallationType.downloadsInApp, isFalse);
    },
  );

  test('missing release web URL falls back to the fork release page', () async {
    adapter.respond = (_) => _response(200, _release()..remove('html_url'));
    expect((await AutoUpdater().checkForUpdates())!.releaseNotes, _releasePage);
  });

  test('types without in-app formats do not select an arbitrary asset', () {
    final assets = [_asset('Kazumi_android_999.0.0.apk')];
    expect(getUpdateAssetForType(assets, InstallationType.ios), isNull);
    expect(getUpdateAssetForType(assets, InstallationType.unknown), isNull);
  });

  test('Windows with only ZIP recommends the existing portable asset', () {
    final types = getAvailableUpdateInstallationTypes(
      [_asset('Kazumi_999.0.0_windows_x64.zip')],
      [InstallationType.windowsMsix, InstallationType.windowsPortable],
    );
    expect(types, [InstallationType.windowsPortable]);
    final info = UpdateInfo(
      version: '999.0.0',
      description: '',
      downloadUrl: '',
      releaseNotes: _releasePage,
      publishedAt: '',
      availableInstallationTypes: types,
    );
    expect(info.recommendedInstallationType, InstallationType.windowsPortable);
  });

  test('iOS IPA remains an external release-page update', () {
    expect(
      getAvailableUpdateInstallationTypes(
        [_asset('Kazumi_999.0.0_ipa_unsigned.ipa')],
        [InstallationType.ios],
      ),
      [InstallationType.ios],
    );
    expect(InstallationType.ios.downloadsInApp, isFalse);
  });

  test('checksum sidecars do not masquerade as platform packages', () {
    final package = _asset('Kazumi_999.0.0_windows_x64.zip');
    expect(
      getUpdateAssetForType([
        _asset('Kazumi_999.0.0_windows_x64.zip.sha256'),
        package,
      ], InstallationType.windowsPortable),
      same(package),
    );
  });

  test(
    'a network timeout remains visible without retrying another source',
    () async {
      adapter.respond = (options) => throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionTimeout,
      );
      await expectLater(
        AutoUpdater().checkForUpdates(),
        throwsA(
          isA<NetworkException>().having(
            (error) => error.type,
            'type',
            NetworkExceptionType.connectionTimeout,
          ),
        ),
      );
      expect(adapter.requests.single.uri.toString(), _releaseApi);
    },
  );

  test('missing SHA256 is rejected before any download begins', () async {
    await expectLater(
      downloadUpdateFile(
        url: 'https://github.com/unused.apk',
        filePath: '${directory.path}/missing-hash.apk',
        expectedHash: '',
        cancelToken: CancelToken(),
        onReceiveProgress: (_, _) {},
      ),
      throwsArgumentError,
    );
    expect(adapter.requests, isEmpty);
  });

  test('cached packages are reused only after their SHA256 matches', () async {
    final file = File('${directory.path}/verified.apk');
    await file.writeAsString('abc');
    final path = await downloadUpdateFile(
      url: 'https://github.com/unused.apk',
      filePath: file.path,
      expectedHash:
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      cancelToken: CancelToken(),
      onReceiveProgress: (_, _) {},
    );
    expect(path, file.path);
    expect(adapter.requests, isEmpty);
  });

  testWidgets('changing package type removes unavailable mirror sources', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: UpdateAvailableDialog(
          updateInfo: UpdateInfo(
            version: '999.0.0',
            description: 'Fork release',
            downloadUrl: '',
            releaseNotes: _releasePage,
            publishedAt: '',
            availableInstallationTypes: const [
              InstallationType.windowsMsix,
              InstallationType.windowsPortable,
            ],
            assets: [
              _asset('Kazumi_windows_999.0.0.msix', mirror: true),
              _asset('Kazumi_windows_999.0.0.zip'),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    var source = tester.widget<SettingsDropdownTile<UpdateDownloadSource>>(
      find.byType(SettingsDropdownTile<UpdateDownloadSource>),
    );
    expect(source.value, UpdateDownloadSource.github);
    expect(source.options.keys, UpdateDownloadSource.values);
    source.onChanged(UpdateDownloadSource.mirror);
    await tester.pumpAndSettle();
    final type = tester.widget<SettingsDropdownTile<InstallationType>>(
      find.byType(SettingsDropdownTile<InstallationType>),
    );
    type.onChanged(InstallationType.windowsPortable);
    await tester.pumpAndSettle();

    source = tester.widget<SettingsDropdownTile<UpdateDownloadSource>>(
      find.byType(SettingsDropdownTile<UpdateDownloadSource>),
    );
    expect(source.value, UpdateDownloadSource.github);
    expect(source.options.keys, [UpdateDownloadSource.github]);
  });

  testWidgets('release-page updates open the fork externally', (tester) async {
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return true;
    });
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    });
    adapter.respond = (_) => _response(200, _release()..remove('html_url'));
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: rootNavigatorKey,
        scaffoldMessengerKey: rootScaffoldMessengerKey,
        navigatorObservers: [KazumiDialog.observer],
        home: const Scaffold(body: Text('home')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() => AutoUpdater().manualCheckForUpdates());
    await tester.pumpAndSettle();
    expect(find.text('前往下载'), findsOneWidget);

    await tester.tap(find.text('前往下载'));
    await tester.pumpAndSettle();
    expect(find.text('前往下载'), findsNothing);
    // Metadata fetching started this dialog in runAsync's real event loop.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));

    expect(calls.single.method, 'launch');
    expect(calls.single.arguments['url'], _releasePage);
    expect(calls.single.arguments['useSafariVC'], isFalse);
    expect(calls.single.arguments['useWebView'], isFalse);
  });

  testWidgets('download dialog defaults to GitHub and omits a missing mirror', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: UpdateAvailableDialog(
          updateInfo: UpdateInfo(
            version: '999.0.0',
            description: 'Fork release',
            downloadUrl: '',
            releaseNotes: _releasePage,
            publishedAt: '',
            installationType: InstallationType.windowsPortable,
            availableInstallationTypes: const [
              InstallationType.windowsPortable,
            ],
            assets: [_asset('Kazumi_windows_999.0.0.zip')],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final source = tester.widget<SettingsDropdownTile<UpdateDownloadSource>>(
      find.byType(SettingsDropdownTile<UpdateDownloadSource>),
    );
    expect(source.value, UpdateDownloadSource.github);
    expect(source.options.keys, [UpdateDownloadSource.github]);
    expect(find.text('MSIX'), findsNothing);
  });
}

class _RecordingAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  FutureOr<ResponseBody> Function(RequestOptions)? respond;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return respond == null
        ? _response(200, _release())
        : await respond!(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _response(int status, Map<String, dynamic> data) =>
    ResponseBody.fromString(
      jsonEncode(data),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}
