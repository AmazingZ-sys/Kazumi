import 'dart:convert';

import 'package:kazumi/modules/roads/road_module.dart';
import 'package:kazumi/modules/search/plugin_search_module.dart';
import 'package:kazumi/plugins/api_rule_config.dart';
import 'package:kazumi/plugins/tvbox_site.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart';
import 'package:xml/xml.dart';

class TvBoxPlayback {
  const TvBoxPlayback({
    required this.url,
    required this.needsSniffing,
    required this.headers,
  });
  final String url;
  final bool needsSniffing;
  final Map<String, String> headers;
}

class TvBoxEpisode {
  const TvBoxEpisode(this.site, this.flag, this.id);
  final TvBoxSite site;
  final String flag;
  final String id;
}

/// Standard TVBox XML/JSON HTTP protocols; script runtimes are unsupported.
class TvBoxRuleStrategy {
  const TvBoxRuleStrategy();

  PreparedRuleRequest prepareSearchRequest(TvBoxSite site, String keyword) =>
      _request(site, {
        if (site.type == 0) 'ac': 'list',
        'wd': keyword,
        'quick': 'false',
      });

  PreparedRuleRequest prepareChapterRequest(TvBoxSite site, String source) =>
      _request(site, {
        'ac': site.type == 0 ? 'videolist' : 'detail',
        'ids': source,
      });

  PreparedRuleRequest preparePlaybackRequest(TvBoxEpisode episode) =>
      _request(episode.site, {'play': episode.id, 'flag': episode.flag});

  PreparedRuleRequest _request(TvBoxSite site, Map<String, String> params) {
    final uri = Uri.parse(site.api);
    final ext = site.ext is String
        ? site.ext as String
        : site.ext == null
        ? ''
        : jsonEncode(site.ext);
    final query = <String, String>{
      ...uri.queryParameters,
      ...params,
      if (ext.isNotEmpty) 'extend': ext,
    };
    // Match upstream SiteApi.call: long site parameters use a form body.
    final post = ext.length > 1000;
    return PreparedRuleRequest(
      method: post ? 'POST' : 'GET',
      url: uri.replace(query: null).toString(),
      headers: site.headers,
      query: post ? const {} : query,
      bodyType: post ? ApiBodyType.form : ApiBodyType.none,
      body: post ? query : null,
    );
  }

  RuleSearchParseResult parseSearch(String raw, TvBoxSite site) {
    final items = <SearchItem>[];
    final fragments = <String>[];
    final diagnostics = <String>[];
    final nodes = site.type == 0
        ? _xml(raw).findAllElements('video').toList()
        : _jsonList(raw);
    for (var i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      final name = node is XmlElement
          ? _xmlText(node, 'name')
          : node is Map
          ? _text(node['vod_name'])
          : '';
      final id = node is XmlElement
          ? _xmlText(node, 'id')
          : node is Map
          ? _text(node['vod_id'])
          : '';
      if (name.isEmpty || id.isEmpty) {
        diagnostics.add('搜索条目 $i 缺少名称或 ID，已跳过');
        continue;
      }
      items.add(SearchItem(name: name, src: id));
      fragments.add(node is XmlElement ? node.toXmlString() : jsonEncode(node));
    }
    return RuleSearchParseResult(
      items: items,
      matchedFragments: fragments,
      diagnostics: diagnostics,
    );
  }

  RuleChapterParseResult parseChapters(String raw, TvBoxSite site) {
    final groups = <(String, String)>[];
    if (site.type == 0) {
      final video = _xml(raw).findAllElements('video').firstOrNull;
      if (video == null) throw const FormatException('XML 详情缺少 video');
      for (final dd in video.findAllElements('dd')) {
        groups.add((dd.getAttribute('flag') ?? '', dd.innerText.trim()));
      }
    } else {
      final item = _jsonList(raw).firstOrNull;
      if (item is! Map) throw const FormatException('JSON 详情缺少 list 条目');
      final flags = _text(item['vod_play_from']).split(r'$$$');
      final episodes = _text(item['vod_play_url']).split(r'$$$');
      for (var i = 0; i < episodes.length; i++) {
        groups.add((i < flags.length ? flags[i] : '', episodes[i]));
      }
    }
    final roads = <Road>[];
    final diagnostics = <String>[];
    for (final (flag, episodes) in groups) {
      final urls = <String>[];
      final names = <String>[];
      for (final entry in episodes.split('#')) {
        if (entry.trim().isEmpty) continue;
        final split = entry.indexOf(r'$');
        final name = split < 0 ? '' : entry.substring(0, split).trim();
        final id = (split < 0 ? entry : entry.substring(split + 1)).trim();
        if (id.isEmpty) {
          diagnostics.add('线路 $flag 的剧集缺少播放地址，已跳过');
          continue;
        }
        urls.add(episodeReference(site, flag, id));
        names.add(name.isEmpty ? '第${names.length + 1}集' : name);
      }
      if (urls.isNotEmpty) {
        roads.add(
          Road(
            name: flag.isEmpty ? '播放线路${roads.length + 1}' : flag,
            data: urls,
            identifier: names,
          ),
        );
      }
    }
    return RuleChapterParseResult(roads: roads, diagnostics: diagnostics);
  }

  /// A self-contained reference survives history restoration and can be resolved
  /// by the shared playback/download service without global plugin lookups.
  static String episodeReference(TvBoxSite site, String flag, String id) => Uri(
    scheme: 'kazumi-tvbox',
    host: 'play',
    queryParameters: {
      'data': base64Url.encode(
        utf8.encode(
          jsonEncode({'site': site.toJson(), 'flag': flag, 'id': id}),
        ),
      ),
    },
  ).toString();

  static bool isEpisodeReference(String url) =>
      Uri.tryParse(url)?.scheme == 'kazumi-tvbox';

  static TvBoxEpisode decodeEpisodeReference(String url) {
    final uri = Uri.parse(url);
    if (uri.scheme != 'kazumi-tvbox' || uri.host != 'play')
      throw const FormatException('无效的影视仓剧集引用');
    final data = jsonDecode(
      utf8.decode(base64Url.decode(uri.queryParameters['data'] ?? '')),
    );
    if (data is! Map ||
        data['site'] is! Map ||
        data['id'] is! String ||
        (data['id'] as String).isEmpty) {
      throw const FormatException('影视仓剧集引用缺少站点或播放 ID');
    }
    return TvBoxEpisode(
      TvBoxSite.fromJson(Map<String, dynamic>.from(data['site'])),
      _text(data['flag']),
      data['id'],
    );
  }

  TvBoxPlayback directPlayback(TvBoxEpisode episode) {
    final prefix = episode.site.playUrl;
    final url = TvBoxSite.resolveHttpUrl(
      '$prefix${episode.id}',
      baseUrl: episode.site.api,
    );
    return TvBoxPlayback(
      url: url,
      needsSniffing: prefix.isNotEmpty || !_isMedia(url),
      headers: episode.site.headers,
    );
  }

  TvBoxPlayback parsePlayback(String raw, TvBoxSite site) {
    final result = jsonDecode(raw);
    if (result is! Map) throw const FormatException('播放响应必须为 JSON 对象');
    final parse = int.tryParse(result['parse']?.toString() ?? '0');
    if (parse != 0 && parse != 1)
      throw FormatException('不支持 parse=$parse 的自定义解析运行时');
    if (_text(result['jx']) == '1')
      throw const FormatException('暂不支持需要外部解析器的 jx=1 播放响应');
    final prefix = _text(result['playUrl']);
    final rawUrl = _text(result['url']);
    if (rawUrl.isEmpty) throw const FormatException('播放响应缺少 url');
    final url = TvBoxSite.resolveHttpUrl('$prefix$rawUrl', baseUrl: site.api);
    return TvBoxPlayback(
      url: url,
      needsSniffing: parse == 1 || prefix.isNotEmpty,
      headers: Map.unmodifiable({
        ...site.headers,
        ...TvBoxSite.decodeHeaders(result['header'] ?? result['headers']),
      }),
    );
  }

  static bool _isMedia(String url) => RegExp(
    r'\.(m3u8|mp4|mkv|flv|mpd|avi|mov|m4v|ts)(?:$|[?&#])',
    caseSensitive: false,
  ).hasMatch(url);
  static String _text(Object? value) => value?.toString().trim() ?? '';
  static String _xmlText(XmlElement element, String name) =>
      element.getElement(name)?.innerText.trim() ?? '';
  XmlDocument _xml(String raw) => XmlDocument.parse(raw);
  List<dynamic> _jsonList(String raw) {
    final document = jsonDecode(raw);
    if (document is! Map || document['list'] is! List)
      throw const FormatException('响应缺少标准 TVBox list 列表');
    return document['list'] as List;
  }
}
