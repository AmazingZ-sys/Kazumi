import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/widget/empty_state_widget.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/search/plugin_search_module.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart';

/// Searches non-anime rules and opens their episode lists in the existing
/// video player. This is deliberately separate from Bangumi search because
/// drama sites do not provide Bangumi subject IDs.
class DramaSearchPage extends StatefulWidget {
  const DramaSearchPage({
    super.key,
    required this.pluginsController,
  });

  final PluginsController pluginsController;

  @override
  State<DramaSearchPage> createState() => _DramaSearchPageState();
}

class _DramaSearchPageState extends State<DramaSearchPage> {
  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  final Map<String, List<SearchItem>> _results = {};
  final Map<String, String> _errors = {};
  bool _isSearching = false;
  String? _submittedQuery;
  String? _openingItem;

  List<Plugin> get _dramaPlugins => widget.pluginsController.pluginList
      .where((plugin) => plugin.type.trim().toLowerCase() != 'anime')
      .toList();

  @override
  void dispose() {
    _input.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  Future<void> _submit(String value) async {
    final keyword = value.trim();
    if (keyword.isEmpty || _isSearching) return;
    _inputFocus.unfocus();
    setState(() {
      _submittedQuery = keyword;
      _isSearching = true;
      _results.clear();
      _errors.clear();
    });

    final plugins = _dramaPlugins;
    await Future.wait(plugins.map((plugin) async {
      try {
        final response = await plugin.queryBangumi(
          keyword,
          shouldRethrow: true,
        );
        if (!mounted) return;
        setState(() => _results[plugin.name] = response.data);
      } catch (error) {
        if (!mounted) return;
        setState(() => _errors[plugin.name] = _errorMessage(error));
      }
    }));

    if (mounted) setState(() => _isSearching = false);
  }

  String _errorMessage(Object error) {
    if (error is NoResultException) return '没有找到结果';
    if (error is CaptchaRequiredException) return '需要完成验证';
    return '搜索失败';
  }

  int _stableId(String pluginName, String source) {
    // FNV-1a keeps the locally generated ID stable across app restarts.
    var value = 0x811c9dc5;
    for (final codeUnit in '$pluginName\u0000$source'.codeUnits) {
      value ^= codeUnit;
      value = (value * 0x01000193) & 0x7fffffff;
    }
    return value == 0 ? 1 : value;
  }

  BangumiItem _mediaItem(Plugin plugin, SearchItem item) {
    return BangumiItem(
      id: _stableId(plugin.name, item.src),
      type: 6,
      name: item.name,
      nameCn: item.name,
      summary: '',
      airDate: '',
      airWeekday: 0,
      rank: 0,
      images: const <String, String>{},
      tags: const [],
      alias: const [],
      ratingScore: 0,
      votes: 0,
      votesCount: const [],
      info: '',
    );
  }

  Future<void> _openItem(Plugin plugin, SearchItem item) async {
    if (_openingItem != null) return;
    final key = '${plugin.name}:${item.src}';
    setState(() => _openingItem = key);
    try {
      final roads = await plugin.queryChapterRoads(item.src);
      if (!mounted) return;
      if (roads.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未找到可播放的剧集')),
        );
        return;
      }
      await context.pushNamed(
        '/video/',
        arguments: OnlineVideoPlaybackArgs(
          bangumiItem: _mediaItem(plugin, item),
          plugin: plugin,
          title: item.name,
          src: item.src,
          roads: roads,
        ),
      );
    } catch (error, stackTrace) {
      KazumiLogger().w(
        'DramaSearchPage: failed to load chapters',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未能获取播放列表，请稍后重试')),
        );
      }
    } finally {
      if (mounted) setState(() => _openingItem = null);
    }
  }

  Widget _searchBar() {
    return SearchBar(
      controller: _input,
      focusNode: _inputFocus,
      hintText: '搜索电视剧、电影或综艺',
      textInputAction: TextInputAction.search,
      leading: IconButton(
        tooltip: '搜索',
        onPressed: () => _submit(_input.text),
        icon: const Icon(Icons.search_rounded),
      ),
      trailing: [
        if (_input.text.isNotEmpty)
          IconButton(
            tooltip: '清空',
            onPressed: () {
              _input.clear();
              setState(() {
                _submittedQuery = null;
                _results.clear();
              });
            },
            icon: const Icon(Icons.close_rounded),
          ),
      ],
      onSubmitted: _submit,
    );
  }

  Widget _resultGroup(Plugin plugin) {
    final results = _results[plugin.name] ?? const <SearchItem>[];
    final error = _errors[plugin.name];
    return ExpansionTile(
      initiallyExpanded: true,
      title: Text(plugin.name),
      subtitle: Text(
        _isSearching && !_results.containsKey(plugin.name)
            ? '正在搜索…'
            : error ?? '${results.length} 个结果',
      ),
      children: [
        for (final item in results)
          ListTile(
            title: Text(item.name),
            subtitle: Text(
              item.src,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: _openingItem == '${plugin.name}:${item.src}'
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow_rounded),
            onTap: () => _openItem(plugin, item),
          ),
        if (results.isEmpty && error == null && !_isSearching)
          const ListTile(title: Text('没有找到结果')),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final plugins = _dramaPlugins;
    final hasResults = _submittedQuery != null;
    return Scaffold(
      appBar: const SysAppBar(
        backgroundColor: Colors.transparent,
        title: Text('剧集搜索'),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                _searchBar(),
                const SizedBox(height: 20),
                if (plugins.isEmpty)
                  const GeneralEmptyState(
                    icon: Icons.extension_off_rounded,
                    title: '还没有安装剧集规则',
                  )
                else if (!hasResults)
                  const GeneralEmptyState(
                    icon: Icons.live_tv_rounded,
                    title: '搜索电视剧、电影或综艺',
                  )
                else if (_isSearching && _results.isEmpty)
                  const Center(child: CircularProgressIndicator())
                else
                  for (final plugin in plugins) _resultGroup(plugin),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
