import 'dart:async';

import 'package:dio/dio.dart';
import 'package:kazumi/services/plugin/rule_engine.dart';
import 'package:kazumi/services/plugin/tvbox_rule_strategy.dart';
import 'package:kazumi/services/video_source/video_source_service.dart';
import 'package:kazumi/webview/video/video_webview_controller.dart';

class WebViewVideoSourceService implements IVideoSourceService {
  WebViewVideoSourceService({
    RuleEngine? ruleEngine,
    VideoWebviewController Function()? webviewFactory,
  }) : _ruleEngine = ruleEngine ?? RuleEngine(),
       _webviewFactory =
           webviewFactory ?? VideoWebviewControllerFactory.getController;

  final RuleEngine _ruleEngine;
  final VideoWebviewController Function() _webviewFactory;
  VideoWebviewController? _webview;
  StreamSubscription? _logSubscription;
  Future<void>? _resolveTail = Future<void>.value();
  _ResolveRequest? _activeRequest;
  CancelToken? _activeCancelToken;
  final StreamController<String> _logController =
      StreamController<String>.broadcast();
  Stream<String> get onLog => _logController.stream;

  @override
  Future<VideoSource> resolve(
    String episodeUrl, {
    required bool useLegacyParser,
    int offset = 0,
    Duration timeout = const Duration(seconds: 15),
    Map<String, String> headers = const {},
  }) async {
    if (TvBoxRuleStrategy.isEpisodeReference(episodeUrl)) {
      final request = _ResolveRequest();
      _activeRequest?.cancel();
      _activeCancelToken?.cancel();
      _activeRequest = request;
      final cancelToken = CancelToken();
      _activeCancelToken = cancelToken;
      try {
        final episode = TvBoxRuleStrategy.decodeEpisodeReference(episodeUrl);
        final playback = episode.site.type == 4
            ? await _ruleEngine.resolveTvBoxPlayback(
                episodeUrl,
                cancelToken: cancelToken,
              )
            : const TvBoxRuleStrategy().directPlayback(episode);
        final mergedHeaders = <String, String>{...playback.headers, ...headers};
        if (!playback.needsSniffing) {
          return VideoSource(
            url: playback.url,
            offset: offset,
            type: VideoSourceType.online,
            headers: mergedHeaders,
          );
        }
        return await _resolveWebview(
          request,
          playback.url,
          useLegacyParser: useLegacyParser,
          offset: offset,
          timeout: timeout,
          headers: mergedHeaders,
        );
      } on DioException catch (error) {
        if (CancelToken.isCancel(error))
          throw const VideoSourceCancelledException();
        rethrow;
      } catch (error) {
        if (cancelToken.isCancelled || request.isCancelled)
          throw const VideoSourceCancelledException();
        rethrow;
      } finally {
        _activeCancelToken = null;
        if (identical(_activeRequest, request)) _activeRequest = null;
      }
    }
    final tail = _resolveTail;
    if (tail == null) throw const VideoSourceCancelledException();
    _activeRequest?.cancel();
    final request = _ResolveRequest();
    _activeRequest = request;
    final future = tail.then(
      (_) => _runResolve(
        request,
        episodeUrl,
        useLegacyParser: useLegacyParser,
        offset: offset,
        timeout: timeout,
        headers: headers,
      ),
    );
    _resolveTail = future.then<void>((_) {}, onError: (_) {});
    return future;
  }

  Future<VideoSource> _resolveWebview(
    _ResolveRequest request,
    String url, {
    required bool useLegacyParser,
    required int offset,
    required Duration timeout,
    required Map<String, String> headers,
  }) async {
    request.throwIfNotCurrent(_activeRequest);
    if (_webview == null) {
      _webview = _webviewFactory();
      await _webview!.init();
    }
    _logSubscription ??= _webview!.onLog.listen((log) {
      if (!_logController.isClosed) _logController.add(log);
    });
    final parser = _webview!.onVideoURLParser.first.timeout(
      timeout,
      onTimeout: () {
        request.throwIfNotCurrent(_activeRequest);
        throw VideoSourceTimeoutException(timeout);
      },
    );
    final cancelled = request.cancelled.then<VideoParserEvent>(
      (_) => throw const VideoSourceCancelledException(),
    );
    await _webview!.loadUrl(
      url,
      useLegacyParser,
      offset: offset,
      headers: headers,
    );
    final event = await Future.any([parser, cancelled]);
    request.throwIfNotCurrent(_activeRequest);
    return VideoSource(
      url: event.url,
      offset: event.offset,
      type: VideoSourceType.online,
      format: event.format,
      headers: headers,
    );
  }

  Future<VideoSource> _runResolve(
    _ResolveRequest request,
    String episodeUrl, {
    required bool useLegacyParser,
    required int offset,
    required Duration timeout,
    required Map<String, String> headers,
  }) async {
    request.throwIfNotCurrent(_activeRequest);
    try {
      final result = await _resolveWebview(
        request,
        episodeUrl,
        useLegacyParser: useLegacyParser,
        offset: offset,
        timeout: timeout,
        headers: headers,
      );
      await _webview?.unloadPage();
      return result;
    } finally {
      if (identical(_activeRequest, request)) _activeRequest = null;
    }
  }

  @override
  void cancel() {
    _activeRequest?.cancel();
    _activeCancelToken?.cancel();
  }

  @override
  Future<void> dispose() async {
    final tail = _resolveTail;
    _resolveTail = null;
    cancel();
    await tail;
    await _logSubscription?.cancel();
    _logSubscription = null;
    if (!_logController.isClosed) await _logController.close();
    await _webview?.dispose();
    _webview = null;
  }
}

class _ResolveRequest {
  final Completer<void> _cancelled = Completer<void>();
  Future<void> get cancelled => _cancelled.future;
  bool get isCancelled => _cancelled.isCompleted;
  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }

  void throwIfNotCurrent(_ResolveRequest? current) {
    if (_cancelled.isCompleted || !identical(current, this))
      throw const VideoSourceCancelledException();
  }
}
