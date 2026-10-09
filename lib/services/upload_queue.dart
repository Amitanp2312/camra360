import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sphere360/data/app_database.dart';
import 'package:sphere360/services/supabase_service.dart';
import 'package:sphere360/services/upload_backoff.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A tile saved on disk and waiting for Storage plus a captures row.
class QueuedCapture {
  const QueuedCapture({
    required this.id,
    required this.userId,
    required this.sessionId,
    required this.localPath,
    required this.yaw,
    required this.pitch,
    this.roll,
    this.fov,
    this.width,
    this.height,
  });

  final String id;
  final String userId;
  final String sessionId;
  final String localPath;
  final double yaw;
  final double pitch;
  final double? roll;
  final double? fov;
  final int? width;
  final int? height;
}

Future<AppDatabase> openUploadDatabase() async {
  final directory = await getApplicationSupportDirectory();
  final file = File(p.join(directory.path, 'upload_queue.sqlite'));
  final database = AppDatabase(NativeDatabase.createInBackground(file));
  await database.customSelect('select 1').get();
  return database;
}

/// Whether a pending photo may leave the phone on this radio.
///
/// [wifiOnly] still allows a VPN sitting on top of Wi-Fi. Mobile data waits.
bool uploadAllowed(
  List<ConnectivityResult> results, {
  required bool wifiOnly,
}) {
  final online = results.any((result) => result != ConnectivityResult.none);
  if (!online) return false;
  if (!wifiOnly) return true;
  return results.contains(ConnectivityResult.wifi);
}

/// What [UploadQueue] does next when undo may have interrupted a send.
enum SendAction { upload, insertRow, deleteRemote, stop }

/// Next step for one queued JPEG.
///
/// Undo before the upload leaves nothing remote. Undo after the bytes are
/// stored, or after the captures row exists, has to delete that remote data
/// or the shot comes back.
SendAction nextSendAction({
  required bool cancelled,
  required bool uploaded,
  required bool inserted,
}) {
  if (!cancelled && !uploaded) return SendAction.upload;
  if (!cancelled && !inserted) return SendAction.insertRow;
  if (cancelled && (uploaded || inserted)) return SendAction.deleteRemote;
  return SendAction.stop;
}

/// Uploads queued JPEGs and inserts their capture rows.
///
/// A failed attempt waits [uploadBackoff] before the next try. Coming online,
/// and launching the app while online, runs pending jobs immediately.
class UploadQueue {
  UploadQueue({
    required this.database,
    required this.service,
    Connectivity? connectivity,
    this.wifiOnly,
  }) : _connectivity = connectivity ?? Connectivity();

  final AppDatabase database;
  final SupabaseService service;
  final Connectivity _connectivity;
  final bool Function()? wifiOnly;

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  Timer? _timer;
  var _started = false;
  var _closed = false;
  var _running = false;
  var _kickAgain = false;
  var _retryNow = false;
  final _cancelled = <String>{};

  /// Set when a drain or radio check fails. The pending job keeps its own error.
  Object? lastFailure;

  void start() {
    if (_started) return;
    _started = true;
    _subscription = _connectivity.onConnectivityChanged.listen(
      _onConnectivity,
      onError: (Object error) {
        lastFailure = error;
      },
    );
    unawaited(_resume());
  }

  /// Runs every pending job on the next pass, skipping any backoff still open.
  void resumeNow() {
    _retryNow = true;
    unawaited(kick());
  }

  void dispose() {
    _closed = true;
    _timer?.cancel();
    unawaited(_subscription?.cancel());
  }

  Future<void> enqueue(QueuedCapture capture) async {
    await database.enqueueJob(
      UploadJobsCompanion.insert(
        id: capture.id,
        userId: capture.userId,
        sessionId: capture.sessionId,
        localPath: capture.localPath,
        yaw: capture.yaw,
        pitch: capture.pitch,
        roll: Value(capture.roll),
        fov: Value(capture.fov),
        width: Value(capture.width),
        height: Value(capture.height),
        nextAttemptAt: DateTime.now(),
      ),
    );
    await kick();
  }

  Future<void> kick() async {
    if (_closed) return;
    if (_running) {
      _kickAgain = true;
      return;
    }
    _running = true;
    try {
      do {
        _kickAgain = false;
        await _drain();
      } while (_kickAgain && !_closed);
    } catch (error) {
      lastFailure = error;
      _schedule(DateTime.now().add(uploadBackoff(1)));
    } finally {
      _running = false;
    }
  }

  Future<void> _resume() async {
    try {
      final current = await _connectivity.checkConnectivity();
      if (_isOnline(current)) _retryNow = true;
    } catch (error) {
      lastFailure = error;
    }
    await kick();
  }

  void _onConnectivity(List<ConnectivityResult> results) {
    if (!_isOnline(results)) return;
    _retryNow = true;
    unawaited(kick());
  }

  bool _isOnline(List<ConnectivityResult> results) {
    return uploadAllowed(results, wifiOnly: wifiOnly?.call() ?? false);
  }

  Future<void> _drain() async {
    try {
      final current = await _connectivity.checkConnectivity();
      if (!_isOnline(current)) {
        _schedule(DateTime.now().add(const Duration(seconds: 30)));
        return;
      }
    } catch (error) {
      lastFailure = error;
      _schedule(DateTime.now().add(const Duration(seconds: 30)));
      return;
    }
    if (_retryNow) {
      _retryNow = false;
      await database.releaseBackoff(DateTime.now());
    }
    while (!_closed) {
      final job = await database.nextDue(DateTime.now());
      if (job == null) {
        final next = await database.earliestPendingAttempt();
        if (next != null) _schedule(next);
        return;
      }
      await _attempt(job);
    }
  }

  Future<void> _attempt(UploadJob job) async {
    final attempts = job.attempts + 1;
    await database.markAttempt(
      id: job.id,
      attempts: attempts,
      nextAttemptAt: DateTime.now().add(uploadBackoff(attempts)),
    );
    try {
      await _send(job);
    } catch (error) {
      final message = '$error';
      if (_isMissingFile(error)) {
        await database.abandon(job.id, message);
      } else {
        await database.setError(job.id, message);
      }
      return;
    }
    await database.deleteJob(job.id);
    await _deleteLocal(job.localPath);
  }

  bool isCancelled(String id) => _cancelled.contains(id);

  /// Drops a capture that the user undid, even if [enqueue] has not finished.
  ///
  /// Call this before waiting on the save. [cancel] then removes the job row.
  void markCancelled(String id) {
    _cancelled.add(id);
  }

  /// Deletes every queued JPEG and its row. Used when the account data goes.
  Future<void> clearLocal() async {
    final jobs = await database.allJobs();
    for (final job in jobs) {
      await _deleteLocal(job.localPath);
    }
    await database.deleteAllJobs();
  }

  /// Removes [id] from the queue and deletes its local JPEG.
  ///
  /// A send that already passed a step deletes the remote object or row
  /// before it returns. See [nextSendAction].
  Future<void> cancel(String id) async {
    markCancelled(id);
    final job = await database.jobById(id);
    await database.deleteJob(id);
    if (job != null) await _deleteLocal(job.localPath);
  }

  Future<void> _send(UploadJob job) async {
    final storagePath = SupabaseService.capturePath(
      userId: job.userId,
      sessionId: job.sessionId,
      captureId: job.id,
    );
    var uploaded = false;
    var inserted = false;
    while (!_closed) {
      final action = nextSendAction(
        cancelled: _cancelled.contains(job.id),
        uploaded: uploaded,
        inserted: inserted,
      );
      switch (action) {
        case SendAction.stop:
          return;
        case SendAction.upload:
          final file = File(job.localPath);
          if (!await file.exists()) {
            throw StateError('The saved photo is missing.');
          }
          final bytes = await file.readAsBytes();
          await service.uploadJpeg(path: storagePath, bytes: bytes);
          uploaded = true;
          break;
        case SendAction.insertRow:
          try {
            await service.insertCapture(
              id: job.id,
              sessionId: job.sessionId,
              storagePath: storagePath,
              yaw: job.yaw,
              pitch: job.pitch,
              roll: job.roll,
              fov: job.fov,
              width: job.width,
              height: job.height,
            );
          } on SupabaseServiceException catch (error) {
            if (!_alreadyStored(error)) rethrow;
          }
          inserted = true;
          break;
        case SendAction.deleteRemote:
          await service.deleteCapture(id: job.id, storagePath: storagePath);
          return;
      }
    }
    throw StateError('Upload stopped before it finished.');
  }

  bool _alreadyStored(SupabaseServiceException error) {
    final cause = error.cause;
    return cause is PostgrestException && cause.code == '23505';
  }

  bool _isMissingFile(Object error) {
    return error is FileSystemException ||
        (error is StateError && error.message.contains('missing'));
  }

  Future<void> _deleteLocal(String path) async {
    final file = File(path);
    if (!await file.exists()) return;
    try {
      await file.delete();
    } on FileSystemException catch (error) {
      lastFailure = error;
    }
  }

  void _schedule(DateTime when) {
    _timer?.cancel();
    if (_closed) return;
    var delay = when.difference(DateTime.now());
    if (delay.isNegative) delay = Duration.zero;
    if (delay > const Duration(days: 1)) delay = const Duration(days: 1);
    _timer = Timer(delay, () {
      unawaited(kick());
    });
  }
}
