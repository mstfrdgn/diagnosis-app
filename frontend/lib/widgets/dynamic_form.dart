import 'package:flutter/material.dart';

import '../models/model_domain.dart';
import 'variable_field.dart';

/// Builds one [VariableField] per feature in [domain]. Collected values live
/// in [values]; read `values.value` after `formKey.currentState!.validate()`
/// passes to get the map ready for `ApiService.predict`.
class DynamicForm extends StatelessWidget {
  const DynamicForm({
    super.key,
    required this.formKey,
    required this.domain,
    required this.values,
    this.showRangeHints = true,
  });

  final GlobalKey<FormState> formKey;
  final ModelDomain domain;
  final ValueNotifier<Map<String, dynamic>> values;
  final bool showRangeHints;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: domain.features.length,
        itemBuilder: (context, index) {
          final variable = domain.features[index];
          return VariableField(
            variable: variable,
            value: values.value[variable.name],
            showRangeHints: showRangeHints,
            onChanged: (newValue) {
              values.value = {...values.value, variable.name: newValue};
            },
          );
        },
      ),
    );
  }
}
