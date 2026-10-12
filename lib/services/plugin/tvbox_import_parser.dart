import 'dart:convert';

import 'package:kazumi/plugins/api_rule_config.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/tvbox_site.dart';

class TvBoxImportResult {
  TvBoxImportResult({
    required List<Plugin> plugins,
    required List<String> warnings,
  }) : plugins = List.unmodifiable(plugins),
       warnings = List.unmodifiable(warnings);
  final List<Plugin> plugins;
  final List<String> warnings;
}

class TvBoxImportParser {
  static TvBoxImportResult parse(String input, {String? baseUrl}) {
    final trimmed = input.trim().replaceFirst('\uFEFF', '');
    if (trimmed.startsWith('<')) {
      throw const FormatException('地址返回了 HTML/XML 页面，不是影视仓 JSON 配置');
    }
    dynamic document;
    try {
      document = jsonDecode(_cleanJson(trimmed));
    } on FormatException {
      throw const FormatException('配置不是有效 JSON；暂不支持加密配置');
    }
    final List<dynamic> sites;
    if (document is List) {
      sites = document;
    } else if (document is Map && document['sites'] is List) {
      sites = document['sites'] as List;
    } else if (document is Map && document.containsKey('api')) {
      sites = [document];
    } else if (document is Map &&
        (document.containsKey('urls') || document.containsKey('storeHouse'))) {
      throw const FormatException('暂不支持多仓配置，请提供其中一个含 sites 的配置');
    } else {
      throw const FormatException('配置缺少 sites 列表或有效的单个站点');
    }
    final plugins = <Plugin>[];
    final warnings = <String>[];
    final keys = <String>{};
    for (var index = 0; index < sites.length; index++) {
      final raw = sites[index];
      final label = raw is Map
          ? (raw['name'] ?? raw['key'] ?? '#${index + 1}')
          : '#${index + 1}';
      try {
        if (raw is! Map) throw const FormatException('站点不是 JSON 对象');
        if (raw['searchable'] == false ||
            raw['searchable']?.toString() == '0') {
          throw const FormatException('站点未开启搜索，已跳过');
        }
        final site = TvBoxSite.fromJson(
          Map<String, dynamic>.from(raw),
          baseUrl: baseUrl,
        );
        if (!keys.add(site.key))
          throw FormatException('站点 key 重复: ${site.key}');
        final plugin = Plugin.fromTemplate()
          ..name = site.name
          ..type = 'tv'
          ..version = '1'
          ..baseUrl = site.api
          ..searchMode = RuleMode.api
          ..chapterMode = RuleMode.api
          ..tvBoxSite = site
          ..userAgent = site.headers['user-agent'] ?? ''
          ..referer = site.headers['referer'] ?? '';
        plugins.add(plugin);
      } on FormatException catch (error) {
        warnings.add('$label：${error.message}');
      }
    }
    return TvBoxImportResult(plugins: plugins, warnings: warnings);
  }

  // Strip comments and trailing commas only outside strings. URLs and embedded
  // JSON/ext strings remain byte-for-byte intact.
  static String _cleanJson(String source) {
    final buffer = StringBuffer();
    var inString = false;
    var escaped = false;
    for (var i = 0; i < source.length; i++) {
      final char = source[i];
      if (inString) {
        buffer.write(char);
        if (escaped) {
          escaped = false;
        } else if (char == '\\') {
          escaped = true;
        } else if (char == '"') {
          inString = false;
        }
      } else if (char == '"') {
        inString = true;
        buffer.write(char);
      } else if (char == '/' && i + 1 < source.length && source[i + 1] == '/') {
        while (i + 1 < source.length && source[i + 1] != '\n') {
          i++;
        }
        buffer.write(' ');
      } else if (char == '/' && i + 1 < source.length && source[i + 1] == '*') {
        final end = source.indexOf('*/', i + 2);
        if (end < 0) throw const FormatException('注释未闭合');
        i = end + 1;
        buffer.write(' ');
      } else {
        buffer.write(char);
      }
    }
    final clean = buffer.toString();
    final result = StringBuffer();
    inString = false;
    escaped = false;
    for (var i = 0; i < clean.length; i++) {
      final char = clean[i];
      if (!inString && char == ',') {
        var next = i + 1;
        while (next < clean.length && clean[next].trim().isEmpty) {
          next++;
        }
        if (next < clean.length && (clean[next] == ']' || clean[next] == '}'))
          continue;
      }
      result.write(char);
      if (inString && escaped) {
        escaped = false;
      } else if (inString && char == '\\') {
        escaped = true;
      } else if (char == '"') {
        inString = !inString;
      }
    }
    return result.toString();
  }
}
