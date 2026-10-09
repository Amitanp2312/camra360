import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sphere360/data/app_database.dart';
import 'package:sphere360/services/app_settings.dart';
import 'package:sphere360/services/auth_service.dart';
import 'package:sphere360/services/orientation_service.dart';
import 'package:sphere360/services/supabase_service.dart';
import 'package:sphere360/services/target_planner.dart';
import 'package:sphere360/services/upload_queue.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref.watch(supabaseClientProvider));
});

final supabaseServiceProvider = Provider<SupabaseService>((ref) {
  return SupabaseService(ref.watch(supabaseClientProvider));
});

/// Capture dots for the open lens. Updated once the phone reports its field of view.
class LiveTargets extends Notifier<List<SphereTarget>> {
  @override
  List<SphereTarget> build() {
    return const TargetPlanner().plan(
      horizontalFovDegrees: TargetPlanner.referenceHorizontalFov,
    );
  }

  void useLens(double horizontalFovDegrees) {
    state = const TargetPlanner().plan(
      horizontalFovDegrees: horizontalFovDegrees,
    );
  }
}

final liveTargetsProvider = NotifierProvider<LiveTargets, List<SphereTarget>>(
  LiveTargets.new,
);

/// Sensors for the live screen. Disposed when the screen stops watching.
final orientationServiceProvider = Provider.autoDispose<OrientationService>((
  ref,
) {
  final service = OrientationService();
  ref.onDispose(service.dispose);
  return service;
});

final orientationProvider = StreamProvider.autoDispose<OrientationSample>((
  ref,
) {
  final service = ref.watch(orientationServiceProvider);
  service.start();
  return service.samples;
});

/// Opened in [main] before [runApp]. The queue keeps this for the process.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  throw StateError('The upload database was not opened.');
});

/// Loaded in [main] before [runApp].
final settingsStoreProvider = Provider<SettingsStore>((ref) {
  throw StateError('Settings were not opened.');
});

class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.watch(settingsStoreProvider).current;

  Future<void> update(AppSettings next) async {
    state = next;
    await ref.read(settingsStoreProvider).save(next);
  }
}

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);

final pendingUploadsProvider = StreamProvider<List<UploadJob>>((ref) {
  return ref.watch(appDatabaseProvider).watchPending();
});

/// Retries pending uploads for as long as the app is running.
final uploadQueueProvider = Provider<UploadQueue>((ref) {
  final queue = UploadQueue(
    database: ref.watch(appDatabaseProvider),
    service: ref.watch(supabaseServiceProvider),
    wifiOnly: () => ref.read(settingsProvider).wifiOnly,
  );
  queue.start();
  ref.onDispose(queue.dispose);
  return queue;
});

final currentUserProvider = StreamProvider<User?>((ref) async* {
  final auth = ref.watch(authServiceProvider);
  yield auth.currentUser;
  await for (final state in auth.onAuthStateChange) {
    yield state.session?.user;
  }
});
