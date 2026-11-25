class AppConfig {
  const AppConfig({
    this.appTitle = 'Medical Diagnosis Assistant',
    this.appTheme = 'light',
    this.backendHost = '127.0.0.1',
    this.backendFixedPort,
    this.backendStartupTimeoutSeconds = 15,
    this.showRangeHints = true,
    this.resultDisplayShowProbability = true,
    this.resultDisplayProbabilityFormat = 'percent',
    this.evaluationDialogEnabled = true,
    this.evaluationDialogFieldOrder = const ['doctor_diagnosis', 'notes'],
    this.evaluationDialogIncludeUncertainOption = true,
    this.evaluationDialogAutoOpenAfterResult = true,
    this.csvLoggingEnabled = true,
    this.csvOutputPath = 'sessions.csv',
    this.csvTimestampFormat = '%Y-%m-%d %H:%M:%S',
  });

  final String appTitle;
  final String appTheme;
  final String backendHost;

  /// Port the backend must use; null (the default) lets the OS pick a free
  /// one on every start. Read from `backend.fixed_port`: the `backend.port`
  /// key that config files from older versions carry is ignored, because
  /// they all hold the old default 8765, which nobody chose.
  final int? backendFixedPort;
  final int backendStartupTimeoutSeconds;
  final bool showRangeHints;

  final bool resultDisplayShowProbability;
  final String resultDisplayProbabilityFormat;

  final bool evaluationDialogEnabled;
  final List<String> evaluationDialogFieldOrder;

  /// Whether "Uncertain" is offered as a doctor diagnosis after the model's
  /// own classes.
  final bool evaluationDialogIncludeUncertainOption;
  final bool evaluationDialogAutoOpenAfterResult;

  final bool csvLoggingEnabled;
  final String csvOutputPath;
  final String csvTimestampFormat;

  static const AppConfig defaults = AppConfig();

  /// Reads the keys this version knows and ignores all others, so a file from
  /// an older version can be read as it is. A key that is missing, or holds a
  /// value of the wrong type, falls back to its own default only.
  factory AppConfig.fromYaml(Map<dynamic, dynamic> yaml) {
    Map section(String name) => switch (yaml[name]) {
          final Map values => values,
          _ => const {},
        };
    T read<T>(Map values, String key, T fallback) {
      final value = values[key];
      return value is T ? value : fallback;
    }

    final app = section('app');
    final backend = section('backend');
    final form = section('form');
    final resultDisplay = section('result_display');
    final evaluationDialog = section('evaluation_dialog');
    final csvLogging = section('csv_logging');

    return AppConfig(
      appTitle: read(app, 'title', defaults.appTitle),
      appTheme: read(app, 'theme', defaults.appTheme),
      backendHost: read(backend, 'host', defaults.backendHost),
      backendFixedPort: switch (backend['fixed_port']) {
        final int port when port > 0 => port,
        _ => null,
      },
      backendStartupTimeoutSeconds: read(backend, 'startup_timeout_seconds',
          defaults.backendStartupTimeoutSeconds),
      showRangeHints: read(form, 'show_range_hints', defaults.showRangeHints),
      resultDisplayShowProbability: read(resultDisplay, 'show_probability',
          defaults.resultDisplayShowProbability),
      resultDisplayProbabilityFormat: read(resultDisplay, 'probability_format',
          defaults.resultDisplayProbabilityFormat),
      evaluationDialogEnabled:
          read(evaluationDialog, 'enabled', defaults.evaluationDialogEnabled),
      evaluationDialogFieldOrder: switch (evaluationDialog['field_order']) {
        final List fields => fields.whereType<String>().toList(),
        _ => defaults.evaluationDialogFieldOrder,
      },
      evaluationDialogIncludeUncertainOption: read(
          evaluationDialog,
          'include_uncertain_option',
          defaults.evaluationDialogIncludeUncertainOption),
      evaluationDialogAutoOpenAfterResult: read(
          evaluationDialog,
          'auto_open_after_result',
          defaults.evaluationDialogAutoOpenAfterResult),
      csvLoggingEnabled:
          read(csvLogging, 'enabled', defaults.csvLoggingEnabled),
      csvOutputPath: read(csvLogging, 'output_path', defaults.csvOutputPath),
      csvTimestampFormat:
          read(csvLogging, 'timestamp_format', defaults.csvTimestampFormat),
    );
  }
}
