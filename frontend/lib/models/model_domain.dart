import 'orange_variable.dart';

/// Mirrors the backend's `DomainResponse` schema.
class ModelDomain {
  const ModelDomain({required this.features, required this.classVar});

  final List<OrangeVariable> features;
  final OrangeVariable classVar;

  factory ModelDomain.fromJson(Map<String, dynamic> json) {
    return ModelDomain(
      features: (json['features'] as List)
          .map((e) => OrangeVariable.fromJson(e as Map<String, dynamic>))
          .toList(),
      classVar:
          OrangeVariable.fromJson(json['class_var'] as Map<String, dynamic>),
    );
  }
}
