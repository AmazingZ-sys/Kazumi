part of 'plugins_controller.dart';

/// Configuration lifecycle shares the rule controller's serial write queue so
/// a saved configuration can never refer to a separately failed rule update.
extension TvBoxConfigurationManagement on _PluginsController {
  /// Import once, then refresh the subscription at this URL. Lookup and install
  /// share the write queue so concurrent requests cannot create duplicates.
  Future<TvBoxImportResult> fetchRemoteTvBoxConfig({
    String url = TvBoxSourceApi.configUrl,
  }) => _mutations.run(() async {
    final input = url.trim();
    final uri = Uri.tryParse(input);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty) {
      throw const FormatException('远端配置地址必须是有效的 HTTP(S) 地址');
    }
    final previous = tvBoxSubscriptions
        .where((subscription) => subscription.input == input)
        .firstOrNull;
    final loaded = await _loadTvBoxConfig(input);
    return _mutateAndPersistNow(
      () => _installTvBoxConfig(
        id: previous?.id ?? _newTvBoxId(),
        name: previous?.name ?? TvBoxSourceApi.subscriptionName,
        input: input,
        snapshot: loaded.snapshot,
        result: loaded.result,
        preserveLocalChanges: true,
      ),
      errorMessage: 'Plugin: failed to import remote TVBox configuration',
    );
  });

  Future<TvBoxImportResult> previewTvBoxConfig(String input) async =>
      (await _loadTvBoxConfig(input)).result;

  Future<({String snapshot, TvBoxImportResult result})> _loadTvBoxConfig(
    String input,
  ) async {
    final value = input.trim();
    if (value.isEmpty) throw const FormatException('请输入配置地址或 JSON');
    final uri = Uri.tryParse(value);
    final isUrl =
        uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
    final snapshot = isUrl ? await _tvBoxConfigLoader(value) : value;
    if (snapshot.length > 8 * 1024 * 1024) {
      throw const FormatException('配置内容过大，请使用较小的配置');
    }
    final result = TvBoxImportParser.parse(
      snapshot,
      baseUrl: isUrl ? value : null,
    );
    if (result.plugins.isEmpty) {
      throw FormatException(
        result.warnings.isEmpty
            ? '配置中没有可导入的来源'
            : '没有可导入的来源：${result.warnings.take(5).join('；')}',
      );
    }
    return (snapshot: snapshot, result: result);
  }

  Future<TvBoxImportResult> saveTvBoxConfig({
    String? id,
    required String name,
    required String input,
  }) => _mutations.run(() async {
    if (name.trim().isEmpty) throw const FormatException('请输入配置名称');
    if (id != null && !tvBoxSubscriptions.any((s) => s.id == id)) {
      throw const FormatException('配置已删除，请返回列表后重试');
    }
    final loaded = await _loadTvBoxConfig(input);
    final configId = id ?? _newTvBoxId();
    return _mutateAndPersistNow(
      () => _installTvBoxConfig(
        id: configId,
        name: name.trim(),
        input: input.trim(),
        snapshot: loaded.snapshot,
        result: loaded.result,
        preserveLocalChanges: false,
      ),
      errorMessage: 'Plugin: failed to save TVBox configuration',
    );
  });

  Future<TvBoxImportResult> refreshTvBoxConfig(String id) =>
      _mutations.run(() async {
        final subscription = _tvBoxConfig(id);
        final loaded = await _loadTvBoxConfig(subscription.input);
        return _mutateAndPersistNow(
          () => _installTvBoxConfig(
            id: id,
            name: subscription.name,
            input: subscription.input,
            snapshot: loaded.snapshot,
            result: loaded.result,
            preserveLocalChanges: true,
          ),
          errorMessage: 'Plugin: failed to refresh TVBox configuration',
        );
      });

  Future<void> removeTvBoxConfig(String id) => _mutateAndPersist(() {
    _tvBoxConfig(id);
    pluginList.removeWhere((p) => p.subscriptionId == id);
    tvBoxSubscriptions.removeWhere((s) => s.id == id);
  }, errorMessage: 'Plugin: failed to remove TVBox configuration');

  TvBoxSubscription _tvBoxConfig(String id) {
    for (final config in tvBoxSubscriptions) {
      if (config.id == id) return config;
    }
    throw const FormatException('配置已删除，请返回列表后重试');
  }

  TvBoxImportResult _installTvBoxConfig({
    required String id,
    required String name,
    required String input,
    required String snapshot,
    required TvBoxImportResult result,
    required bool preserveLocalChanges,
  }) {
    final index = tvBoxSubscriptions.indexWhere((s) => s.id == id);
    final previous = index < 0 ? null : tvBoxSubscriptions[index];
    final existing = {
      for (final p in pluginList)
        if (p.subscriptionId == id && p.tvBoxSite != null) p.tvBoxSite!.key: p,
    };
    final excluded = <String>{};
    if (preserveLocalChanges && previous != null) {
      excluded.addAll(previous.excludedSiteKeys);
      excluded.addAll(
        previous.ruleSnapshots.keys.where((key) => !existing.containsKey(key)),
      );
    }
    final usedNames = pluginList
        .where((p) => p.subscriptionId != id)
        .map((p) => pluginNameKey(p.name))
        .toSet();
    // Reserve existing names before naming new sources, preserving history keys.
    usedNames.addAll(existing.values.map((p) => pluginNameKey(p.name)));
    final installed = <Plugin>[];
    final baselines = <String, String>{};
    final warnings = List<String>.of(result.warnings);
    for (final imported in result.plugins) {
      final key = imported.tvBoxSite!.key;
      if (excluded.contains(key)) continue;
      final old = existing[key];
      final plugin = Plugin.fromJson(imported.toJson());
      plugin.subscriptionId = id;
      plugin.name =
          old?.name ?? _availableTvBoxName('$name · ${plugin.name}', usedNames);
      baselines[key] = jsonEncode(plugin.toJson());
      final baseline = previous?.ruleSnapshots[key];
      final locallyEdited =
          preserveLocalChanges &&
          old != null &&
          baseline != null &&
          baseline != jsonEncode(old.toJson());
      if (locallyEdited) {
        installed.add(old);
        // Keep the last upstream baseline until this local override is reset.
        baselines[key] = baseline;
        warnings.add('${old.name}：保留了本地修改');
      } else {
        installed.add(plugin);
      }
    }
    // Retain locally edited sources that were removed from the upstream list.
    if (preserveLocalChanges && previous != null) {
      final incomingKeys = result.plugins.map((p) => p.tvBoxSite!.key).toSet();
      for (final entry in existing.entries) {
        final baseline = previous.ruleSnapshots[entry.key];
        if (!incomingKeys.contains(entry.key) &&
            baseline != null &&
            baseline != jsonEncode(entry.value.toJson())) {
          installed.add(entry.value);
          baselines[entry.key] = baseline;
          warnings.add('${entry.value.name}：上游已移除，保留了本地修改');
        }
      }
    }
    if (excluded.isNotEmpty) warnings.add('保留了 ${excluded.length} 个来源的本地删除记录');
    pluginList.removeWhere((p) => p.subscriptionId == id);
    pluginList.addAll(installed);
    final subscription = TvBoxSubscription(
      id: id,
      name: name,
      input: input,
      snapshot: snapshot,
      updatedAt: DateTime.now(),
      ruleSnapshots: baselines,
      excludedSiteKeys: excluded.toList(),
    );
    if (index < 0) {
      tvBoxSubscriptions.add(subscription);
    } else {
      tvBoxSubscriptions[index] = subscription;
    }
    return TvBoxImportResult(plugins: installed, warnings: warnings);
  }
}

String _newTvBoxId() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

String _availableTvBoxName(String name, Set<String> used) {
  var candidate = name;
  var suffix = 2;
  while (!used.add(pluginNameKey(candidate))) {
    candidate = '$name ($suffix)';
    suffix++;
  }
  return candidate;
}
