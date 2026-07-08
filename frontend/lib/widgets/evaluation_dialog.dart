import 'package:flutter/material.dart';

import '../config/app_config.dart';

/// What the doctor entered in an [EvaluationDialog], returned on confirm.
class EvaluationResult {
  const EvaluationResult({this.doctorDiagnosis, this.notes});

  final String? doctorDiagnosis;
  final String? notes;
}

/// Dialog shown after a prediction result, letting the doctor record their
/// own diagnosis and notes. Fields shown and their order are driven by
/// `config.evaluationDialog.fieldOrder`.
class EvaluationDialog extends StatefulWidget {
  const EvaluationDialog({super.key, required this.config});

  final AppConfig config;

  /// Shows the dialog and returns the [EvaluationResult] entered, or `null`
  /// if the user dismissed it without confirming.
  static Future<EvaluationResult?> show(
    BuildContext context, {
    required AppConfig config,
  }) {
    return showDialog<EvaluationResult>(
      context: context,
      builder: (_) => EvaluationDialog(config: config),
    );
  }

  @override
  State<EvaluationDialog> createState() => _EvaluationDialogState();
}

class _EvaluationDialogState extends State<EvaluationDialog> {
  final _formKey = GlobalKey<FormState>();
  final _notesController = TextEditingController();
  String? _doctorDiagnosis;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Evaluation'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final field in widget.config.evaluationDialogFieldOrder)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _buildField(field),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Skip'),
        ),
        FilledButton(
          onPressed: _confirm,
          child: const Text('Save'),
        ),
      ],
    );
  }

  Widget _buildField(String field) {
    switch (field) {
      case 'doctor_diagnosis':
        return DropdownButtonFormField<String>(
          initialValue: _doctorDiagnosis,
          decoration: const InputDecoration(
            labelText: 'Doctor diagnosis',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final option
                in widget.config.evaluationDialogDoctorDiagnosisOptions)
              DropdownMenuItem(value: option, child: Text(option)),
          ],
          onChanged: (selected) => setState(() => _doctorDiagnosis = selected),
        );
      case 'notes':
        return TextFormField(
          controller: _notesController,
          decoration: const InputDecoration(
            labelText: 'Notes',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
          minLines: 3,
          maxLines: 6,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  void _confirm() {
    if (!(_formKey.currentState?.validate() ?? true)) return;
    final notes = _notesController.text.trim();
    Navigator.of(context).pop(
      EvaluationResult(
        doctorDiagnosis: _doctorDiagnosis,
        notes: notes.isEmpty ? null : notes,
      ),
    );
  }
}
