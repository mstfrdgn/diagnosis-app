import 'package:path/path.dart' as p;

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
/// path, the name and description the user sees it under, when it was first
/// configured and last opened, and its saved configuration (if the user has
/// completed the Configuration Screen for it at least once).
class ModelConfigEntry {
  const ModelConfigEntry({
    required this.path,
    required this.createdAt,
    required this.lastOpened,
    this.displayName,
    this.description,
    this.configuration,
  });

  final String path;

  /// When this model was first added to the store. Written once and never
  /// updated, so the Home Screen can show how long a model has been around.
  final DateTime createdAt;
  final DateTime lastOpened;

  /// User-chosen name for the model. Null until the user renames it, in
  /// which case [effectiveName] falls back to the model's file name.
  final String? displayName;

  /// One-line summary of the model — generated from its domain the first
  /// time it is loaded, then owned by the user (editable in the wizard).
  final String? description;

  final ModelConfiguration? configuration;

  /// The name to show for this model, and the basis for its CSV file names.
  String get effectiveName {
    final name = displayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return p.basename(path);
  }

  factory ModelConfigEntry.fromJson(String path, Map<String, dynamic> json) {
    final rawConfig = json['configuration'] as Map<String, dynamic>?;
    final lastOpened = DateTime.parse(json['lastOpened'] as String);
    final rawCreatedAt = json['createdAt'] as String?;
    return ModelConfigEntry(
      path: path,
      // Entries written before `createdAt` existed only know when they were
      // last opened; treating that as the creation time is the closest
      // truthful answer available.
      createdAt:
          rawCreatedAt == null ? lastOpened : DateTime.parse(rawCreatedAt),
      lastOpened: lastOpened,
      displayName: json['displayName'] as String?,
      description: json['description'] as String?,
      configuration:
          rawConfig == null ? null : ModelConfiguration.fromJson(rawConfig),
    );
  }

  Map<String, dynamic> toJson() => {
        'createdAt': createdAt.toIso8601String(),
        'lastOpened': lastOpened.toIso8601String(),
        if (displayName != null) 'displayName': displayName,
        if (description != null) 'description': description,
        if (configuration != null) 'configuration': configuration!.toJson(),
      };

  ModelConfigEntry copyWith({
    DateTime? lastOpened,
    String? displayName,
    String? description,
    ModelConfiguration? configuration,
  }) {
    return ModelConfigEntry(
      path: path,
      createdAt: createdAt,
      lastOpened: lastOpened ?? this.lastOpened,
      displayName: displayName ?? this.displayName,
      description: description ?? this.description,
      configuration: configuration ?? this.configuration,
    );
  }
}
