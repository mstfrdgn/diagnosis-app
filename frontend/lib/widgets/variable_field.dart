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

  /// Bounds come from Orange as doubles; trim the `.0` off whole numbers so
  /// hints read "0 – 120" rather than "0.0 – 120.0".
  static String? _format(double? value) {
    if (value == null) return null;
    return value == value.roundToDouble() && value.abs() < 1e15
        ? value.toStringAsFixed(0)
        : value.toString();
  }

  @override
  Widget build(BuildContext context) {
    switch (variable.type) {
      case VariableType.discrete:
        return _buildDropdown(context);
      case VariableType.continuous:
      case VariableType.time:
        return _buildNumberField(context);
      case VariableType.string:
        return const SizedBox.shrink();
    }
  }

  Widget _buildDropdown(BuildContext context) {
    final options = variable.values ?? const <String>[];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: DropdownButtonFormField<String>(
        initialValue: value as String? ?? _unknownOption,
        decoration: InputDecoration(
          labelText: variable.name,
          prefixIcon: const Icon(Icons.checklist_rtl, size: 20),
        ),
        items: [
          DropdownMenuItem(
            value: _unknownOption,
            child: Text(
              _unknownOption,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
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

  Widget _buildNumberField(BuildContext context) {
    final hasRange = variable.min != null || variable.max != null;
    final hint = showRangeHints && hasRange
        ? 'Expected range: ${_format(variable.min) ?? '−∞'} – ${_format(variable.max) ?? '+∞'}'
        : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextFormField(
        initialValue: value?.toString() ?? '',
        decoration: InputDecoration(
          labelText: variable.name,
          helperText: hint,
          hintText: 'Leave empty if unknown',
          prefixIcon: Icon(
            variable.type == VariableType.time
                ? Icons.schedule
                : Icons.straighten,
            size: 20,
          ),
        ),
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true, signed: true),
        // Re-run [validator] on every keystroke once the user has touched the
        // field, so an out-of-range number is flagged as it is typed instead
        // of only when the form is submitted.
        autovalidateMode: AutovalidateMode.onUserInteraction,
        validator: (input) {
          if (input == null || input.trim().isEmpty) {
            return null; // empty is a valid "unknown" value
          }
          final parsed = double.tryParse(input.trim());
          if (parsed == null) return 'Enter a number';
          if (variable.min != null && parsed < variable.min!) {
            return 'Must be ≥ ${_format(variable.min)}';
          }
          if (variable.max != null && parsed > variable.max!) {
            return 'Must be ≤ ${_format(variable.max)}';
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
