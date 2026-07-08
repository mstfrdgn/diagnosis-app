enum VariableType { continuous, discrete, string, time }

enum VariableRole { feature, classVar }

/// Mirrors the backend's `VariableInfo` schema (see
/// `backend/schemas/domain_schema.py`).
class OrangeVariable {
  const OrangeVariable({
    required this.name,
    required this.type,
    required this.role,
    this.values,
    this.min,
    this.max,
  });

  final String name;
  final VariableType type;
  final VariableRole role;
  final List<String>? values; // discrete only
  final double? min; // continuous hint
  final double? max;

  factory OrangeVariable.fromJson(Map<String, dynamic> json) {
    return OrangeVariable(
      name: json['name'] as String,
      type: _typeFromJson(json['type'] as String),
      role: (json['role'] as String) == 'class'
          ? VariableRole.classVar
          : VariableRole.feature,
      values: (json['values'] as List?)?.cast<String>(),
      min: (json['min'] as num?)?.toDouble(),
      max: (json['max'] as num?)?.toDouble(),
    );
  }

  static VariableType _typeFromJson(String value) {
    switch (value) {
      case 'continuous':
        return VariableType.continuous;
      case 'discrete':
        return VariableType.discrete;
      case 'time':
        return VariableType.time;
      case 'string':
      default:
        return VariableType.string;
    }
  }
}
