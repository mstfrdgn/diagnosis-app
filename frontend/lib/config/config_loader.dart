import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:yaml/yaml.dart';

import 'app_config.dart';
import 'preference.dart';

abstract final class ConfigLoader {
  static const fileName = 'app_config.yaml';
  static const _assetPath = 'assets/config/$fileName';

  /// Load config using this resolution order:
  ///   1. {appDocumentsDir}/app_config.yaml  – user-edited copy
  ///   2. Bundled assets/config/app_config.yaml – shipped default
  /// On first launch the bundled file is copied to the documents dir so the
  /// user can edit it without recompiling.
  /// Any parse error falls back to [AppConfig.defaults] silently.
  static Future<AppConfig> load() async {
    try {
      final userFile = await _userFile();
      final content = await userFile.readAsString();
      final yaml = loadYaml(content);
      if (yaml is Map) return AppConfig.fromYaml(yaml);
    } catch (e) {
      debugPrint('ConfigLoader: failed to load config ($e), using defaults.');
    }
    return AppConfig.defaults;
  }

  /// Sets [preference] to [value] in the user's file and returns the config
  /// that file then holds.
  ///
  /// The file is read afresh, so changes made to it in an editor since the
  /// last load are kept. Throws, leaving the file as it was, when it cannot be
  /// read as YAML or cannot be written.
  static Future<AppConfig> save(Preference preference, Object value) async {
    final userFile = await _userFile();
    final content = preference.applyTo(await userFile.readAsString(), value);
    final config = AppConfig.fromYaml(loadYaml(content) as Map);

    // Written next to the file and then moved over it, so a crash halfway
    // cannot leave a truncated config behind.
    final temp = File('${userFile.path}.tmp');
    try {
      await temp.writeAsString(content, flush: true);
      await temp.rename(userFile.path);
    } catch (_) {
      if (temp.existsSync()) await temp.delete();
      rethrow;
    }
    return config;
  }

  /// The user's copy of the config, created from the bundled one if needed.
  static Future<File> _userFile() async {
    final appDir = await getApplicationDocumentsDirectory();
    final userFile = File(p.join(appDir.path, fileName));
    if (!userFile.existsSync()) {
      final bundled = await rootBundle.loadString(_assetPath);
      await userFile.writeAsString(bundled);
    }
    return userFile;
  }
}
