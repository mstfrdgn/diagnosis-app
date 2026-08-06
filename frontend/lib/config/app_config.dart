class AppConfig {
  const AppConfig({
    this.appTitle = 'Medical Diagnosis Assistant',
    this.appTheme = 'light',
    this.backendHost = '127.0.0.1',
    this.backendPort = 8765,
    this.backendStartupTimeoutSeconds = 15,
    this.defaultModelPath = '',
    this.showRangeHints = true,
    this.resultDisplayShowProbability = true,
    this.resultDisplayProbabilityFormat = 'percent',
    this.evaluationDialogEnabled = true,
    this.evaluationDialogFieldOrder = const ['doctor_diagnosis', 'notes'],
    this.evaluationDialogDoctorDiagnosisOptions = const [
      'Positive',
      'Negative',
      'Uncertain',
    ],
    this.evaluationDialogAutoOpenAfterResult = true,
    this.csvLoggingEnabled = true,
    this.csvOutputPath = 'sessions.csv',
    this.csvTimestampFormat = '%Y-%m-%d %H:%M:%S',
    this.csvIncludeProbability = true,
    this.csvIncludeDoctorDiagnosis = true,
    this.csvIncludeNotes = true,
  });

  final String appTitle;
  final String appTheme;
  final String backendHost;
  final int backendPort;
  final int backendStartupTimeoutSeconds;
  final String defaultModelPath;
  final bool showRangeHints;

  final bool resultDisplayShowProbability;
  final String resultDisplayProbabilityFormat;

  final bool evaluationDialogEnabled;
  final List<String> evaluationDialogFieldOrder;
  final List<String> evaluationDialogDoctorDiagnosisOptions;
  final bool evaluationDialogAutoOpenAfterResult;

  final bool csvLoggingEnabled;
  final String csvOutputPath;
  final String csvTimestampFormat;
  final bool csvIncludeProbability;
  final bool csvIncludeDoctorDiagnosis;
  final bool csvIncludeNotes;

  static const AppConfig defaults = AppConfig();

  factory AppConfig.fromYaml(Map<dynamic, dynamic> yaml) {
    final app = (yaml['app'] as Map?) ?? {};
    final backend = (yaml['backend'] as Map?) ?? {};
    final model = (yaml['model'] as Map?) ?? {};
    final form = (yaml['form'] as Map?) ?? {};
    final resultDisplay = (yaml['result_display'] as Map?) ?? {};
    final evaluationDialog = (yaml['evaluation_dialog'] as Map?) ?? {};
    final csvLogging = (yaml['csv_logging'] as Map?) ?? {};

    const defaultFieldOrder = ['doctor_diagnosis', 'notes'];
    const defaultDiagnosisOptions = ['Positive', 'Negative', 'Uncertain'];

    return AppConfig(
      appTitle: (app['title'] as String?) ?? 'Medical Diagnosis Assistant',
      appTheme: (app['theme'] as String?) ?? 'light',
      backendHost: (backend['host'] as String?) ?? '127.0.0.1',
      backendPort: (backend['port'] as int?) ?? 8765,
      backendStartupTimeoutSeconds:
          (backend['startup_timeout_seconds'] as int?) ?? 15,
      defaultModelPath: (model['default_path'] as String?) ?? '',
      showRangeHints: (form['show_range_hints'] as bool?) ?? true,
      resultDisplayShowProbability:
          (resultDisplay['show_probability'] as bool?) ?? true,
      resultDisplayProbabilityFormat:
          (resultDisplay['probability_format'] as String?) ?? 'percent',
      evaluationDialogEnabled: (evaluationDialog['enabled'] as bool?) ?? true,
      evaluationDialogFieldOrder:
          (evaluationDialog['field_order'] as List?)?.cast<String>() ??
              defaultFieldOrder,
      evaluationDialogDoctorDiagnosisOptions:
          (evaluationDialog['doctor_diagnosis_options'] as List?)
                  ?.cast<String>() ??
              defaultDiagnosisOptions,
      evaluationDialogAutoOpenAfterResult:
          (evaluationDialog['auto_open_after_result'] as bool?) ?? true,
      csvLoggingEnabled: (csvLogging['enabled'] as bool?) ?? true,
      csvOutputPath: (csvLogging['output_path'] as String?) ?? 'sessions.csv',
      csvTimestampFormat:
          (csvLogging['timestamp_format'] as String?) ?? '%Y-%m-%d %H:%M:%S',
      csvIncludeProbability:
          (csvLogging['include_probability'] as bool?) ?? true,
      csvIncludeDoctorDiagnosis:
          (csvLogging['include_doctor_diagnosis'] as bool?) ?? true,
      csvIncludeNotes: (csvLogging['include_notes'] as bool?) ?? true,
    );
  }
}
