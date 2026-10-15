import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config_notifier.dart';
import '../models/logged_session.dart';
import '../services/api_service.dart';
import '../services/batch_run_log.dart';
import '../services/model_config_notifier.dart';
import '../services/session_log_service.dart';
import '../theme/app_theme.dart';
import '../widgets/result_display.dart';

/// Data passed via `extra` when navigating to [SessionsScreen] (normally by
/// [InputScreen], which already knows which model is loaded).
class SessionsScreenArgs {
  const SessionsScreenArgs({required this.modelPath});

  final String modelPath;
}

/// Which slice of the log the table is showing.
enum SessionFilter {
  today('Today'),
  thisWeek('This week'),
  all('All');

  const SessionFilter(this.label);

  final String label;
}

/// Read-only view of the sessions recorded for the currently loaded model,
/// with each batch run shown as a single entry among them.
///
/// If [initialArgs] is supplied it is used directly; otherwise the model path
/// is fetched from the backend, which keeps this screen reachable on its own
/// (e.g. after a hot restart).
class SessionsScreen extends StatefulWidget {
  const SessionsScreen({super.key, this.initialArgs});

  final SessionsScreenArgs? initialArgs;

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  /// Shared by the [Scrollbar] and the list it wraps. Without an explicit
  /// controller the Scrollbar falls back to the PrimaryScrollController,
  /// which desktop platforms do not attach, so it never finds a scroll
  /// position and asserts as soon as the user scrolls.
  final _scrollController = ScrollController();

  SessionFilter _filter = SessionFilter.today;
  SessionLog? _log;

  /// [SessionLog.entries] of [_log], merged once per load rather than on
  /// every build.
  List<SessionLogEntry> _entries = const [];
  bool _loading = true;
  String? _error;

  /// Rows the user has expanded, by their index in [_entries]. Reset on
  /// every reload because the indices move with the data.
  final _expanded = <int>{};

  /// Batch result files read so far, by path. A batch is only read when it
  /// is first expanded, and kept so that collapsing and re-expanding it (or
  /// scrolling it out of view) does not read the file again.
  final _batchResults = <String, Future<BatchResult>>{};

  @override
  void initState() {
    super.initState();
    // Reading the log touches providers, so it waits for the first frame
    // rather than running in initState directly.
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _expanded.clear();
      _batchResults.clear();
    });

    final config = context.read<AppConfigNotifier>().config;
    final modelConfigNotifier = context.read<ModelConfigNotifier>();
    final api = context.read<ApiService>();

    try {
      var modelPath = widget.initialArgs?.modelPath ?? '';
      if (modelPath.isEmpty) {
        final status = await api.getModelStatus();
        modelPath = status.path ?? '';
      }
      final log = await const SessionLogService().load(
        modelPath: modelPath,
        config: config,
        modelDisplayName: modelConfigNotifier.displayNameFor(modelPath),
      );
      if (!mounted) return;
      setState(() {
        _log = log;
        _entries = log.entries;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Midnight today, and the start of the current week (Monday), against
  /// which [SessionFilter] is resolved.
  static DateTime _startOfToday(DateTime now) =>
      DateTime(now.year, now.month, now.day);

  static DateTime _startOfWeek(DateTime now) =>
      _startOfToday(now).subtract(Duration(days: now.weekday - 1));

  /// Applies [_filter], pairing each row with its position in the full log so
  /// that expansion state survives a change of filter.
  ///
  /// Rows whose timestamp could not be parsed cannot be placed on a calendar,
  /// so they only appear under "All" — where they are still worth showing
  /// rather than silently dropping.
  List<(int, SessionLogEntry)> _visible(List<SessionLogEntry> entries) {
    final indexed = [
      for (var i = 0; i < entries.length; i++) (i, entries[i]),
    ];
    if (_filter == SessionFilter.all) return indexed;
    final now = DateTime.now();
    final from = _filter == SessionFilter.today
        ? _startOfToday(now)
        : _startOfWeek(now);
    return indexed
        .where((e) => e.$2.timestamp != null && !e.$2.timestamp!.isBefore(from))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final log = _log;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sessions'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload log',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _buildBody(log),
    );
  }

  Widget _buildBody(SessionLog? log) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final error = _error ?? log?.error;
    if (error != null) {
      return _SessionsMessage(
        icon: Icons.error_outline,
        title: 'Could not read the session log',
        message: error,
        tone: Theme.of(context).colorScheme.error,
        onRetry: _load,
      );
    }
    if (log == null) return const SizedBox.shrink();

    if (log.isEmpty) {
      return _SessionsMessage(
        icon: Icons.inbox_outlined,
        title: 'No sessions recorded yet',
        message: 'Sessions you run for this model are logged to\n${log.path}',
        onRetry: _load,
      );
    }

    final visible = _visible(_entries);
    return Padding(
      padding: AppSpacing.page,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FilterBar(
            filter: _filter,
            onChanged: (filter) => setState(() => _filter = filter),
            visible: [for (final (_, entry) in visible) entry],
            totalCount: _entries.length,
          ),
          const SizedBox(height: 16),
          const _TableHeader(),
          const Divider(height: 1),
          Expanded(
            child: visible.isEmpty
                ? Center(
                    child: SizedBox(
                      width: AppSpacing.narrowWidth,
                      child: EmptyStateCard(
                        icon: Icons.filter_alt_outlined,
                        message:
                            'Nothing recorded ${_filter == SessionFilter.today ? 'today' : 'this week'}. '
                            'Switch to "All" to see the full log.',
                      ),
                    ),
                  )
                : Scrollbar(
                    controller: _scrollController,
                    child: ListView.separated(
                      controller: _scrollController,
                      itemCount: visible.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final (key, entry) = visible[index];
                        final expanded = _expanded.contains(key);
                        void onToggle() => setState(() {
                              if (!_expanded.remove(key)) _expanded.add(key);
                            });
                        return switch (entry) {
                          LoggedSession() => _SessionRow(
                              session: entry,
                              expanded: expanded,
                              onToggle: onToggle,
                            ),
                          LoggedBatchRun() => _BatchRunRow(
                              run: entry,
                              expanded: expanded,
                              onToggle: onToggle,
                              result: expanded
                                  ? _batchResults.putIfAbsent(
                                      entry.resultPath,
                                      () => const BatchRunLog()
                                          .loadResult(entry.resultPath),
                                    )
                                  : null,
                            ),
                        };
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── column widths ─────────────────────────────────────────────────────────────

/// One flex spec shared by the header and every data row, which is what keeps
/// the columns lined up without a real table widget. A [DataTable] would give
/// alignment for free but cannot host the expandable detail panel that keeps
/// a 17-variable model off a mile-wide horizontal scroll.
const _timeFlex = 4;
const _predictedFlex = 4;
const _confidenceFlex = 3;
const _doctorFlex = 3;
const _notesFlex = 5;
const _chevronWidth = 40.0;

// ── filter bar ────────────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.filter,
    required this.onChanged,
    required this.visible,
    required this.totalCount,
  });

  final SessionFilter filter;
  final ValueChanged<SessionFilter> onChanged;

  /// Entries the current filter lets through.
  final List<SessionLogEntry> visible;

  /// Entries in the whole log.
  final int totalCount;

  /// "3 sessions · 1 batch run" for [entries], leaving out batch runs when
  /// there are none.
  static String describe(List<SessionLogEntry> entries) {
    final batches = entries.whereType<LoggedBatchRun>().length;
    final sessions = entries.length - batches;
    String count(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';
    return [
      if (sessions > 0 || batches == 0) count(sessions, 'session'),
      if (batches > 0) count(batches, 'batch run'),
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SegmentedButton<SessionFilter>(
          segments: [
            for (final value in SessionFilter.values)
              ButtonSegment(value: value, label: Text(value.label)),
          ],
          selected: {filter},
          showSelectedIcon: false,
          onSelectionChanged: (selection) => onChanged(selection.first),
        ),
        const SizedBox(width: 16),
        Text(
          visible.length == totalCount
              ? describe(visible)
              : '${describe(visible)} (of $totalCount entries)',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

// ── table ─────────────────────────────────────────────────────────────────────

class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w700,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(flex: _timeFlex, child: Text('Timestamp', style: style)),
          Expanded(
            flex: _predictedFlex,
            child: Text('Predicted class', style: style),
          ),
          Expanded(
            flex: _confidenceFlex,
            child: Text('Confidence', style: style),
          ),
          Expanded(
            flex: _doctorFlex,
            child: Text('Doctor diagnosis', style: style),
          ),
          Expanded(flex: _notesFlex, child: Text('Notes', style: style)),
          const SizedBox(width: _chevronWidth),
        ],
      ),
    );
  }
}

/// One logged session: the summary columns, plus the input values the
/// prediction was made from once the row is expanded.
class _SessionRow extends StatelessWidget {
  const _SessionRow({
    required this.session,
    required this.expanded,
    required this.onToggle,
  });

  final LoggedSession session;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final config = context.watch<AppConfigNotifier>().config;
    final confidence = session.confidence;
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    Widget cell(int flex, String value, {TextStyle? style}) => Expanded(
          flex: flex,
          child: Text(
            value.isEmpty ? '—' : value,
            maxLines: expanded ? null : 1,
            overflow: expanded ? null : TextOverflow.ellipsis,
            style: value.isEmpty ? muted : style ?? theme.textTheme.bodyMedium,
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(AppSpacing.smallRadius),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                cell(
                  _timeFlex,
                  session.rawTimestamp,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                cell(
                  _predictedFlex,
                  session.predictedClass,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                cell(
                  _confidenceFlex,
                  confidence == null
                      ? ''
                      : formatProbability(
                          confidence,
                          config.resultDisplayProbabilityFormat,
                        ),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                cell(_doctorFlex, session.doctorDiagnosis),
                cell(_notesFlex, session.notes),
                SizedBox(
                  width: _chevronWidth,
                  child: Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.only(bottom: 16, right: _chevronWidth),
            child: _InputValues(inputs: session.inputs),
          ),
      ],
    );
  }
}

/// The feature values behind one prediction, laid out as wrapping
/// label/value pairs so a model with many variables stays readable.
class _InputValues extends StatelessWidget {
  const _InputValues({required this.inputs});

  final Map<String, String> inputs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (inputs.isEmpty) {
      return Text(
        'This log records no input values.',
        style:
            theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(AppSpacing.smallRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Input values',
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 24,
            runSpacing: 8,
            children: [
              for (final entry in inputs.entries)
                SizedBox(
                  width: 240,
                  child: RichText(
                    text: TextSpan(
                      style: theme.textTheme.bodySmall,
                      children: [
                        TextSpan(
                          text: '${entry.key}: ',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                        TextSpan(
                          text: entry.value.isEmpty ? '—' : entry.value,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── batch runs ────────────────────────────────────────────────────────────────

/// Rows of a batch result listed in the expanded panel. Past this the panel
/// would dwarf the rest of the log; the file has them all.
const _maxBatchRowsShown = 200;

/// One batch run: its time, then — across the remaining columns, which
/// describe a single prediction and have nothing to say about a whole run —
/// the input file and row counts. Expanding it reads the result file.
class _BatchRunRow extends StatelessWidget {
  const _BatchRunRow({
    required this.run,
    required this.expanded,
    required this.onToggle,
    required this.result,
  });

  final LoggedBatchRun run;
  final bool expanded;
  final VoidCallback onToggle;

  /// The result file being read, once the row is expanded.
  final Future<BatchResult>? result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final rows = run.rowCount;
    final failures = run.failureCount ?? 0;
    final details = [
      run.inputFileName ?? 'Input file unknown',
      rows == null ? 'row count unknown' : '$rows row${rows == 1 ? '' : 's'}',
      if (failures > 0) '$failures failed',
    ].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(AppSpacing.smallRadius),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: _timeFlex,
                  child: Text(
                    run.rawTimestamp,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                Expanded(
                  flex: _predictedFlex +
                      _confidenceFlex +
                      _doctorFlex +
                      _notesFlex,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.secondaryContainer,
                          borderRadius:
                              BorderRadius.circular(AppSpacing.smallRadius),
                        ),
                        child: Text(
                          'Batch',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSecondaryContainer,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          details,
                          maxLines: expanded ? null : 1,
                          overflow: expanded ? null : TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: _chevronWidth,
                  child: Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (expanded && result != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _BatchDetails(run: run, result: result!),
          ),
      ],
    );
  }
}

/// The expanded panel of a batch run: where its result file is and how the
/// predictions came out, then the first [_maxBatchRowsShown] of them.
///
/// The panel is inset like a session's input values, but the row table
/// below it is not: it spans the full row and uses the list's own column
/// flexes, so each prediction sits under the header that names it.
class _BatchDetails extends StatelessWidget {
  const _BatchDetails({required this.run, required this.result});

  final LoggedBatchRun run;
  final Future<BatchResult> result;

  Future<void> _openFile(BuildContext context) async {
    final path = run.resultPath;
    try {
      if (Platform.isWindows) {
        // 'start' is a cmd.exe builtin; the empty title arg avoids it being
        // misread as the window title when the path contains spaces/quotes.
        await Process.run('cmd', ['/c', 'start', '', path]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [path]);
      } else {
        await Process.run('xdg-open', [path]);
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open $path: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final labelStyle = theme.textTheme.labelMedium?.copyWith(
      color: scheme.onSurfaceVariant,
      fontWeight: FontWeight.w700,
    );
    final muted =
        theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);

    return FutureBuilder<BatchResult>(
      future: result,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final Widget status;
        if (data == null) {
          status = const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        } else if (!data.succeeded) {
          status = Text(
            'Could not read the result file: ${data.error}',
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
          );
        } else if (data.rows.isEmpty) {
          status = Text('The result file has no rows.', style: muted);
        } else {
          final failures = data.failureCount;
          status = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Predictions', style: labelStyle),
              const SizedBox(height: 6),
              Text(
                [
                  for (final MapEntry(key: label, value: count)
                      in data.classCounts)
                    '$label: $count',
                  if (failures > 0) 'failed: $failures',
                ].join(' · '),
                style: theme.textTheme.bodySmall,
              ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: _chevronWidth),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(AppSpacing.smallRadius),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Batch result file', style: labelStyle),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: SelectableText(
                            run.resultPath,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        TextButton.icon(
                          onPressed: () => _openFile(context),
                          icon: const Icon(Icons.open_in_new, size: 18),
                          label: const Text('Open file'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    status,
                  ],
                ),
              ),
            ),
            if (data != null && data.succeeded && data.rows.isNotEmpty) ...[
              const SizedBox(height: 12),
              _BatchPredictionTable(rows: data.rows, labelStyle: labelStyle),
            ],
          ],
        );
      },
    );
  }
}

/// The first [_maxBatchRowsShown] predictions of a batch, laid out on the
/// list's own columns: row number under "Timestamp", class under "Predicted
/// class", confidence under "Confidence".
class _BatchPredictionTable extends StatelessWidget {
  const _BatchPredictionTable({required this.rows, required this.labelStyle});

  final List<BatchResultRow> rows;
  final TextStyle? labelStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final config = context.watch<AppConfigNotifier>().config;
    final shown = rows.take(_maxBatchRowsShown).toList();
    final numbers = theme.textTheme.bodySmall?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    Widget line(
      String index,
      String predicted,
      String confidence, {
      TextStyle? style,
    }) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Expanded(
                flex: _timeFlex,
                child: Text(index, style: style ?? numbers),
              ),
              Expanded(
                flex: _predictedFlex,
                child: Text(
                  predicted,
                  style: style ??
                      theme.textTheme.bodySmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Expanded(
                flex: _confidenceFlex,
                child: Text(confidence, style: style ?? numbers),
              ),
              // Doctor diagnosis and notes are filled in later, in the file.
              const Spacer(flex: _doctorFlex + _notesFlex),
              const SizedBox(width: _chevronWidth),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        line('Row', 'Predicted class', 'Confidence', style: labelStyle),
        for (var i = 0; i < shown.length; i++)
          line(
            '${i + 1}',
            shown[i].failed ? 'Prediction failed' : shown[i].predictedClass,
            switch (shown[i].confidence) {
              null => '—',
              final c => formatProbability(
                  c,
                  config.resultDisplayProbabilityFormat,
                ),
            },
          ),
        if (rows.length > shown.length) ...[
          const SizedBox(height: 8),
          Text(
            'Showing the first ${shown.length} of ${rows.length} rows. '
            'Open the file for the rest.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

// ── empty / error state ───────────────────────────────────────────────────────

class _SessionsMessage extends StatelessWidget {
  const _SessionsMessage({
    required this.icon,
    required this.title,
    required this.message,
    required this.onRetry,
    this.tone,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback onRetry;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = tone ?? theme.colorScheme.onSurfaceVariant;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.narrowWidth),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 32, color: color),
              const SizedBox(height: 16),
              Text(title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              SelectableText(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Reload'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
