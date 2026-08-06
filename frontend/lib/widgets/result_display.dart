import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../models/prediction_result.dart';
import '../theme/app_theme.dart';

/// Renders a [PredictionResult] as a card: the predicted class in large
/// type, followed by a probability bar per class (when
/// `config.resultDisplay.show_probability` is on).
class ResultDisplay extends StatelessWidget {
  const ResultDisplay({super.key, required this.result, required this.config});

  final PredictionResult result;
  final AppConfig config;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sorted = result.probabilities.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final confidence = sorted.isEmpty ? null : sorted.first.value;

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Headline band: the answer itself, given the most visual weight.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
            color: scheme.primary.withValues(alpha: 0.07),
            child: Column(
              children: [
                Text(
                  'PREDICTED CLASS',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.primary,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  result.predictedClass,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.displaySmall
                      ?.copyWith(color: scheme.onSurface),
                ),
                if (config.resultDisplayShowProbability &&
                    confidence != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${_formatProbability(confidence, config.resultDisplayProbabilityFormat)} confidence',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (config.resultDisplayShowProbability && sorted.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'All classes',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 14),
                  for (final entry in sorted)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _ProbabilityBar(
                        label: entry.key,
                        value: entry.value,
                        highlighted: entry.key == result.predictedClass,
                        format: config.resultDisplayProbabilityFormat,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

String _formatProbability(double value, String format) {
  return format == 'decimal'
      ? value.toStringAsFixed(3)
      : '${(value * 100).toStringAsFixed(1)}%';
}

class _ProbabilityBar extends StatelessWidget {
  const _ProbabilityBar({
    required this.label,
    required this.value,
    required this.highlighted,
    required this.format,
  });

  final String label;
  final double value;
  final bool highlighted;
  final String format;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = highlighted ? scheme.primary : scheme.outline;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: highlighted ? FontWeight.w600 : FontWeight.w400,
                color: highlighted ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
            ),
            Text(
              _formatProbability(value, format),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: highlighted ? FontWeight.w700 : FontWeight.w500,
                color: highlighted ? scheme.primary : scheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.smallRadius / 2),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOutCubic,
            builder: (context, animated, _) => LinearProgressIndicator(
              value: animated,
              minHeight: 8,
              backgroundColor: color.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
      ],
    );
  }
}
