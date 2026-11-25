import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

/// The keys of `app_config.yaml` that the Settings screen can change. Every
/// other key is only ever edited by hand.
enum Preference {
  theme('app', 'theme'),
  showProbability('result_display', 'show_probability'),
  probabilityFormat('result_display', 'probability_format'),
  evaluationEnabled('evaluation_dialog', 'enabled'),
  includeUncertainOption('evaluation_dialog', 'include_uncertain_option'),
  csvLoggingEnabled('csv_logging', 'enabled'),
  showRangeHints('form', 'show_range_hints');

  const Preference(this.section, this.key);

  final String section;
  final String key;

  /// Returns [contents], the text of an `app_config.yaml`, with this key set
  /// to [value].
  ///
  /// Only the value itself is replaced: comments, blank lines, the order of
  /// the keys and any key this version does not know stay as they are. A key
  /// or section the file does not have yet is added. Throws when [contents]
  /// is not a YAML mapping, so that a file the app could not read is never
  /// overwritten.
  String applyTo(String contents, Object value) {
    final root = loadYaml(contents);
    if (root == null) {
      // Nothing but comments, which the editor would replace.
      final lead = contents.isEmpty || contents.endsWith('\n') ? '' : '\n';
      return '$contents$lead$section:\n  $key: $value\n';
    }
    if (root is! YamlMap) {
      throw const FormatException('the file holds no settings');
    }

    final editor = YamlEditor(contents);
    final values = root.nodes[section];
    if (values is YamlMap) {
      // Keep the quotes of a value that had them.
      final old = values.nodes[key];
      editor.update(
        [section, key],
        old is YamlScalar && value is String
            ? wrapAsYamlNode(value, scalarStyle: old.style)
            : value,
      );
    } else {
      // Missing, or an empty `section:`.
      editor.update([section], {key: value});
    }
    return editor.toString();
  }
}
