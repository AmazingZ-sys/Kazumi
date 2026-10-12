import 'package:kazumi/request/config/api_endpoints.dart';

// Bangumi mirror API credentials for the search signature flow.
// Release/PR CI injects them via --dart-define=KAZUMI_APPID / KAZUMI_KEY.
const Map<String, String> bangumiMirrorCredentials = {
  'id': String.fromEnvironment('KAZUMI_APPID'),
  'value': String.fromEnvironment('KAZUMI_KEY'),
};

bool get hasBangumiMirrorCredentials =>
    bangumiMirrorCredentials.values.every((value) => value.trim().isNotEmpty);

bool requiresBangumiMirrorSignature(Uri uri, String method) {
  if (!ApiEndpoints.bangumiPublicApiHosts.contains(uri.host)) return false;
  final path = uri.path;
  if (method == 'POST' && path == '/v0/search/subjects') return true;
  if (method != 'GET') return false;
  return path.startsWith('/p1/subjects/') && path.endsWith('/comments') ||
      path.startsWith('/p1/episodes/') && path.endsWith('/comments') ||
      path.startsWith('/p1/characters/') && path.endsWith('/comments');
}
