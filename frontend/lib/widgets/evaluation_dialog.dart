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

  /// Asks whether the doctor wants to record an evaluation at all, so a case
  /// that needs no comment can be logged without dismissing a form. Returns
  /// `false` when declined or dismissed.
  static Future<bool> confirm(BuildContext context) async {
    final wanted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return AlertDialog(
          icon: Container(
            height: 44,
            width: 44,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.help_outline,
                size: 22, color: theme.colorScheme.primary),
          ),
          title: const Text('Would you like to add a doctor evaluation?'),
          contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          content: SizedBox(
            width: 420,
            child: Text(
              'Choosing “No” still logs this session — just without a '
              'diagnosis or notes of your own.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('No'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Yes'),
            ),
          ],
        );
      },
    );
    return wanted ?? false;
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
    final theme = Theme.of(context);
    return AlertDialog(
      icon: Container(
        height: 44,
        width: 44,
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.assignment_turned_in_outlined,
            size: 22, color: theme.colorScheme.primary),
      ),
      title: const Text('Record your evaluation'),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 420,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Saved alongside the model’s prediction in the session log.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              for (final field in widget.config.evaluationDialogFieldOrder)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: _buildField(field),
                ),
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Skip'),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: _confirm,
          icon: const Icon(Icons.check, size: 20),
          label: const Text('Save'),
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
            prefixIcon: Icon(Icons.medical_information_outlined, size: 20),
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
            hintText: 'Anything worth recording about this case…',
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
