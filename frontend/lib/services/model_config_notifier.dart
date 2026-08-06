import 'package:flutter/foundation.dart';

import '../models/model_configuration.dart';
import 'model_config_store.dart';

/// Wraps the on-disk `model_configs.json` (via [ModelConfigStore]) as a
/// [ChangeNotifier] so widgets can watch the "recently used models" list and
/// look up / save a model's saved [ModelConfiguration].
class ModelConfigNotifier extends ChangeNotifier {
  ModelConfigNotifier(Map<String, ModelConfigEntry> initialEntries)
      : _entries = Map.of(initialEntries);

  final Map<String, ModelConfigEntry> _entries;

  /// Entries sorted most-recently-opened first.
  List<ModelConfigEntry> get recentModels => _entries.values.toList()
    ..sort((a, b) => b.lastOpened.compareTo(a.lastOpened));

  ModelConfiguration? configurationFor(String path) =>
      _entries[path]?.configuration;

  /// Records that [path] was just opened, preserving any existing saved
  /// configuration. Called as soon as a model load succeeds, before the
  /// user has necessarily been through the Configuration Screen.
  Future<void> recordOpened(String path) async {
    final existing = _entries[path];
    _entries[path] = (existing ?? ModelConfigEntry(path: path, lastOpened: DateTime.now()))
        .copyWith(lastOpened: DateTime.now());
    await ModelConfigStore.save(_entries);
    notifyListeners();
  }

  /// Saves [config] for [path], as produced by the Configuration Screen.
  Future<void> saveConfiguration(String path, ModelConfiguration config) async {
    _entries[path] = ModelConfigEntry(
      path: path,
      lastOpened: DateTime.now(),
      configuration: config,
    );
    await ModelConfigStore.save(_entries);
    notifyListeners();
  }
}
