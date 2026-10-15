/// One line on the Sessions screen: either a single logged session or a
/// whole batch run. Both are placed on the same timeline, which is all the
/// screen's sorting and date filters need from them.
sealed class SessionLogEntry {
  const SessionLogEntry();

  /// When the entry was recorded, or null when that cannot be told — such a
  /// row only shows up under the "All" filter.
  DateTime? get timestamp;
}

/// One row read back from a model's CSV session log.
///
/// The write-side counterpart is [SessionRecord]; the two are kept apart on
/// purpose. A record being written is always well-formed, whereas a row read
/// from a file on disk may have been edited by hand, written by an older
/// version of the app, or carry a timestamp in a format the current config no
/// longer describes — so everything here tolerates missing or unparseable
/// values instead of asserting them away.
class LoggedSession extends SessionLogEntry {
  const LoggedSession({
    required this.timestamp,
    required this.rawTimestamp,
    required this.inputs,
    required this.predictedClass,
    required this.probabilities,
    required this.doctorDiagnosis,
    required this.notes,
  });

  /// Parsed timestamp, or null when the cell did not match the configured
  /// `csv_logging.timestamp_format`. [rawTimestamp] is then all we can show.
  @override
  final DateTime? timestamp;

  /// The timestamp cell exactly as it appears in the file.
  final String rawTimestamp;

  /// Feature name → value, in the column order of the file's header.
  final Map<String, String> inputs;

  final String predictedClass;

  /// Class label → probability, for the `prob_*` columns that parsed as
  /// numbers. Empty when the log was written with probabilities disabled.
  final Map<String, double> probabilities;

  final String doctorDiagnosis;
  final String notes;

  /// The highest probability in [probabilities], or null when the log carries
  /// none — which is what the Sessions screen shows as "confidence".
  double? get confidence {
    if (probabilities.isEmpty) return null;
    return probabilities.values.reduce((a, b) => a > b ? a : b);
  }
}

/// One batch run, found from its `{model}_batch_{timestamp}.csv` result file.
///
/// The run is shown as a single entry; the per-row predictions stay in
/// [resultPath] and are only read when the entry is expanded.
class LoggedBatchRun extends SessionLogEntry {
  const LoggedBatchRun({
    required this.timestamp,
    required this.rawTimestamp,
    required this.resultPath,
    required this.inputFileName,
    required this.rowCount,
    required this.failureCount,
  });

  /// When the result file was written, taken from its file name — which the
  /// app always stamps in one fixed format, so unlike a session's timestamp
  /// it never fails to parse.
  @override
  final DateTime timestamp;

  /// [timestamp] in the configured `csv_logging.timestamp_format`, so batch
  /// runs read the same as the sessions around them.
  final String rawTimestamp;

  /// Absolute path of the batch result CSV.
  final String resultPath;

  /// Name of the file the rows were read from, or null for a run recorded
  /// before the app kept track of it.
  final String? inputFileName;

  /// Data rows in the run, or null when the result file could not be read.
  final int? rowCount;

  /// Rows whose prediction failed, or null when that is not known.
  final int? failureCount;
}

/// One data row of a batch result CSV.
class BatchResultRow {
  const BatchResultRow({
    required this.inputs,
    required this.predictedClass,
    required this.probabilities,
  });

  /// Every input column of the row, in file order.
  final Map<String, String> inputs;

  /// Empty when the prediction for this row failed.
  final String predictedClass;

  final Map<String, double> probabilities;

  bool get failed => predictedClass.isEmpty;

  /// The highest probability, as for [LoggedSession.confidence].
  double? get confidence {
    if (probabilities.isEmpty) return null;
    return probabilities.values.reduce((a, b) => a > b ? a : b);
  }
}
