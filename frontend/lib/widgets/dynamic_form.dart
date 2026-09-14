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
class DynamicForm extends StatefulWidget {
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
  State<DynamicForm> createState() => _DynamicFormState();
}

class _DynamicFormState extends State<DynamicForm> {
  /// Shared by the [Scrollbar] and the list it wraps. Without an explicit
  /// controller the Scrollbar falls back to the PrimaryScrollController,
  /// which desktop platforms do not attach, so it never finds a scroll
  /// position and asserts as soon as the user scrolls.
  ///
  /// One per instance rather than one shared by the caller: the input screen
  /// puts a [DynamicForm] per group inside an `IndexedStack`, which builds
  /// every child, so several of these lists are attached at the same time and
  /// a single controller across them would assert in its own right.
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _scrollController,
      child: ListView.builder(
        controller: _scrollController,
        padding: AppSpacing.page,
        itemCount: widget.variables.length,
        itemBuilder: (context, index) {
          final variable = widget.variables[index];
          return Center(
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(maxWidth: AppSpacing.narrowWidth),
              child: VariableField(
                variable: variable,
                value: widget.values.value[variable.name],
                showRangeHints: widget.showRangeHints,
                onChanged: (newValue) {
                  widget.values.value = {
                    ...widget.values.value,
                    variable.name: newValue,
                  };
                },
              ),
            ),
          );
        },
      ),
    );
  }
}
