import 'model_domain.dart';
import 'orange_variable.dart';

/// Builds the one-line summary shown for a model on the Home Screen, e.g.
///
///     Decision Tree · 17 variables (8 discrete, 9 continuous) · Output: Den_outcome → 0, 1
///
/// It is generated the first time a model is loaded and stored in
/// `model_configs.json`; from then on the user owns the text and can rewrite
/// it freely in step 1 of the Configuration Wizard.
String describeModel(ModelDomain domain) {
  final parts = <String>[
    if (domain.modelType != null) humanizeModelType(domain.modelType!),
    _variablesPart(domain),
    _outputPart(domain),
  ];
  return parts.where((part) => part.isNotEmpty).join(' · ');
}

String _variablesPart(ModelDomain domain) {
  final total = domain.features.length;
  final counts = <VariableType, int>{};
  for (final feature in domain.features) {
    counts[feature.type] = (counts[feature.type] ?? 0) + 1;
  }
  // Listed in a fixed order so the same model always describes itself the
  // same way, and only for the types the model actually uses.
  const labels = {
    VariableType.discrete: 'discrete',
    VariableType.continuous: 'continuous',
    VariableType.time: 'time',
    VariableType.string: 'text',
  };
  final breakdown = [
    for (final entry in labels.entries)
      if ((counts[entry.key] ?? 0) > 0) '${counts[entry.key]} ${entry.value}',
  ];
  final noun = total == 1 ? 'variable' : 'variables';
  // A single-type model reads better without a breakdown that just repeats
  // the total ("3 variables (3 discrete)").
  if (breakdown.length < 2) return '$total $noun';
  return '$total $noun (${breakdown.join(', ')})';
}

String _outputPart(ModelDomain domain) {
  final classVar = domain.classVar;
  final values = classVar.values;
  if (values == null || values.isEmpty) return 'Output: ${classVar.name}';
  return 'Output: ${classVar.name} → ${values.join(', ')}';
}

/// Friendly names for the Orange model classes users are most likely to
/// meet. Anything unknown falls back to [_prettifyClassName].
const _friendlyModelTypes = <String, String>{
  'TreeModel': 'Decision Tree',
  'SklTreeClassifier': 'Decision Tree',
  'DecisionTreeClassifier': 'Decision Tree',
  'RandomForestClassifier': 'Random Forest',
  'SklRandomForestClassifier': 'Random Forest',
  'LogisticRegressionClassifier': 'Logistic Regression',
  'NaiveBayesModel': 'Naive Bayes',
  'SVMClassifier': 'Support Vector Machine',
  'KNNModel': 'k-Nearest Neighbours',
  'NNClassifier': 'Neural Network',
  'MajorityModel': 'Majority (baseline)',
  'ConstantModel': 'Majority (baseline)',
  'GBClassifier': 'Gradient Boosting',
  'CatGBClassifier': 'Gradient Boosting (CatBoost)',
  'XGBClassifier': 'Gradient Boosting (XGBoost)',
};

/// Turns the backend's `model_type` (a Python class name) into something
/// readable: `TreeModel` → `Decision Tree`, `AdaBoostClassifier` → `Ada Boost`.
String humanizeModelType(String raw) {
  final name = raw.trim();
  if (name.isEmpty) return '';
  final friendly = _friendlyModelTypes[name];
  if (friendly != null) return friendly;
  return _prettifyClassName(name);
}

/// Strips the Orange/scikit-learn affixes that carry no meaning for a reader
/// and splits the remaining CamelCase into words.
String _prettifyClassName(String name) {
  var stripped = name;
  if (stripped.startsWith('Skl')) stripped = stripped.substring(3);
  for (final suffix in const ['Classifier', 'Learner', 'Model']) {
    if (stripped.length > suffix.length && stripped.endsWith(suffix)) {
      stripped = stripped.substring(0, stripped.length - suffix.length);
      break;
    }
  }
  if (stripped.isEmpty) return name;
  final spaced = stripped
      .replaceAllMapped(
        RegExp(r'(.)([A-Z][a-z]+)'),
        (m) => '${m[1]} ${m[2]}',
      )
      .replaceAllMapped(
        RegExp(r'([a-z0-9])([A-Z])'),
        (m) => '${m[1]} ${m[2]}',
      );
  return spaced.trim();
}
