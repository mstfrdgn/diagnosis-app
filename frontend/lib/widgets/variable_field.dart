import 'package:flutter/material.dart';

import '../models/orange_variable.dart';

/// Renders one input control for [variable], selected by its Orange type:
///   continuous / time → number TextFormField
///   discrete          → DropdownButtonFormField
///   string            → hidden (informational only, not sent to backend)
///
/// A value of `null` always means "left unknown" and is submitted as JSON
/// `null`, which the backend maps to a missing value.
class VariableField extends StatelessWidget {
  const VariableField({
    super.key,
    required this.variable,
    required this.value,
    required this.onChanged,
    this.showRangeHints = true,
  });

  final OrangeVariable variable;
  final dynamic value;
  final ValueChanged<dynamic> onChanged;
  final bool showRangeHints;

  static const _unknownOption = '— Unknown —';

  @override
  Widget build(BuildContext context) {
    switch (variable.type) {
      case VariableType.discrete:
        return _buildDropdown();
      case VariableType.continuous:
      case VariableType.time:
        return _buildNumberField();
      case VariableType.string:
        return const SizedBox.shrink();
    }
  }

  Widget _buildDropdown() {
    final options = variable.values ?? const <String>[];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: DropdownButtonFormField<String>(
        initialValue: value as String? ?? _unknownOption,
        decoration: InputDecoration(
          labelText: variable.name,
          border: const OutlineInputBorder(),
        ),
        items: [
          const DropdownMenuItem(
            value: _unknownOption,
            child: Text(_unknownOption),
          ),
          ...options.map(
            (option) => DropdownMenuItem(value: option, child: Text(option)),
          ),
        ],
        onChanged: (selected) =>
            onChanged(selected == _unknownOption ? null : selected),
      ),
    );
  }

  Widget _buildNumberField() {
    final hasRange = variable.min != null || variable.max != null;
    final hint = showRangeHints && hasRange
        ? '(${variable.min?.toString() ?? '-∞'} – ${variable.max?.toString() ?? '+∞'})'
        : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextFormField(
        initialValue: value?.toString() ?? '',
        decoration: InputDecoration(
          labelText: variable.name,
          helperText: hint,
          border: const OutlineInputBorder(),
        ),
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true, signed: true),
        validator: (input) {
          if (input == null || input.trim().isEmpty) {
            return null; // empty is a valid "unknown" value
          }
          final parsed = double.tryParse(input.trim());
          if (parsed == null) return 'Enter a number';
          if (variable.min != null && parsed < variable.min!) {
            return 'Must be ≥ ${variable.min}';
          }
          if (variable.max != null && parsed > variable.max!) {
            return 'Must be ≤ ${variable.max}';
          }
          return null;
        },
        onChanged: (input) {
          final trimmed = input.trim();
          if (trimmed.isEmpty) {
            onChanged(null);
          } else {
            onChanged(double.tryParse(trimmed) ?? trimmed);
          }
        },
      ),
    );
  }
}
