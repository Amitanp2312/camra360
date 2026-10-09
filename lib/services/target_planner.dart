import 'dart:math' as math;

/// One dot on the capture sphere. Angles are degrees.
class SphereTarget {
  const SphereTarget({
    required this.id,
    required this.yaw,
    required this.pitch,
  });

  final int id;

  /// Wrapped to [-180, 180]. Zero is the forward direction at session start.
  final double yaw;

  /// Zero is the horizon. Positive looks up.
  final double pitch;
}

/// Builds the sphere of capture dots.
///
/// Rings sit at pitch 0°, ±40°, and ±75°. The number of dots on a ring is
/// the count that closes the parallel when neighboring shots are
/// `horizontalFov * (1 - overlap)` apart along the sphere, about 20% frame
/// overlap. A 45° horizontal field of view yields 10, 8, 8, 2, and 2 dots.
class TargetPlanner {
  const TargetPlanner({this.overlap = 0.20});

  final double overlap;

  /// Horizontal field of view that produces the 30-dot layout.
  static const referenceHorizontalFov = 45.0;

  static const pitches = <double>[0, 40, -40, 75, -75];

  /// Great-circle step, in degrees, between neighboring shots.
  double alongTrackSpacing(double horizontalFovDegrees) {
    return horizontalFovDegrees * (1 - overlap);
  }

  List<SphereTarget> plan({required double horizontalFovDegrees}) {
    if (horizontalFovDegrees <= 0 || horizontalFovDegrees >= 180) {
      throw ArgumentError.value(
        horizontalFovDegrees,
        'horizontalFovDegrees',
        'Expected a field of view between 0 and 180 degrees.',
      );
    }
    final spacing = alongTrackSpacing(horizontalFovDegrees);
    final targets = <SphereTarget>[];
    for (final pitch in pitches) {
      final count = dotsOnRing(pitchDegrees: pitch, spacingDegrees: spacing);
      final yawStep = 360 / count;
      // Shift the upper rings by half a step so they don't stack on the
      // horizon dots.
      final phase = pitch > 0 ? yawStep / 2 : 0.0;
      for (var i = 0; i < count; i++) {
        targets.add(
          SphereTarget(
            id: targets.length,
            yaw: _wrap(i * yawStep + phase),
            pitch: pitch,
          ),
        );
      }
    }
    return targets;
  }

  /// How many dots fit around the parallel at [pitchDegrees].
  ///
  /// The parallel is shorter than the equator by `cos(pitch)`. Within 20° of
  /// a pole, fewer than three samples collapse to the two-dot cap.
  int dotsOnRing({
    required double pitchDegrees,
    required double spacingDegrees,
  }) {
    final cosine = math
        .cos(pitchDegrees.abs() * math.pi / 180)
        .abs()
        .clamp(0.05, 1.0);
    final raw = 360 * cosine / spacingDegrees;
    if (pitchDegrees.abs() >= 70 && raw < 3) return 2;
    return raw.round().clamp(1, 36);
  }
}

double _wrap(double degrees) {
  var value = degrees % 360;
  if (value > 180) value -= 360;
  if (value <= -180) value += 360;
  return value;
}
