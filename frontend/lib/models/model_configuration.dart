/// A per-variable min/max override set on the Configuration Screen.
/// Either bound may be `null`, meaning "use the model's own hint".
class VariableRangeOverride {
  const VariableRangeOverride({this.min, this.max});

  final double? min;
  final double? max;

  factory VariableRangeOverride.fromJson(Map<String, dynamic> json) {
    return VariableRangeOverride(
      min: (json['min'] as num?)?.toDouble(),
      max: (json['max'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {'min': min, 'max': max};
}

/// The per-model configuration produced by the Configuration Wizard: the
/// user-created groups, which group each variable belongs to, and any
/// continuous-range overrides.
class ModelConfiguration {
  const ModelConfiguration({
    required this.groups,
    required this.variableGroups,
    required this.variableRanges,
  });

  /// User-created group names, in the order they should appear as Input
  /// Screens. Created/deleted in the wizard's first step; not predefined.
  final List<String> groups;
  final Map<String, String> variableGroups;
  final Map<String, VariableRangeOverride> variableRanges;

  /// Empty configuration, used the first time a model is opened (before the
  /// user has been through the Configuration Wizard for it).
  static const empty = ModelConfiguration(
    groups: [],
    variableGroups: {},
    variableRanges: {},
  );

  factory ModelConfiguration.fromJson(Map<String, dynamic> json) {
    final rawGroups = (json['variableGroups'] as Map?) ?? {};
    final rawRanges = (json['variableRanges'] as Map?) ?? {};
    return ModelConfiguration(
      groups: (json['groups'] as List?)?.cast<String>() ?? const [],
      variableGroups: rawGroups.map(
        (key, value) => MapEntry(key as String, value as String),
      ),
      variableRanges: rawRanges.map(
        (key, value) => MapEntry(
          key as String,
          VariableRangeOverride.fromJson(
            Map<String, dynamic>.from(value as Map),
          ),
        ),
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'groups': groups,
        'variableGroups': variableGroups,
        'variableRanges':
            variableRanges.map((key, value) => MapEntry(key, value.toJson())),
      };
}

/// One entry in the local "recently used models" store: the model's file
/// path, when it was last opened, and its saved configuration (if the user
/// has completed the Configuration Screen for it at least once).
class ModelConfigEntry {
  const ModelConfigEntry({
    required this.path,
    required this.lastOpened,
    this.configuration,
  });

  final String path;
  final DateTime lastOpened;
  final ModelConfiguration? configuration;

  factory ModelConfigEntry.fromJson(String path, Map<String, dynamic> json) {
    final rawConfig = json['configuration'] as Map<String, dynamic>?;
    return ModelConfigEntry(
      path: path,
      lastOpened: DateTime.parse(json['lastOpened'] as String),
      configuration:
          rawConfig == null ? null : ModelConfiguration.fromJson(rawConfig),
    );
  }

  Map<String, dynamic> toJson() => {
        'lastOpened': lastOpened.toIso8601String(),
        if (configuration != null) 'configuration': configuration!.toJson(),
      };

  ModelConfigEntry copyWith({
    DateTime? lastOpened,
    ModelConfiguration? configuration,
  }) {
    return ModelConfigEntry(
      path: path,
      lastOpened: lastOpened ?? this.lastOpened,
      configuration: configuration ?? this.configuration,
    );
  }
}
