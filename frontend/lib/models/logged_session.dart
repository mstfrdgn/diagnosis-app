/// One row read back from a model's CSV session log.
///
/// The write-side counterpart is [SessionRecord]; the two are kept apart on
/// purpose. A record being written is always well-formed, whereas a row read
/// from a file on disk may have been edited by hand, written by an older
/// version of the app, or carry a timestamp in a format the current config no
/// longer describes — so everything here tolerates missing or unparseable
/// values instead of asserting them away.
class LoggedSession {
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
