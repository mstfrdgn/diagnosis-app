import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'config/app_config_notifier.dart';
import 'screens/configuration_screen.dart';
import 'screens/home_screen.dart';
import 'screens/input_screen.dart';
import 'screens/result_screen.dart';
import 'screens/sessions_screen.dart';
import 'screens/settings_screen.dart';
import 'services/backend_manager.dart';
import 'theme/app_theme.dart';

// ── router ────────────────────────────────────────────────────────────────────

/// Build a GoRouter that automatically redirects based on [BackendNotifier].
///
/// State machine:
///   starting → /splash  (loading indicator)
///   error    → /error   (cause, advice, retry/repair buttons)
///   ready    → /home    (or wherever the user was)
GoRouter buildRouter(BackendNotifier notifier) {
  return GoRouter(
    refreshListenable: notifier,
    initialLocation: '/splash',
    redirect: (context, state) {
      final loc = state.matchedLocation;
      switch (notifier.status) {
        case BackendStatus.starting:
          return loc == '/splash' ? null : '/splash';
        case BackendStatus.error:
          return loc == '/error' ? null : '/error';
        case BackendStatus.ready:
          if (loc == '/splash' || loc == '/error') return '/home';
          return null;
      }
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const _SplashScreen()),
      GoRoute(path: '/error', builder: (_, __) => const _ErrorScreen()),
      GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
      GoRoute(
        path: '/configuration',
        builder: (_, state) =>
            ConfigurationScreen(args: state.extra as ConfigurationScreenArgs),
      ),
      GoRoute(
        path: '/input',
        builder: (_, state) =>
            InputScreen(initialArgs: state.extra as InputScreenArgs?),
      ),
      GoRoute(
        path: '/result',
        builder: (_, state) =>
            ResultScreen(args: state.extra as ResultScreenArgs),
      ),
      GoRoute(
        path: '/sessions',
        builder: (_, state) =>
            SessionsScreen(initialArgs: state.extra as SessionsScreenArgs?),
      ),
      GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
    ],
  );
}

// ── root widget ───────────────────────────────────────────────────────────────

class DiagnosticApp extends StatelessWidget {
  const DiagnosticApp({super.key, required this.router});

  final GoRouter router;

  @override
  Widget build(BuildContext context) {
    final config = context.watch<AppConfigNotifier>().config;
    final isDark = config.appTheme == 'dark';
    return MaterialApp.router(
      title: config.appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(Brightness.light),
      darkTheme: AppTheme.build(Brightness.dark),
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      routerConfig: router,
    );
  }
}

// ── splash screen ─────────────────────────────────────────────────────────────

class _SplashScreen extends StatefulWidget {
  const _SplashScreen();

  @override
  State<_SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<_SplashScreen> {
  /// Set once the start takes longer than usual, so that a slow first start
  /// does not look like a hang. Not shown at once: most starts are quick.
  bool _slow = false;
  late final Timer _slowTimer;

  @override
  void initState() {
    super.initState();
    _slowTimer = Timer(const Duration(seconds: 10), () {
      if (mounted) setState(() => _slow = true);
    });
  }

  @override
  void dispose() {
    _slowTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phase = context.watch<BackendNotifier>().phase;
    final (title, subtitle) = switch (phase) {
      BackendPhase.unpacking => (
          'Preparing diagnostic engine…',
          'This is only needed after installing or updating the app.',
        ),
      BackendPhase.launching => (
          'Starting diagnostic engine…',
          'This may take a few seconds.',
        ),
      BackendPhase.repairing => (
          'Repairing diagnostic engine…',
          'Removing the old files.',
        ),
    };
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 72,
                width: 72,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  Icons.monitor_heart_outlined,
                  size: 36,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: 180,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: const LinearProgressIndicator(minHeight: 4),
                ),
              ),
              const SizedBox(height: 24),
              Text(title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(subtitle, style: muted, textAlign: TextAlign.center),
              if (_slow) ...[
                const SizedBox(height: 16),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: Text(
                    'The first start can take a few minutes while the system '
                    'checks the files. Please keep the app open.',
                    style: muted,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── error screen ──────────────────────────────────────────────────────────────

/// Says in plain words what went wrong and what to do about it, for people
/// who will never open a log; the technical account is folded away below.
class _ErrorScreen extends StatelessWidget {
  const _ErrorScreen();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notifier = context.watch<BackendNotifier>();
    final failure = notifier.failure ??
        const StartupFailure(StartupCause.unknown, 'Unknown error.');
    final isBusy = notifier.status == BackendStatus.starting;
    final muted = theme.colorScheme.onSurfaceVariant;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppSpacing.narrowWidth),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      height: 64,
                      width: 64,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.error.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(
                        Icons.error_outline,
                        size: 32,
                        color: theme.colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      failure.title,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      failure.explanation,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color:
                            theme.colorScheme.primary.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(AppSpacing.radius),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.lightbulb_outline,
                              size: 20, color: theme.colorScheme.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              failure.suggestion,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (notifier.waitingInBackground) ...[
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox.square(
                            dimension: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              'Still waiting for the engine in the background…',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: muted),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 24),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton.icon(
                          onPressed: isBusy ? null : notifier.retry,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                        OutlinedButton.icon(
                          onPressed: isBusy ? null : notifier.repair,
                          icon: const Icon(Icons.build_outlined),
                          label: const Text('Repair'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 4,
                      children: [
                        TextButton.icon(
                          onPressed: () => _openLogFolder(context, notifier),
                          icon:
                              const Icon(Icons.folder_open_outlined, size: 18),
                          label: const Text('Open log folder'),
                        ),
                        TextButton.icon(
                          onPressed: () => _copyReport(context, notifier),
                          icon: const Icon(Icons.copy_outlined, size: 18),
                          label: const Text('Copy diagnostic report'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Theme(
                      data: theme.copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: Text(
                          'Technical details',
                          style:
                              theme.textTheme.bodySmall?.copyWith(color: muted),
                        ),
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: SelectableText(
                              failure.detail,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontFamily: 'monospace',
                                color: muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openLogFolder(
    BuildContext context,
    BackendNotifier notifier,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final path = (await notifier.logDirectory).path;
      if (Platform.isWindows) {
        // explorer.exe exits non-zero even when it opened the window, so its
        // exit code says nothing about success.
        await Process.run('explorer', [path]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [path]);
      } else {
        await Process.run('xdg-open', [path]);
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not open the log folder: $e')),
      );
    }
  }

  Future<void> _copyReport(
    BuildContext context,
    BackendNotifier notifier,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final report = await notifier.diagnosticReport();
    await Clipboard.setData(ClipboardData(text: report));
    messenger.showSnackBar(
      const SnackBar(
        content: Text(
          'Diagnostic report copied. Paste it into an email or message.',
        ),
      ),
    );
  }
}
