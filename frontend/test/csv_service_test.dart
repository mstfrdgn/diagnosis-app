import 'package:diagnostic_app/services/csv_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('CsvService.logFileNameFor', () {
    test('derives a per-model name from the configured output path', () {
      expect(
        CsvService.logFileNameFor(r'C:\models\dengue_model.pkcls',
            'sessions.csv'),
        'dengue_model_sessions.csv',
      );
    });

    test('slugifies spaces and punctuation in the model file name', () {
      expect(
        CsvService.logFileNameFor(r'C:\Users\me\Desktop\Dengue orange.pkcls',
            'sessions.csv'),
        'dengue_orange_sessions.csv',
      );
    });

    test('gives different models different files', () {
      final a = CsvService.logFileNameFor('heart_risk_model.pkcls',
          'sessions.csv');
      final b = CsvService.logFileNameFor('Dengue orange.pkcls',
          'sessions.csv');
      expect(a, isNot(b));
    });

    test('preserves a directory part of the configured path', () {
      expect(
        CsvService.logFileNameFor('dengue_model.pkcls', r'logs/sessions.csv'),
        p.join('logs', 'dengue_model_sessions.csv'),
      );
    });

    test('falls back to the configured path when no model is loaded', () {
      expect(CsvService.logFileNameFor('', 'sessions.csv'), 'sessions.csv');
    });
  });
}
