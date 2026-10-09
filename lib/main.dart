import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sphere360/core/constants.dart';
import 'package:sphere360/core/providers.dart';
import 'package:sphere360/core/theme.dart';
import 'package:sphere360/data/app_database.dart';
import 'package:sphere360/screens/gallery_screen.dart';
import 'package:sphere360/screens/login_screen.dart';
import 'package:sphere360/services/app_settings.dart';
import 'package:sphere360/services/upload_queue.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The client appends `/auth/v1` and `/rest/v1` itself. A dashboard REST
/// URL (`…/rest/v1/`) would make those paths invalid.
String _projectUrl(String raw) {
  var url = raw.trim();
  while (url.endsWith('/')) {
    url = url.substring(0, url.length - 1);
  }
  for (final suffix in ['/rest/v1', '/auth/v1']) {
    if (url.endsWith(suffix)) {
      url = url.substring(0, url.length - suffix.length);
    }
  }
  return url;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await dotenv.load(fileName: '.env');
  } on FileNotFoundError {
    runApp(
      const ConfigErrorApp(
        message: 'Missing .env. Copy .env.example to .env and set SUPABASE_URL and SUPABASE_ANON_KEY.',
      ),
    );
    return;
  } on EmptyEnvFileError {
    runApp(
      const ConfigErrorApp(
        message: '.env is empty. Set SUPABASE_URL and SUPABASE_ANON_KEY, then restart.',
      ),
    );
    return;
  }

  const requiredKeys = [
    AppConstants.supabaseUrlKey,
    AppConstants.supabaseAnonKeyKey,
  ];
  if (!dotenv.isEveryDefined(requiredKeys)) {
    runApp(
      const ConfigErrorApp(
        message: 'Set SUPABASE_URL and SUPABASE_ANON_KEY in .env, then restart the app.',
      ),
    );
    return;
  }

  try {
    await Supabase.initialize(
      url: _projectUrl(dotenv.env[AppConstants.supabaseUrlKey]!),
      publishableKey: dotenv.env[AppConstants.supabaseAnonKeyKey]!,
    );
    // initialize() starts session restore and returns before it finishes.
    // Wait for the first auth event so the gate does not flash the login screen
    // over a session that is still being read from local storage.
    await Supabase.instance.client.auth.onAuthStateChange
        .firstWhere((state) => state.event == AuthChangeEvent.initialSession)
        .timeout(const Duration(seconds: 8));
  } on TimeoutException {
    // Restore did not report in time. Continue with whatever is already loaded.
  } catch (error) {
    runApp(
      ConfigErrorApp(
        message:
            'Could not start Supabase. Check the URL and anon key.\n$error',
      ),
    );
    return;
  }

  final AppDatabase database;
  try {
    database = await openUploadDatabase();
  } catch (error) {
    runApp(
      ConfigErrorApp(message: 'Could not open the local upload queue.\n$error'),
    );
    return;
  }

  final SettingsStore settings;
  try {
    final directory = await getApplicationSupportDirectory();
    settings = SettingsStore(
      File(p.join(directory.path, 'settings.json')),
    );
    await settings.load();
  } catch (error) {
    runApp(
      ConfigErrorApp(message: 'Could not open settings.\n$error'),
    );
    return;
  }

  runApp(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        settingsStoreProvider.overrideWithValue(settings),
      ],
      child: const Sphere360App(),
    ),
  );
}

class Sphere360App extends ConsumerWidget {
  const Sphere360App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(uploadQueueProvider);
    ref.listen(currentUserProvider, (_, next) {
      if (next.asData?.value != null) {
        ref.read(uploadQueueProvider).resumeNow();
      }
    });
    return MaterialApp(
      title: AppConstants.appName,
      theme: SphereTheme.dark(),
      darkTheme: SphereTheme.dark(),
      themeMode: ThemeMode.dark,
      home: const AuthGate(),
    );
  }
}

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    return user.when(
      loading: () => const _Splash(),
      error: (error, _) => _AuthError(
        message: error.toString(),
        onRetry: () => ref.invalidate(currentUserProvider),
      ),
      data: (signedIn) {
        if (signedIn == null) return const LoginScreen();
        return const GalleryScreen();
      },
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppConstants.appName,
              style: TextStyle(
                color: SphereColors.accent,
                fontSize: 28,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 20),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}

class _AuthError extends StatelessWidget {
  const _AuthError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ),
      ),
    );
  }
}

class ConfigErrorApp extends StatelessWidget {
  const ConfigErrorApp({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      theme: SphereTheme.dark(),
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppConstants.appName,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: SphereColors.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                Text(message),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
