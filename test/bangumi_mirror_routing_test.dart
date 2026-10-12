import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/request/clients/bangumi_client.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/request/core/network_exception.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/bangumi_mirror_credentials.dart';
import 'package:logger/logger.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

void main() {
  final signedBuild = bangumiMirrorCredentials.values.every(
    (value) => value.trim().isNotEmpty,
  );
  late Directory directory;
  late PathProviderPlatform originalPathProvider;
  late _RecordingAdapter adapter;

  setUpAll(() async {
    Logger.level = Level.off;
    directory = await Directory.systemTemp.createTemp('kazumi_mirror_routing_');
    originalPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TestPaths(directory.path);
    Hive.init(directory.path);
    await GStorage.init();
  });

  setUp(() async {
    await GStorage.putSetting(SettingsKeys.bangumiAcceleration, 'mirror');
    await GStorage.putSetting(SettingsKeys.bangumiSyncEnable, false);
    await GStorage.putSetting(SettingsKeys.bangumiAccessToken, '');
    DioFactory.reset();
    adapter = _RecordingAdapter();
    DioFactory.bangumiDio.httpClientAdapter.close();
    DioFactory.bangumiDio.httpClientAdapter = adapter;
  });

  tearDownAll(() async {
    DioFactory.reset();
    await Hive.close();
    PathProviderPlatform.instance = originalPathProvider;
    await directory.delete(recursive: true);
  });

  void expectProtectedRoute(RequestOptions request, String officialHost) {
    expect(request.uri.host, signedBuild ? 'api.kazumi.fyi' : officialHost);
    expect(request.extra['bangumiEch'], signedBuild ? isNull : isTrue);
    final headers = request.headers.map(
      (name, value) => MapEntry(name.toLowerCase(), value),
    );
    if (signedBuild) {
      expect(headers['x-appid'], bangumiMirrorCredentials['id']);
      expect(headers['x-timestamp'], isA<int>());
      expect(headers['x-signature'], isNotEmpty);
    } else {
      expect(headers.containsKey('x-appid'), isFalse);
      expect(headers.containsKey('x-timestamp'), isFalse);
      expect(headers.containsKey('x-signature'), isFalse);
    }
    expect(GStorage.getSetting(SettingsKeys.bangumiAcceleration), 'mirror');
  }

  test(
    'routes protected search while preserving body and pagination',
    () async {
      final body = {
        'keyword': '海贼王',
        'filter': {
          'type': [2],
          'nsfw': false,
        },
      };
      await BangumiClient.instance.post(
        'https://api.bgm.tv/v0/search/subjects?limit=20',
        queryParameters: {'offset': 40},
        data: body,
      );
      final request = adapter.requests.single;
      expectProtectedRoute(request, 'api.bgm.tv');
      expect(request.method, 'POST');
      expect(request.uri.path, '/v0/search/subjects');
      expect(request.uri.queryParameters, {'limit': '20', 'offset': '40'});
      expect(request.data, body);
    },
  );

  for (final resource in ['subjects', 'episodes', 'characters']) {
    test(
      'routes protected $resource comments and retains authorization',
      () async {
        await BangumiClient.instance.get(
          'https://next.bgm.tv/p1/$resource/1/comments',
          queryParameters: {'limit': 10, 'offset': 20},
          requiresAuth: true,
          accessToken: 'test-access-token',
        );
        final request = adapter.requests.single;
        expectProtectedRoute(request, 'next.bgm.tv');
        expect(request.uri.path, '/p1/$resource/1/comments');
        expect(request.uri.queryParameters, {'limit': '10', 'offset': '20'});
        expect(request.headers['Authorization'], 'Bearer test-access-token');
      },
    );
  }

  test(
    'keeps other public and account requests on the selected mirror',
    () async {
      for (final path in ['/v0/subjects/1', '/v0/me']) {
        await BangumiClient.instance.get(
          'https://api.bgm.tv$path',
          requiresAuth: true,
          accessToken: 'test-access-token',
        );
        final request = adapter.requests.last;
        expect(request.uri, Uri.parse('https://api.kazumi.fyi$path'));
        expect(request.extra['bangumiEch'], isNull);
        expect(request.headers['Authorization'], 'Bearer test-access-token');
        expect(request.headers.containsKey('X-Signature'), isFalse);
      }
    },
  );

  test('keeps explicit direct mode and OAuth hosts unchanged', () async {
    await GStorage.putSetting(SettingsKeys.bangumiAcceleration, 'direct');
    await BangumiClient.instance.post(
      'https://api.bgm.tv/v0/search/subjects',
      data: {'keyword': 'test'},
    );
    expect(adapter.requests.last.uri.host, 'api.bgm.tv');
    expect(adapter.requests.last.extra['bangumiEch'], isNull);
    expect(adapter.requests.last.headers.containsKey('X-Signature'), isFalse);

    await GStorage.putSetting(SettingsKeys.bangumiAcceleration, 'mirror');
    await BangumiClient.instance.post(
      'https://bgm.tv/oauth/access_token',
      data: {'grant_type': 'authorization_code'},
    );
    expect(adapter.requests.last.uri.host, 'bgm.tv');
    expect(adapter.requests.last.extra['bangumiEch'], isNull);
    expect(adapter.requests.last.headers.containsKey('X-Signature'), isFalse);
  });

  group(
    'mirror 401 fallback',
    () {
      test(
        'retries search once through official ECH with the same body and query',
        () async {
          final body = {
            'keyword': '海贼王 & test',
            'filter': {
              'type': [2],
            },
          };
          final token = CancelToken();
          adapter.respond = (request) => _response(
            request.uri.host == 'api.kazumi.fyi' ? 401 : 200,
            body: '{"data":[{"name":"result"}]}',
          );
          final result = await BangumiClient.instance.post(
            'https://api.bgm.tv/v0/search/subjects?limit=20&tag=a%2Bb&tag=c%26d',
            queryParameters: {'offset': 40, 'q': 'a & b'},
            data: body,
            cancelToken: token,
          );

          expect(result['data'].single['name'], 'result');
          expect(adapter.requests, hasLength(2));
          final first = adapter.requests.first;
          final retry = adapter.requests.last;
          expect(first.uri.host, 'api.kazumi.fyi');
          expect(first.headers['X-Signature'], isNotEmpty);
          expect(retry.uri.host, 'api.bgm.tv');
          expect(retry.uri.path, first.uri.path);
          expect(retry.uri.query, first.uri.query);
          expect(retry.uri.queryParametersAll, {
            'limit': ['20'],
            'tag': ['a+b', 'c&d'],
            'offset': ['40'],
            'q': ['a & b'],
          });
          expect(retry.data, body);
          expect(retry.method, 'POST');
          expect(retry.extra['bangumiEch'], isTrue);
          expect(retry.cancelToken, same(token));
          expect(
            retry.headers.keys.map((key) => key.toLowerCase()),
            isNot(
              anyOf(
                contains('x-appid'),
                contains('x-timestamp'),
                contains('x-signature'),
              ),
            ),
          );
          expect(first.headers['X-Signature'], isNotEmpty);
          expect(
            GStorage.getSetting(SettingsKeys.bangumiAcceleration),
            'mirror',
          );
        },
      );

      for (final resource in ['subjects', 'episodes', 'characters']) {
        test(
          'retries $resource comments on next.bgm.tv and retains user token',
          () async {
            adapter.respond = (request) =>
                _response(request.uri.host == 'api.kazumi.fyi' ? 401 : 200);
            await BangumiClient.instance.get(
              'https://next.bgm.tv/p1/$resource/1/comments',
              queryParameters: {'limit': 10, 'offset': 20},
              requiresAuth: true,
              accessToken: 'test-access-token',
            );
            expect(adapter.requests, hasLength(2));
            expect(adapter.requests.last.uri.host, 'next.bgm.tv');
            expect(adapter.requests.last.extra['bangumiEch'], isTrue);
            expect(
              adapter.requests.last.headers['Authorization'],
              'Bearer test-access-token',
            );
          },
        );
      }

      for (final status in [401, 503]) {
        test('propagates official $status after exactly one retry', () async {
          adapter.respond = (request) =>
              _response(request.uri.host == 'api.kazumi.fyi' ? 401 : status);
          await expectLater(
            BangumiClient.instance.post(
              'https://api.bgm.tv/v0/search/subjects',
              data: {'keyword': 'test'},
            ),
            throwsA(
              isA<NetworkException>().having(
                (error) => error.statusCode,
                'status',
                status,
              ),
            ),
          );
          expect(adapter.requests, hasLength(2));
        });
      }

      for (final status in [403, 500]) {
        test('does not retry mirror $status', () async {
          adapter.respond = (_) => _response(status);
          await expectLater(
            BangumiClient.instance.post(
              'https://api.bgm.tv/v0/search/subjects',
              data: {'keyword': 'test'},
            ),
            throwsA(isA<NetworkException>()),
          );
          expect(adapter.requests, hasLength(1));
        });
      }

      test('does not retry account or OAuth authentication failures', () async {
        adapter.respond = (_) => _response(401);
        for (final url in [
          'https://api.bgm.tv/v0/me',
          'https://bgm.tv/oauth/access_token',
          'https://api.kazumi.fyi/v0/search/subjects',
        ]) {
          await expectLater(
            BangumiClient.instance.get(url),
            throwsA(isA<NetworkException>()),
          );
        }
        expect(adapter.requests, hasLength(3));
      });

      for (final mode in ['direct', 'ech']) {
        test('does not retry official 401 in $mode mode', () async {
          await GStorage.putSetting(SettingsKeys.bangumiAcceleration, mode);
          adapter.respond = (_) => _response(401);
          await expectLater(
            BangumiClient.instance.post(
              'https://api.bgm.tv/v0/search/subjects',
              data: {'keyword': 'test'},
            ),
            throwsA(isA<NetworkException>()),
          );
          expect(adapter.requests, hasLength(1));
        });
      }

      test('does not retry a cancelled mirror request', () async {
        final token = CancelToken();
        adapter.respond = (_) {
          token.cancel('cancelled');
          return _response(401);
        };
        await expectLater(
          BangumiClient.instance.post(
            'https://api.bgm.tv/v0/search/subjects',
            data: {'keyword': 'test'},
            cancelToken: token,
          ),
          throwsA(
            isA<NetworkException>().having(
              (error) => error.type,
              'type',
              NetworkExceptionType.cancel,
            ),
          ),
        );
        expect(adapter.requests, hasLength(1));
      });

      test('honors cancellation during the official retry', () async {
        final token = CancelToken();
        adapter.respond = (request) {
          if (request.uri.host == 'api.kazumi.fyi') return _response(401);
          token.cancel('cancelled during fallback');
          return _response(200);
        };
        await expectLater(
          BangumiClient.instance.post(
            'https://api.bgm.tv/v0/search/subjects',
            data: {'keyword': 'test'},
            cancelToken: token,
          ),
          throwsA(
            isA<NetworkException>().having(
              (error) => error.type,
              'type',
              NetworkExceptionType.cancel,
            ),
          ),
        );
        expect(adapter.requests, hasLength(2));
      });
    },
    skip: !signedBuild
        ? 'Run with KAZUMI_APPID and KAZUMI_KEY test defines'
        : false,
  );
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
    return respond == null ? _response(200) : await respond!(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _response(int status, {String body = '{}'}) =>
    ResponseBody.fromString(
      body,
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
