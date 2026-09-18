import 'dart:io';

import 'package:csv/csv.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../config/app_config.dart';
import '../models/logged_session.dart';
import 'csv_service.dart';

/// Outcome of [SessionLogService.load].
///
/// A log file that does not exist yet is not an error — it is what every
/// model looks like before its first session — so that case comes back as a
/// success with an empty [sessions] list and [exists] false.
class SessionLog {
  const SessionLog({
    required this.path,
    required this.exists,
    required this.featureNames,
    required this.sessions,
    this.error,
  });

  const SessionLog.failure(this.path, this.error)
      : exists = false,
        featureNames = const [],
        sessions = const [];

  /// Absolute path of the log this model writes to.
  final String path;

  /// Whether the file was there. False means "no sessions recorded yet".
  final bool exists;

  /// Feature columns found in the header, in file order.
  final List<String> featureNames;

  /// Rows, newest first.
  final List<LoggedSession> sessions;

  /// Human-readable reason the read failed, or null when it succeeded.
  final String? error;

  bool get succeeded => error == null;
}

/// Reads back the CSV logs [CsvService] writes.
///
/// Columns are taken from the file's own header rather than from the current
/// [AppConfig], because the two can disagree: turning `include_notes` off
/// does not rewrite rows that already have a notes column. The header is the
/// only description of a given file that is guaranteed to match its rows.
class SessionLogService {
  const SessionLogService();

  static const _predictedClassColumn = 'predicted_class';
  static const _timestampColumn = 'timestamp';
  static const _doctorDiagnosisColumn = 'doctor_diagnosis';
  static const _notesColumn = 'notes';
  static const _probabilityPrefix = 'prob_';

  Future<SessionLog> load({
    required String modelPath,
    required AppConfig config,
    String? modelDisplayName,
  }) async {
    String? path;
    try {
      final appDir = await getApplicationDocumentsDirectory();
      path = p.join(
        appDir.path,
        CsvService.logFileNameFor(
          modelPath,
          config.csvOutputPath,
          displayName: modelDisplayName,
        ),
      );
      final file = File(path);
      if (!await file.exists()) {
        return SessionLog(
          path: path,
          exists: false,
          featureNames: const [],
          sessions: const [],
        );
      }
      return parse(await file.readAsString(), path: path, config: config);
    } on FileSystemException catch (e) {
      return SessionLog.failure(
        path ?? config.csvOutputPath,
        e.osError?.message ?? e.message,
      );
    } catch (e) {
      return SessionLog.failure(path ?? config.csvOutputPath, '$e');
    }
  }

  /// Parses raw CSV [contents]. Split out from [load] so the column and
  /// timestamp handling can be tested without touching the file system.
  SessionLog parse(
    String contents, {
    required String path,
    required AppConfig config,
  }) {
    final rows = const CsvToListConverter(
      shouldParseNumbers: false,
      eol: '\n',
    ).convert(contents.replaceAll('\r\n', '\n'));

    // A file with only a header (or nothing at all) has no sessions to show,
    // which reads the same to the user as a file that was never written.
    if (rows.isEmpty) {
      return SessionLog(
        path: path,
        exists: true,
        featureNames: const [],
        sessions: const [],
      );
    }

    final header = rows.first.map((c) => '$c'.trim()).toList();
    final predictedIndex = header.indexOf(_predictedClassColumn);
    if (header.first != _timestampColumn || predictedIndex < 0) {
      return SessionLog.failure(
        path,
        'Unrecognised log format: expected a "$_timestampColumn" column '
        'followed by the model\'s features and "$_predictedClassColumn".',
      );
    }

    // Everything between the timestamp and the prediction is a feature, so a
    // model's own variable names need no separate lookup.
    final featureNames = header.sublist(1, predictedIndex);
    final probabilityColumns = <int, String>{
      for (var i = predictedIndex + 1; i < header.length; i++)
        if (header[i].startsWith(_probabilityPrefix))
          i: header[i].substring(_probabilityPrefix.length),
    };
    final doctorIndex = header.indexOf(_doctorDiagnosisColumn);
    final notesIndex = header.indexOf(_notesColumn);

    final timestampPattern = _TimestampPattern.from(config.csvTimestampFormat);

    final sessions = <LoggedSession>[];
    for (final row in rows.skip(1)) {
      // A short row is a truncated write, not a reason to drop everything
      // after it; pad it out and show what it does have.
      String cell(int index) =>
          index >= 0 && index < row.length ? '${row[index]}'.trim() : '';

      final rawTimestamp = cell(0);
      // Trailing blank line, or a row with nothing in it worth showing.
      if (row.every((c) => '$c'.trim().isEmpty)) continue;

      sessions.add(
        LoggedSession(
          timestamp: timestampPattern.parse(rawTimestamp),
          rawTimestamp: rawTimestamp,
          inputs: {
            for (var i = 0; i < featureNames.length; i++)
              featureNames[i]: cell(i + 1),
          },
          predictedClass: cell(predictedIndex),
          probabilities: {
            for (final entry in probabilityColumns.entries)
              if (double.tryParse(cell(entry.key)) case final value?)
                entry.value: value,
          },
          doctorDiagnosis: cell(doctorIndex),
          notes: cell(notesIndex),
        ),
      );
    }

    // Newest first: the session a user opens this screen to check is almost
    // always the one they just recorded. Rows whose timestamp did not parse
    // cannot be placed among the rest, so they sink to the bottom in file
    // order — returning 0 for them instead would not be a total order, and
    // List.sort is free to shuffle the rest around on the back of it.
    sessions.sort((a, b) {
      final at = a.timestamp;
      final bt = b.timestamp;
      if (at == null) return bt == null ? 0 : 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });

    return SessionLog(
      path: path,
      exists: true,
      featureNames: featureNames,
      sessions: sessions,
    );
  }
}

/// Reads timestamps back in whatever `csv_logging.timestamp_format` wrote
/// them, supporting the same strftime tokens `CsvService` formats with
/// (%Y %m %d %H %M %S).
///
/// `DateTime.parse` is not enough here: the format is user-configurable, so
/// the file may hold `14.09.2026 12:43:07` just as legitimately as an ISO
/// string.
class _TimestampPattern {
  const _TimestampPattern(this._regExp, this._tokens);

  final RegExp? _regExp;
  final List<String> _tokens;

  static final _tokenPattern = RegExp('%[YmdHMS]');
  static const _tokenWidths = {
    '%Y': r'(\d{4})',
    '%m': r'(\d{1,2})',
    '%d': r'(\d{1,2})',
    '%H': r'(\d{1,2})',
    '%M': r'(\d{1,2})',
    '%S': r'(\d{1,2})',
  };

  factory _TimestampPattern.from(String format) {
    final tokens = <String>[];
    final buffer = StringBuffer('^');
    var index = 0;
    for (final match in _tokenPattern.allMatches(format)) {
      buffer.write(RegExp.escape(format.substring(index, match.start)));
      final token = match.group(0)!;
      tokens.add(token);
      buffer.write(_tokenWidths[token]);
      index = match.end;
    }
    buffer
      ..write(RegExp.escape(format.substring(index)))
      ..write(r'$');

    // A format with no recognised token can never identify a date; fall back
    // to leaving every timestamp unparsed rather than matching everything.
    if (tokens.isEmpty) return const _TimestampPattern(null, []);
    return _TimestampPattern(RegExp(buffer.toString()), tokens);
  }

  /// The timestamp in [value], or null when it does not match the format.
  DateTime? parse(String value) {
    final regExp = _regExp;
    if (regExp == null) return null;
    final match = regExp.firstMatch(value.trim());
    if (match == null) return null;

    var year = 1970, month = 1, day = 1, hour = 0, minute = 0, second = 0;
    for (var i = 0; i < _tokens.length; i++) {
      final part = int.tryParse(match.group(i + 1)!);
      if (part == null) return null;
      switch (_tokens[i]) {
        case '%Y':
          year = part;
        case '%m':
          month = part;
        case '%d':
          day = part;
        case '%H':
          hour = part;
        case '%M':
          minute = part;
        case '%S':
          second = part;
      }
    }
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    return DateTime(year, month, day, hour, minute, second);
  }
}
