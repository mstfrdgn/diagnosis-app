import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'config/app_config_notifier.dart';
import 'models/model_domain.dart';
import 'screens/home_screen.dart';
import 'screens/input_screen.dart';
import 'screens/result_screen.dart';
import 'screens/settings_screen.dart';
import 'services/backend_manager.dart';

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
        path: '/input',
        builder: (_, state) =>
            InputScreen(initialDomain: state.extra as ModelDomain?),
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
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      routerConfig: router,
    );
  }

  static ThemeData _buildTheme(Brightness brightness) {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF1565C0),
        brightness: brightness,
      ),
      useMaterial3: true,
    );
  }
}

// ── splash screen ─────────────────────────────────────────────────────────────

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(strokeWidth: 3),
            SizedBox(height: 24),
            Text(
              'Starting diagnostic engine…',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 8),
            Text(
              'This may take a few seconds on first launch.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
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
    final notifier = context.watch<BackendNotifier>();
    final isRetrying = notifier.status == BackendStatus.starting;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  'Backend failed to start',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Text(
                  notifier.errorMessage ?? 'Unknown error.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: isRetrying ? null : notifier.retry,
                  icon: isRetrying
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  label: Text(isRetrying ? 'Retrying…' : 'Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
