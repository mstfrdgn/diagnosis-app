import 'dart:io';

import 'package:csv/csv.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../config/app_config.dart';
import '../models/model_domain.dart';
import '../models/session_record.dart';

/// Appends [SessionRecord]s to the CSV log configured by
/// `config.csv_logging`. The header (and its column set) is written once,
/// derived from [domain] so it stays stable across appends regardless of
/// which fields a particular session happened to fill in.
class CsvService {
  const CsvService();

  static const _converter = ListToCsvConverter();

  Future<void> appendRecord(
    SessionRecord record, {
    required ModelDomain domain,
    required AppConfig config,
  }) async {
    final file = await _resolveFile(config);
    final featureNames = domain.features.map((f) => f.name).toList();
    final classLabels =
        domain.classVar.values ?? record.probabilities.keys.toList();

    final needsHeader = !await file.exists() || await file.length() == 0;

    final sink = file.openWrite(mode: FileMode.append);
    try {
      if (needsHeader) {
        sink.write(
          '${_converter.convert([
                _buildHeader(featureNames, classLabels, config),
              ])}\r\n',
        );
      }
      sink.write(
        '${_converter.convert([
              _buildRow(record, featureNames, classLabels, config),
            ])}\r\n',
      );
    } finally {
      await sink.close();
    }
  }

  Future<File> _resolveFile(AppConfig config) async {
    final appDir = await getApplicationDocumentsDirectory();
    final file = File(p.join(appDir.path, config.csvOutputPath));
    await file.parent.create(recursive: true);
    return file;
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
          (label) => record.probabilities[label]?.toString() ?? '',
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
