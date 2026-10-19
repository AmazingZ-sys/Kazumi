import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:mobx/mobx.dart';
import 'package:flutter/services.dart' show rootBundle, AssetManifest;
import 'package:path_provider/path_provider.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/tvbox_subscription.dart';
import 'package:kazumi/plugins/tvbox_source_api.dart';
import 'package:kazumi/request/clients/plugin_site_client.dart';
import 'package:kazumi/services/plugin/tvbox_import_parser.dart';
import 'package:kazumi/services/plugin/plugin_validity_tracker.dart';
import 'package:kazumi/request/apis/plugin_catalog_api.dart';
import 'package:kazumi/modules/plugin/plugin_http_module.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/utils/async_serial_queue.dart';
import 'package:kazumi/utils/async_single_flight.dart';
import 'package:kazumi/utils/version.dart';

part 'plugins_controller.g.dart';
part 'tvbox_config_controller.dart';

class PluginsController = _PluginsController with _$PluginsController;

enum PluginUpdateAvailability { unknown, notInCatalog, latest, updatable }

enum PluginCatalogItemStatus { install, installed, update }

enum PluginUpdateResult { updated, requiresNewerClient, failed, notNewer }

class PluginBatchUpdateResult {
  const PluginBatchUpdateResult({
    required this.candidates,
    required this.updated,
    required this.requiresNewerClient,
    required this.failed,
    required this.notNewer,
  });

  final int candidates;
  final int updated;
  final int requiresNewerClient;
  final int failed;
  final int notNewer;

  bool get hasNoCandidates => candidates == 0;
}

typedef PluginCatalogLoader = Future<List<PluginHTTPItem>> Function();
typedef PluginLoader = Future<Plugin> Function(String name);
typedef TvBoxConfigLoader = Future<String> Function(String url);
typedef PluginJsonWriter = Future<void> Function(String jsonData);
typedef PluginErrorReporter =
    void Function(String message, Object error, StackTrace stackTrace);
typedef _PluginUpdateAttempt = ({PluginUpdateResult result, Plugin? plugin});

void _defaultPluginErrorReporter(
  String message,
  Object error,
  StackTrace stackTrace,
) {
  KazumiLogger().e(message, error: error, stackTrace: stackTrace);
}

abstract class _PluginsController with Store {
  _PluginsController({
    PluginCatalogLoader? catalogLoader,
    PluginLoader? pluginLoader,
    PluginJsonWriter? pluginJsonWriter,
    TvBoxConfigLoader? tvBoxConfigLoader,
    PluginErrorReporter? errorReporter,
  }) : _catalogLoader = catalogLoader ?? PluginCatalogApi.getPluginList,
       _pluginLoader = pluginLoader ?? PluginCatalogApi.getPlugin,
       _pluginJsonWriter = pluginJsonWriter,
       _tvBoxConfigLoader =
           tvBoxConfigLoader ??
           ((url) => PluginSiteClient.instance.requestText(url, method: 'GET')),
       _errorReporter = errorReporter ?? _defaultPluginErrorReporter;

  final PluginCatalogLoader _catalogLoader;
  final PluginLoader _pluginLoader;
  final PluginJsonWriter? _pluginJsonWriter;
  final TvBoxConfigLoader _tvBoxConfigLoader;
  final ObservableList<TvBoxSubscription> tvBoxSubscriptions =
      ObservableList.of([]);
  final PluginErrorReporter _errorReporter;
  final AsyncSingleFlight<List<PluginHTTPItem>> _catalogRefreshSingleFlight =
      AsyncSingleFlight<List<PluginHTTPItem>>();
  final AsyncSerialQueue _mutations = AsyncSerialQueue();
  Map<String, PluginHTTPItem> _pluginCatalogByName = const {};
  DateTime? _pluginCatalogRefreshedAt;
  int _optimisticReorderRevision = 0;

  // Reuse a recent catalog across startup, the rule list, and the rule shop.
  // Explicit refresh actions always bypass this window.
  static const _pluginCatalogMaxAge = Duration(minutes: 5);
  static const _maxConcurrentRuleDownloads = 4;

  @observable
  ObservableList<Plugin> pluginList = ObservableList.of([]);

  @observable
  ObservableList<PluginHTTPItem> pluginHTTPList = ObservableList.of([]);

  final validityTracker = PluginValidityTracker();

  static const _pluginsFileName = 'plugins.json';
  File? _pluginsFile;

  Future<void> init() async {
    final supportDirectory = await getApplicationSupportDirectory();
    final legacyDirectory = Directory('${supportDirectory.path}/plugins');
    final directory = Directory('${legacyDirectory.path}/v2');
    await directory.create(recursive: true);
    KazumiLogger().i('Plugins Directory: ${directory.path}');
    final pluginsFile = File('${directory.path}/$_pluginsFileName');
    _pluginsFile = pluginsFile;
    pluginList.clear();
    tvBoxSubscriptions.clear();
    if (await pluginsFile.exists()) {
      final decoded = jsonDecode(await pluginsFile.readAsString());
      final List<dynamic> json;
      if (decoded is Map) {
        if (decoded['version'] != 1 ||
            decoded['plugins'] is! List ||
            decoded['tvBoxSubscriptions'] is! List) {
          throw const FormatException('不支持的本地规则存储格式');
        }
        tvBoxSubscriptions.addAll(
          (decoded['tvBoxSubscriptions'] as List).map(
            (item) => TvBoxSubscription.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          ),
        );
        json = decoded['plugins'] as List;
      } else {
        json = decoded as List;
      }
      pluginList.addAll([for (final item in json) Plugin.fromJson(item)]);
      KazumiLogger().i('Plugin: Current Plugin number: ${pluginList.length}');
    } else {
      await _migrateLegacyPlugins(legacyDirectory);
    }
    // Keep the fork's bundled drama rule available after installation/upgrades
    // without replacing user-customized rules or subscription sources.
    await _installMissingBundledRules();
    await _savePlugins();
  }

  // Before 1.5.1 each rule was a separate JSON file in the parent directory.
  Future<void> _migrateLegacyPlugins(Directory legacyDirectory) async {
    final legacyFiles = legacyDirectory.listSync().whereType<File>().where(
      (file) => file.path.endsWith('.json'),
    );
    for (final file in legacyFiles) {
      pluginList.add(Plugin.fromJson(jsonDecode(await file.readAsString())));
      await file.delete();
    }
    await _savePlugins();
  }

  Future<void> _installMissingBundledRules() async {
    final assetManifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assets = assetManifest.listAssets();
    final jsonFiles = assets.where(
      (String asset) =>
          asset.startsWith('assets/plugins/') && asset.endsWith('.json'),
    );

    for (var filePath in jsonFiles) {
      final jsonString = await rootBundle.loadString(filePath);
      final plugin = Plugin.fromJson(jsonDecode(jsonString));
      final installedIndex = pluginList.indexWhere(
        (installed) =>
            pluginNameKey(installed.name) == pluginNameKey(plugin.name),
      );
      if (installedIndex < 0) {
        pluginList.add(plugin);
        continue;
      }
      final installed = pluginList[installedIndex];
      // Repair the shipped 1.0 selector without replacing customized rules
      // or resetting their playback and anti-crawler settings.
      if (plugin.name == '欧乐影院' &&
          installed.version == '1.0' &&
          installed.baseUrl == 'https://olevod.com/' &&
          installed.searchURL ==
              'https://olevod.com/index.php/vod/search.html?wd=@keyword' &&
          installed.searchName == '//h4/a/text()[last()]') {
        installed.searchName = plugin.searchName;
        installed.version = plugin.version;
      }
    }
  }

  List<dynamic> _pluginListToJson() => [
    for (final plugin in pluginList) plugin.toJson(),
  ];

  Future<void> removePlugin(Plugin plugin) {
    return _mutateAndPersist(() {
      final owned = plugin.subscriptionId != null && plugin.tvBoxSite != null;
      pluginList.removeWhere(
        (candidate) => owned
            ? candidate.subscriptionId == plugin.subscriptionId &&
                  candidate.tvBoxSite?.key == plugin.tvBoxSite!.key
            : pluginNameKey(candidate.name) == pluginNameKey(plugin.name),
      );
      if (owned) {
        final index = tvBoxSubscriptions.indexWhere(
          (subscription) => subscription.id == plugin.subscriptionId,
        );
        if (index >= 0) {
          final current = tvBoxSubscriptions[index];
          final excluded = {...current.excludedSiteKeys, plugin.tvBoxSite!.key};
          tvBoxSubscriptions[index] = current.copyWith(
            excludedSiteKeys: excluded.toList(),
          );
        }
      }
    }, errorMessage: 'Plugin: failed to persist rule removal');
  }

  bool get isPluginCatalogFresh {
    final refreshedAt = _pluginCatalogRefreshedAt;
    return refreshedAt != null &&
        DateTime.now().difference(refreshedAt) < _pluginCatalogMaxAge;
  }

  void _replacePlugin(Plugin plugin) {
    bool flag = false;
    for (int i = 0; i < pluginList.length; ++i) {
      if (pluginNameKey(pluginList[i].name) == pluginNameKey(plugin.name)) {
        pluginList.replaceRange(i, i + 1, [plugin]);
        flag = true;
        break;
      }
    }
    if (!flag) {
      pluginList.add(plugin);
    }
  }

  Future<T> _mutateAndPersist<T>(
    T Function() mutate, {
    required String errorMessage,
  }) {
    return _mutations.run(
      () => _mutateAndPersistNow(mutate, errorMessage: errorMessage),
    );
  }

  Future<T> _mutateAndPersistNow<T>(
    T Function() mutate, {
    required String errorMessage,
  }) async {
    final previous = List<Plugin>.from(pluginList);
    final previousSubscriptions = List<TvBoxSubscription>.from(
      tvBoxSubscriptions,
    );
    try {
      final result = mutate();
      await _savePlugins();
      return result;
    } catch (error, stackTrace) {
      pluginList
        ..clear()
        ..addAll(previous);
      tvBoxSubscriptions
        ..clear()
        ..addAll(previousSubscriptions);
      _errorReporter(errorMessage, error, stackTrace);
      rethrow;
    }
  }

  Future<void> updatePlugin(Plugin plugin) {
    return _mutateAndPersist(() {
      if (plugin.subscriptionId != null && plugin.tvBoxSite != null) {
        final index = pluginList.indexWhere(
          (p) =>
              p.subscriptionId == plugin.subscriptionId &&
              p.tvBoxSite?.key == plugin.tvBoxSite!.key,
        );
        if (index < 0) {
          throw const FormatException('来源已删除，请返回列表后重试');
        }
        if (pluginList.indexed.any(
          (entry) =>
              entry.$1 != index &&
              pluginNameKey(entry.$2.name) == pluginNameKey(plugin.name),
        )) {
          throw const FormatException('已有同名来源，请使用其他名称');
        }
        pluginList[index] = plugin;
      } else {
        _replacePlugin(plugin);
      }
    }, errorMessage: 'Plugin: failed to persist rule update');
  }

  Future<void> updateTvBoxSource({
    required Plugin original,
    required Plugin edited,
  }) {
    return _mutateAndPersist(() {
      final index = pluginList.indexWhere(
        (candidate) =>
            candidate.tvBoxSite?.key == original.tvBoxSite?.key &&
            candidate.subscriptionId == original.subscriptionId &&
            (candidate.subscriptionId != null ||
                pluginNameKey(candidate.name) == pluginNameKey(original.name)),
      );
      if (index < 0) {
        throw const FormatException('来源已删除，请返回列表后重试');
      }
      if (edited.tvBoxSite?.key != original.tvBoxSite?.key) {
        throw const FormatException('不能修改来源标识 key');
      }
      if (pluginList.indexed.any(
        (entry) =>
            entry.$1 != index &&
            pluginNameKey(entry.$2.name) == pluginNameKey(edited.name),
      )) {
        throw const FormatException('已有同名来源，请使用其他名称');
      }
      pluginList[index] = edited;
    }, errorMessage: 'Plugin: failed to persist TVBox source update');
  }

  Future<void> updatePlugins(Iterable<Plugin> plugins) {
    return _mutateAndPersist(() {
      for (final incoming in plugins) {
        var plugin = incoming;
        if (plugin.tvBoxSite != null && plugin.subscriptionId == null) {
          final collision = pluginList.any(
            (existing) =>
                pluginNameKey(existing.name) == pluginNameKey(plugin.name) &&
                existing.tvBoxSite != null &&
                existing.subscriptionId != null,
          );
          if (collision) {
            final used = pluginList
                .map((item) => pluginNameKey(item.name))
                .toSet();
            plugin = Plugin.fromJson(plugin.toJson())
              ..name = _availableTvBoxName(plugin.name, used);
          }
        }
        _replacePlugin(plugin);
      }
    }, errorMessage: 'Plugin: failed to persist imported rules');
  }

  Future<void> onReorder(int oldIndex, int newIndex) {
    final previous = List<Plugin>.from(pluginList);
    final plugin = pluginList.removeAt(oldIndex);
    pluginList.insert(newIndex, plugin);
    final revision = ++_optimisticReorderRevision;
    return _mutations.run(() async {
      try {
        await _savePlugins();
      } catch (error, stackTrace) {
        if (revision == _optimisticReorderRevision) {
          // Other queued mutations may have installed/deleted sources since
          // this optimistic reorder. Roll back order without reviving or
          // dropping those sources.
          final order = {
            for (final entry in previous.indexed)
              pluginNameKey(entry.$2.name): entry.$1,
          };
          final current = pluginList.toList();
          final currentOrder = {
            for (final entry in current.indexed)
              pluginNameKey(entry.$2.name): entry.$1 + previous.length,
          };
          current.sort(
            (a, b) =>
                (order[pluginNameKey(a.name)] ??
                        currentOrder[pluginNameKey(a.name)]!)
                    .compareTo(
                      order[pluginNameKey(b.name)] ??
                          currentOrder[pluginNameKey(b.name)]!,
                    ),
          );
          pluginList
            ..clear()
            ..addAll(current);
        }
        _errorReporter(
          'Plugin: failed to persist rule order',
          error,
          stackTrace,
        );
        rethrow;
      }
    });
  }

  Future<void> _savePlugins() async {
    final rules = _pluginListToJson();
    final Object data = tvBoxSubscriptions.isEmpty
        ? rules
        : {
            'version': 1,
            'plugins': rules,
            'tvBoxSubscriptions': tvBoxSubscriptions
                .map((s) => s.toJson())
                .toList(),
          };
    await _writePluginsJson(jsonEncode(data));
  }

  Future<void> _writePluginsJson(String jsonData) async {
    final writer = _pluginJsonWriter;
    if (writer != null) {
      await writer(jsonData);
    } else {
      final pluginsFile = _pluginsFile!;
      final temporary = File('${pluginsFile.path}.tmp');
      try {
        await temporary.writeAsString(jsonData, flush: true);
        await temporary.rename(pluginsFile.path);
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
      KazumiLogger().i('Plugin: updated plugin file $_pluginsFileName');
    }
  }

  Future<List<PluginHTTPItem>> refreshPluginCatalog() {
    return _catalogRefreshSingleFlight.run(() async {
      try {
        final catalog = await _catalogLoader();
        _pluginCatalogByName = {
          for (final item in catalog) pluginNameKey(item.name): item,
        };
        pluginHTTPList
          ..clear()
          ..addAll(catalog);
        _pluginCatalogRefreshedAt = DateTime.now();
        return List<PluginHTTPItem>.unmodifiable(catalog);
      } catch (error, stackTrace) {
        _errorReporter(
          'Plugin: failed to refresh rule catalog',
          error,
          stackTrace,
        );
        rethrow;
      }
    });
  }

  Future<List<PluginHTTPItem>> ensurePluginCatalog() {
    if (isPluginCatalogFresh) {
      return Future.value(List<PluginHTTPItem>.unmodifiable(pluginHTTPList));
    }
    return refreshPluginCatalog();
  }

  Future<int> checkPluginUpdatesOnStartup({required bool enabled}) async {
    if (!enabled) {
      return 0;
    }
    await refreshPluginCatalog();
    return _updatablePluginNames().length;
  }

  bool _remoteIsNewer(String localVersion, String remoteVersion) {
    try {
      return needUpdate(localVersion, remoteVersion);
    } catch (_) {
      return localVersion != remoteVersion;
    }
  }

  PluginCatalogItemStatus pluginStatus(PluginHTTPItem pluginHTTPItem) {
    var pluginStatus = PluginCatalogItemStatus.install;
    for (Plugin plugin in pluginList) {
      if (pluginNameKey(pluginHTTPItem.name) == pluginNameKey(plugin.name)) {
        if (_remoteIsNewer(plugin.version, pluginHTTPItem.version)) {
          pluginStatus = PluginCatalogItemStatus.update;
        } else {
          pluginStatus = PluginCatalogItemStatus.installed;
        }
        break;
      }
    }
    return pluginStatus;
  }

  PluginUpdateAvailability pluginUpdateStatus(Plugin plugin) {
    if (_pluginCatalogRefreshedAt == null) {
      return PluginUpdateAvailability.unknown;
    }
    final remote = _pluginCatalogByName[pluginNameKey(plugin.name)];
    if (remote == null) {
      return PluginUpdateAvailability.notInCatalog;
    }
    return _remoteIsNewer(plugin.version, remote.version)
        ? PluginUpdateAvailability.updatable
        : PluginUpdateAvailability.latest;
  }

  List<String> _updatablePluginNames() {
    return [
      for (final plugin in pluginList)
        if (pluginUpdateStatus(plugin) == PluginUpdateAvailability.updatable)
          _pluginCatalogByName[pluginNameKey(plugin.name)]!.name,
    ];
  }

  Future<PluginUpdateResult> tryUpdatePluginByName(String name) {
    return _mutations.run(() async {
      final catalogName =
          _pluginCatalogByName[pluginNameKey(name)]?.name ?? name;
      final attempt = await _preparePluginUpdate(catalogName);
      if (attempt.result == PluginUpdateResult.updated) {
        await _mutateAndPersistNow(
          () => _replacePlugin(attempt.plugin!),
          errorMessage:
              'Plugin: failed to persist downloaded rule $catalogName',
        );
      }
      return attempt.result;
    });
  }

  Future<_PluginUpdateAttempt> _preparePluginUpdate(String name) async {
    late final Plugin remotePlugin;
    try {
      remotePlugin = await _pluginLoader(name);
    } catch (error, stackTrace) {
      _errorReporter(
        'Plugin: failed to download rule $name',
        error,
        stackTrace,
      );
      return (result: PluginUpdateResult.failed, plugin: null);
    }
    // Validate at the injected loader boundary so production and test/custom
    // loaders follow the same integrity rule. Preserve the catalog spelling.
    if (remotePlugin.name.isEmpty ||
        pluginNameKey(remotePlugin.name) != pluginNameKey(name)) {
      final error = FormatException(
        'Downloaded rule name ${remotePlugin.name} does not match $name',
      );
      _errorReporter(
        'Plugin: rejected mismatched rule payload',
        error,
        StackTrace.current,
      );
      return (result: PluginUpdateResult.failed, plugin: null);
    }
    remotePlugin.name = name;
    try {
      if (remotePlugin.requiresNewerClient) {
        return (result: PluginUpdateResult.requiresNewerClient, plugin: null);
      }
    } catch (error, stackTrace) {
      _errorReporter(
        'Plugin: invalid API level in rule $name',
        error,
        stackTrace,
      );
      return (result: PluginUpdateResult.failed, plugin: null);
    }
    Plugin? local;
    for (final plugin in pluginList) {
      if (pluginNameKey(plugin.name) == pluginNameKey(name)) {
        local = plugin;
        break;
      }
    }
    // Never downgrade an installed plugin; mirrors may lag behind upstream.
    if (local != null && !_remoteIsNewer(local.version, remotePlugin.version)) {
      return (result: PluginUpdateResult.notNewer, plugin: null);
    }
    return (result: PluginUpdateResult.updated, plugin: remotePlugin);
  }

  Future<PluginBatchUpdateResult> tryUpdateAllPlugin({
    bool ensureCatalog = true,
  }) {
    return _mutations.run(
      () => _tryUpdateAllPlugin(ensureCatalog: ensureCatalog),
    );
  }

  Future<PluginBatchUpdateResult> _tryUpdateAllPlugin({
    required bool ensureCatalog,
  }) async {
    if (ensureCatalog) {
      await ensurePluginCatalog();
    } else if (_pluginCatalogRefreshedAt == null) {
      throw StateError('Plugin catalog has not been loaded');
    }

    final candidates = _updatablePluginNames();
    final attempts = await _preparePluginUpdates(candidates);
    var updated = 0;
    var requiresNewerClient = 0;
    var failed = 0;
    var notNewer = 0;

    final updatedPlugins = <Plugin>[];
    for (final attempt in attempts) {
      switch (attempt.result) {
        case PluginUpdateResult.updated:
          updated++;
          updatedPlugins.add(attempt.plugin!);
        case PluginUpdateResult.requiresNewerClient:
          requiresNewerClient++;
        case PluginUpdateResult.failed:
          failed++;
        case PluginUpdateResult.notNewer:
          notNewer++;
      }
    }

    if (updatedPlugins.isNotEmpty) {
      await _mutateAndPersistNow(() {
        for (final plugin in updatedPlugins) {
          _replacePlugin(plugin);
        }
      }, errorMessage: 'Plugin: failed to persist batch rule update');
    }
    return PluginBatchUpdateResult(
      candidates: candidates.length,
      updated: updated,
      requiresNewerClient: requiresNewerClient,
      failed: failed,
      notNewer: notNewer,
    );
  }

  Future<List<_PluginUpdateAttempt>> _preparePluginUpdates(
    List<String> names,
  ) async {
    if (names.isEmpty) {
      return const [];
    }
    final results = List<_PluginUpdateAttempt?>.filled(names.length, null);
    var nextIndex = 0;

    Future<void> worker() async {
      while (nextIndex < names.length) {
        final index = nextIndex++;
        results[index] = await _preparePluginUpdate(names[index]);
      }
    }

    final workerCount = names.length < _maxConcurrentRuleDownloads
        ? names.length
        : _maxConcurrentRuleDownloads;
    await Future.wait(List.generate(workerCount, (_) => worker()));
    return results.cast<_PluginUpdateAttempt>();
  }

  Future<void> removePlugins(Set<String> pluginNames) {
    final names = Set<String>.of(pluginNames);
    return _mutateAndPersist(() {
      for (int i = pluginList.length - 1; i >= 0; --i) {
        var name = pluginList[i].name;
        if (names.contains(name)) {
          pluginList.removeAt(i);
        }
      }
    }, errorMessage: 'Plugin: failed to persist batch rule removal');
  }
}
