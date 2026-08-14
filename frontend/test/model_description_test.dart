import 'package:diagnostic_app/models/model_description.dart';
import 'package:diagnostic_app/models/model_domain.dart';
import 'package:diagnostic_app/models/orange_variable.dart';
import 'package:flutter_test/flutter_test.dart';

OrangeVariable _discrete(String name, {List<String>? values}) => OrangeVariable(
      name: name,
      type: VariableType.discrete,
      role: VariableRole.feature,
      values: values ?? const ['0', '1'],
    );

OrangeVariable _continuous(String name) => OrangeVariable(
      name: name,
      type: VariableType.continuous,
      role: VariableRole.feature,
    );

void main() {
  group('describeModel', () {
    test('summarises type, variable counts and the output class', () {
      final domain = ModelDomain(
        modelType: 'TreeModel',
        features: [
          for (var i = 0; i < 8; i++) _discrete('d$i'),
          for (var i = 0; i < 9; i++) _continuous('c$i'),
        ],
        classVar: const OrangeVariable(
          name: 'Den_outcome',
          type: VariableType.discrete,
          role: VariableRole.classVar,
          values: ['0', '1'],
        ),
      );

      expect(
        describeModel(domain),
        'Decision Tree · 17 variables (8 discrete, 9 continuous) · '
        'Output: Den_outcome → 0, 1',
      );
    });

    test('drops the breakdown when every variable has the same type', () {
      final domain = ModelDomain(
        modelType: 'RandomForestClassifier',
        features: [_discrete('a'), _discrete('b')],
        classVar: const OrangeVariable(
          name: 'target',
          type: VariableType.discrete,
          role: VariableRole.classVar,
          values: ['yes', 'no'],
        ),
      );

      expect(
        describeModel(domain),
        'Random Forest · 2 variables · Output: target → yes, no',
      );
    });

    test('omits the model type when the backend did not report one', () {
      final domain = ModelDomain(
        features: [_continuous('age')],
        classVar: const OrangeVariable(
          name: 'risk',
          type: VariableType.continuous,
          role: VariableRole.classVar,
        ),
      );

      expect(describeModel(domain), '1 variable · Output: risk');
    });
  });

  group('humanizeModelType', () {
    test('maps the Orange classes users are likely to meet', () {
      expect(humanizeModelType('TreeModel'), 'Decision Tree');
      expect(humanizeModelType('NaiveBayesModel'), 'Naive Bayes');
    });

    test('splits an unknown class name into words', () {
      expect(humanizeModelType('SklAdaBoostClassifier'), 'Ada Boost');
      expect(humanizeModelType('GradientBoostingModel'), 'Gradient Boosting');
    });

    test('keeps a name that is left empty by stripping affixes', () {
      expect(humanizeModelType('Model'), 'Model');
    });
  });
}
