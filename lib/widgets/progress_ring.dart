import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sphere360/core/theme.dart';

class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.captured,
    required this.total,
    this.size = 76,
  });

  final int captured;
  final int total;
  final double size;

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : (captured / total).clamp(0.0, 1.0);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(progress: progress),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${(progress * 100).round()}%',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                '$captured/$total',
                style: const TextStyle(
                  color: SphereColors.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.08;
    final rect = Offset.zero & size;
    final inset = rect.deflate(stroke);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = SphereColors.surfaceHigh;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = SphereColors.accent;
    canvas.drawArc(inset, 0, math.pi * 2, false, base);
    canvas.drawArc(inset, -math.pi / 2, math.pi * 2 * progress, false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
