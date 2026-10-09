import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:sphere360/models/hotspot.dart';
import 'package:sphere360/services/little_planet.dart';
import 'package:sphere360/services/preview_composite.dart';

/// Stereographic little planet. Pinch zooms, one finger turns the view.
class LittlePlanetView extends StatefulWidget {
  const LittlePlanetView({
    super.key,
    required this.image,
    required this.yaw,
    required this.pitch,
    required this.zoom,
    required this.onView,
    required this.hotspots,
    required this.onLongPress,
    required this.onHotspotTap,
  });

  final ui.Image image;

  /// Radians.
  final double yaw;
  final double pitch;
  final double zoom;

  final void Function(double yaw, double pitch, double zoom) onView;

  final List<CaptureHotspot> hotspots;

  /// Yaw and pitch in degrees where the finger pressed.
  final void Function(double yaw, double pitch) onLongPress;

  final ValueChanged<CaptureHotspot> onHotspotTap;

  @override
  State<LittlePlanetView> createState() => _LittlePlanetViewState();
}

class _LittlePlanetViewState extends State<LittlePlanetView> {
  ui.FragmentProgram? _program;
  ui.FragmentShader? _shader;
  Object? _loadError;
  var _zoomAtStart = 1.0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final program = await ui.FragmentProgram.fromAsset('shaders/planet.frag');
      if (!mounted) return;
      setState(() {
        _program = program;
        _shader = program.fragmentShader();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadError = error);
    }
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  void _onScaleStart(ScaleStartDetails details) {
    _zoomAtStart = widget.zoom;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount >= 2) {
      widget.onView(
        widget.yaw,
        widget.pitch,
        (_zoomAtStart * details.scale).clamp(0.35, 5).toDouble(),
      );
      return;
    }
    widget.onView(
      widget.yaw + details.focalPointDelta.dx * 0.006,
      (widget.pitch - details.focalPointDelta.dy * 0.006).clamp(
        -1.57079632679,
        1.57079632679,
      ),
      widget.zoom,
    );
  }

  void _onLongPressEnd(LongPressEndDetails details, Size size) {
    final aspect = size.width / size.height;
    final nx = ((details.localPosition.dx / size.width) * 2 - 1) * aspect;
    final ny = -((details.localPosition.dy / size.height) * 2 - 1);
    final direction = planetDirection(
      nx: nx,
      ny: ny,
      zoom: widget.zoom,
      yaw: widget.yaw,
      pitch: widget.pitch,
    );
    final angles = yawPitchFromDirection(direction);
    widget.onLongPress(angles.yaw, angles.pitch);
  }

  @override
  Widget build(BuildContext context) {
    final error = _loadError;
    final shader = _shader;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Could not show the little planet: $error',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (shader == null || _program == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return GestureDetector(
          onScaleStart: _onScaleStart,
          onScaleUpdate: _onScaleUpdate,
          onLongPressEnd: (details) => _onLongPressEnd(details, size),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(
                painter: _PlanetPainter(
                  shader: shader,
                  image: widget.image,
                  yaw: widget.yaw,
                  pitch: widget.pitch,
                  zoom: widget.zoom,
                ),
                child: const SizedBox.expand(),
              ),
              for (final hotspot in widget.hotspots)
                _marker(size, hotspot),
            ],
          ),
        );
      },
    );
  }

  Widget _marker(Size size, CaptureHotspot hotspot) {
    final point = planetScreenPoint(
      direction: directionFromYawPitch(hotspot.yaw, hotspot.pitch),
      yaw: widget.yaw,
      pitch: widget.pitch,
      zoom: widget.zoom,
      width: size.width,
      height: size.height,
    );
    if (point == null) return const SizedBox.shrink();
    return Positioned(
      left: point.$1 - 16,
      top: point.$2 - 16,
      width: 32,
      height: 32,
      child: GestureDetector(
        onTap: () => widget.onHotspotTap(hotspot),
        child: const Icon(Icons.place, color: Colors.amber),
      ),
    );
  }
}

class _PlanetPainter extends CustomPainter {
  _PlanetPainter({
    required this.shader,
    required this.image,
    required this.yaw,
    required this.pitch,
    required this.zoom,
  });

  final ui.FragmentShader shader;
  final ui.Image image;
  final double yaw;
  final double pitch;
  final double zoom;

  @override
  void paint(Canvas canvas, Size size) {
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, zoom)
      ..setFloat(3, yaw)
      ..setFloat(4, pitch)
      ..setImageSampler(0, image);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_PlanetPainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.yaw != yaw ||
        oldDelegate.pitch != pitch ||
        oldDelegate.zoom != zoom;
  }
}
