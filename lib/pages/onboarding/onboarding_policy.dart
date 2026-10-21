import 'package:kazumi/plugins/plugins.dart';

bool hasAnimeSources(Iterable<Plugin> plugins) =>
    plugins.any((plugin) => plugin.type.trim().toLowerCase() == 'anime');

bool shouldShowOnboarding({
  required bool completed,
  required Iterable<Plugin> plugins,
}) => !completed && !hasAnimeSources(plugins);
