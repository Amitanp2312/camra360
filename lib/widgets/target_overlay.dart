import 'package:flutter/material.dart';
import 'package:sphere360/core/theme.dart';
import 'package:sphere360/services/orientation_service.dart';
import 'package:sphere360/services/preview_composite.dart';
import 'package:sphere360/services/target_planner.dart';

class TargetOverlay extends StatelessWidget {
  const TargetOverlay({
    super.key,
    required this.sample,
    required this.targets,
    required this.horizontalFov,
    required this.pulse,
    this.capturedIds = const {},
  });

  final OrientationSample sample;
  final List<SphereTarget> targets;
  final double horizontalFov;
  final double pulse;
  final Set<int> capturedIds;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _TargetPainter(
        sample: sample,
        targets: targets,
        horizontalFov: horizontalFov,
        pulse: pulse,
        capturedIds: capturedIds,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _PlacedTarget {
  const _PlacedTarget({
    required this.target,
    required this.projection,
    required this.distance,
  });

  final SphereTarget target;
  final ViewportProjection projection;
  final double distance;
}

class _TargetPainter extends CustomPainter {
  _TargetPainter({
    required this.sample,
    required this.targets,
    required this.horizontalFov,
    required this.pulse,
    required this.capturedIds,
  });

  final OrientationSample sample;
  final List<SphereTarget> targets;
  final double horizontalFov;
  final double pulse;
  final Set<int> capturedIds;

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width.round();
    final height = size.height.round();
    if (width < 2 || height < 2) return;

    final basis = cameraBasis(sample.yaw, sample.pitch, sample.roll);
    final look = directionFromYawPitch(sample.yaw, sample.pitch);
    final verticalFov = verticalFovDegrees(
      horizontalFov,
      size.height / size.width,
    );
    final placed = <_PlacedTarget>[
      for (final target in targets)
        _PlacedTarget(
          target: target,
          projection: projectToViewport(
            direction: directionFromYawPitch(target.yaw, target.pitch),
            basis: basis,
            horizontalFovDegrees: horizontalFov,
            verticalFovDegrees: verticalFov,
            imageWidth: width,
            imageHeight: height,
          ),
          distance: angularDistance(
            look,
            directionFromYawPitch(target.yaw, target.pitch),
          ),
        ),
    ];

    _PlacedTarget? active;
    for (final dot in placed) {
      if (capturedIds.contains(dot.target.id)) continue;
      if (active == null || dot.distance < active.distance) active = dot;
    }

    _drawReticle(canvas, size);
    final visibleUncaptured = placed.where((dot) {
      return !capturedIds.contains(dot.target.id) &&
          dot.projection.inside(width, height);
    });
    if (visibleUncaptured.isEmpty && active != null) {
      _drawArrow(canvas, size, active.projection);
    }

    for (final dot in placed) {
      if (!dot.projection.inside(width, height)) continue;
      final captured = capturedIds.contains(dot.target.id);
      final isActive = active?.target.id == dot.target.id;
      _drawDot(
        canvas,
        Offset(dot.projection.x, dot.projection.y),
        captured: captured,
        active: isActive,
      );
    }
  }

  void _drawReticle(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = SphereColors.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    canvas.drawCircle(center, 22, paint);
    canvas.drawLine(
      center + const Offset(-34, 0),
      center + const Offset(-10, 0),
      paint,
    );
    canvas.drawLine(
      center + const Offset(10, 0),
      center + const Offset(34, 0),
      paint,
    );
    canvas.drawLine(
      center + const Offset(0, -34),
      center + const Offset(0, -10),
      paint,
    );
    canvas.drawLine(
      center + const Offset(0, 10),
      center + const Offset(0, 34),
      paint,
    );
  }

  void _drawDot(
    Canvas canvas,
    Offset center, {
    required bool captured,
    required bool active,
  }) {
    final radius = active ? 8 + (4 * pulse) : 7.0;
    final fill = Paint()
      ..color = captured ? SphereColors.captured : Colors.white;
    canvas.drawCircle(center, radius, fill);
    if (active && !captured) {
      final ring = Paint()
        ..color = SphereColors.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawCircle(center, radius + 4, ring);
    }
  }

  /// Points from the reticle toward a target that is off the screen.
  ///
  /// [localX] is camera-right and [localY] is camera-up, including targets
  /// behind the phone, so the arrow still indicates the turn.
  void _drawArrow(Canvas canvas, Size size, ViewportProjection projection) {
    final direction = Offset(projection.localX, -projection.localY);
    if (direction.distance < 1e-6) return;
    final normal = direction / direction.distance;
    final origin = Offset(size.width / 2, size.height / 2);
    final tip = origin + normal * 78;
    final paint = Paint()
      ..color = SphereColors.accent
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(origin + normal * 36, tip, paint);
    final side = Offset(-normal.dy, normal.dx);
    final head = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(
        (tip - normal * 12 + side * 7).dx,
        (tip - normal * 12 + side * 7).dy,
      )
      ..lineTo(
        (tip - normal * 12 - side * 7).dx,
        (tip - normal * 12 - side * 7).dy,
      )
      ..close();
    canvas.drawPath(head, Paint()..color = SphereColors.accent);
  }

  @override
  bool shouldRepaint(_TargetPainter oldDelegate) {
    return oldDelegate.sample != sample ||
        oldDelegate.pulse != pulse ||
        oldDelegate.targets != targets ||
        oldDelegate.capturedIds != capturedIds ||
        oldDelegate.horizontalFov != horizontalFov;
  }
}
