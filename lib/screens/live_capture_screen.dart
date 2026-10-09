import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sphere360/core/constants.dart';
import 'package:sphere360/core/providers.dart';
import 'package:sphere360/core/theme.dart';
import 'package:sphere360/data/app_database.dart';
import 'package:sphere360/models/session.dart';
import 'package:sphere360/screens/viewer_screen.dart';
import 'package:sphere360/services/capture_gate.dart';
import 'package:sphere360/services/device_location.dart';
import 'package:sphere360/services/device_model.dart';
import 'package:sphere360/services/jpeg_resize.dart';
import 'package:sphere360/services/orientation_service.dart';
import 'package:sphere360/services/preview_bitmap.dart';
import 'package:sphere360/services/stitch_service.dart';
import 'package:sphere360/services/supabase_service.dart';
import 'package:sphere360/services/target_planner.dart';
import 'package:sphere360/services/upload_queue.dart';
import 'package:sphere360/widgets/progress_ring.dart';
import 'package:sphere360/widgets/target_overlay.dart';
import 'package:uuid/uuid.dart';

class LiveCaptureScreen extends ConsumerStatefulWidget {
  const LiveCaptureScreen({super.key, this.sessionId});

  /// A session left in `capturing` when the app was last closed.
  ///
  /// Null starts a new session.
  final String? sessionId;

  @override
  ConsumerState<LiveCaptureScreen> createState() => _LiveCaptureScreenState();
}

class _LiveCaptureScreenState extends ConsumerState<LiveCaptureScreen> {
  var _checkingPermission = true;
  var _permanentlyDenied = false;
  String? _permissionError;

  @override
  void initState() {
    super.initState();
    _prepareCamera();
  }

  Future<void> _prepareCamera() async {
    try {
      final status = await Permission.camera.status;
      if (!mounted) return;
      if (status.isGranted) {
        setState(() {
          _checkingPermission = false;
          _permissionError = null;
        });
        return;
      }
      setState(() {
        _checkingPermission = false;
        _permanentlyDenied = status.isPermanentlyDenied;
        _permissionError = status.isPermanentlyDenied
            ? 'Camera access is blocked. Open settings and allow Sphere360 to use the camera.'
            : 'Sphere360 needs the camera to show the live preview and capture each tile.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _checkingPermission = false;
        _permissionError = 'Could not check camera access: $error';
      });
    }
  }

  Future<void> _requestCamera() async {
    try {
      final status = await Permission.camera.request();
      if (!mounted) return;
      setState(() {
        _checkingPermission = false;
        _permanentlyDenied = status.isPermanentlyDenied;
        _permissionError = status.isGranted
            ? null
            : status.isPermanentlyDenied
            ? 'Camera access is blocked. Open settings and allow Sphere360 to use the camera.'
            : 'Sphere360 needs the camera to show the live preview and capture each tile.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _checkingPermission = false;
        _permissionError = 'Could not request camera access: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingPermission) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_permissionError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Live capture')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_permissionError!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _permanentlyDenied
                      ? openAppSettings
                      : _requestCamera,
                  child: Text(
                    _permanentlyDenied ? 'Open settings' : 'Allow camera',
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return _LiveSession(sessionId: widget.sessionId);
  }
}

class _LiveSession extends ConsumerStatefulWidget {
  const _LiveSession({this.sessionId});

  final String? sessionId;

  @override
  ConsumerState<_LiveSession> createState() => _LiveSessionState();
}

class _LiveSessionState extends ConsumerState<_LiveSession>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  CameraController? _camera;
  late final AnimationController _pulse;
  late final AnimationController _flash;
  final _gate = CaptureGate();
  final _captured = <int>{};
  final _shots = <_StoredShot>[];
  String? _sessionId;
  String? _cameraError;
  String? _sessionError;
  String? _lockWarning;
  String? _finishStep;
  double _finishProgress = 0;
  DateTime? _capturedUntil;
  Timer? _capturedTimer;
  Timer? _finishCueTimer;
  var _finishCueVisible = false;
  var _finishCueShown = false;
  var _shutterBusy = false;
  var _shutterToken = 0;
  Future<void> _saveTail = Future<void>.value();
  Future<void> _livePaintTail = Future<void>.value();
  ui.Image? _liveFrame;
  Uint8List? _liveRgba;
  Float32List? _liveWeights;
  StitchResult? _finishedPreview;
  var _finishing = false;
  var _openingSession = false;
  var _undoing = false;
  var _alive = true;
  var _keepLens = false;
  var _permissionRevoked = false;
  var _announcedLivePaintError = false;
  ({String id, int targetId})? _pendingShot;
  var _saveLocation = false;
  var _readingLocation = false;
  var _locationRequest = 0;
  double? _latitude;
  double? _longitude;
  double _lensFov = TargetPlanner.referenceHorizontalFov;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _flash = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    );
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    unawaited(_startCamera());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_openThenLocation());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_recheckPermission());
    }
  }

  Future<void> _recheckPermission() async {
    try {
      final status = await Permission.camera.status;
      if (!_alive) return;
      if (status.isGranted) {
        if (!_permissionRevoked) return;
        setState(() {
          _permissionRevoked = false;
          _cameraError = null;
        });
        unawaited(_startCamera());
        return;
      }
      await _dropCamera();
      if (!_alive) return;
      setState(() {
        _permissionRevoked = true;
        _cameraError = status.isPermanentlyDenied
            ? 'Camera access is blocked. Open settings and allow Sphere360 to use the camera.'
            : 'Camera access was turned off. Allow it to keep capturing.';
      });
    } catch (error) {
      if (!_alive) return;
      setState(() => _cameraError = 'Could not check camera access: $error');
    }
  }

  Future<void> _allowCameraAgain() async {
    try {
      final status = await Permission.camera.request();
      if (!_alive) return;
      if (status.isGranted) {
        setState(() {
          _permissionRevoked = false;
          _cameraError = null;
        });
        unawaited(_startCamera());
        return;
      }
      if (status.isPermanentlyDenied) await openAppSettings();
    } catch (error) {
      if (!_alive) return;
      _showMessage('Could not request camera access: $error');
    }
  }

  Future<void> _openThenLocation() async {
    await _openSession();
    if (!mounted || _sessionId == null) return;
    if (!ref.read(settingsProvider).saveLocation) return;
    await _setSaveLocation(true, skipPrompt: true);
  }

  Future<void> _openSession() async {
    if (_openingSession) return;
    final existing = widget.sessionId;
    if (existing != null) {
      await _loadExistingSession(existing);
      return;
    }
    setState(() {
      _openingSession = true;
      _sessionError = null;
    });
    try {
      final model = await readDeviceModel();
      final session = await ref
          .read(supabaseServiceProvider)
          .createSession(deviceModel: model)
          .timeout(AppConstants.networkTimeout);
      if (!mounted) return;
      setState(() {
        _sessionId = session.id;
        _openingSession = false;
      });
      final latitude = _latitude;
      final longitude = _longitude;
      if (_saveLocation && latitude != null && longitude != null) {
        await _storeLocation(
          DeviceLocation(latitude: latitude, longitude: longitude),
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _openingSession = false;
        _sessionError = 'Could not start the session: $error';
      });
    }
  }

  /// Restores dots and local shots for a session the app did not finish.
  Future<void> _loadExistingSession(String sessionId) async {
    setState(() {
      _openingSession = true;
      _sessionError = null;
      _sessionId = sessionId;
    });
    try {
      final captures = await ref
          .read(supabaseServiceProvider)
          .fetchCaptures(sessionId)
          .timeout(AppConstants.networkTimeout);
      final jobs = await ref.read(appDatabaseProvider).jobsForSession(sessionId);
      if (!mounted) return;
      final byId = <String, _StoredShot>{};
      for (final job in jobs) {
        if (job.status == uploadJobAbandoned) continue;
        byId[job.id] = _StoredShot(
          captureId: job.id,
          localPath: job.localPath,
          yaw: job.yaw,
          pitch: job.pitch,
          roll: job.roll ?? 0,
          fov: job.fov ?? _lensFov,
        );
      }
      for (final capture in captures) {
        byId.putIfAbsent(
          capture.id,
          () => _StoredShot(
            captureId: capture.id,
            localPath: '',
            yaw: capture.yaw,
            pitch: capture.pitch,
            roll: capture.roll ?? 0,
            fov: capture.fov ?? _lensFov,
          ),
        );
      }
      final shots = byId.values.toList();
      final storedFov = shots
          .map((shot) => shot.fov)
          .where((fov) => fov > 0)
          .firstOrNull;
      if (storedFov != null) {
        _keepLens = true;
        _lensFov = storedFov;
        ref.read(liveTargetsProvider.notifier).useLens(storedFov);
      }
      final matches = matchShotsToTargets(
        targets: ref.read(liveTargetsProvider),
        shots: [
          for (final shot in shots) (yaw: shot.yaw, pitch: shot.pitch),
        ],
      );
      final restored = <_StoredShot>[
        for (var i = 0; i < shots.length; i++)
          shots[i].withTarget(matches[i]),
      ];
      setState(() {
        _shots
          ..clear()
          ..addAll(restored);
        _captured
          ..clear()
          ..addAll(matches.whereType<int>());
        _openingSession = false;
      });
      _noteReadyToFinish();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _openingSession = false;
        _sessionError = 'Could not resume the session: $error';
      });
    }
  }

  Future<void> _startCamera() async {
    CameraController? controller;
    try {
      final cameras = await availableCameras();
      if (!_alive) return;
      if (cameras.isEmpty) {
        setState(() => _cameraError = 'No camera was found on this phone.');
        return;
      }
      final back =
          cameras
              .where(
                (camera) => camera.lensDirection == CameraLensDirection.back,
              )
              .firstOrNull ??
          cameras.first;
      final fovFuture = readImageHorizontalFov(
        cameraId: back.name,
        sensorOrientation: back.sensorOrientation,
      );
      controller = CameraController(
        back,
        ResolutionPreset.veryHigh,
        enableAudio: false,
      );
      await controller.initialize();
      if (!_alive) return;
      if (controller.value.previewSize == null) {
        throw CameraException('preview', 'The camera did not produce a frame.');
      }
      final measured = await fovFuture;
      if (!_alive) return;
      final owned = controller;
      _camera = owned;
      controller = null;
      if (!_keepLens) {
        _lensFov = measured ?? TargetPlanner.referenceHorizontalFov;
        ref.read(liveTargetsProvider.notifier).useLens(_lensFov);
      }
      if (mounted) setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_alive || _camera != owned) return;
        unawaited(_lockPreview(owned));
      });
    } on CameraException catch (error) {
      if (!_alive) return;
      setState(() => _cameraError = error.description ?? error.code);
    } catch (error) {
      if (!_alive) return;
      setState(() => _cameraError = '$error');
    } finally {
      final leftover = controller;
      if (leftover != null) await _closeCamera(leftover);
    }
  }

  Future<void> _dropCamera() async {
    final camera = _camera;
    _camera = null;
    if (camera != null) await _closeCamera(camera);
  }

  Future<void> _closeCamera(CameraController camera) async {
    try {
      await camera.dispose();
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'live capture',
          context: ErrorDescription('while closing the camera'),
        ),
      );
    }
  }

  /// Lets autofocus and exposure settle, then locks them for the session.
  ///
  /// Locking on the first frame freezes a soft, unmetered image. A short wait
  /// gives the lens time to focus before the values are held.
  Future<void> _lockPreview(CameraController controller) async {
    try {
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
    } on CameraException catch (error) {
      if (!mounted) return;
      setState(() {
        _lockWarning = error.description ?? 'Could not lock orientation.';
      });
    }
    if (!mounted || _camera != controller) return;
    try {
      await controller.setFocusMode(FocusMode.auto);
    } on CameraException {
      // The phone may already be focusing. The later lock still runs.
    }
    try {
      await controller.setExposureMode(ExposureMode.auto);
    } on CameraException {
      // Metering may already be running. The later lock still runs.
    }
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted || _camera != controller) return;
    await _lockExposureAndFocus(controller);
  }

  /// Locks the values measured on the first preview frame.
  Future<void> _lockExposureAndFocus(CameraController controller) async {
    final messages = <String>[];
    try {
      await controller.setFocusMode(FocusMode.locked);
    } on CameraException catch (error) {
      messages.add(error.description ?? 'Could not lock focus.');
    }
    try {
      await controller.setExposureMode(ExposureMode.locked);
    } on CameraException catch (error) {
      messages.add(error.description ?? 'Could not lock exposure.');
    }
    if (messages.isNotEmpty && mounted) {
      setState(() => _lockWarning = messages.join(' '));
    }
  }

  void _considerCapture(OrientationSample sample) {
    if (_shutterBusy || _finishing || _sessionId == null || _cameraError != null) {
      return;
    }
    final targets = ref.read(liveTargetsProvider);
    final aim = nearestUncapturedTarget(
      yaw: sample.yaw,
      pitch: sample.pitch,
      targets: targets,
      capturedIds: _captured,
    );
    final targetId = _gate.evaluate(
      now: DateTime.now(),
      targetId: aim?.targetId,
      distanceDegrees: aim?.distanceDegrees ?? double.infinity,
      angularSpeedDegreesPerSecond: sample.angularSpeed,
      alreadyCaptured: false,
    );
    if (targetId == null) return;
    final target = targets.where((item) => item.id == targetId).firstOrNull;
    if (target == null) return;
    unawaited(_capture(target, sample));
  }

  Future<void> _capture(SphereTarget target, OrientationSample sample) async {
    final camera = _camera;
    final sessionId = _sessionId;
    final userId = ref.read(authServiceProvider).currentUser?.id;
    final queue = ref.read(uploadQueueProvider);
    if (camera == null || sessionId == null || userId == null) return;
    if (!camera.value.isInitialized || camera.value.isTakingPicture) return;

    final token = ++_shutterToken;
    setState(() {
      _shutterBusy = true;
      _captured.add(target.id);
    });
    try {
      await HapticFeedback.mediumImpact();
    } on PlatformException {
      // Some phones have no vibrator. The shot still saves.
    }
    try {
      await SystemSound.play(SystemSoundType.click);
    } on PlatformException {
      // The shutter flash still marks the shot.
    }
    if (mounted) {
      setState(() {
        _capturedUntil = DateTime.now().add(const Duration(milliseconds: 500));
      });
      _capturedTimer?.cancel();
      _capturedTimer = Timer(const Duration(milliseconds: 500), () {
        if (!mounted) return;
        setState(() => _capturedUntil = null);
      });
      _noteReadyToFinish();
    }
    if (mounted) {
      unawaited(
        _flash.forward(from: 0).then((_) {
          if (mounted) unawaited(_flash.reverse());
        }),
      );
    }

    try {
      final shot = await camera.takePicture();
      final original = await shot.readAsBytes();
      final tempPath = shot.path;
      if (mounted && _shutterToken == token) {
        setState(() => _shutterBusy = false);
      }
      _queueLivePaint(original, sample);
      final captureId = const Uuid().v4();
      _pendingShot = (id: captureId, targetId: target.id);
      final persist = _saveTail.then((_) async {
        if (queue.isCancelled(captureId)) {
          await _deleteTemp(tempPath);
          if (_pendingShot?.id == captureId) _pendingShot = null;
          return;
        }
        final resized = await _fitCapture(original);
        if (queue.isCancelled(captureId)) {
          await _deleteTemp(tempPath);
          if (_pendingShot?.id == captureId) _pendingShot = null;
          return;
        }
        final directory = await getApplicationDocumentsDirectory();
        final folder = Directory(p.join(directory.path, 'captures', sessionId));
        await folder.create(recursive: true);
        final local = File(p.join(folder.path, '$captureId.jpg'));
        await local.writeAsBytes(resized.bytes);
        await _deleteTemp(tempPath);
        if (queue.isCancelled(captureId)) {
          await _deleteTemp(local.path);
          if (_pendingShot?.id == captureId) _pendingShot = null;
          return;
        }
        _shots.add(
          _StoredShot(
            captureId: captureId,
            localPath: local.path,
            yaw: sample.yaw,
            pitch: sample.pitch,
            roll: sample.roll,
            fov: _lensFov,
            targetId: target.id,
          ),
        );
        await queue.enqueue(
          QueuedCapture(
            id: captureId,
            userId: userId,
            sessionId: sessionId,
            localPath: local.path,
            yaw: sample.yaw,
            pitch: sample.pitch,
            roll: sample.roll,
            fov: _lensFov,
            width: resized.width,
            height: resized.height,
          ),
        );
        if (_pendingShot?.id == captureId) _pendingShot = null;
      });
      _saveTail = persist.catchError((Object _) {});
      await persist;
    } catch (error) {
      if (!mounted) return;
      if (_pendingShot?.targetId == target.id) _pendingShot = null;
      setState(() {
        _captured.remove(target.id);
        if (_shutterToken == token) _shutterBusy = false;
      });
      final full = isDiskFull(
        osErrorCode: error is FileSystemException
            ? error.osError?.errorCode
            : null,
        message: '$error',
      );
      _showMessage(
        full
            ? 'Storage is full. Free some space, then aim at that dot again.'
            : 'Could not save that shot: $error',
      );
    }
  }

  /// Keeps a camera JPEG that already fits. Only an oversized photo is decoded.
  Future<JpegResizeResult> _fitCapture(Uint8List bytes) {
    final size = jpegSize(bytes);
    final longest = size == null
        ? 0
        : (size.$1 > size.$2 ? size.$1 : size.$2);
    if (size != null && longest <= AppConstants.captureMaxEdge) {
      return Future.value(
        JpegResizeResult(bytes: bytes, width: size.$1, height: size.$2),
      );
    }
    return compute(
      resizeJpeg,
      JpegResizeRequest(
        bytes: bytes,
        maxEdge: AppConstants.captureMaxEdge,
        quality: AppConstants.captureJpegQuality,
      ),
    );
  }

  Future<void> _deleteTemp(String path) async {
    final file = File(path);
    if (!await file.exists()) return;
    try {
      await file.delete();
    } on FileSystemException {
      // The resized copy is the file that uploads.
    }
  }

  Future<void> _finish() async {
    final sessionId = _sessionId;
    final targets = ref.read(liveTargetsProvider);
    if (sessionId == null || _finishing || targets.isEmpty) return;
    if (_captured.length / targets.length < AppConstants.finishCoverage) return;
    final userId = ref.read(authServiceProvider).currentUser?.id;
    if (userId == null) {
      _showMessage('Sign in before finishing the session.');
      return;
    }
    final service = ref.read(supabaseServiceProvider);
    setState(() {
      _finishing = true;
      _finishStep = 'Reading captures…';
      _finishProgress = 0;
    });
    try {
      await _saveTail;
      if (!_alive) return;
      final stitched = await _readyPreview(service, userId, sessionId);
      if (stitched == null || !_alive) return;
      setState(() {
        _finishStep = 'Uploading the preview…';
        _finishProgress = 1;
      });
      final online = await _networkUp();
      if (!_alive) return;
      if (online == null) {
        setState(() {
          _finishing = false;
          _finishStep = null;
          _finishProgress = 0;
        });
        return;
      }
      if (!online) throw const OfflineFailure();
      final previewPath = SupabaseService.previewPath(
        userId: userId,
        sessionId: sessionId,
      );
      final thumbPath = SupabaseService.thumbPath(
        userId: userId,
        sessionId: sessionId,
      );
      await service.uploadJpeg(path: previewPath, bytes: stitched.preview);
      await service.uploadJpeg(path: thumbPath, bytes: stitched.thumb);
      await service.updateSession(
        sessionId,
        status: SessionStatus.complete,
        completedAt: DateTime.now(),
        previewPath: previewPath,
        thumbPath: thumbPath,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (context) => ViewerScreen(sessionId: sessionId),
        ),
      );
    } on StitchCancelled {
      return;
    } catch (error) {
      if (!_alive) return;
      setState(() {
        _finishing = false;
        _finishStep = null;
        _finishProgress = 0;
      });
      _showMessage(
        error is OfflineFailure
            ? '$error'
            : isOfflineError(error)
            ? const OfflineFailure().toString()
            : 'Could not finish the session: $error',
      );
    }
  }

  /// True when a network is up, false in airplane mode, null when the
  /// check itself failed. A failed check is already shown to the user.
  Future<bool?> _networkUp() async {
    try {
      final results = await Connectivity().checkConnectivity();
      return results.any((result) => result != ConnectivityResult.none);
    } catch (error) {
      if (_alive) {
        _showMessage('Could not check the connection: $error');
      }
      return null;
    }
  }

  Future<StitchResult?> _readyPreview(
    SupabaseService service,
    String userId,
    String sessionId,
  ) async {
    final cached = _finishedPreview;
    if (cached != null) return cached;
    final stitched = await _stitchPreview(service, userId, sessionId);
    if (stitched == null) return null;
    _finishedPreview = stitched;
    return stitched;
  }

  Future<StitchResult?> _stitchPreview(
    SupabaseService service,
    String userId,
    String sessionId,
  ) async {
    final shots = List<_StoredShot>.from(_shots);
    final tiles = <StitchTileBytes>[];
    final skipped = <String>[];
    for (var index = 0; index < shots.length; index++) {
      if (!_alive) throw const StitchCancelled();
      final shot = shots[index];
      try {
        final bytes = await _shotBytes(service, userId, sessionId, shot);
        tiles.add(
          await decodeStitchTile(
            jpeg: bytes,
            yaw: shot.yaw,
            pitch: shot.pitch,
            roll: shot.roll,
            fov: shot.fov,
          ),
        );
      } on StitchCancelled {
        rethrow;
      } catch (error) {
        skipped.add('$error');
      }
      if (!_alive) throw const StitchCancelled();
      setState(() {
        _finishStep = 'Reading captures…';
        _finishProgress = shots.isEmpty ? 0 : (index + 1) / shots.length * 0.2;
      });
    }
    if (tiles.isEmpty) {
      throw StateError(
        skipped.isEmpty
            ? 'No photos are ready to stitch.'
            : 'No photos are ready to stitch. ${skipped.first}',
      );
    }
    if (skipped.isNotEmpty && _alive) {
      final count = skipped.length;
      _showMessage(
        'Skipped $count photo${count == 1 ? '' : 's'} that could not be read.',
      );
    }
    if (!_alive) throw const StitchCancelled();
    setState(() => _finishStep = 'Building the preview…');
    return stitchPanoramaInBackground(
      StitchRequest(
        tiles: tiles,
        outputWidth: ref.read(settingsProvider).previewWidth,
      ),
      (progress) {
        if (!mounted) return;
        setState(() {
          final built = (progress * 100).round();
          _finishStep = 'Building the preview · $built%';
          _finishProgress = 0.2 + progress * 0.8;
        });
      },
      isCancelled: () => !_alive,
    );
  }

  Future<Uint8List> _shotBytes(
    SupabaseService service,
    String userId,
    String sessionId,
    _StoredShot shot,
  ) async {
    final file = File(shot.localPath);
    if (shot.localPath.isNotEmpty && await file.exists()) {
      return file.readAsBytes();
    }
    return service.downloadObject(
      SupabaseService.capturePath(
        userId: userId,
        sessionId: sessionId,
        captureId: shot.captureId,
      ),
    );
  }

  Future<void> _setSaveLocation(bool enabled, {bool skipPrompt = false}) async {
    if (!enabled) {
      _locationRequest++;
      setState(() {
        _saveLocation = false;
        _readingLocation = false;
      });
      if (_latitude != null) {
        _showMessage('Location already saved with this session stays stored.');
      }
      return;
    }

    if (!skipPrompt) {
      final agreed = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            backgroundColor: SphereColors.surface,
            title: const Text('Save location?'),
            content: const Text(
              'Sphere360 can store where this panorama was captured. '
              'It reads your location only after you turn this on.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Not now'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Turn on'),
              ),
            ],
          );
        },
      );
      if (agreed != true || !mounted) return;
    }

    final status = await Permission.locationWhenInUse.request();
    if (!mounted) return;
    if (!status.isGranted) {
      _showMessage(
        status.isPermanentlyDenied
            ? 'Location is blocked. Allow it in settings to save a place.'
            : 'Location stays off until you allow it.',
      );
      if (status.isPermanentlyDenied) await openAppSettings();
      return;
    }

    final request = ++_locationRequest;
    setState(() {
      _saveLocation = true;
      _readingLocation = true;
    });
    try {
      final location = await readDeviceLocation();
      if (!mounted || request != _locationRequest) return;
      if (location == null) {
        setState(() {
          _saveLocation = false;
          _readingLocation = false;
        });
        _showMessage('No location was available. The session is saved without one.');
        return;
      }
      setState(() {
        _latitude = location.latitude;
        _longitude = location.longitude;
        _readingLocation = false;
      });
      await _storeLocation(location);
    } on PlatformException catch (error) {
      if (!mounted || request != _locationRequest) return;
      setState(() {
        _saveLocation = false;
        _readingLocation = false;
      });
      _showMessage(error.message ?? 'Location is unavailable.');
    } on TimeoutException {
      if (!mounted || request != _locationRequest) return;
      setState(() {
        _saveLocation = false;
        _readingLocation = false;
      });
      _showMessage('Location took too long. The session is saved without one.');
    }
  }

  Future<void> _storeLocation(DeviceLocation location) async {
    final sessionId = _sessionId;
    if (sessionId == null || !_saveLocation) return;
    try {
      await ref
          .read(supabaseServiceProvider)
          .updateSession(
            sessionId,
            latitude: location.latitude,
            longitude: location.longitude,
          );
    } catch (error) {
      if (!mounted) return;
      _showMessage('Could not save the location: $error');
    }
  }

  void _noteReadyToFinish() {
    if (_finishCueShown) return;
    final targets = ref.read(liveTargetsProvider);
    if (targets.isEmpty) return;
    if (_captured.length / targets.length < AppConstants.finishCoverage) return;
    _finishCueShown = true;
    setState(() => _finishCueVisible = true);
    _finishCueTimer?.cancel();
    _finishCueTimer = Timer(const Duration(milliseconds: 2500), () {
      if (!mounted) return;
      setState(() => _finishCueVisible = false);
    });
  }

  String? _coachText(OrientationSample sample, List<SphereTarget> targets) {
    if (_finishCueVisible) return 'Ready to finish';
    final aim = nearestUncapturedTarget(
      yaw: sample.yaw,
      pitch: sample.pitch,
      targets: targets,
      capturedIds: _captured,
    );
    if (aim == null) return null;
    final target = targets.where((item) => item.id == aim.targetId).firstOrNull;
    if (target == null) return null;
    return sweepCue(yaw: sample.yaw, pitch: sample.pitch, target: target);
  }

  void _queueLivePaint(Uint8List jpeg, OrientationSample sample) {
    _livePaintTail = _livePaintTail.then((_) => _paintLive(jpeg, sample));
  }

  Future<void> _paintLive(Uint8List jpeg, OrientationSample sample) async {
    try {
      if (!_alive) return;
      final tile = await decodeStitchTile(
        jpeg: jpeg,
        yaw: sample.yaw,
        pitch: sample.pitch,
        roll: sample.roll,
        fov: _lensFov,
        maxEdge: AppConstants.livePreviewSourceMaxEdge,
      );
      if (!_alive) return;
      final painted = await compute(
        paintLiveTile,
        LiveTilePaintRequest(
          tile: tile,
          rgba: _liveRgba,
          bestForward: _liveWeights,
        ),
      );
      if (!_alive) return;
      final frame = await _imageFromRgba(
        painted.rgba,
        painted.width,
        painted.height,
      );
      if (!_alive) {
        frame.dispose();
        return;
      }
      final previous = _liveFrame;
      setState(() {
        _liveRgba = painted.rgba;
        _liveWeights = painted.bestForward;
        _liveFrame = frame;
      });
      previous?.dispose();
    } catch (error) {
      if (!_alive || _announcedLivePaintError) return;
      _announcedLivePaintError = true;
      _showMessage('The live map missed a photo: $error');
    }
  }

  Future<void> _undoLast() async {
    if (_finishing || _undoing) return;
    final pending = _pendingShot;
    final stored = _shots.isEmpty ? null : _shots.last;
    final captureId = pending?.id ?? stored?.captureId;
    final targetId = pending?.targetId ?? stored?.targetId;
    final sessionId = _sessionId;
    if (captureId == null || sessionId == null) return;
    final queue = ref.read(uploadQueueProvider);
    queue.markCancelled(captureId);
    setState(() => _undoing = true);
    try {
      await _saveTail;
      if (!_alive) return;
      await queue.cancel(captureId);
      final userId = ref.read(authServiceProvider).currentUser?.id;
      if (userId != null) {
        await ref.read(supabaseServiceProvider).deleteCapture(
          id: captureId,
          storagePath: SupabaseService.capturePath(
            userId: userId,
            sessionId: sessionId,
            captureId: captureId,
          ),
        );
      }
      if (!_alive) return;
      setState(() {
        _shots.removeWhere((shot) => shot.captureId == captureId);
        if (_pendingShot?.id == captureId) _pendingShot = null;
        if (targetId != null) _captured.remove(targetId);
        _undoing = false;
        _finishedPreview = null;
        if (ref.read(liveTargetsProvider).isEmpty ||
            _captured.length / ref.read(liveTargetsProvider).length <
                AppConstants.finishCoverage) {
          _finishCueVisible = false;
        }
      });
    } catch (error) {
      if (!_alive) return;
      setState(() => _undoing = false);
      _showMessage('Could not undo that shot: $error');
    }
  }

  Future<ui.Image> _imageFromRgba(Uint8List rgba, int width, int height) {
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      width,
      height,
      ui.PixelFormat.rgba8888,
      done.complete,
    );
    return done.future;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _alive = false;
    WidgetsBinding.instance.removeObserver(this);
    _capturedTimer?.cancel();
    _finishCueTimer?.cancel();
    _liveFrame?.dispose();
    _pulse.dispose();
    _flash.dispose();
    final camera = _camera;
    _camera = null;
    if (camera != null) unawaited(_closeCamera(camera));
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final orientation = ref.watch(orientationProvider);
    final targets = ref.watch(liveTargetsProvider);
    final camera = _camera;
    final coverage = targets.isEmpty ? 0.0 : _captured.length / targets.length;
    final canFinish =
        _sessionId != null &&
        !_finishing &&
        !_shutterBusy &&
        coverage >= AppConstants.finishCoverage;

    ref.listen(orientationProvider, (_, next) {
      final sample = next.asData?.value;
      if (sample != null) _considerCapture(sample);
    });

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_cameraError != null && camera == null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _cameraError!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    if (_permissionRevoked) ...[
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _allowCameraAgain,
                        child: const Text('Allow camera'),
                      ),
                    ],
                  ],
                ),
              ),
            )
          else if (camera == null)
            const Center(child: CircularProgressIndicator())
          else
            ValueListenableBuilder<CameraValue>(
              valueListenable: camera,
              builder: (context, value, _) {
                final ready = value.isInitialized && _cameraError == null;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    if (ready)
                      _CoverPreview(controller: camera)
                    else
                      const SizedBox.expand(),
                    if (_cameraError != null)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _cameraError!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      )
                    else if (!value.isInitialized)
                      const Center(child: CircularProgressIndicator())
                    else
                      orientation.when(
                        loading: () => const SizedBox.shrink(),
                        error: (error, _) => Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'Orientation is unavailable: $error',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                        data: (sample) => AnimatedBuilder(
                          animation: _pulse,
                          builder: (context, _) {
                            return TargetOverlay(
                              sample: sample,
                              targets: targets,
                              horizontalFov: _lensFov,
                              pulse: _pulse.value,
                              capturedIds: {..._captured},
                            );
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      _HudButton(
                        tooltip: 'Cancel',
                        icon: Icons.close,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      IconButton(
                        tooltip: _saveLocation
                            ? 'Location on'
                            : 'Save location',
                        onPressed: _finishing
                            ? null
                            : () => _setSaveLocation(!_saveLocation),
                        icon: _readingLocation
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                _saveLocation
                                    ? Icons.place
                                    : Icons.place_outlined,
                                color: _saveLocation
                                    ? SphereColors.accent
                                    : Colors.white,
                              ),
                      ),
                      const Spacer(),
                      orientation.maybeWhen(
                        data: (sample) => Text(
                          'Y ${sample.yaw.toStringAsFixed(0)}°   P ${sample.pitch.toStringAsFixed(0)}°',
                          style: const TextStyle(
                            color: Colors.white,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        orElse: () => const SizedBox.shrink(),
                      ),
                    ],
                  ),
                  const Spacer(),
                  if (_sessionError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TextButton(
                        onPressed: _openSession,
                        child: Text(
                          '$_sessionError\nTap to try again',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  else if (_sessionId == null)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Starting session…',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  if (_lockWarning != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _lockWarning!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: SphereColors.accent),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AspectRatio(
                      aspectRatio: 2,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: ColoredBox(
                          color: Colors.black,
                          child: _liveFrame == null
                              ? const SizedBox.expand()
                              : RawImage(
                                  image: _liveFrame,
                                  fit: BoxFit.fill,
                                ),
                        ),
                      ),
                    ),
                  ),
                  orientation.maybeWhen(
                    data: (sample) {
                      final capturedNow =
                          _capturedUntil != null &&
                          DateTime.now().isBefore(_capturedUntil!);
                      final coach = _coachText(sample, targets);
                      final hold =
                          sample.angularSpeed >=
                          AppConstants.captureMaxAngularSpeed;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          children: [
                            _LevelBar(roll: sample.roll),
                            const SizedBox(height: 8),
                            Text(
                              capturedNow
                                  ? 'Captured'
                                  : hold
                                  ? 'Hold steady'
                                  : 'Steady',
                              style: TextStyle(
                                color: capturedNow || hold
                                    ? SphereColors.accent
                                    : SphereColors.muted,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (coach != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                coach,
                                style: TextStyle(
                                  color: _finishCueVisible
                                      ? SphereColors.accent
                                      : Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                    orElse: () => const SizedBox.shrink(),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        tooltip: 'Undo last shot',
                        onPressed:
                            (_pendingShot != null || _shots.isNotEmpty) &&
                                !_finishing &&
                                !_undoing
                            ? _undoLast
                            : null,
                        icon: const Icon(Icons.undo, color: Colors.white),
                      ),
                      ProgressRing(
                        captured: _captured.length,
                        total: targets.length,
                      ),
                      const SizedBox(width: 20),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(104, 48),
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                        ),
                        onPressed: canFinish ? _finish : null,
                        child: Text(_finishing ? 'Finishing…' : 'Finish'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_finishing)
            ColoredBox(
              color: const Color(0xCC000000),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 96,
                      height: 96,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CircularProgressIndicator(
                            value: _finishProgress.clamp(0, 1),
                            strokeWidth: 6,
                            color: SphereColors.accent,
                            backgroundColor: SphereColors.surfaceHigh,
                          ),
                          Text(
                            '${(_finishProgress * 100).round()}%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _finishStep ?? 'Building the preview…',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          AnimatedBuilder(
            animation: _flash,
            builder: (context, _) {
              final alpha = _flash.value * 0.85;
              if (alpha == 0) return const SizedBox.shrink();
              return IgnorePointer(
                child: ColoredBox(
                  color: Colors.white.withValues(alpha: alpha),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CoverPreview extends StatelessWidget {
  const _CoverPreview({required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final portraitAspect = 1 / controller.value.aspectRatio;
        var width = size.width;
        var height = width / portraitAspect;
        if (height < size.height) {
          height = size.height;
          width = height * portraitAspect;
        }
        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.center,
            minWidth: width,
            maxWidth: width,
            minHeight: height,
            maxHeight: height,
            child: CameraPreview(controller),
          ),
        );
      },
    );
  }
}

class _StoredShot {
  const _StoredShot({
    required this.captureId,
    required this.localPath,
    required this.yaw,
    required this.pitch,
    required this.roll,
    required this.fov,
    this.targetId,
  });

  final String captureId;
  final String localPath;
  final double yaw;
  final double pitch;
  final double roll;
  final double fov;
  final int? targetId;

  _StoredShot withTarget(int? targetId) {
    return _StoredShot(
      captureId: captureId,
      localPath: localPath,
      yaw: yaw,
      pitch: pitch,
      roll: roll,
      fov: fov,
      targetId: targetId,
    );
  }
}

class _HudButton extends StatelessWidget {
  const _HudButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white),
      ),
    );
  }
}

class _LevelBar extends StatelessWidget {
  const _LevelBar({required this.roll});

  final double roll;

  @override
  Widget build(BuildContext context) {
    final level = roll.abs() <= 8;
    final offset = (roll / 30).clamp(-1.0, 1.0).toDouble();
    return SizedBox(
      width: 128,
      height: 16,
      child: CustomPaint(
        painter: _LevelPainter(offset: offset, level: level),
      ),
    );
  }
}

class _LevelPainter extends CustomPainter {
  const _LevelPainter({required this.offset, required this.level});

  final double offset;
  final bool level;

  @override
  void paint(Canvas canvas, Size size) {
    final color = level ? SphereColors.captured : SphereColors.accent;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, size.height / 2 - 2, size.width, 4),
        const Radius.circular(2),
      ),
      Paint()..color = SphereColors.surfaceHigh,
    );
    canvas.drawLine(
      Offset(size.width / 2, 2),
      Offset(size.width / 2, size.height - 2),
      Paint()
        ..color = Colors.white54
        ..strokeWidth = 1,
    );
    final centerX = size.width / 2 + offset * (size.width / 2 - 8);
    canvas.drawCircle(
      Offset(centerX, size.height / 2),
      5,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_LevelPainter oldDelegate) {
    return oldDelegate.offset != offset || oldDelegate.level != level;
  }
}
