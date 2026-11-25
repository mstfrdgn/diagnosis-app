import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../config/app_config.dart';
import '../models/model_domain.dart';
import '../models/session_record.dart';

/// Outcome of [CsvService.appendRecord].
///
/// The service never throws on I/O failure — a log file that is locked or
/// unwritable must not tear down the result screen — so callers check
/// [succeeded] and surface [error] themselves.
class CsvWriteResult {
  const CsvWriteResult.success(this.path) : error = null;
  const CsvWriteResult.failure(this.path, this.error);

  /// Absolute path of the log that was written, or that the write targeted.
  final String path;

  /// Human-readable reason the write failed, or null when it succeeded.
  final String? error;

  bool get succeeded => error == null;
}

/// Appends [SessionRecord]s to the CSV log configured by
/// `config.csv_logging`. The header (and its column set) is written once,
/// derived from [domain] so it stays stable across appends regardless of
/// which fields a particular session happened to fill in.
///
/// Each model logs to its own file (see [logFileNameFor]).
class CsvService {
  const CsvService();

  static const _converter = ListToCsvConverter();

  Future<CsvWriteResult> appendRecord(
    SessionRecord record, {
    required ModelDomain domain,
    required String modelPath,
    required AppConfig config,
    String? modelDisplayName,
  }) async {
    File? file;
    try {
      file = await _resolveFile(modelPath, config, modelDisplayName);
      final featureNames = domain.features.map((f) => f.name).toList();
      final classLabels =
          domain.classVar.values ?? record.probabilities.keys.toList();

      final needsHeader = !await file.exists() || await file.length() == 0;

      final columns = _buildHeader(featureNames, classLabels);
      var row = _buildRow(record, featureNames, classLabels, config);

      final buffer = StringBuffer();
      if (needsHeader) {
        buffer.write(_line(columns));
      } else {
        row = await _alignToHeader(
          file,
          columns: columns,
          row: row,
          // The timestamp, the features and the predicted class.
          fixed: featureNames.length + 2,
        );
      }
      buffer.write(_line(row));

      await file.writeAsString(buffer.toString(), mode: FileMode.append);
      return CsvWriteResult.success(file.path);
    } on FileSystemException catch (e) {
      return CsvWriteResult.failure(
        file?.path ?? config.csvOutputPath,
        e.osError?.message ?? e.message,
      );
    } catch (e) {
      return CsvWriteResult.failure(file?.path ?? config.csvOutputPath, '$e');
    }
  }

  /// Absolute directory every per-model log is written to — the app documents
  /// directory plus any directory part of `csv_logging.output_path`. Exposed
  /// so the Settings screen can show and open it.
  Future<Directory> logDirectory(AppConfig config) async {
    final appDir = await getApplicationDocumentsDirectory();
    return Directory(
      p.normalize(p.join(appDir.path, p.dirname(config.csvOutputPath))),
    );
  }

  Future<File> _resolveFile(
    String modelPath,
    AppConfig config,
    String? modelDisplayName,
  ) async {
    final appDir = await getApplicationDocumentsDirectory();
    final file = File(
      p.join(
        appDir.path,
        logFileNameFor(
          modelPath,
          config.csvOutputPath,
          displayName: modelDisplayName,
        ),
      ),
    );
    await file.parent.create(recursive: true);
    return file;
  }

  /// File-name stem identifying a model: its display name once the user has
  /// given it one, otherwise its file name, reduced to a safe slug.
  ///
  /// Renaming a model therefore starts a new log file rather than rewriting
  /// the old one; files written under the previous name are left untouched.
  static String modelSlug(String modelPath, {String? displayName}) {
    final name = displayName?.trim();
    return _slug(
      name != null && name.isNotEmpty
          ? name
          : p.basenameWithoutExtension(modelPath),
    );
  }

  /// Log file name for [modelPath], derived from the configured
  /// `csv_logging.output_path` ([configuredPath]).
  ///
  /// Every model gets its own file — `sessions.csv` plus a model
  /// `Dengue orange.pkcls` becomes `dengue_orange_sessions.csv`, or
  /// `dengue_pediatric_sessions.csv` once it has been renamed "Dengue
  /// Pediatric" — because the header is built from the model's domain.
  /// Sharing one file across models would append rows under a header
  /// describing entirely different columns.
  ///
  /// Any directory part of [configuredPath] is preserved. A [modelPath] with
  /// no usable name falls back to [configuredPath] unchanged.
  static String logFileNameFor(
    String modelPath,
    String configuredPath, {
    String? displayName,
  }) {
    final slug = modelSlug(modelPath, displayName: displayName);
    if (slug.isEmpty) return configuredPath;

    final stem = p.basenameWithoutExtension(configuredPath);
    final ext = p.extension(configuredPath);
    final name = stem.isEmpty ? '$slug$ext' : '${slug}_$stem$ext';

    final dir = p.dirname(configuredPath);
    return dir == '.' ? name : p.join(dir, name);
  }

  /// Whether [fileName] (a bare file name, no directory) is one of the
  /// per-model logs [logFileNameFor] produces for [configuredPath].
  ///
  /// That is `<slug>_<stem><ext>` for a named model, plus the bare
  /// `<stem><ext>` that a model with no usable name falls back to. Compared
  /// case-insensitively because the log folder lives on a Windows file system
  /// as often as not, and it keeps unrelated files the user dropped in the
  /// folder out of the count.
  static bool isModelLogFileName(String fileName, String configuredPath) {
    final target = p.basename(configuredPath).toLowerCase();
    final name = fileName.toLowerCase();
    if (name == target) return true;

    final stem = p.basenameWithoutExtension(target);
    if (stem.isEmpty) return false;
    return name.endsWith('_$stem${p.extension(target)}');
  }

  /// Lowercases [value] and reduces it to `[a-z0-9_]` so it is safe as a file
  /// name component on every platform.
  static String _slug(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }

  static String _line(List<String> cells) =>
      '${_converter.convert([cells])}\r\n';

  /// Puts the cells of [row] in the order of the columns [file] already has.
  ///
  /// Versions before 1.2.0 could be configured to leave the probabilities,
  /// the diagnosis or the notes out of a log. Such a file gets the missing
  /// columns added at the end of its header; its rows are left untouched, and
  /// read as having nothing in them. The first [fixed] columns are the model's
  /// own: a file in which those differ is not one this can sort out.
  Future<List<String>> _alignToHeader(
    File file, {
    required List<String> columns,
    required List<String> row,
    required int fixed,
  }) async {
    final line = await file
        .openRead()
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .first;
    final header = const CsvToListConverter(shouldParseNumbers: false)
        .convert(line)
        .expand((cells) => cells.map((c) => '$c'.trim()))
        .toList();
    if (listEquals(header, columns) ||
        header.length < fixed ||
        !listEquals(header.sublist(0, fixed), columns.sublist(0, fixed))) {
      return row;
    }

    final cells = Map.fromIterables(columns.skip(fixed), row.skip(fixed));
    final existing = header.skip(fixed).toSet();
    final missing = [
      for (final column in cells.keys)
        if (!existing.contains(column)) column,
    ];
    if (missing.isNotEmpty) await _replaceHeader(file, [...header, ...missing]);
    return [
      ...row.take(fixed),
      for (final column in header.skip(fixed)) cells[column] ?? '',
      for (final column in missing) cells[column]!,
    ];
  }

  /// Puts [columns] in place of the first line of [file], keeping everything
  /// after it byte for byte.
  Future<void> _replaceHeader(File file, List<String> columns) async {
    final bytes = await file.readAsBytes();
    final end = bytes.indexOf(0x0A);
    // Moved into place in one go, so the log is never half-written.
    final temp = File('${file.path}.tmp');
    try {
      await temp.writeAsBytes(
        [...utf8.encode(_line(columns)), if (end >= 0) ...bytes.skip(end + 1)],
        flush: true,
      );
      await temp.rename(file.path);
    } catch (_) {
      if (await temp.exists()) await temp.delete();
      rethrow;
    }
  }

  List<String> _buildHeader(
    List<String> featureNames,
    List<String> classLabels,
  ) {
    return [
      'timestamp',
      ...featureNames,
      'predicted_class',
      ...classLabels.map((label) => 'prob_$label'),
      'doctor_diagnosis',
      'notes',
    ];
  }

  List<String> _buildRow(
    SessionRecord record,
    List<String> featureNames,
    List<String> classLabels,
    AppConfig config,
  ) {
    return [
      formatTimestamp(record.timestamp, config.csvTimestampFormat),
      ...featureNames.map((name) => record.inputs[name]?.toString() ?? ''),
      record.predictedClass,
      ...classLabels.map(
        // Two decimals is all a reader acts on, and it keeps the column
        // narrow enough to scan in a spreadsheet.
        (label) => record.probabilities[label]?.toStringAsFixed(2) ?? '',
      ),
      record.doctorDiagnosis ?? '',
      record.notes ?? '',
    ];
  }

  /// Minimal strftime-style formatter supporting the tokens used by
  /// `csv_logging.timestamp_format` (%Y %m %d %H %M %S).
  static String formatTimestamp(DateTime timestamp, String format) {
    String two(int n) => n.toString().padLeft(2, '0');
    return format
        .replaceAll('%Y', timestamp.year.toString().padLeft(4, '0'))
        .replaceAll('%m', two(timestamp.month))
        .replaceAll('%d', two(timestamp.day))
        .replaceAll('%H', two(timestamp.hour))
        .replaceAll('%M', two(timestamp.minute))
        .replaceAll('%S', two(timestamp.second));
  }
}
