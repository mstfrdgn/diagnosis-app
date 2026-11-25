import 'package:diagnostic_app/config/app_config.dart';
import 'package:diagnostic_app/widgets/evaluation_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const zoo = ['amphibian', 'bird', 'fish', 'mammal'];
  const withoutUncertain =
      AppConfig(evaluationDialogIncludeUncertainOption: false);

  test('the options are the classes of the model, then "Uncertain"', () {
    expect(
      EvaluationDialog.diagnosisOptions(zoo, const AppConfig()),
      [...zoo, 'Uncertain'],
    );
    expect(EvaluationDialog.diagnosisOptions(zoo, withoutUncertain), zoo);
  });

  test('a model with its own "uncertain" class does not get a second one', () {
    const classes = ['yes', 'uncertain'];
    expect(
      EvaluationDialog.diagnosisOptions(classes, const AppConfig()),
      classes,
    );
  });

  testWidgets('the chosen class is returned on save', (tester) async {
    EvaluationResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await EvaluationDialog.show(
              context,
              config: const AppConfig(),
              classValues: zoo,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();

    expect(find.text('Uncertain'), findsWidgets);
    expect(find.text('Positive'), findsNothing);
    await tester.tap(find.text('fish').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(result?.doctorDiagnosis, 'fish');
  });
}
