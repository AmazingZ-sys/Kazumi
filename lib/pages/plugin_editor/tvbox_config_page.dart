import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/settings/settings_detail_scaffold.dart';
import 'package:kazumi/bean/widget/empty_state_widget.dart';
import 'package:kazumi/bean/widget/loading_indicator.dart';
import 'package:kazumi/pages/plugin_editor/rule_management_widgets.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/plugins/tvbox_source_api.dart';
import 'package:kazumi/plugins/tvbox_subscription.dart';
import 'package:kazumi/services/plugin/tvbox_import_parser.dart';

class TvBoxConfigPage extends StatefulWidget {
  const TvBoxConfigPage({super.key, required this.controller});

  final PluginsController controller;

  @override
  State<TvBoxConfigPage> createState() => _TvBoxConfigPageState();
}

class _TvBoxConfigPageState extends State<TvBoxConfigPage> {
  String? _busyId;
  bool _editing = false;
  String? _message;
  bool _hasError = false;
  List<String> _warnings = const [];

  bool get _busy => _busyId != null || _editing;

  void _feedback(
    String message, {
    bool error = false,
    List<String> warnings = const [],
  }) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _hasError = error;
      _warnings = warnings;
    });
  }

  Future<void> _edit([TvBoxSubscription? subscription]) async {
    if (_busy) return;
    setState(() => _editing = true);
    final result = await KazumiDialog.show<TvBoxImportResult>(
      context: context,
      clickMaskDismiss: false,
      builder: (_) => _TvBoxConfigEditor(
        controller: widget.controller,
        subscription: subscription,
      ),
    );
    if (!mounted) return;
    setState(() => _editing = false);
    if (result != null) {
      _feedback(
        '配置已保存，已导入 ${result.plugins.length} 个来源。',
        warnings: result.warnings,
      );
    }
  }

  Future<void> _refresh(TvBoxSubscription subscription) async {
    if (_busy) return;
    setState(() => _busyId = subscription.id);
    try {
      final result = await widget.controller.refreshTvBoxConfig(
        subscription.id,
      );
      _feedback(
        '「${subscription.name}」已刷新，已保留单独修改和删除的来源设置。',
        warnings: result.warnings,
      );
    } catch (error) {
      _feedback('刷新失败，原有配置和来源已保留。${_errorDescription(error)}', error: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _fetchRemote() async {
    if (_busy) return;
    setState(() => _busyId = 'remote-fetch');
    try {
      final result = await widget.controller.fetchRemoteTvBoxConfig();
      _feedback(
        '远端配置已保存到本地，已导入 ${result.plugins.length} 个来源。再次导入会保留单独修改和删除的来源。',
        warnings: result.warnings,
      );
    } catch (error) {
      _feedback(
        '远端配置导入失败，原有配置和来源已保留。请确认远端接口已部署且可以访问。${_errorDescription(error)}',
        error: true,
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _delete(TvBoxSubscription subscription) async {
    if (_busy) return;
    setState(() => _busyId = subscription.id);
    final count = widget.controller.pluginList
        .where((plugin) => plugin.subscriptionId == subscription.id)
        .length;
    final confirmed = await KazumiDialog.show<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.delete_outline_rounded),
        title: const Text('删除这项配置？'),
        content: Text('将同时删除配置「${subscription.name}」及其 $count 个关联来源。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('保留'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除配置'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (confirmed != true) {
      setState(() => _busyId = null);
      return;
    }
    try {
      await widget.controller.removeTvBoxConfig(subscription.id);
      _feedback('已删除「${subscription.name}」及其关联来源。');
    } catch (error) {
      _feedback('删除失败，原有配置和来源已保留。${_errorDescription(error)}', error: true);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) => SettingsDetailScaffold(
    title: const Text('影视仓配置'),
    body: SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Observer(
            builder: (context) {
              final subscriptions = widget.controller.tvBoxSubscriptions
                  .toList();
              final plugins = widget.controller.pluginList.toList();
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  RulePageIntro(
                    title: '我的影视仓配置',
                    description: '添加影视仓 / TVBox 配置中的兼容来源，保存后即可在剧集搜索中使用。',
                    icon: Icons.live_tv_rounded,
                    actions: [
                      Tooltip(
                        message: '从 ${TvBoxSourceApi.configUrl} 获取配置并保存到本地',
                        child: FilledButton.tonalIcon(
                          onPressed: _busy ? null : _fetchRemote,
                          icon: _busyId == 'remote-fetch'
                              ? const LoadingIndicator(size: 18)
                              : const Icon(Icons.cloud_download_outlined),
                          label: Text(
                            _busyId == 'remote-fetch' ? '正在获取远端配置' : '一键导入远端配置',
                          ),
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: _busy ? null : () => _edit(),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('添加配置'),
                      ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                    child: Text(
                      '刷新会保留单独修改或删除的来源。要调整配置中的站点，请编辑配置；要调整某个来源，请前往规则管理。',
                    ),
                  ),
                  if (_message != null) ...[
                    _ConfigNotice(
                      message: _message!,
                      warnings: _warnings,
                      error: _hasError,
                      onClose: () => setState(() {
                        _message = null;
                        _warnings = const [];
                      }),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (subscriptions.isEmpty)
                    const GeneralEmptyState(
                      icon: Icons.playlist_add_rounded,
                      title: '还没有添加影视仓配置',
                    ),
                  for (final subscription in subscriptions)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _subscriptionCard(
                        subscription,
                        plugins
                            .where(
                              (plugin) =>
                                  plugin.subscriptionId == subscription.id,
                            )
                            .length,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );

  Widget _subscriptionCard(TvBoxSubscription subscription, int siteCount) {
    final theme = Theme.of(context);
    final uri = Uri.tryParse(subscription.input.trim());
    final isUrl =
        uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(subscription.name, style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              isUrl ? subscription.input : '粘贴的 JSON 配置',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$siteCount 个来源 · 更新于 ${_formatTime(subscription.updatedAt)}',
              style: theme.textTheme.bodySmall,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (_busyId == subscription.id)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: LoadingIndicator(size: 20),
                  ),
                IconButton(
                  tooltip: '编辑 ${subscription.name}',
                  onPressed: _busy ? null : () => _edit(subscription),
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: '刷新 ${subscription.name}',
                  onPressed: _busy ? null : () => _refresh(subscription),
                  icon: const Icon(Icons.refresh_rounded),
                ),
                IconButton(
                  tooltip: '删除 ${subscription.name}',
                  onPressed: _busy ? null : () => _delete(subscription),
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TvBoxConfigEditor extends StatefulWidget {
  const _TvBoxConfigEditor({required this.controller, this.subscription});
  final PluginsController controller;
  final TvBoxSubscription? subscription;

  @override
  State<_TvBoxConfigEditor> createState() => _TvBoxConfigEditorState();
}

class _TvBoxConfigEditorState extends State<_TvBoxConfigEditor> {
  late final _name = TextEditingController(
    text: widget.subscription?.name ?? '',
  );
  late final _input = TextEditingController(
    text: widget.subscription?.input ?? '',
  );
  TvBoxImportResult? _preview;
  String? _error;
  bool _loading = false;
  bool _saving = false;
  bool _hasInput = false;

  bool get _busy => _loading || _saving;

  @override
  void initState() {
    super.initState();
    _hasInput = _input.text.trim().isNotEmpty;
  }

  @override
  void dispose() {
    _name.dispose();
    _input.dispose();
    super.dispose();
  }

  Future<void> _previewSources() async {
    if (_busy || _input.text.trim().isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _preview = null;
    });
    try {
      final result = await widget.controller.previewTvBoxConfig(_input.text);
      if (mounted) setState(() => _preview = result);
    } catch (error) {
      if (mounted) setState(() => _error = _errorDescription(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    if (_name.text.trim().isEmpty || _input.text.trim().isEmpty) {
      setState(() => _error = '请填写配置名称和配置地址或内容。');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await widget.controller.saveTvBoxConfig(
        id: widget.subscription?.id,
        name: _name.text.trim(),
        input: _input.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } catch (error) {
      if (mounted) {
        setState(() => _error = '保存失败，内容已保留。${_errorDescription(error)}');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      constraints: const BoxConstraints(maxWidth: 640),
      scrollable: true,
      icon: const Icon(Icons.live_tv_rounded),
      title: Text(widget.subscription == null ? '添加影视仓配置' : '编辑影视仓配置'),
      content: SizedBox(
        width: 540,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('输入配置地址或粘贴 JSON，预览可导入的来源和跳过原因。'),
            if (widget.subscription != null) ...[
              const SizedBox(height: 12),
              const Text('保存编辑会重新导入此配置的来源，重置单独修改和删除的来源设置。仅更新远程内容时，请使用列表中的刷新。'),
            ],
            const SizedBox(height: 20),
            TextField(
              key: const ValueKey('tvbox-name'),
              controller: _name,
              enabled: !_busy,
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() => _error = null),
              decoration: ruleInputDecoration(
                context,
                label: '配置名称',
                hint: '为这项配置起个名字',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const ValueKey('tvbox-input'),
              controller: _input,
              enabled: !_busy,
              minLines: 4,
              maxLines: 7,
              keyboardType: TextInputType.multiline,
              autocorrect: false,
              onChanged: (value) => setState(() {
                _error = null;
                _preview = null;
                _hasInput = value.trim().isNotEmpty;
              }),
              decoration: ruleInputDecoration(
                context,
                label: '配置地址或 JSON',
                hint: 'https://… 或包含站点的 JSON',
              ).copyWith(alignLabelWithHint: true),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              _ConfigNotice(message: _error!, error: true),
            ],
            if (_preview != null) ...[
              const SizedBox(height: 16),
              Text(
                '识别到 ${_preview!.plugins.length} 个来源',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              for (final plugin in _preview!.plugins)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(plugin.name),
                ),
              if (_preview!.warnings.isNotEmpty) ...[
                const SizedBox(height: 12),
                _ConfigNotice(message: '部分内容已跳过', warnings: _preview!.warnings),
              ],
            ],
          ],
        ),
      ),
      actionsOverflowButtonSpacing: 8,
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        OutlinedButton.icon(
          onPressed: _busy || !_hasInput ? null : _previewSources,
          icon: _loading
              ? const LoadingIndicator(size: 18)
              : const Icon(Icons.preview_outlined, size: 18),
          label: Text(_loading ? '正在预览' : '预览来源'),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : _save,
          icon: _saving
              ? const LoadingIndicator(size: 18)
              : const Icon(Icons.save_outlined, size: 18),
          label: Text(_saving ? '正在保存' : '保存配置'),
        ),
      ],
    ),
  );
}

class _ConfigNotice extends StatelessWidget {
  const _ConfigNotice({
    required this.message,
    this.warnings = const [],
    this.error = false,
    this.onClose,
  });
  final String message;
  final List<String> warnings;
  final bool error;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: error ? colors.errorContainer : colors.secondaryContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: DefaultTextStyle.merge(
          style: TextStyle(
            color: error
                ? colors.onErrorContainer
                : colors.onSecondaryContainer,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text(message)),
                  if (onClose != null)
                    IconButton(
                      tooltip: '关闭提示',
                      onPressed: onClose,
                      icon: const Icon(Icons.close_rounded),
                    ),
                ],
              ),
              for (final warning in warnings)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(warning),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

String _errorDescription(Object error) {
  if (error is FormatException) {
    return error.message;
  }
  if (error is ArgumentError && error.message is String) {
    return error.message as String;
  }
  return '请检查网络连接或存储空间后重试。';
}

String _formatTime(DateTime value) {
  final local = value.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}
