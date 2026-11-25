import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_config.dart';
import 'config_loader.dart';
import 'preference.dart';

/// Wraps the current [AppConfig] in a [ChangeNotifier] so widgets can
/// `watch` it and rebuild when the settings screen changes or reloads the YAML
/// file.
class AppConfigNotifier extends ChangeNotifier {
  AppConfigNotifier(this._config, {Object? startupError})
      : _startupError = startupError;

  AppConfig _config;
  AppConfig get config => _config;

  /// Why `app_config.yaml` could not be used when the app started, for as long
  /// as the defaults are in use because of it.
  Object? _startupError;
  Object? get startupError => _startupError;

  void _use(AppConfig config) {
    _config = config;
    _startupError = null;
    notifyListeners();
  }

  /// Absolute path to the user-editable `app_config.yaml`.
  Future<String> configFilePath() async {
    final appDir = await getApplicationDocumentsDirectory();
    return p.join(appDir.path, ConfigLoader.fileName);
  }

  /// Re-reads `app_config.yaml` from disk and notifies listeners. Throws, with
  /// the config unchanged, when the file could not be read.
  Future<void> reload() async {
    try {
      _use(await ConfigLoader.load());
    } catch (e) {
      // Still on the defaults, but perhaps for a different reason by now.
      if (_startupError != null) {
        _startupError = e;
        notifyListeners();
      }
      rethrow;
    }
  }

  /// Completes when the last save has, so that each one builds on the file
  /// the one before it wrote.
  Future<void> _lastSave = Future.value();

  /// Writes [value] to `app_config.yaml` and notifies listeners. Throws, with
  /// the config unchanged, when the file could not be saved.
  Future<void> setPreference(Preference preference, Object value) {
    final save = _lastSave.then((_) async {
      _use(await ConfigLoader.save(preference, value));
    });
    _lastSave = save.catchError((Object _) {});
    return save;
  }
}
