import 'package:dio/dio.dart';
import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/request/core/ech_adapter.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/network/bangumi_acceleration.dart';
import 'package:kazumi/services/network/rules_mirror.dart';
import 'package:kazumi/utils/bangumi_mirror_credentials.dart';

const _mirrorOriginalUrlKey = 'bangumiMirrorOriginalUrl';
const _mirrorRetriedKey = 'bangumiMirrorRetried';

class BangumiAccelerationInterceptor extends Interceptor {
  BangumiAccelerationInterceptor(this._dio);

  final Dio _dio;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.clearEch();
    options.extra.remove(_mirrorOriginalUrlKey);
    final uri = options.uri;
    if (ApiEndpoints.bangumiPublicApiHosts.contains(uri.host)) {
      // A rejected mirror request must not be routed back to the mirror.
      final selectedAcceleration = options.extra[_mirrorRetriedKey] == true
          ? BangumiAcceleration.ech
          : BangumiAcceleration.current;
      // Local builds may lack the private mirror signing credentials. Public
      // search/comments remain available from the official API through ECH.
      final acceleration =
          selectedAcceleration == BangumiAcceleration.mirror &&
              !hasBangumiMirrorCredentials &&
              requiresBangumiMirrorSignature(uri, options.method)
          ? BangumiAcceleration.ech
          : selectedAcceleration;
      switch (acceleration) {
        case BangumiAcceleration.direct:
          break;
        case BangumiAcceleration.ech:
          options.path = uri.replace(scheme: 'https').toString();
          options.queryParameters = {};
          options.requireEch();
        case BangumiAcceleration.mirror:
          if (requiresBangumiMirrorSignature(uri, options.method)) {
            options.extra[_mirrorOriginalUrlKey] = uri.toString();
          }
          options.path =
              ApiEndpoints.bangumiMirrorDomain +
              uri.path +
              (uri.hasQuery ? '?${uri.query}' : '');
          options.queryParameters = {};
          KazumiLogger().d('Bangumi mirror: ${options.path}');
      }
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final options = err.requestOptions;
    final originalUrl = options.extra[_mirrorOriginalUrlKey];
    if (err.response?.statusCode != 401 ||
        originalUrl is! String ||
        options.uri.host != Uri.parse(ApiEndpoints.bangumiMirrorDomain).host ||
        options.extra[_mirrorRetriedKey] == true ||
        options.cancelToken?.isCancelled == true) {
      handler.next(err);
      return;
    }

    final headers = Map<String, dynamic>.from(options.headers)
      ..removeWhere(
        (name, _) => const {
          'x-appid',
          'x-timestamp',
          'x-signature',
        }.contains(name.toLowerCase()),
      );
    final extra = Map<String, dynamic>.from(options.extra)
      ..remove(_mirrorOriginalUrlKey)
      ..[_mirrorRetriedKey] = true;
    // The saved URL already contains pagination and encoded query parameters.
    // copyWith retains the body, user authorization and cancellation token.
    final retry = options.copyWith(
      path: originalUrl,
      queryParameters: {},
      headers: headers,
      extra: extra,
    );
    KazumiLogger().d(
      'Bangumi mirror returned 401; retrying official API via ECH',
    );
    try {
      handler.resolve(await _dio.fetch<dynamic>(retry));
    } on DioException catch (retryError) {
      // The nested fetch has already run the error interceptors.
      handler.reject(retryError);
    }
  }
}

class RulesMirrorInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final url = options.uri.toString();
    if (url.startsWith(ApiEndpoints.pluginShop)) {
      switch (RulesMirror.current) {
        case RulesMirror.direct:
          break;
        case RulesMirror.ghProxy:
          options.path = ApiEndpoints.ghProxyMirror + url;
          options.requireEch();
        case RulesMirror.ghfast:
          options.path = ApiEndpoints.ghfastMirror + url;
        case RulesMirror.gitcode:
          options.path =
              ApiEndpoints.gitcodeMirror +
              url.substring(ApiEndpoints.pluginShop.length);
      }
    }
    handler.next(options);
  }
}
