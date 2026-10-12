import 'dart:convert';
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/tvbox_site.dart';
import 'package:kazumi/services/plugin/rule_engine.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart';
import 'package:kazumi/services/plugin/tvbox_import_parser.dart';
import 'package:kazumi/services/plugin/tvbox_rule_strategy.dart';
import 'package:kazumi/services/video_source/webview_video_source_service.dart';
import 'package:kazumi/services/video_source/video_source_service.dart';
import 'package:kazumi/webview/video/video_webview_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'imports supported sites and reports unsupported/disabled/duplicate sites',
    () {
      final result = TvBoxImportParser.parse(
        jsonEncode({
          'sites': [
            for (final type in [0, 1, 2, 4])
              {
                'key': 'k$type',
                'name': '源$type',
                'type': type,
                'api': './api.php?token=a',
              },
            {'key': 'spider', 'name': '脚本', 'type': 3, 'api': 'csp_Demo'},
            {
              'key': 'disabled',
              'name': '禁搜',
              'type': 1,
              'api': 'https://api.test',
              'searchable': 0,
            },
            {'key': 'bad', 'name': '未知', 'type': 9, 'api': 'https://api.test'},
            {'key': 'k1', 'name': '重复', 'type': 1, 'api': 'https://api.test'},
            {'key': 'file', 'name': '本地', 'type': 1, 'api': 'file:///tmp/api'},
          ],
        }),
        baseUrl: 'https://config.test/path/config.json',
      );
      expect(result.plugins, hasLength(4));
      expect(result.warnings, hasLength(5));
      expect(result.warnings.join(), contains('Spider'));
      expect(result.plugins.every((plugin) => plugin.type == 'tv'), isTrue);
      expect(
        result.plugins.first.tvBoxSite!.api,
        'https://config.test/path/api.php?token=a',
      );
    },
  );

  test('round trips immutable headers ext and subscription metadata', () {
    final plugin = TvBoxImportParser.parse(
      jsonEncode({
        'key': 'json',
        'name': 'JSON',
        'type': 1,
        'api': 'https://api.test',
        'header': {'User-Agent': 'fixture', 'Referer': 'https://origin.test'},
        'ext': {
          'token': 'keep',
          'nested': [1, 2],
        },
        'playUrl': 'https://parse.test/?url=',
      }),
    ).plugins.single;
    plugin.subscriptionId = 'subscription';
    final clone = Plugin.fromJson(plugin.toJson());
    expect(clone.subscriptionId, 'subscription');
    expect(clone.tvBoxSite!.ext, {
      'token': 'keep',
      'nested': [1, 2],
    });
    expect(clone.tvBoxSite!.playUrl, 'https://parse.test/?url=');
    expect(clone.buildHttpHeaders()['user-agent'], 'fixture');
    expect(() => clone.tvBoxSite!.headers['x'] = 'y', throwsUnsupportedError);
    expect(
      () => (clone.tvBoxSite!.ext as Map)['token'] = 'changed',
      throwsUnsupportedError,
    );
  });

  test(
    'rejects HTML multiwarehouse encrypted or invalid root with clear diagnostics',
    () {
      for (final input in [
        '<html>not json</html>',
        '{"urls":[{"url":"https://other.test"}]}',
        '**encrypted**',
        '{}',
      ]) {
        expect(
          () => TvBoxImportParser.parse(input),
          throwsA(isA<FormatException>()),
        );
      }
    },
  );

  test('accepts arrays and common JSON comments and trailing commas', () {
    final result = TvBoxImportParser.parse('''[
      // configuration comment
      {"key":"a", "name":"A", "type":1, "api":"https://api.test/a//b",},
    ]''');
    expect(result.plugins.single.tvBoxSite!.api, 'https://api.test/a//b');
  });

  for (final type in [1, 2, 4]) {
    test(
      'type $type search detail keep query parameters and resolve only selected episode',
      () async {
        final site = TvBoxSite.fromJson({
          'key': 'k',
          'name': 'Name',
          'type': type,
          'api': 'https://api.test/api?token=secret',
          'header': {'User-Agent': 'fixture'},
          'ext': {'token': 3},
        });
        final executor = _FakeExecutor([
          '{"list":[{"vod_id":42,"vod_name":"测试影片"}]}',
          r'{"list":[{"vod_play_from":"A$$$B","vod_play_url":"一$https://cdn.test/1.m3u8#二$episode-token$$$正片$https://cdn.test/main.mp4"}]}',
          '{"parse":0,"url":"https://cdn.test/selected","header":"{\\"Referer\\":\\"https://play.test/\\"}"}',
        ]);
        // Supply the playback JSON without double escaping a nested JSON string.
        executor.responses[2] = jsonEncode({
          'parse': 0,
          'url': 'https://cdn.test/selected',
          'header': jsonEncode({'Referer': 'https://play.test/'}),
        });
        final engine = RuleEngine(
          requestExecutor: executor,
          logFailures: false,
        );
        final config = RuleExecutionConfig.fromTvBoxSite(site);
        final search = await engine.search(config, '测试 & /');
        expect(search.response.data.single.src, '42');
        expect(executor.requests.first.query['wd'], '测试 & /');
        expect(executor.requests.first.query['token'], 'secret');
        expect(executor.requests.first.headers['user-agent'], 'fixture');
        final chapters = await engine.queryChapters(config, '42');
        expect(executor.requests, hasLength(2));
        expect(executor.requests[1].query['ids'], '42');
        expect(chapters.roads.map((road) => road.name), ['A', 'B']);
        expect(chapters.roads.first.identifier, ['一', '二']);
        if (type == 4) {
          expect(
            executor.requests.first.query['extend'],
            jsonEncode({'token': 3}),
          );
          final playback = await engine.resolveTvBoxPlayback(
            chapters.roads.first.data[1],
          );
          expect(executor.requests, hasLength(3));
          expect(executor.requests.last.query['play'], 'episode-token');
          expect(executor.requests.last.query['flag'], 'A');
          expect(playback.url, 'https://cdn.test/selected');
          expect(playback.needsSniffing, isFalse);
          expect(playback.headers, {
            'user-agent': 'fixture',
            'referer': 'https://play.test/',
          });
        } else {
          final playback = await engine.resolveTvBoxPlayback(
            chapters.roads.first.data[0],
          );
          expect(playback.url, 'https://cdn.test/1.m3u8');
          expect(playback.needsSniffing, isFalse);
          expect(executor.requests, hasLength(2));
        }
      },
    );
  }

  test('XML search and CDATA chapter groups retain names and ampersands', () async {
    final site = TvBoxSite.fromJson({
      'key': 'x',
      'name': 'XML',
      'type': 0,
      'api': 'https://api.test/xml',
    });
    final executor = _FakeExecutor([
      '<rss><list><video><id>7</id><name><![CDATA[电影 & 特辑]]></name></video></list></rss>',
      r'<rss><list><video><dl><dd flag="高清"><![CDATA[第一集$https://cdn.test/1.m3u8?a=1&b=2#第二集$https://cdn.test/2.mp4]]></dd></dl></video></list></rss>',
    ]);
    final engine = RuleEngine(requestExecutor: executor, logFailures: false);
    final config = RuleExecutionConfig.fromTvBoxSite(site);
    expect(
      (await engine.search(config, '电影')).response.data.single.name,
      '电影 & 特辑',
    );
    final chapters = await engine.queryChapters(config, '7');
    expect(executor.requests.first.query['ac'], 'list');
    expect(executor.requests.last.query['ac'], 'videolist');
    expect(chapters.roads.single.name, '高清');
    expect(
      (await engine.resolveTvBoxPlayback(chapters.roads.single.data.first)).url,
      'https://cdn.test/1.m3u8?a=1&b=2',
    );
  });

  test('parse=1 stays a sniffing page and merges dynamic headers', () async {
    final site = TvBoxSite.fromJson({
      'key': 'k',
      'name': 'Remote',
      'type': 4,
      'api': 'https://api.test',
      'headers': {'Referer': 'https://old.test'},
    });
    final engine = RuleEngine(
      requestExecutor: _FakeExecutor([
        jsonEncode({
          'parse': 1,
          'url': 'https://page.test/watch',
          'header': {'Referer': 'https://new.test', 'Cookie': 'a=b'},
        }),
      ]),
      logFailures: false,
    );
    final reference = TvBoxRuleStrategy.episodeReference(site, 'line', 'token');
    final playback = await engine.resolveTvBoxPlayback(reference);
    expect(playback.needsSniffing, isTrue);
    expect(playback.headers['referer'], 'https://new.test');
    expect(playback.headers['cookie'], 'a=b');
  });

  test(
    'shared resolver bypasses webview for direct media and retains headers',
    () async {
      final site = TvBoxSite.fromJson({
        'key': 'k',
        'name': 'Direct',
        'type': 1,
        'api': 'https://api.test',
        'header': {'User-Agent': 'fixture'},
      });
      final service = WebViewVideoSourceService(
        webviewFactory: () => throw StateError('WebView must not be created'),
      );
      final result = await service.resolve(
        TvBoxRuleStrategy.episodeReference(
          site,
          'm3u8',
          'https://cdn.test/video.m3u8',
        ),
        useLegacyParser: false,
        offset: 25,
      );
      expect(result.url, 'https://cdn.test/video.m3u8');
      expect(result.offset, 25);
      expect(result.headers['user-agent'], 'fixture');
      await service.dispose();
    },
  );

  test(
    'shared resolver sends sniff headers and captures immediate parser event',
    () async {
      final site = TvBoxSite.fromJson({
        'key': 'k',
        'name': 'Remote',
        'type': 4,
        'api': 'https://api.test',
      });
      final webview = _FakeWebview();
      final service = WebViewVideoSourceService(
        ruleEngine: RuleEngine(
          requestExecutor: _FakeExecutor([
            jsonEncode({
              'parse': 1,
              'url': 'https://page.test',
              'header': {'Referer': 'https://origin.test'},
            }),
          ]),
          logFailures: false,
        ),
        webviewFactory: () => webview,
      );
      final result = await service.resolve(
        TvBoxRuleStrategy.episodeReference(site, 'line', 'token'),
        useLegacyParser: false,
      );
      expect(webview.headers['referer'], 'https://origin.test');
      expect(result.url, 'https://cdn.test/video.mp4');
      expect(result.headers, webview.headers);
      await service.dispose();
    },
  );

  test(
    'shared resolver cancels an in-flight remote playback request',
    () async {
      final site = TvBoxSite.fromJson({
        'key': 'k',
        'name': 'Remote',
        'type': 4,
        'api': 'https://api.test',
      });
      final executor = _PendingExecutor();
      final service = WebViewVideoSourceService(
        ruleEngine: RuleEngine(requestExecutor: executor, logFailures: false),
      );
      final future = service.resolve(
        TvBoxRuleStrategy.episodeReference(site, 'line', 'token'),
        useLegacyParser: false,
      );
      final assertion = expectLater(
        future,
        throwsA(isA<VideoSourceCancelledException>()),
      );
      await executor.started.future;
      service.cancel();
      await assertion;
      expect(executor.token!.isCancelled, isTrue);
      await service.dispose();
    },
  );

  test(
    'unsupported parse runtime fails instead of treating page as media',
    () async {
      final site = TvBoxSite.fromJson({
        'key': 'k',
        'name': 'Remote',
        'type': 4,
        'api': 'https://api.test',
      });
      final engine = RuleEngine(
        requestExecutor: _FakeExecutor([
          '{"parse":2,"url":"https://page.test"}',
        ]),
        logFailures: false,
      );
      await expectLater(
        engine.resolveTvBoxPlayback(
          TvBoxRuleStrategy.episodeReference(site, 'line', 'token'),
        ),
        throwsA(isA<FormatException>()),
      );
    },
  );
}

class _FakeExecutor implements RuleRequestExecutor {
  _FakeExecutor(this.responses);
  final List<String> responses;
  final List<PreparedRuleRequest> requests = [];
  @override
  Future<String> execute(
    PreparedRuleRequest request,
    RuleExecutionConfig config, {
    CancelToken? cancelToken,
  }) async {
    requests.add(request);
    return responses[requests.length - 1];
  }
}

class _FakeWebview extends VideoWebviewController<Object> {
  Map<String, String> headers = {};
  @override
  Future<void> init() async {}
  @override
  Future<void> loadUrl(
    String url,
    bool useLegacyParser, {
    int offset = 0,
    Map<String, String> headers = const {},
  }) async {
    this.headers = headers;
    notifyVideoSourceResolved('https://cdn.test/video.mp4');
  }

  @override
  Future<void> unloadPage() async {}
  @override
  Future<void> dispose() async {
    disposeEventControllers();
  }
}

class _PendingExecutor implements RuleRequestExecutor {
  final started = Completer<void>();
  CancelToken? token;
  @override
  Future<String> execute(
    PreparedRuleRequest request,
    RuleExecutionConfig config, {
    CancelToken? cancelToken,
  }) async {
    token = cancelToken;
    started.complete();
    await cancelToken!.whenCancel;
    throw StateError('cancelled');
  }
}
