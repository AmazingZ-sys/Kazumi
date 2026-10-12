import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/plugins/anti_crawler_config.dart';
import 'package:kazumi/plugins/api_rule_config.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart';
import 'package:kazumi/services/plugin/xpath_rule_strategy.dart';

void main() {
  test('bundled Olevod rule parses a search result', () {
    final plugin = Plugin.fromJson(
      jsonDecode(File('assets/plugins/olevod.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    final config = RuleExecutionConfig(
      pluginName: plugin.name,
      baseUrl: plugin.baseUrl,
      usePost: plugin.usePost,
      searchMode: plugin.searchMode,
      chapterMode: plugin.chapterMode,
      searchUrl: plugin.searchURL,
      searchList: plugin.searchList,
      searchName: plugin.searchName,
      searchResult: plugin.searchResult,
      chapterRoads: plugin.chapterRoads,
      chapterResult: plugin.chapterResult,
      searchApiConfig: ApiSearchConfig(),
      chapterApiConfig: ApiChapterConfig(),
      antiCrawlerConfig: AntiCrawlerConfig.empty(),
    );

    final result = const XPathRuleStrategy().parseSearch('''
      <html><body>
        <ul>
          <li class="searchlist_item">
            <h4><a href="/index.php/vod/detail/id/1.html" title="测试剧">
              <span class="info_right">连续剧</span>测试剧
            </a></h4>
          </li>
        </ul>
      </body></html>
    ''', config);

    expect(result.items, hasLength(1));
    expect(result.items.single.name, '测试剧');
    expect(result.items.single.src, '/index.php/vod/detail/id/1.html');
  });
}
