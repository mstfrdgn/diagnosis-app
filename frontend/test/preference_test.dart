import 'dart:convert';
import 'dart:io';

import 'package:diagnostic_app/config/preference.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

/// Changing one value in the user's app_config.yaml must leave the rest of
/// the file alone: it is kept across updates, so it may come from any older
/// version and hold comments and keys of the user's own.
void main() {
  /// A value for [preference] that differs from the default.
  Object changed(Preference preference) => switch (preference) {
        Preference.theme => 'dark',
        Preference.probabilityFormat => 'decimal',
        _ => false,
      };

  final files = {
    for (final name in ['1.0.0', '1.1.0'])
      name: File('test/fixtures/app_config_$name.yaml').readAsStringSync(),
    'current': File('assets/config/app_config.yaml').readAsStringSync(),
  };
  files['1.1.0 CRLF'] = files['1.1.0']!.replaceAll('\n', '\r\n');
  files['1.1.0 unterminated'] = files['1.1.0']!.trimRight();

  for (final MapEntry(key: name, value: original) in files.entries) {
    for (final preference in Preference.values) {
      test('${preference.name} is set in a $name file, and nothing else', () {
        final updated = preference.applyTo(original, changed(preference));

        final expected = jsonDecode(jsonEncode(loadYaml(original))) as Map;
        (expected[preference.section] as Map)[preference.key] =
            changed(preference);
        expect(jsonDecode(jsonEncode(loadYaml(updated))), expected);

        // Line by line: one line changed, or one added, and every comment is
        // still there.
        final before = const LineSplitter().convert(original);
        final after = const LineSplitter().convert(updated);
        final added =
            (loadYaml(original)[preference.section] as Map)
                    .containsKey(preference.key)
                ? 0
                : 1;
        expect(after, hasLength(before.length + added));
        if (added == 1) {
          final line = '  ${preference.key}: ${changed(preference)}';
          expect(after.where((l) => l == line), hasLength(1));
          expect([...after]..remove(line), before);
        } else {
          final differing = [
            for (var i = 0; i < before.length; i++)
              if (before[i] != after[i]) i,
          ];
          expect(differing, hasLength(1));
          expect(after[differing.single].trim(),
              startsWith('${preference.key}: '));
        }
        Iterable<String> comments(List<String> lines) => lines
            .where((l) => l.contains('# '))
            .map((l) => l.substring(l.indexOf('# ')));
        expect(comments(after), comments(before));
      });
    }
  }

  test('every preference can be changed one after the other', () {
    var contents = files['1.0.0']!;
    for (final preference in Preference.values) {
      contents = preference.applyTo(contents, changed(preference));
    }
    final yaml = loadYaml(contents) as Map;
    for (final preference in Preference.values) {
      expect(yaml[preference.section][preference.key], changed(preference));
    }
    // Keys from 1.0.0 that mean nothing any more.
    expect(yaml['backend']['port'], 8765);
    expect(yaml['result_display']['style'], 'card');
    expect(yaml['evaluation_dialog']['doctor_diagnosis_options'], hasLength(3));
  });

  test('keeps the quotes and the comment of the value it replaces', () {
    final updated = Preference.probabilityFormat.applyTo(
      'result_display:\n  probability_format: "percent" # percent | decimal\n',
      'decimal',
    );
    expect(
      updated,
      'result_display:\n  probability_format: "decimal" # percent | decimal\n',
    );
  });

  test('adds a missing key, a missing section and an empty one', () {
    for (final contents in [
      'app:\n  theme: light\nform:\n  other: 1\n',
      'app:\n  theme: light\n',
      'app:\n  theme: light\nform:\n',
      'app:\n  theme: light\nform: # hints\n\ncsv_logging:\n  enabled: true\n',
      'app:\n  theme: light\nform: nonsense\n',
      'app: {theme: light}\nform: {}\n',
    ]) {
      final yaml =
          loadYaml(Preference.showRangeHints.applyTo(contents, false)) as Map;
      expect(yaml['form']['show_range_hints'], isFalse, reason: contents);
      expect(yaml['app']['theme'], 'light', reason: contents);
    }
  });

  test('writes into an empty file or one holding only comments', () {
    const expected = {
      'app': {'theme': 'dark'},
    };
    expect(loadYaml(Preference.theme.applyTo('', 'dark')), expected);
    final updated = Preference.theme.applyTo('# mine', 'dark');
    expect(updated, startsWith('# mine\n'));
    expect(loadYaml(updated), expected);
  });

  test('refuses a file that is not a YAML mapping', () {
    for (final contents in ['app: [', '- a\n- b\n', 'just text']) {
      expect(
        () => Preference.theme.applyTo(contents, 'dark'),
        throwsA(isA<FormatException>()),
        reason: contents,
      );
    }
  });
}
