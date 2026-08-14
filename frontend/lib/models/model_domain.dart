import 'orange_variable.dart';

/// Mirrors the backend's `DomainResponse` schema.
class ModelDomain {
  const ModelDomain({
    required this.features,
    required this.classVar,
    this.modelType,
  });

  final List<OrangeVariable> features;
  final OrangeVariable classVar;

  /// Class name of the pickled classifier (e.g. `TreeModel`), or null when
  /// the backend could not determine it.
  final String? modelType;

  factory ModelDomain.fromJson(Map<String, dynamic> json) {
    return ModelDomain(
      features: (json['features'] as List)
          .map((e) => OrangeVariable.fromJson(e as Map<String, dynamic>))
          .toList(),
      classVar:
          OrangeVariable.fromJson(json['class_var'] as Map<String, dynamic>),
      modelType: json['model_type'] as String?,
    );
  }
}
