import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'config/app_config_notifier.dart';
import 'screens/configuration_screen.dart';
import 'screens/home_screen.dart';
import 'screens/input_screen.dart';
import 'screens/result_screen.dart';
import 'screens/settings_screen.dart';
import 'services/backend_manager.dart';
import 'theme/app_theme.dart';

// ── router ────────────────────────────────────────────────────────────────────

/// Build a GoRouter that automatically redirects based on [BackendNotifier].
///
/// State machine:
///   starting → /splash  (loading indicator)
///   error    → /error   (message + retry button)
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

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
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
            Text(
              'Starting diagnostic engine…',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'This may take a few seconds on first launch.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── error screen ──────────────────────────────────────────────────────────────

class _ErrorScreen extends StatelessWidget {
  const _ErrorScreen();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notifier = context.watch<BackendNotifier>();
    final isRetrying = notifier.status == BackendStatus.starting;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSpacing.narrowWidth),
          child: Padding(
            padding: const EdgeInsets.all(32),
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
                      'Backend failed to start',
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      notifier.errorMessage ?? 'Unknown error.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 28),
                    FilledButton.icon(
                      onPressed: isRetrying ? null : notifier.retry,
                      icon: isRetrying
                          ? const SizedBox.square(
                              dimension: 18,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh),
                      label: Text(isRetrying ? 'Retrying…' : 'Retry'),
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
}
