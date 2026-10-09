import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:panorama_viewer/panorama_viewer.dart';
import 'package:sphere360/core/constants.dart';
import 'package:sphere360/core/providers.dart';
import 'package:sphere360/core/theme.dart';
import 'package:sphere360/models/capture.dart';
import 'package:sphere360/models/hotspot.dart';
import 'package:sphere360/screens/gallery_screen.dart';
import 'package:sphere360/services/gallery_export.dart';
import 'package:sphere360/services/little_planet.dart';
import 'package:sphere360/services/preview_bitmap.dart';
import 'package:sphere360/services/preview_composite.dart';
import 'package:sphere360/services/stitch_service.dart';
import 'package:sphere360/services/supabase_service.dart';
import 'package:sphere360/widgets/little_planet_view.dart';
import 'package:sphere360/widgets/session_card.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ViewerScreen extends ConsumerStatefulWidget {
  const ViewerScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends ConsumerState<ViewerScreen> {
  String _title = 'Panorama';
  String _storedTitle = '';
  String? _previewUrl;
  String? _previewPath;
  Uint8List? _composited;
  List<String> _shotUrls = const [];
  var _showingPanorama = false;
  String? _error;
  String? _status;
  var _loading = true;
  var _started = false;
  var _showLookHint = false;
  var _closed = false;
  var _planet = false;
  var _planetYaw = 0.0;
  var _planetPitch = -math.pi / 2;
  var _planetZoom = 1.0;
  var _exporting = false;
  Uint8List? _equirectBytes;
  Uint8List? _seamBefore;
  var _seamShown = false;
  var _seamBusy = false;
  ui.Image? _planetImage;
  List<CaptureHotspot> _hotspots = const [];
  double? _hintLongitude;
  double? _hintLatitude;

  @override
  void dispose() {
    _closed = true;
    _planetImage?.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _open();
  }

  Future<void> _open() async {
    final service = ref.read(supabaseServiceProvider);
    try {
      setState(() => _status = 'Loading photos…');
      final session = await service
          .fetchSession(widget.sessionId)
          .timeout(AppConstants.networkTimeout);
      final captures = await service
          .fetchCaptures(widget.sessionId)
          .timeout(AppConstants.networkTimeout);
      final signed = await service
          .createSignedUrls([
            for (final capture in captures) capture.storagePath,
          ])
          .timeout(AppConstants.networkTimeout);
      final urls = <String>[
        for (final result in signed)
          if (result is SignedUrlSuccess) result.signedUrl,
      ];
      if (!mounted) return;
      final title = session.title;
      final previewPath = session.previewPath;
      setState(() {
        _storedTitle = title ?? '';
        _title = (title == null || title.isEmpty) ? 'Untitled' : title;
        _shotUrls = urls;
        _previewPath = (previewPath == null || previewPath.isEmpty)
            ? null
            : previewPath;
        _showingPanorama = urls.isEmpty;
        _loading = urls.isEmpty;
        _status = urls.isEmpty ? 'Downloading the preview…' : null;
      });
      if (urls.isEmpty) await _loadPanorama();
      await _loadHotspots();
    } on SupabaseServiceException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
        _status = null;
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _error =
            'The preview took too long to download. Check the connection and try again.';
        _loading = false;
        _status = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
        _status = null;
      });
    }
  }

  Future<void> _openPanorama() async {
    if (_previewUrl != null || _composited != null) {
      setState(() => _showingPanorama = true);
      return;
    }
    setState(() {
      _showingPanorama = true;
      _loading = true;
      _error = null;
      _status = 'Downloading the preview…';
    });
    await _loadPanorama();
  }

  Future<void> _loadPanorama() async {
    final service = ref.read(supabaseServiceProvider);
    try {
      final previewPath = _previewPath;
      if (previewPath != null) {
        final url = await service
            .createSignedUrl(previewPath)
            .timeout(AppConstants.networkTimeout);
        if (!mounted) return;
        setState(() => _status = 'Downloading the preview…');
        await _previewPixelWidth(url);
        if (!mounted) return;
        setState(() {
          _previewUrl = url;
          _loading = false;
          _status = null;
          _showingPanorama = true;
        });
        return;
      }
      await _composite(service);
      if (!mounted) return;
      setState(() => _showingPanorama = true);
    } on SupabaseServiceException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
        _status = null;
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _error =
            'The preview took too long to download. Check the connection and try again.';
        _loading = false;
        _status = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
        _status = null;
      });
    }
  }

  Future<int> _previewPixelWidth(String url) async {
    final stream = NetworkImage(url).resolve(const ImageConfiguration());
    final done = Completer<int>();
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        if (!done.isCompleted) done.complete(info.image.width);
      },
      onError: (error, stackTrace) {
        if (!done.isCompleted) done.completeError(error, stackTrace);
      },
    );
    stream.addListener(listener);
    try {
      return await done.future.timeout(AppConstants.imageDownloadTimeout);
    } finally {
      stream.removeListener(listener);
    }
  }

  Future<void> _composite(SupabaseService service) async {
    if (!mounted || _composited != null || _previewPath != null) return;
    setState(() {
      _loading = true;
      _error = null;
      _status = 'Loading captures…';
    });
    final ({StitchResult result, List<String> failures}) built;
    try {
      built = await _stitchCaptures(
        blend: true,
        onStatus: (status) {
          if (!mounted) return;
          setState(() => _status = status);
        },
      );
    } on StitchCancelled {
      return;
    } on StateError catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
        _status = null;
      });
      return;
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
        _status = null;
      });
      return;
    }
    final stitched = built.result;
    final failures = built.failures;
    final bytes = stitched.preview;
    if (!mounted) return;
    if (failures.isNotEmpty) {
      _showMessage(
        'Skipped ${failures.length} capture${failures.length == 1 ? '' : 's'} that failed to download.',
      );
    }
    setState(() {
      _composited = bytes;
      _loading = false;
      _status = null;
    });
    unawaited(_storePreview(service, stitched));
  }

  Future<({StitchResult result, List<String> failures})> _stitchCaptures({
    required bool blend,
    void Function(String status)? onStatus,
  }) async {
    final service = ref.read(supabaseServiceProvider);
    onStatus?.call('Loading captures…');
    final captures = await service
        .fetchCaptures(widget.sessionId)
        .timeout(AppConstants.networkTimeout);
    if (_closed) throw const StitchCancelled();
    if (captures.isEmpty) {
      throw StateError('This session has no preview and no captures yet.');
    }
    final tiles = <CompositeTile>[];
    final failures = <String>[];
    var next = 0;
    var finished = 0;
    Future<void> worker() async {
      while (next < captures.length && !_closed) {
        final capture = captures[next++];
        await _downloadTile(service, capture, tiles, failures);
        finished++;
        if (!mounted || _closed) return;
        onStatus?.call('Downloading photos $finished of ${captures.length}');
      }
    }

    final workers = captures.length < 2 ? 1 : 2;
    await Future.wait([for (var i = 0; i < workers; i++) worker()]);
    if (_closed) throw const StitchCancelled();
    if (tiles.isEmpty) {
      throw StateError(
        failures.isEmpty ? 'Could not download the captures.' : failures.first,
      );
    }
    onStatus?.call('Building the preview · 0%');
    final bitmaps = <StitchTileBytes>[];
    for (final tile in tiles) {
      if (_closed) throw const StitchCancelled();
      bitmaps.add(
        await decodeStitchTile(
          jpeg: tile.bytes,
          yaw: tile.yaw,
          pitch: tile.pitch,
          roll: tile.roll,
          fov: tile.fov ?? AppConstants.fallbackHorizontalFov,
        ),
      );
    }
    if (_closed) throw const StitchCancelled();
    final result = await stitchPanoramaInBackground(
      StitchRequest(
        tiles: bitmaps,
        outputWidth: ref.read(settingsProvider).previewWidth,
        blend: blend,
      ),
      (progress) {
        final built = (progress * 100).round();
        onStatus?.call('Building the preview · $built%');
      },
      isCancelled: () => _closed,
    );
    return (result: result, failures: failures);
  }

  Future<void> _toggleSeam() async {
    if (_seamShown) {
      setState(() => _seamShown = false);
      return;
    }
    final cached = _seamBefore;
    if (cached != null) {
      setState(() => _seamShown = true);
      return;
    }
    setState(() => _seamBusy = true);
    try {
      final built = await _stitchCaptures(blend: false);
      if (!mounted || _closed) return;
      setState(() {
        _seamBefore = built.result.preview;
        _seamShown = true;
        _seamBusy = false;
      });
    } on StitchCancelled {
      return;
    } catch (error) {
      if (!mounted) return;
      setState(() => _seamBusy = false);
      final message = error is StateError ? error.message : '$error';
      _showMessage('Could not build the unblended panorama: $message');
    }
  }

  Future<void> _storePreview(SupabaseService service, StitchResult stitched) async {
    if (_previewPath != null) return;
    final userId = ref.read(authServiceProvider).currentUser?.id;
    if (userId == null) return;
    try {
      final previewPath = SupabaseService.previewPath(
        userId: userId,
        sessionId: widget.sessionId,
      );
      final thumbPath = SupabaseService.thumbPath(
        userId: userId,
        sessionId: widget.sessionId,
      );
      await service.uploadJpeg(path: previewPath, bytes: stitched.preview);
      await service.uploadJpeg(path: thumbPath, bytes: stitched.thumb);
      await service.updateSession(
        widget.sessionId,
        previewPath: previewPath,
        thumbPath: thumbPath,
      );
      if (!mounted) return;
      setState(() => _previewPath = previewPath);
    } catch (error) {
      if (!mounted) return;
      _showMessage('Could not save the preview: $error');
    }
  }

  Future<void> _downloadTile(
    SupabaseService service,
    Capture capture,
    List<CompositeTile> tiles,
    List<String> failures,
  ) async {
    try {
      final bytes = await _downloadBytes(service, capture.storagePath);
      tiles.add(
        CompositeTile(
          bytes: bytes,
          yaw: capture.yaw,
          pitch: capture.pitch,
          roll: capture.roll ?? 0,
          fov: capture.fov,
          width: capture.width,
          height: capture.height,
        ),
      );
    } on SupabaseServiceException catch (error) {
      failures.add(error.message);
    } on TimeoutException {
      failures.add('One photo did not finish downloading. Try again.');
    }
  }

  Future<Uint8List> _downloadBytes(SupabaseService service, String path) async {
    try {
      return await service
          .downloadObject(path)
          .timeout(AppConstants.imageDownloadTimeout);
    } on TimeoutException {
      return service
          .downloadObject(path)
          .timeout(AppConstants.imageDownloadTimeout);
    }
  }

  Future<void> _rename() async {
    final saved = await showSessionNameDialog(
      context,
      initialName: _storedTitle,
    );
    if (saved == null || !mounted) return;
    try {
      await ref
          .read(supabaseServiceProvider)
          .updateSession(widget.sessionId, title: saved);
      if (!mounted) return;
      setState(() {
        _storedTitle = saved;
        _title = saved;
      });
      ref.read(galleryProvider.notifier).rename(widget.sessionId, saved);
    } on SupabaseServiceException catch (error) {
      _showMessage(error.message);
    } catch (error) {
      _showMessage('$error');
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: SphereColors.surface,
          title: const Text('Delete session?'),
          content: const Text(
            'This removes the session, its captures, and the stored images.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(supabaseServiceProvider).deleteSession(widget.sessionId);
      if (!mounted) return;
      ref.read(galleryProvider.notifier).remove(widget.sessionId);
      Navigator.of(context).pop();
    } on SupabaseServiceException catch (error) {
      _showMessage(error.message);
    } catch (error) {
      _showMessage('$error');
    }
  }

  void _openShot(int index) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _ShotPage(urls: _shotUrls, initialIndex: index),
      ),
    );
  }

  void _revealLookHint() {
    if (!mounted || _showLookHint) return;
    setState(() {
      _showLookHint = true;
      _hintLongitude = null;
      _hintLatitude = null;
    });
  }

  void _onLookAround(double longitude, double latitude, double tilt) {
    if (!_showLookHint || !mounted) return;
    final startLongitude = _hintLongitude;
    final startLatitude = _hintLatitude;
    if (startLongitude == null || startLatitude == null) {
      _hintLongitude = longitude;
      _hintLatitude = latitude;
      return;
    }
    final moved =
        _wrappedDelta(longitude, startLongitude) > 6 ||
        (latitude - startLatitude).abs() > 6;
    if (!moved) return;
    setState(() => _showLookHint = false);
  }

  double _wrappedDelta(double a, double b) {
    var delta = a - b;
    while (delta > 180) {
      delta -= 360;
    }
    while (delta < -180) {
      delta += 360;
    }
    return delta.abs();
  }

  Future<void> _loadHotspots() async {
    try {
      final hotspots = await ref
          .read(supabaseServiceProvider)
          .fetchHotspots(widget.sessionId)
          .timeout(AppConstants.networkTimeout);
      if (!mounted) return;
      setState(() => _hotspots = hotspots);
    } on SupabaseServiceException catch (error) {
      if (!mounted) return;
      _showMessage(error.message);
    } on TimeoutException {
      if (!mounted) return;
      _showMessage('Hotspots took too long to load.');
    } catch (error) {
      if (!mounted) return;
      _showMessage('Could not load hotspots: $error');
    }
  }

  Future<void> _setPlanet(bool planet) async {
    if (!planet) {
      setState(() => _planet = false);
      return;
    }
    if (_planetImage != null) {
      setState(() => _planet = true);
      return;
    }
    setState(() => _exporting = true);
    try {
      final bytes = await _equirect();
      if (!mounted || _closed) return;
      final image = await _decodeEquirect(bytes);
      if (!mounted || _closed) {
        image.dispose();
        return;
      }
      setState(() {
        _planetImage = image;
        _planet = true;
        _exporting = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _exporting = false);
      _showMessage('Could not open the little planet: $error');
    }
  }

  Future<ui.Image> _decodeEquirect(Uint8List jpeg) async {
    final codec = await ui.instantiateImageCodec(jpeg);
    try {
      final frame = await codec.getNextFrame();
      return frame.image;
    } finally {
      codec.dispose();
    }
  }

  Future<Uint8List> _equirect() async {
    final cached = _equirectBytes;
    if (cached != null) return cached;
    final composited = _composited;
    if (composited != null) {
      _equirectBytes = composited;
      return composited;
    }
    final path = _previewPath;
    if (path == null) {
      throw StateError('This session has no panorama yet.');
    }
    final bytes = await ref
        .read(supabaseServiceProvider)
        .downloadObject(path)
        .timeout(AppConstants.imageDownloadTimeout);
    if (_closed) return bytes;
    _equirectBytes = bytes;
    return bytes;
  }

  Future<({Uint8List planet, Uint8List equirect})> _renderedPair() async {
    final equirect = await _equirect();
    final planet = await compute(
      renderPlanetJpeg,
      PlanetExportRequest(
        equirectJpeg: equirect,
        yaw: _planetYaw,
        pitch: _planetPitch,
        zoom: _planetZoom,
      ),
    );
    return (planet: planet, equirect: equirect);
  }

  List<({String name, Uint8List bytes})> _namedPair(
    ({Uint8List planet, Uint8List equirect}) pair,
  ) {
    final stem = _fileStem();
    return [
      (name: '$stem-planet.jpg', bytes: pair.planet),
      (name: '$stem-panorama.jpg', bytes: pair.equirect),
    ];
  }

  String _fileStem() {
    final raw = _storedTitle.trim().isEmpty ? 'Sphere360' : _storedTitle.trim();
    final cleaned = raw.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    if (cleaned.isEmpty) return 'Sphere360';
    return cleaned.length > 40 ? cleaned.substring(0, 40) : cleaned;
  }

  Future<void> _saveGallery() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final files = _namedPair(await _renderedPair());
      if (!mounted || _closed) return;
      await saveJpegsToGallery(files);
      if (!mounted) return;
      _showMessage('Saved the little planet and the panorama to Pictures.');
    } catch (error) {
      if (!mounted) return;
      _showMessage('$error');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _shareImages() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final files = _namedPair(await _renderedPair());
      if (!mounted || _closed) return;
      await shareJpegs(files);
    } catch (error) {
      if (!mounted) return;
      _showMessage('$error');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _shareMenu() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: SphereColors.surface,
          title: const Text('Share'),
          content: const Text(
            'Share the pictures, or a link to the panorama that expires.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop('images'),
              child: const Text('Pictures'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop('day'),
              child: const Text('Link, 24 hours'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop('week'),
              child: const Text('Link, 7 days'),
            ),
          ],
        );
      },
    );
    if (!mounted || choice == null) return;
    if (choice == 'images') {
      await _shareImages();
      return;
    }
    await _shareLink(
      choice == 'week'
          ? AppConstants.shareLinkWeekSeconds
          : AppConstants.shareLinkDaySeconds,
    );
  }

  Future<void> _shareLink(int ttlSeconds) async {
    final path = _previewPath;
    if (path == null) {
      _showMessage('This session has no panorama link yet.');
      return;
    }
    try {
      final url = await ref
          .read(supabaseServiceProvider)
          .createSignedUrl(path, ttlSeconds: ttlSeconds)
          .timeout(AppConstants.networkTimeout);
      if (!mounted) return;
      final action = await showDialog<String>(
        context: context,
        builder: (context) {
          final label = ttlSeconds == AppConstants.shareLinkWeekSeconds
              ? '7 days'
              : '24 hours';
          return AlertDialog(
            backgroundColor: SphereColors.surface,
            title: Text('Link expires in $label'),
            content: SelectableText(url),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop('copy'),
                child: const Text('Copy'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop('share'),
                child: const Text('Share'),
              ),
            ],
          );
        },
      );
      if (!mounted || action == null) return;
      if (action == 'copy') {
        await Clipboard.setData(ClipboardData(text: url));
        if (!mounted) return;
        _showMessage('Link copied.');
        return;
      }
      await shareText(url);
    } on SupabaseServiceException catch (error) {
      if (!mounted) return;
      _showMessage(error.message);
    } on TimeoutException {
      if (!mounted) return;
      _showMessage('The link took too long. Check the connection and try again.');
    } catch (error) {
      if (!mounted) return;
      _showMessage('$error');
    }
  }

  Future<void> _addHotspot(double yaw, double pitch) async {
    final label = await showDialog<String>(
      context: context,
      builder: (context) => const _LabelDialog(),
    );
    if (label == null || !mounted) return;
    try {
      final hotspot = await ref
          .read(supabaseServiceProvider)
          .insertHotspot(
            sessionId: widget.sessionId,
            yaw: yaw,
            pitch: pitch,
            label: label,
          )
          .timeout(AppConstants.networkTimeout);
      if (!mounted) return;
      setState(() => _hotspots = [..._hotspots, hotspot]);
    } on SupabaseServiceException catch (error) {
      if (!mounted) return;
      _showMessage(error.message);
    } catch (error) {
      if (!mounted) return;
      _showMessage('Could not save the hotspot: $error');
    }
  }

  Future<void> _openHotspot(CaptureHotspot hotspot) async {
    final delete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: SphereColors.surface,
          title: Text(hotspot.label),
          content: Text(
            'Yaw ${hotspot.yaw.toStringAsFixed(0)}°, '
            'pitch ${hotspot.pitch.toStringAsFixed(0)}°.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Close'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (delete != true || !mounted) return;
    try {
      await ref
          .read(supabaseServiceProvider)
          .deleteHotspot(hotspot.id)
          .timeout(AppConstants.networkTimeout);
      if (!mounted) return;
      setState(() {
        _hotspots = [
          for (final item in _hotspots)
            if (item.id != hotspot.id) item,
        ];
      });
    } on SupabaseServiceException catch (error) {
      if (!mounted) return;
      _showMessage(error.message);
    } catch (error) {
      if (!mounted) return;
      _showMessage('Could not delete the hotspot: $error');
    }
  }

  Widget _brokenPreview(Object error) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _error != null) return;
      setState(() {
        _error = 'Could not show the panorama: $error';
        _loading = false;
        _status = null;
      });
    });
    return const SizedBox.shrink();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final previewUrl = _previewUrl;
    final composited = _composited;

    return Scaffold(
      appBar: AppBar(
        leading: _showingPanorama && _shotUrls.isNotEmpty
            ? IconButton(
                tooltip: 'Photos',
                onPressed: () => setState(() {
                  _showingPanorama = false;
                  _error = null;
                  _loading = false;
                }),
                icon: const Icon(Icons.arrow_back),
              )
            : null,
        title: Text(_title),
        actions: [
          if (_showingPanorama) ...[
            IconButton(
              tooltip: 'Save to gallery',
              onPressed: _exporting ? null : _saveGallery,
              icon: const Icon(Icons.download),
            ),
            IconButton(
              tooltip: 'Share',
              onPressed: _exporting ? null : _shareMenu,
              icon: const Icon(Icons.share),
            ),
          ],
          SessionMenuButton(onRename: _rename, onDelete: _delete),
        ],
      ),
      body: _loading
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  if (_status != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _status!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: SphereColors.muted),
                    ),
                  ],
                ],
              ),
            )
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () {
                        final planet = _planetImage;
                        setState(() {
                          _loading = true;
                          _error = null;
                          _previewUrl = null;
                          _composited = null;
                          _equirectBytes = null;
                          _seamBefore = null;
                          _seamShown = false;
                          _planetImage = null;
                          _planet = false;
                          _hotspots = const [];
                          _shotUrls = const [];
                          _showingPanorama = false;
                          _showLookHint = false;
                          _hintLongitude = null;
                          _hintLatitude = null;
                        });
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          planet?.dispose();
                        });
                        _open();
                      },
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            )
          : !_showingPanorama
          ? _PhotoGrid(urls: _shotUrls, onOpen: _openShot, onPanorama: _openPanorama)
          : Stack(
              fit: StackFit.expand,
              children: [
                if (_planet && _planetImage != null)
                  LittlePlanetView(
                    image: _planetImage!,
                    yaw: _planetYaw,
                    pitch: _planetPitch,
                    zoom: _planetZoom,
                    hotspots: _hotspots,
                    onView: (yaw, pitch, zoom) {
                      setState(() {
                        _planetYaw = yaw;
                        _planetPitch = pitch;
                        _planetZoom = zoom;
                      });
                    },
                    onLongPress: (yaw, pitch) {
                      unawaited(_addHotspot(yaw, pitch));
                    },
                    onHotspotTap: (hotspot) {
                      unawaited(_openHotspot(hotspot));
                    },
                  )
                else
                  PanoramaViewer(
                    sensorControl: SensorControl.orientation,
                    interactive: true,
                    onImageLoad: _revealLookHint,
                    onViewChanged: _onLookAround,
                    onLongPressEnd: (longitude, latitude, tilt) {
                      unawaited(_addHotspot(longitude, latitude));
                    },
                    hotspots: [
                      for (final hotspot in _hotspots)
                        Hotspot(
                          latitude: hotspot.pitch,
                          longitude: hotspot.yaw,
                          widget: GestureDetector(
                            onTap: () => unawaited(_openHotspot(hotspot)),
                            child: const Icon(Icons.place, color: Colors.amber),
                          ),
                        ),
                    ],
                    child: _seamShown && _seamBefore != null
                        ? Image.memory(
                            _seamBefore!,
                            errorBuilder: (context, error, stackTrace) =>
                                _brokenPreview(error),
                          )
                        : previewUrl != null
                        ? Image.network(
                            previewUrl,
                            errorBuilder: (context, error, stackTrace) =>
                                _brokenPreview(error),
                          )
                        : Image.memory(
                            composited!,
                            errorBuilder: (context, error, stackTrace) =>
                                _brokenPreview(error),
                          ),
                  ),
                Positioned(
                  top: 12,
                  left: 16,
                  right: 16,
                  child: Center(
                    child: SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('360')),
                        ButtonSegment(
                          value: true,
                          label: Text('Little Planet'),
                        ),
                      ],
                      selected: {_planet},
                      onSelectionChanged: _exporting
                          ? null
                          : (next) => unawaited(_setPlanet(next.first)),
                    ),
                  ),
                ),
                if (_showLookHint && !_planet)
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: SafeArea(
                      child: IgnorePointer(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 24),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: const Color(0xCC000000),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              child: Text(
                                'Move the phone to look around.',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (ref.watch(settingsProvider).seamDebug && !_planet)
                  Positioned(
                    top: 64,
                    left: 16,
                    right: 16,
                    child: Center(
                      child: TextButton(
                        onPressed: _seamBusy ? null : () => unawaited(_toggleSeam()),
                        child: Text(_seamShown ? 'After blend' : 'Before blend'),
                      ),
                    ),
                  ),
                if (_exporting || _seamBusy)
                  const ColoredBox(
                    color: Color(0x88000000),
                    child: Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
    );
  }
}

class _PhotoGrid extends StatelessWidget {
  const _PhotoGrid({
    required this.urls,
    required this.onOpen,
    required this.onPanorama,
  });

  final List<String> urls;
  final ValueChanged<int> onOpen;
  final VoidCallback onPanorama;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: urls.length,
            itemBuilder: (context, index) {
              return GestureDetector(
                onTap: () => onOpen(index),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    urls[index],
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return const ColoredBox(
                        color: SphereColors.surface,
                        child: Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      return const ColoredBox(
                        color: SphereColors.surface,
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: SphereColors.muted,
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 52),
              ),
              onPressed: onPanorama,
              child: const Text('View 360°'),
            ),
          ),
        ),
      ],
    );
  }
}

class _ShotPage extends StatefulWidget {
  const _ShotPage({required this.urls, required this.initialIndex});

  final List<String> urls;
  final int initialIndex;

  @override
  State<_ShotPage> createState() => _ShotPageState();
}

class _ShotPageState extends State<_ShotPage> {
  late final PageController _pages = PageController(
    initialPage: widget.initialIndex,
  );

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black),
      body: PageView.builder(
        controller: _pages,
        itemCount: widget.urls.length,
        itemBuilder: (context, index) {
          return InteractiveViewer(
            child: Center(
              child: Image.network(
                widget.urls[index],
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.broken_image_outlined, color: Colors.white70),
                      SizedBox(height: 8),
                      Text(
                        'Could not load this photo.',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ],
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LabelDialog extends StatefulWidget {
  const _LabelDialog();

  @override
  State<_LabelDialog> createState() => _LabelDialogState();
}

class _LabelDialogState extends State<_LabelDialog> {
  final _label = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  void _save() {
    final label = _label.text.trim();
    if (label.isEmpty) {
      setState(() => _error = 'Enter a label.');
      return;
    }
    Navigator.of(context).pop(label);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: SphereColors.surface,
      title: const Text('Hotspot'),
      content: TextField(
        controller: _label,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        maxLength: 80,
        decoration: InputDecoration(
          labelText: 'Label',
          errorText: _error,
        ),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
