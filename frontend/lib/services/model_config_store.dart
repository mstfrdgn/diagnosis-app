import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/model_configuration.dart';

/// Reads/writes `model_configs.json` in the app documents directory, the
/// same directory `ConfigLoader` and `CsvService` use. Maps absolute model
/// file paths to their [ModelConfigEntry] (last-opened time + saved
/// per-model configuration), so both persist across app restarts.
abstract final class ModelConfigStore {
  static const fileName = 'model_configs.json';

  static Future<File> _file() async {
    final appDir = await getApplicationDocumentsDirectory();
    return File(p.join(appDir.path, fileName));
  }

  /// Any parse error (missing/corrupt file) falls back to an empty map.
  static Future<Map<String, ModelConfigEntry>> load() async {
    try {
      final file = await _file();
      if (!file.existsSync()) return {};
      final content = await file.readAsString();
      final decoded = jsonDecode(content);
      if (decoded is! Map) return {};
      return decoded.map(
        (path, value) => MapEntry(
          path as String,
          ModelConfigEntry.fromJson(path, value as Map<String, dynamic>),
        ),
      );
    } catch (e) {
      debugPrint('ModelConfigStore: failed to load ($e), starting empty.');
      return {};
    }
  }

  static Future<void> save(Map<String, ModelConfigEntry> entries) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    final json = entries.map((path, entry) => MapEntry(path, entry.toJson()));
    await file.writeAsString(jsonEncode(json));
  }
}
