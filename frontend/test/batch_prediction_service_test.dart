import 'package:diagnostic_app/models/model_domain.dart';
import 'package:diagnostic_app/models/orange_variable.dart';
import 'package:diagnostic_app/services/batch_prediction_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

final _domain = ModelDomain(
  modelType: 'TreeModel',
  features: const [
    OrangeVariable(
      name: 'Age',
      type: VariableType.continuous,
      role: VariableRole.feature,
    ),
    OrangeVariable(
      name: 'Fever',
      type: VariableType.discrete,
      role: VariableRole.feature,
      values: ['0', '1'],
    ),
    OrangeVariable(
      name: 'PatientNotes',
      type: VariableType.string,
      role: VariableRole.feature,
    ),
  ],
  classVar: const OrangeVariable(
    name: 'Outcome',
    type: VariableType.discrete,
    role: VariableRole.classVar,
    values: ['0', '1'],
  ),
);

void main() {
  group('BatchPredictionService.readRows', () {
    final fixtures = p.join('test', 'fixtures');

    test('reads a CSV into header-first rows', () async {
      final rows =
          await BatchPredictionService.readRows(p.join(fixtures, 'cases.csv'));

      expect(rows.first.map((c) => c.toString()), ['Age', 'Fever', 'extra']);
      expect(rows.length, 3);
      expect(rows[1].map((c) => c.toString()), ['31', '1', 'note one']);
    });

    // Two flavours of the same workbook: `cases.xlsx` carries the
    // package-absolute relationship targets openpyxl/pandas write, and
    // `cases_relative.xlsx` the relative ones Excel and LibreOffice write.
    for (final file in ['cases.xlsx', 'cases_relative.xlsx']) {
      test('reads the first sheet of $file and ignores the others', () async {
        final rows =
            await BatchPredictionService.readRows(p.join(fixtures, file));

        expect(rows.first.map((c) => c.toString()), ['Age', 'Fever', 'extra']);
        expect(rows.length, 3);
        // Numbers typed into Excel must arrive as the strings a CSV gives.
        expect(rows[1].map((c) => c.toString()), ['31', '1', 'note one']);
        expect(rows[2].map((c) => c.toString()), ['57.5', '0', 'note two']);
      });
    }

    test('matches columns identically whichever format was read', () async {
      final fromCsv =
          await BatchPredictionService.readRows(p.join(fixtures, 'cases.csv'));
      final fromXlsx =
          await BatchPredictionService.readRows(p.join(fixtures, 'cases.xlsx'));
      List<String> header(List<List<dynamic>> rows) =>
          rows.first.map((c) => c.toString().trim()).toList();

      expect(
        BatchPredictionService.missingColumns(header(fromXlsx), _domain),
        BatchPredictionService.missingColumns(header(fromCsv), _domain),
      );
      expect(
        BatchPredictionService.missingColumns(header(fromXlsx), _domain),
        isEmpty,
      );
    });

    test('rejects a workbook that is not really an xlsx', () async {
      expect(
        () => BatchPredictionService.readRows(p.join(fixtures, 'broken.xlsx')),
        throwsA(isA<BatchFileException>()),
      );
    });
  });

  group('BatchPredictionService.isSpreadsheet', () {
    test('routes by extension, case-insensitively', () {
      expect(BatchPredictionService.isSpreadsheet(r'C:\cases.xlsx'), isTrue);
      expect(BatchPredictionService.isSpreadsheet(r'C:\cases.XLSX'), isTrue);
      expect(BatchPredictionService.isSpreadsheet(r'C:\cases.csv'), isFalse);
    });
  });

  group('BatchPredictionService.requiredColumns', () {
    test('asks for every feature the form would, but not string metadata', () {
      expect(
        BatchPredictionService.requiredColumns(_domain),
        ['Age', 'Fever'],
      );
    });
  });

  group('BatchPredictionService.missingColumns', () {
    test('is empty when the header covers every feature', () {
      expect(
        BatchPredictionService.missingColumns(
          ['Fever', 'Age', 'extra_notes'],
          _domain,
        ),
        isEmpty,
      );
    });

    test('lists the missing features in the model’s own order', () {
      expect(
        BatchPredictionService.missingColumns(['Weight'], _domain),
        ['Age', 'Fever'],
      );
    });

    test('does not accept a column that differs only in case', () {
      expect(
        BatchPredictionService.missingColumns(['age', 'Fever'], _domain),
        ['Age'],
      );
    });
  });

  group('BatchPredictionService.outputFileNameFor', () {
    final at = DateTime(2026, 8, 14, 9, 5, 3);

    test('names the file after the model and the run time', () {
      expect(
        BatchPredictionService.outputFileNameFor(
          r'C:\models\Dengue orange.pkcls',
          at,
        ),
        'dengue_orange_batch_20260814_090503.csv',
      );
    });

    test('prefers the display name once the model has been renamed', () {
      expect(
        BatchPredictionService.outputFileNameFor(
          r'C:\models\Dengue orange.pkcls',
          at,
          displayName: 'Dengue Pediatric',
        ),
        'dengue_pediatric_batch_20260814_090503.csv',
      );
    });
  });
}
