import 'dart:convert';

/// Persisted HTTP-only subset of a TVBox site. No external code is evaluated.
class TvBoxSite {
  TvBoxSite({
    required this.key,
    required this.name,
    required this.type,
    required this.api,
    Map<String, String> headers = const {},
    this.playUrl = '',
    Object? ext,
  }) : headers = Map.unmodifiable(headers),
       ext = _freeze(ext);

  final String key;
  final String name;
  final int type;
  final String api;
  final Map<String, String> headers;
  final String playUrl;
  final Object? ext;

  factory TvBoxSite.fromJson(Map<String, dynamic> json, {String? baseUrl}) {
    final key = json['key']?.toString().trim() ?? '';
    final name = json['name']?.toString().trim() ?? '';
    final type = int.tryParse(json['type']?.toString() ?? '');
    if (key.isEmpty || name.isEmpty) {
      throw const FormatException('站点缺少 key 或 name');
    }
    if (type == 3) {
      throw const FormatException('Spider 3 需要 JAR/JS/Python 运行时，暂不支持');
    }
    if (![0, 1, 2, 4].contains(type)) {
      throw FormatException('不支持站点协议 type=${json['type']}');
    }
    final api = resolveHttpUrl(json['api']?.toString() ?? '', baseUrl: baseUrl);
    final playUrl = json['playUrl']?.toString().trim() ?? '';
    return TvBoxSite(
      key: key,
      name: name,
      type: type!,
      api: api,
      headers: decodeHeaders(json['headers'] ?? json['header']),
      playUrl: playUrl.isEmpty ? '' : resolveHttpUrl(playUrl, baseUrl: baseUrl),
      ext: json['ext'],
    );
  }

  Map<String, dynamic> toJson() => {
    'key': key,
    'name': name,
    'type': type,
    'api': api,
    if (headers.isNotEmpty) 'headers': headers,
    if (playUrl.isNotEmpty) 'playUrl': playUrl,
    if (ext != null) 'ext': ext,
  };

  static String resolveHttpUrl(String value, {String? baseUrl}) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) throw const FormatException('HTTP(S) 地址不能为空');
    var uri = Uri.tryParse(trimmed);
    if (uri != null && !uri.hasScheme && baseUrl != null) {
      uri = Uri.tryParse(baseUrl)?.resolveUri(uri);
    }
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty) {
      throw FormatException('仅支持有效 HTTP(S) 地址: $trimmed');
    }
    return uri.toString();
  }

  static Map<String, String> decodeHeaders(Object? value) {
    if (value is String && value.trim().isNotEmpty) value = jsonDecode(value);
    if (value == null || value == '') return {};
    if (value is! Map) throw const FormatException('header/headers 必须为对象');
    return value.map(
      (key, value) => MapEntry(key.toString().toLowerCase(), value.toString()),
    );
  }

  static Object? _freeze(Object? value) {
    if (value is Map)
      return Map<String, Object?>.unmodifiable(
        value.map((key, value) => MapEntry(key.toString(), _freeze(value))),
      );
    if (value is List) return List<Object?>.unmodifiable(value.map(_freeze));
    return value;
  }
}
