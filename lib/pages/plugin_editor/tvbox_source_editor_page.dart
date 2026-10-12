import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/settings/settings_detail_scaffold.dart';
import 'package:kazumi/bean/widget/loading_indicator.dart';
import 'package:kazumi/pages/plugin_editor/rule_management_widgets.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/services/plugin/tvbox_import_parser.dart';

/// Keeps imported source settings and subscription identity together when a
/// user customizes one source instead of replacing its whole configuration.
class TvBoxSourceEditorPage extends StatefulWidget {
  const TvBoxSourceEditorPage({
    super.key,
    required this.plugin,
    required this.controller,
  });

  final Plugin plugin;
  final PluginsController controller;

  @override
  State<TvBoxSourceEditorPage> createState() => _TvBoxSourceEditorPageState();
}

class _TvBoxSourceEditorPageState extends State<TvBoxSourceEditorPage> {
  late final _name = TextEditingController(text: widget.plugin.name);
  late final _json = TextEditingController(
    text: const JsonEncoder.withIndent(
      '  ',
    ).convert(widget.plugin.tvBoxSite!.toJson()),
  );
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _json.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_name.text.trim().isEmpty) {
        throw const FormatException('请填写来源名称。');
      }
      final data = jsonDecode(_json.text);
      if (data is! Map || data.containsKey('sites')) {
        throw const FormatException('请填写单个来源的 JSON 对象。');
      }
      final result = TvBoxImportParser.parse(_json.text);
      if (result.plugins.length != 1 || result.warnings.isNotEmpty) {
        throw FormatException(
          result.warnings.isEmpty ? '没有识别到可保存的来源。' : result.warnings.join('\n'),
        );
      }
      final source = result.plugins.single;
      if (source.tvBoxSite?.key != widget.plugin.tvBoxSite!.key) {
        throw const FormatException('不能修改来源标识 key；添加其他来源请编辑影视仓配置。');
      }
      final edited = Plugin.fromJson(widget.plugin.toJson())
        ..name = _name.text.trim()
        ..tvBoxSite = source.tvBoxSite
        ..baseUrl = source.baseUrl
        ..searchMode = source.searchMode
        ..chapterMode = source.chapterMode
        ..searchApiConfig = source.searchApiConfig
        ..chapterApiConfig = source.chapterApiConfig;
      await widget.controller.updateTvBoxSource(
        original: widget.plugin,
        edited: edited,
      );
      if (!mounted) return;
      setState(() => _saving = false);
      KazumiDialog.showToast(context: context, message: '来源已保存');
      Navigator.of(context).maybePop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is FormatException
            ? error.message
            : error is ArgumentError && error.message is String
            ? error.message as String
            : '保存失败，内容已保留，请重试。';
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: SettingsDetailScaffold(
      title: const Text('影视仓来源编辑'),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                RuleSection(
                  title: '来源设置',
                  icon: Icons.edit_note_rounded,
                  description: '单独修改的来源会在刷新配置时保留。重新编辑并保存整个影视仓配置会重置这些修改。',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        key: const ValueKey('tvbox-source-name'),
                        controller: _name,
                        enabled: !_saving,
                        onChanged: (_) => setState(() => _error = null),
                        decoration: ruleInputDecoration(context, label: '来源名称'),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        key: const ValueKey('tvbox-source-json'),
                        controller: _json,
                        enabled: !_saving,
                        minLines: 8,
                        maxLines: 18,
                        keyboardType: TextInputType.multiline,
                        autocorrect: false,
                        onChanged: (_) => setState(() => _error = null),
                        decoration:
                            ruleInputDecoration(
                              context,
                              label: '来源 JSON',
                            ).copyWith(
                              alignLabelWithHint: true,
                              helperText: '可调整接口地址、请求头和站点参数，保留原有 key。',
                              helperMaxLines: 2,
                            ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const LoadingIndicator(size: 18)
                  : const Icon(Icons.save_outlined, size: 18),
              label: Text(_saving ? '正在保存' : '保存来源'),
            ),
          ),
        ),
      ),
    ),
  );
}
