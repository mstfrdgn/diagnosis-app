import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart' as xlsx;
import 'package:path/path.dart' as p;

import '../config/app_config.dart';
import '../models/model_domain.dart';
import '../models/orange_variable.dart';
import 'api_service.dart';
import 'batch_run_log.dart';
import 'csv_service.dart';

/// Thrown when the chosen file does not carry a column for every feature the
/// model needs, so no rows are sent to `/predict` at all.
class BatchColumnMismatchException implements Exception {
  const BatchColumnMismatchException({
    required this.missing,
    required this.found,
  });

  /// Feature variables the model expects but the file does not provide.
  final List<String> missing;

  /// Column names the file actually has, for the error message.
  final List<String> found;

  @override
  String toString() =>
      'The CSV is missing ${missing.length} required column(s): '
      '${missing.join(', ')}';
}

/// Thrown for problems with the file itself (unreadable, empty, no data rows).
class BatchFileException implements Exception {
  const BatchFileException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Outcome of a completed batch run.
class BatchPredictionResult {
  const BatchPredictionResult({
    required this.rowCount,
    required this.failureCount,
    required this.outputPath,
  });

  /// Data rows read from the input file (successes plus failures).
  final int rowCount;

  /// Rows whose `/predict` call failed; they are written out with an empty
  /// prediction rather than dropped, so the output lines up with the input.
  final int failureCount;

  final String outputPath;

  int get successCount => rowCount - failureCount;
}

/// Runs every row of a user-supplied table through `/predict` and writes the
/// predictions back out as a new CSV next to the session logs. The input may
/// be a `.csv` or an `.xlsx` workbook; only the parsing differs.
///
/// Rows are sent one at a time: the backend holds a single loaded model and
/// `/predict` takes one case, and a batch is small enough (hundreds of rows)
/// that the round-trips cost less than a bulk endpoint would cost to build.
class BatchPredictionService {
  const BatchPredictionService(this._api);

  final ApiService _api;

  static const _converter = ListToCsvConverter();

  /// Reads [inputPath], predicts each row, and writes the results file.
  ///
  /// [onProgress] is called with `(rowsDone, totalRows)` after each row so
  /// the caller can drive a progress indicator.
  Future<BatchPredictionResult> run({
    required String inputPath,
    required ModelDomain domain,
    required String modelPath,
    required AppConfig config,
    String? modelDisplayName,
    void Function(int done, int total)? onProgress,
  }) async {
    final rows = await readRows(inputPath);
    if (rows.isEmpty) throw const BatchFileException('That file is empty.');

    final header = rows.first.map((cell) => cell.toString().trim()).toList();
    final dataRows = rows.skip(1).where(_isNotBlank).toList();
    if (dataRows.isEmpty) {
      throw const BatchFileException(
        'That file has a header row but no data rows.',
      );
    }

    final missing = missingColumns(header, domain);
    if (missing.isNotEmpty) {
      throw BatchColumnMismatchException(missing: missing, found: header);
    }

    final columnIndex = {
      for (var i = 0; i < header.length; i++) header[i]: i,
    };
    final featureNames = requiredColumns(domain);

    final predictions = <String>[];
    final probabilities = <Map<String, double>>[];
    var failures = 0;
    for (final row in dataRows) {
      final values = <String, dynamic>{};
      for (final name in featureNames) {
        final cell = _cell(row, columnIndex[name]!);
        // An empty cell is a missing value; the backend treats an absent key
        // as unknown and lets Orange impute it.
        if (cell.isNotEmpty) values[name] = cell;
      }
      try {
        final result = await _api.predict(values);
        predictions.add(result.predictedClass);
        probabilities.add(result.probabilities);
      } catch (_) {
        failures++;
        predictions.add('');
        probabilities.add(const {});
      }
      onProgress?.call(predictions.length, dataRows.length);
    }

    final classLabels = domain.classVar.values ??
        probabilities
            .firstWhere((probs) => probs.isNotEmpty, orElse: () => const {})
            .keys
            .toList();

    final directory = await const CsvService().logDirectory(config);
    await directory.create(recursive: true);
    final slug = BatchRunLog.slugFor(modelPath, displayName: modelDisplayName);
    final finishedAt = DateTime.now();
    final outputFile = File(
      p.join(directory.path, BatchRunLog.resultFileNameFor(slug, finishedAt)),
    );
    await outputFile.writeAsString(
      _buildCsv(
        header: header,
        dataRows: dataRows,
        predictions: predictions,
        probabilities: probabilities,
        classLabels: classLabels,
      ),
    );

    // The result file is what matters; losing the index entry only costs
    // the Sessions screen the input file's name, so it must not fail a run
    // whose predictions are already safely written.
    try {
      await const BatchRunLog().append(
        directory,
        slug,
        BatchRunRecord(
          timestamp: finishedAt,
          inputFileName: p.basename(inputPath),
          rowCount: dataRows.length,
          failureCount: failures,
          resultFileName: p.basename(outputFile.path),
        ),
      );
    } on FileSystemException {
      // See above.
    }

    return BatchPredictionResult(
      rowCount: dataRows.length,
      failureCount: failures,
      outputPath: outputFile.path,
    );
  }

  // ── column matching ────────────────────────────────────────────────────

  /// Columns the input file must provide: every feature the data-entry form
  /// would ask for. String variables are excluded for the same reason the
  /// Configuration Screen skips them — Orange never feeds them to the model.
  static List<String> requiredColumns(ModelDomain domain) => domain.features
      .where((feature) => feature.type != VariableType.string)
      .map((feature) => feature.name)
      .toList();

  /// Required columns [header] does not contain, in the model's own order.
  /// Comparison is exact: Orange variable names are case-sensitive, and
  /// silently accepting a near-match would put values in the wrong column.
  static List<String> missingColumns(List<String> header, ModelDomain domain) {
    final present = header.toSet();
    return requiredColumns(domain)
        .where((name) => !present.contains(name))
        .toList();
  }

  // ── output ─────────────────────────────────────────────────────────────

  /// `{model}_batch_{timestamp}.csv` in the session-log directory, so batch
  /// results sit alongside the per-model logs the user already knows about.
  static String outputFileNameFor(
    String modelPath,
    DateTime at, {
    String? displayName,
  }) =>
      BatchRunLog.resultFileNameFor(
        BatchRunLog.slugFor(modelPath, displayName: displayName),
        at,
      );

  String _buildCsv({
    required List<String> header,
    required List<List<dynamic>> dataRows,
    required List<String> predictions,
    required List<Map<String, double>> probabilities,
    required List<String> classLabels,
  }) {
    // Only append the evaluation columns the input does not already have, so
    // re-running a batch over its own output cannot duplicate them.
    final existing = header.toSet();
    final extraColumns = [
      for (final name in ['doctor_diagnosis', 'notes'])
        if (!existing.contains(name)) name,
    ];

    final buffer = StringBuffer();
    buffer.write(
      '${_converter.convert([
            [
              ...header,
              'predicted_class',
              ...classLabels.map((label) => 'prob_$label'),
              ...extraColumns,
            ],
          ])}\r\n',
    );
    for (var i = 0; i < dataRows.length; i++) {
      final probs = probabilities[i];
      buffer.write(
        '${_converter.convert([
              [
                // Pad short rows so every line has the same column count.
                for (var c = 0; c < header.length; c++) _cell(dataRows[i], c),
                predictions[i],
                // Rounded to two decimals, matching the session log.
                ...classLabels
                    .map((label) => probs[label]?.toStringAsFixed(2) ?? ''),
                // doctor_diagnosis / notes are the doctor's to fill in later.
                ...extraColumns.map((_) => ''),
              ],
            ])}\r\n',
      );
    }
    return buffer.toString();
  }

  // ── reading ────────────────────────────────────────────────────────────

  /// True when [path] should be read as a spreadsheet rather than as text.
  static bool isSpreadsheet(String path) =>
      p.extension(path).toLowerCase() == '.xlsx';

  /// Reads [path] into rows of cells — header first — picking the parser
  /// from the file extension. Everything downstream (column matching,
  /// prediction, output) works on these rows and never learns which format
  /// they came from.
  static Future<List<List<dynamic>>> readRows(String path) async {
    if (isSpreadsheet(path)) return _readXlsx(path);
    return _parseCsv(await _readCsvText(path));
  }

  /// Reads the first sheet of an `.xlsx` workbook. Cell values are flattened
  /// to strings the same way CSV cells arrive, so a number typed into Excel
  /// and the same number typed into a CSV reach the model identically.
  static Future<List<List<dynamic>>> _readXlsx(String path) async {
    final Uint8List bytes;
    try {
      bytes = await File(path).readAsBytes();
    } on FileSystemException catch (e) {
      throw BatchFileException(
        'Could not read ${p.basename(path)} — ${e.osError?.message ?? e.message}.',
      );
    }

    final xlsx.Excel workbook;
    try {
      workbook = xlsx.Excel.decodeBytes(_normalizeWorkbookRels(bytes));
    } catch (_) {
      throw BatchFileException(
        'Could not open ${p.basename(path)} as an Excel workbook. '
        'If it was saved in the older .xls format, re-save it as .xlsx.',
      );
    }

    final sheetName = workbook.tables.keys.isEmpty
        ? null
        : workbook.tables.keys.first;
    final sheet = sheetName == null ? null : workbook.tables[sheetName];
    if (sheet == null) {
      throw const BatchFileException('That workbook has no sheets.');
    }
    return [
      for (final row in sheet.rows)
        [for (final cell in row) cell?.value?.toString().trim() ?? ''],
    ];
  }

  /// Rewrites package-absolute relationship targets in the workbook's rels
  /// to the relative form.
  ///
  /// openpyxl — and so pandas' `to_excel` — writes worksheet targets as
  /// `/xl/worksheets/sheet1.xml`. That is legal OPC, but the `excel` package
  /// resolves every target as relative to `xl/`, so it looks for
  /// `xl//xl/worksheets/sheet1.xml`, finds nothing, and dies on a null check.
  /// Excel and LibreOffice write the relative form, which is why their files
  /// open fine; normalising here means a workbook exported from a Python
  /// pipeline opens too.
  ///
  /// Workbooks that are already relative are returned untouched, so the
  /// common case never pays for the re-zip.
  static Uint8List _normalizeWorkbookRels(Uint8List bytes) {
    const relsPath = 'xl/_rels/workbook.xml.rels';
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      // Not a readable zip; let the excel package report it as it sees fit.
      return bytes;
    }

    final rels = archive.findFile(relsPath);
    if (rels == null) return bytes;
    final String text;
    try {
      text = utf8.decode(rels.content as List<int>);
    } catch (_) {
      return bytes;
    }
    if (!text.contains('Target="/')) return bytes;

    final fixed = utf8.encode(
      text.replaceAll('Target="/xl/', 'Target="').replaceAll(
            'Target="/',
            'Target="',
          ),
    );
    final rebuilt = Archive();
    for (final file in archive.files) {
      if (!file.isFile || file.name == relsPath) continue;
      final content = file.content as List<int>;
      rebuilt.addFile(ArchiveFile(file.name, content.length, content));
    }
    rebuilt.addFile(ArchiveFile(relsPath, fixed.length, fixed));

    final encoded = ZipEncoder().encode(rebuilt);
    return encoded == null ? bytes : Uint8List.fromList(encoded);
  }

  static Future<String> _readCsvText(String path) async {
    final file = File(path);
    try {
      // Excel prefixes its UTF-8 exports with a byte order mark, which would
      // otherwise glue itself to the first column name and fail the match.
      return _stripBom(await file.readAsString());
    } on FileSystemException catch (e) {
      throw BatchFileException(
        'Could not read ${p.basename(path)} — ${e.osError?.message ?? e.message}.',
      );
    } on FormatException {
      // Not UTF-8 (Excel on Windows still writes ANSI); latin1 decodes any
      // byte, so the file at least opens and the ASCII columns line up.
      return _stripBom(latin1.decode(await file.readAsBytes()));
    }
  }

  /// Drops a leading byte order mark, whether the file decoded as UTF-8
  /// (a single `﻿`) or fell back to latin1 (its three raw bytes).
  static String _stripBom(String content) {
    if (content.startsWith('﻿')) return content.substring(1);
    if (content.startsWith('ï»¿')) return content.substring(3);
    return content;
  }

  static List<List<dynamic>> _parseCsv(String content) {
    return CsvToListConverter(
      fieldDelimiter: _detectDelimiter(content),
      eol: '\n',
      shouldParseNumbers: false,
    ).convert(content.replaceAll('\r\n', '\n'));
  }

  /// Picks between `,` and `;` by which one the header line uses more —
  /// spreadsheets in several European locales export semicolons.
  static String _detectDelimiter(String content) {
    final firstLine = content.split('\n').first;
    final semicolons = ';'.allMatches(firstLine).length;
    final commas = ','.allMatches(firstLine).length;
    return semicolons > commas ? ';' : ',';
  }

  static bool _isNotBlank(List<dynamic> row) =>
      row.any((cell) => cell != null && cell.toString().trim().isNotEmpty);

  static String _cell(List<dynamic> row, int index) {
    if (index >= row.length) return '';
    return row[index]?.toString().trim() ?? '';
  }
}
