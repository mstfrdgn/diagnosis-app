import 'package:flutter/foundation.dart';

import '../models/model_configuration.dart';
import 'model_config_store.dart';

/// Wraps the on-disk `model_configs.json` (via [ModelConfigStore]) as a
/// [ChangeNotifier] so widgets can watch the "recently used models" list and
/// look up / save a model's name, description and [ModelConfiguration].
class ModelConfigNotifier extends ChangeNotifier {
  ModelConfigNotifier(Map<String, ModelConfigEntry> initialEntries)
      : _entries = Map.of(initialEntries);

  final Map<String, ModelConfigEntry> _entries;

  /// Entries sorted most-recently-opened first.
  List<ModelConfigEntry> get recentModels => _entries.values.toList()
    ..sort((a, b) => b.lastOpened.compareTo(a.lastOpened));

  ModelConfigEntry? entryFor(String path) => _entries[path];

  ModelConfiguration? configurationFor(String path) =>
      _entries[path]?.configuration;

  /// The user-chosen name for [path], or null if it has never been renamed.
  /// Callers that need a name to show should use [ModelConfigEntry.effectiveName].
  String? displayNameFor(String path) => _entries[path]?.displayName;

  String? descriptionFor(String path) => _entries[path]?.description;

  /// Records that [path] was just opened, preserving any existing saved
  /// configuration. Called as soon as a model load succeeds, before the
  /// user has necessarily been through the Configuration Screen.
  ///
  /// [autoDescription] is the summary generated from the freshly loaded
  /// domain. It is only stored when the model has no description yet — once
  /// the user has edited it, the text is theirs to keep.
  Future<void> recordOpened(String path, {String? autoDescription}) async {
    final now = DateTime.now();
    final existing = _entries[path];
    _entries[path] = (existing ??
            ModelConfigEntry(path: path, createdAt: now, lastOpened: now))
        .copyWith(
      lastOpened: now,
      description: existing?.description ?? autoDescription,
    );
    await _persist();
  }

  /// Renames [path]. An empty [name] clears the override, so the model goes
  /// back to being shown under its file name.
  Future<void> setDisplayName(String path, String name) async {
    final entry = _entries[path];
    if (entry == null) return;
    final trimmed = name.trim();
    _entries[path] = ModelConfigEntry(
      path: path,
      createdAt: entry.createdAt,
      lastOpened: entry.lastOpened,
      displayName: trimmed.isEmpty ? null : trimmed,
      description: entry.description,
      configuration: entry.configuration,
    );
    await _persist();
  }

  /// Forgets [path] entirely: it leaves the recent list and
  /// `model_configs.json`, taking its name, description and saved
  /// configuration with it.
  ///
  /// The `.pkcls` file itself is untouched, so picking the same model again
  /// simply starts a fresh entry — and session logs, which live in their own
  /// CSVs, are unaffected.
  Future<void> remove(String path) async {
    if (_entries.remove(path) == null) return;
    await _persist();
  }

  /// Saves [config] for [path], as produced by the Configuration Screen,
  /// along with the description the user edited alongside it.
  Future<void> saveConfiguration(
    String path,
    ModelConfiguration config, {
    String? description,
  }) async {
    final now = DateTime.now();
    final existing = _entries[path];
    final trimmed = description?.trim();
    _entries[path] = ModelConfigEntry(
      path: path,
      // "Created" means when the model was first set up here, so an existing
      // entry keeps the timestamp it was given the first time round.
      createdAt: existing?.createdAt ?? now,
      lastOpened: now,
      displayName: existing?.displayName,
      description: (trimmed == null || trimmed.isEmpty)
          ? existing?.description
          : trimmed,
      configuration: config,
    );
    await _persist();
  }

  Future<void> _persist() async {
    await ModelConfigStore.save(_entries);
    notifyListeners();
  }
}
