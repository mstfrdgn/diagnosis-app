import 'dart:io';

import 'package:csv/csv.dart';
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

      final buffer = StringBuffer();
      if (needsHeader) {
        buffer.write(
          '${_converter.convert([
                _buildHeader(featureNames, classLabels, config),
              ])}\r\n',
        );
      }
      buffer.write(
        '${_converter.convert([
              _buildRow(record, featureNames, classLabels, config),
            ])}\r\n',
      );

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

  /// Lowercases [value] and reduces it to `[a-z0-9_]` so it is safe as a file
  /// name component on every platform.
  static String _slug(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }

  List<String> _buildHeader(
    List<String> featureNames,
    List<String> classLabels,
    AppConfig config,
  ) {
    return [
      'timestamp',
      ...featureNames,
      'predicted_class',
      if (config.csvIncludeProbability)
        ...classLabels.map((label) => 'prob_$label'),
      if (config.csvIncludeDoctorDiagnosis) 'doctor_diagnosis',
      if (config.csvIncludeNotes) 'notes',
    ];
  }

  List<String> _buildRow(
    SessionRecord record,
    List<String> featureNames,
    List<String> classLabels,
    AppConfig config,
  ) {
    return [
      _formatTimestamp(record.timestamp, config.csvTimestampFormat),
      ...featureNames.map((name) => record.inputs[name]?.toString() ?? ''),
      record.predictedClass,
      if (config.csvIncludeProbability)
        ...classLabels.map(
          // Two decimals is all a reader acts on, and it keeps the column
          // narrow enough to scan in a spreadsheet.
          (label) => record.probabilities[label]?.toStringAsFixed(2) ?? '',
        ),
      if (config.csvIncludeDoctorDiagnosis) record.doctorDiagnosis ?? '',
      if (config.csvIncludeNotes) record.notes ?? '',
    ];
  }

  /// Minimal strftime-style formatter supporting the tokens used by
  /// `csv_logging.timestamp_format` (%Y %m %d %H %M %S).
  String _formatTimestamp(DateTime timestamp, String format) {
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
