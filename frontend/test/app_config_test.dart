import 'dart:io';

import 'package:diagnostic_app/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

AppConfig parse(String yaml) => AppConfig.fromYaml(loadYaml(yaml) as Map);

void main() {
  group('AppConfig.fromYaml', () {
    for (final version in ['1.0.0', '1.1.0']) {
      test('reads a file from $version, ignoring the keys since removed', () {
        final config = parse(
          File('test/fixtures/app_config_$version.yaml').readAsStringSync(),
        );
        expect(config.appTitle, 'Medical Diagnosis Assistant');
        expect(config.backendFixedPort, isNull);
        expect(config.evaluationDialogFieldOrder, ['doctor_diagnosis', 'notes']);
        expect(config.evaluationDialogIncludeUncertainOption, isTrue);
        expect(config.csvOutputPath, 'sessions.csv');
      });
    }

    for (final path in [
      '../config/app_config.yaml',
      'assets/config/app_config.yaml',
    ]) {
      test('$path holds the defaults and no removed key', () {
        final text = File(path).readAsStringSync();
        final config = parse(text);
        expect(config.evaluationDialogIncludeUncertainOption, isTrue);
        expect(config.csvTimestampFormat, AppConfig.defaults.csvTimestampFormat);
        for (final key in [
          'version',
          'model',
          'missing_value_token',
          'show_tooltips',
          'doctor_diagnosis_options',
          'include_probability',
          'include_doctor_diagnosis',
          'include_notes',
        ]) {
          expect(text, isNot(contains('$key:')));
        }
      });
    }

    test('falls back to the defaults for missing keys and sections', () {
      final config = parse('app:\n  theme: dark\nform:\n');
      expect(config.appTheme, 'dark');
      expect(config.showRangeHints, isTrue);
      expect(config.csvLoggingEnabled, isTrue);
    });

    test('a value of the wrong type costs only that key', () {
      final config = parse('app:\n  theme: dark\n  title: 5\n'
          'form: nonsense\n'
          'evaluation_dialog:\n  enabled: "no"\n  field_order: notes\n'
          'csv_logging:\n  enabled: false\n');
      expect(config.appTheme, 'dark');
      expect(config.appTitle, AppConfig.defaults.appTitle);
      expect(config.showRangeHints, isTrue);
      expect(config.evaluationDialogEnabled, isTrue);
      expect(config.evaluationDialogFieldOrder, ['doctor_diagnosis', 'notes']);
      expect(config.csvLoggingEnabled, isFalse);
    });
  });
}
