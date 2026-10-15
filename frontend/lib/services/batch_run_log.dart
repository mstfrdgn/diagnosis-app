import 'dart:io';

import 'package:csv/csv.dart';
import 'package:path/path.dart' as p;

import '../config/app_config.dart';
import '../models/logged_session.dart';
import 'csv_service.dart';

/// What [BatchRunLog.append] records about one finished run.
class BatchRunRecord {
  const BatchRunRecord({
    required this.timestamp,
    required this.inputFileName,
    required this.rowCount,
    required this.failureCount,
    required this.resultFileName,
  });

  final DateTime timestamp;
  final String inputFileName;
  final int rowCount;
  final int failureCount;

  /// Bare file name of the result CSV, which is what the index is keyed on.
  final String resultFileName;
}

/// The rows of one batch result CSV, as read back for the Sessions screen.
class BatchResult {
  const BatchResult({required this.path, required this.rows}) : error = null;

  const BatchResult.failure(this.path, this.error) : rows = const [];

  final String path;

  /// Data rows, in file order — which is the order of the input file.
  final List<BatchResultRow> rows;

  /// Human-readable reason the read failed, or null when it succeeded.
  final String? error;

  bool get succeeded => error == null;

  int get failureCount => rows.where((row) => row.failed).length;

  /// How many rows got each predicted class, most frequent first. Failed rows
  /// are left out; [failureCount] covers them.
  List<MapEntry<String, int>> get classCounts {
    final counts = <String, int>{};
    for (final row in rows) {
      if (row.failed) continue;
      counts[row.predictedClass] = (counts[row.predictedClass] ?? 0) + 1;
    }
    return counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  }
}

/// Keeps track of batch runs so the Sessions screen can list them.
///
/// The result files `{model}_batch_{yyyyMMdd_HHmmss}.csv` are what decide
/// which runs exist: a run shows up for as long as its result file is in the
/// log folder, and one the user deleted simply goes away. What a result file
/// cannot say for itself — chiefly which input file it came from — goes into
/// a per-model index, `{model}_batch_runs.csv`. Result files written before
/// the index existed still show up, just without an input file name.
///
/// None of this touches the per-model session logs, whose format is
/// unchanged.
class BatchRunLog {
  const BatchRunLog();

  static const _converter = ListToCsvConverter();

  static const _indexColumns = [
    'timestamp',
    'input_file',
    'row_count',
    'failure_count',
    'result_file',
  ];

  static const _predictedClassColumn = 'predicted_class';
  static const _probabilityPrefix = 'prob_';

  static final _resultNamePattern = RegExp(
    r'^(.+)_batch_(\d{4})(\d{2})(\d{2})_(\d{2})(\d{2})(\d{2})\.csv$',
    caseSensitive: false,
  );

  // ── naming ─────────────────────────────────────────────────────────────

  /// File-name stem for a model's batch files. Same as the session log's,
  /// except that a model with no usable name falls back to `model` rather
  /// than to the bare configured file name.
  static String slugFor(String modelPath, {String? displayName}) {
    final slug = CsvService.modelSlug(modelPath, displayName: displayName);
    return slug.isEmpty ? 'model' : slug;
  }

  static String resultFileNameFor(String slug, DateTime at) =>
      '${slug}_batch_${_fileStamp(at)}.csv';

  static String indexFileNameFor(String slug) => '${slug}_batch_runs.csv';

  /// The model slug and run time encoded in a result file name, or null when
  /// [fileName] is not one.
  static (String, DateTime)? parseResultFileName(String fileName) {
    final match = _resultNamePattern.firstMatch(fileName);
    if (match == null) return null;
    final parts = [for (var i = 2; i <= 7; i++) int.parse(match.group(i)!)];
    final [year, month, day, hour, minute, second] = parts;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    if (hour > 23 || minute > 59 || second > 59) return null;
    return (
      match.group(1)!.toLowerCase(),
      DateTime(year, month, day, hour, minute, second),
    );
  }

  static bool isResultFileName(String fileName) =>
      parseResultFileName(fileName) != null;

  static bool isIndexFileName(String fileName) =>
      fileName.toLowerCase().endsWith('_batch_runs.csv');

  // ── writing ────────────────────────────────────────────────────────────

  /// Adds [record] to [slug]'s index in [directory], writing the header
  /// first if the index is new.
  Future<void> append(
    Directory directory,
    String slug,
    BatchRunRecord record,
  ) async {
    final file = File(p.join(directory.path, indexFileNameFor(slug)));
    final needsHeader = !await file.exists() || await file.length() == 0;
    final buffer = StringBuffer();
    if (needsHeader) {
      buffer.write('${_converter.convert([_indexColumns])}\r\n');
    }
    buffer.write(
      '${_converter.convert([
            [
              CsvService.formatTimestamp(record.timestamp, '%Y-%m-%d %H:%M:%S'),
              record.inputFileName,
              '${record.rowCount}',
              '${record.failureCount}',
              record.resultFileName,
            ],
          ])}\r\n',
    );
    await file.writeAsString(buffer.toString(), mode: FileMode.append);
  }

  // ── reading ────────────────────────────────────────────────────────────

  /// Every batch run of [slug] whose result file is in [directory], newest
  /// first.
  ///
  /// A missing folder or index is normal and yields what can be found
  /// without it. A result file that cannot be read is still listed, with
  /// unknown counts, so the user can see it is there.
  Future<List<LoggedBatchRun>> loadRuns(
    Directory directory,
    String slug, {
    required AppConfig config,
  }) async {
    if (!await directory.exists()) return const [];

    final index = await _readIndex(
      File(p.join(directory.path, indexFileNameFor(slug))),
    );

    final runs = <LoggedBatchRun>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      final parsed = parseResultFileName(name);
      if (parsed == null || parsed.$1 != slug.toLowerCase()) continue;
      final (_, timestamp) = parsed;

      final entry = index[name.toLowerCase()];
      var rowCount = entry?.rowCount;
      var failureCount = entry?.failureCount;
      if (rowCount == null || failureCount == null) {
        // Written before the index existed (or the index was edited by
        // hand): count the rows from the result file itself.
        final result = await loadResult(entity.path);
        if (result.succeeded) {
          rowCount = result.rows.length;
          failureCount = result.failureCount;
        }
      }

      runs.add(
        LoggedBatchRun(
          timestamp: timestamp,
          rawTimestamp:
              CsvService.formatTimestamp(timestamp, config.csvTimestampFormat),
          resultPath: entity.path,
          inputFileName: entry?.inputFileName,
          rowCount: rowCount,
          failureCount: failureCount,
        ),
      );
    }
    runs.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return runs;
  }

  /// Reads the result CSV at [path]. Never throws.
  Future<BatchResult> loadResult(String path) async {
    try {
      return parseResult(await File(path).readAsString(), path: path);
    } on FileSystemException catch (e) {
      return BatchResult.failure(path, e.osError?.message ?? e.message);
    } catch (e) {
      return BatchResult.failure(path, '$e');
    }
  }

  /// Parses the contents of a batch result CSV.
  ///
  /// The input file's own columns come first and the prediction columns are
  /// appended after them. A batch re-run over an earlier result therefore
  /// carries `predicted_class` twice; the last one is this run's.
  BatchResult parseResult(String contents, {required String path}) {
    final rows = const CsvToListConverter(
      shouldParseNumbers: false,
      eol: '\n',
    ).convert(contents.replaceAll('\r\n', '\n'));
    if (rows.isEmpty) return BatchResult(path: path, rows: const []);

    final header = rows.first.map((c) => '$c'.trim()).toList();
    final predictedIndex = header.lastIndexOf(_predictedClassColumn);
    if (predictedIndex < 0) {
      return BatchResult.failure(
        path,
        'Unrecognised batch result: no "$_predictedClassColumn" column.',
      );
    }
    final probabilityColumns = <int, String>{
      for (var i = predictedIndex + 1; i < header.length; i++)
        if (header[i].startsWith(_probabilityPrefix))
          i: header[i].substring(_probabilityPrefix.length),
    };

    final results = <BatchResultRow>[];
    for (final row in rows.skip(1)) {
      if (row.every((c) => '$c'.trim().isEmpty)) continue;
      String cell(int index) =>
          index < row.length ? '${row[index]}'.trim() : '';
      results.add(
        BatchResultRow(
          inputs: {
            for (var i = 0; i < predictedIndex; i++) header[i]: cell(i),
          },
          predictedClass: cell(predictedIndex),
          probabilities: {
            for (final entry in probabilityColumns.entries)
              if (double.tryParse(cell(entry.key)) case final value?)
                entry.value: value,
          },
        ),
      );
    }
    return BatchResult(path: path, rows: results);
  }

  /// Index rows keyed by lower-cased result file name. A missing or
  /// unreadable index is treated as empty: the result files are still found,
  /// they just lack an input file name.
  Future<Map<String, BatchIndexEntry>> _readIndex(File file) async {
    try {
      if (!await file.exists()) return const {};
      return parseIndex(await file.readAsString());
    } catch (_) {
      return const {};
    }
  }

  /// Parses the contents of a batch index. Split out from [loadRuns] for
  /// testing.
  Map<String, BatchIndexEntry> parseIndex(String contents) {
    final rows = const CsvToListConverter(
      shouldParseNumbers: false,
      eol: '\n',
    ).convert(contents.replaceAll('\r\n', '\n'));
    if (rows.isEmpty) return const {};

    final header = rows.first.map((c) => '$c'.trim()).toList();
    final inputIndex = header.indexOf('input_file');
    final rowIndex = header.indexOf('row_count');
    final failureIndex = header.indexOf('failure_count');
    final resultIndex = header.indexOf('result_file');
    if (resultIndex < 0) return const {};

    final entries = <String, BatchIndexEntry>{};
    for (final row in rows.skip(1)) {
      String cell(int index) =>
          index >= 0 && index < row.length ? '${row[index]}'.trim() : '';
      final result = cell(resultIndex);
      if (result.isEmpty) continue;
      final input = cell(inputIndex);
      entries[result.toLowerCase()] = BatchIndexEntry(
        inputFileName: input.isEmpty ? null : input,
        rowCount: int.tryParse(cell(rowIndex)),
        failureCount: int.tryParse(cell(failureIndex)),
      );
    }
    return entries;
  }

  static String _fileStamp(DateTime at) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${at.year}${two(at.month)}${two(at.day)}'
        '_${two(at.hour)}${two(at.minute)}${two(at.second)}';
  }
}

/// What the index knows about one result file.
class BatchIndexEntry {
  const BatchIndexEntry({
    required this.inputFileName,
    required this.rowCount,
    required this.failureCount,
  });

  final String? inputFileName;
  final int? rowCount;
  final int? failureCount;
}
