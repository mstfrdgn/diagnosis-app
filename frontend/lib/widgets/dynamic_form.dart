import 'package:flutter/material.dart';

import '../models/orange_variable.dart';
import '../theme/app_theme.dart';
import 'variable_field.dart';

/// Builds one [VariableField] per entry in [variables]. Collected values
/// live in [values]; read `values.value` after the enclosing `Form`'s
/// `formKey.currentState!.validate()` passes to get the map ready for
/// `ApiService.predict`.
///
/// Does not create its own [Form] — callers that page through several
/// [DynamicForm]s (e.g. one per input group) wrap them all in a single
/// shared `Form` so validation covers every group at once.
class DynamicForm extends StatelessWidget {
  const DynamicForm({
    super.key,
    required this.variables,
    required this.values,
    this.showRangeHints = true,
  });

  final List<OrangeVariable> variables;
  final ValueNotifier<Map<String, dynamic>> values;
  final bool showRangeHints;

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      child: ListView.builder(
        padding: AppSpacing.page,
        itemCount: variables.length,
        itemBuilder: (context, index) {
          final variable = variables[index];
          return Center(
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(maxWidth: AppSpacing.narrowWidth),
              child: VariableField(
                variable: variable,
                value: values.value[variable.name],
                showRangeHints: showRangeHints,
                onChanged: (newValue) {
                  values.value = {...values.value, variable.name: newValue};
                },
              ),
            ),
          );
        },
      ),
    );
  }
}
