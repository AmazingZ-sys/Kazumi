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
import 'package:kazumi/services/plugin/plugin_install_time_tracker.dart';
import 'package:kazumi/request/apis/plugin_catalog_api.dart';
import 'package:kazumi/modules/plugin/plugin_http_module.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/utils/async_serial_queue.dart';
import 'package:kazumi/utils/async_single_flight.dart';
import 'package:kazumi/utils/version.dart';

part 'plugins_controller.g.dart';
part 'tvbox_config_controller.dart';

// 从 1.5.1 版本开始，规则文件储存在单一的 plugins.json 文件中。
// 之前的版本中，规则以分离文件形式存储，版本更新后将这些分离文件合并为单一的 plugins.json 文件。

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

  // 规则有效性追踪器
  final validityTracker = PluginValidityTracker();

  // 规则安装时间追踪器
  final installTimeTracker = PluginInstallTimeTracker();

  String pluginsFileName = "plugins.json";

  Directory? oldPluginDirectory;

  Directory? newPluginDirectory;

  // Initializes the plugin directory and loads all plugins
  Future<void> init() async {
    final directory = await getApplicationSupportDirectory();
    oldPluginDirectory = Directory('${directory.path}/plugins');
    if (!await oldPluginDirectory!.exists()) {
      await oldPluginDirectory!.create(recursive: true);
    }
    newPluginDirectory = Directory('${directory.path}/plugins/v2');
    if (!await newPluginDirectory!.exists()) {
      await newPluginDirectory!.create(recursive: true);
    }
    await _loadAllPlugins();
    // Add newly bundled rules after an app upgrade without duplicating rules
    // that the user already has installed. This also makes the first bundled
    // drama rule available to existing installations.
    await _installMissingBundledRules();
    await _savePlugins();
  }

  // Loads all plugins from the directory, populates the plugin list, and saves to plugins.json if needed
  Future<void> _loadAllPlugins() async {
    pluginList.clear();
    tvBoxSubscriptions.clear();
    KazumiLogger().i('Plugins Directory: ${newPluginDirectory!.path}');
    if (await newPluginDirectory!.exists()) {
      final pluginsFile = File('${newPluginDirectory!.path}/$pluginsFileName');
      if (await pluginsFile.exists()) {
        final jsonString = await pluginsFile.readAsString();
        final decoded = jsonDecode(jsonString);
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
          pluginList.addAll(
            _getPluginListFromJson(jsonEncode(decoded['plugins'])),
          );
        } else {
          pluginList.addAll(_getPluginListFromJson(jsonString));
        }
        KazumiLogger().i('Plugin: Current Plugin number: ${pluginList.length}');
      } else {
        // No plugins.json
        var jsonFiles = await _getPluginFiles();
        for (var filePath in jsonFiles) {
          final file = File(filePath);
          final jsonString = await file.readAsString();
          final data = jsonDecode(jsonString);
          final plugin = Plugin.fromJson(data);
          pluginList.add(plugin);
          await file.delete(recursive: true);
        }
        await _savePlugins();
      }
    } else {
      KazumiLogger().w('Plugin: plugin directory does not exist');
    }
  }

  // Retrieves a list of JSON plugin file paths from the plugin directory
  Future<List<String>> _getPluginFiles() async {
    if (await oldPluginDirectory!.exists()) {
      final jsonFiles = oldPluginDirectory!
          .listSync()
          .where((file) => file.path.endsWith('.json') && file is File)
          .map((file) => file.path)
          .toList();
      return jsonFiles;
    } else {
      return [];
    }
  }

  // Copies plugin JSON files from the assets to the plugin directory
  Future<void> copyPluginsToExternalDirectory() async {
    await _installMissingBundledRules();
    await _savePlugins();
    KazumiLogger().i(
      'Plugin: bundled rules installed to ${newPluginDirectory!.path}',
    );
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

  List<dynamic> _pluginListToJson() {
    final List<dynamic> json = [];
    for (var plugin in pluginList) {
      json.add(plugin.toJson());
    }
    return json;
  }

  // Converts a JSON string into a list of Plugin objects.
  List<Plugin> _getPluginListFromJson(String jsonString) {
    List<dynamic> json = jsonDecode(jsonString);
    List<Plugin> plugins = [];
    for (var j in json) {
      plugins.add(Plugin.fromJson(j));
    }
    return plugins;
  }

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
      final pluginsFile = File('${newPluginDirectory!.path}/$pluginsFileName');
      final temporary = File('${pluginsFile.path}.tmp');
      try {
        await temporary.writeAsString(jsonData, flush: true);
        await temporary.rename(pluginsFile.path);
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
      KazumiLogger().i('Plugin: updated plugin file $pluginsFileName');
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
