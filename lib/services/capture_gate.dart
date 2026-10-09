import 'dart:math' as math;

import 'package:sphere360/core/constants.dart';
import 'package:sphere360/services/preview_composite.dart';
import 'package:sphere360/services/target_planner.dart';

/// The closest uncaptured target and how far the phone is aimed from it.
class TargetAim {
  const TargetAim({required this.targetId, required this.distanceDegrees});

  final int targetId;

  /// Great-circle separation between the look direction and the target.
  final double distanceDegrees;
}

/// Closest uncaptured target on the sphere, or null when every target is shot.
///
/// Distance is [angularDistance] converted to degrees: the angle between the
/// phone's look ray and the ray through the target.
TargetAim? nearestUncapturedTarget({
  required double yaw,
  required double pitch,
  required List<SphereTarget> targets,
  required Set<int> capturedIds,
}) {
  final look = directionFromYawPitch(yaw, pitch);
  TargetAim? best;
  for (final target in targets) {
    if (capturedIds.contains(target.id)) continue;
    final degrees =
        angularDistance(look, directionFromYawPitch(target.yaw, target.pitch)) *
        180 /
        math.pi;
    if (best == null || degrees < best.distanceDegrees) {
      best = TargetAim(targetId: target.id, distanceDegrees: degrees);
    }
  }
  return best;
}

/// Which way to turn so [target] comes into the reticle.
///
/// Positive yaw is toward the camera's right, and positive pitch is up.
/// The larger gap is spoken. A gap under 2° in both axes is already on the dot.
String sweepCue({
  required double yaw,
  required double pitch,
  required SphereTarget target,
}) {
  var yawDelta = target.yaw - yaw;
  while (yawDelta > 180) {
    yawDelta -= 360;
  }
  while (yawDelta < -180) {
    yawDelta += 360;
  }
  final pitchDelta = target.pitch - pitch;
  if (yawDelta.abs() < 2 && pitchDelta.abs() < 2) return 'On the dot';
  if (yawDelta.abs() >= pitchDelta.abs()) {
    final degrees = yawDelta.abs().round();
    if (degrees == 0) return 'On the dot';
    return yawDelta > 0 ? 'Turn right $degrees°' : 'Turn left $degrees°';
  }
  final degrees = pitchDelta.abs().round();
  if (degrees == 0) return 'On the dot';
  return pitchDelta > 0 ? 'Look up $degrees°' : 'Look down $degrees°';
}

/// Fires once the phone has been aimed at one target and held still.
///
/// A sample counts when the target is uncaptured, the angular distance is
/// under [AppConstants.captureAlignDegrees], and the turn rate is under
/// [AppConstants.captureMaxAngularSpeed]. The same target must stay in that
/// state for [AppConstants.captureDwell]. Leaving the condition, or switching
/// targets, starts the wait over.
class CaptureGate {
  DateTime? _stableSince;
  int? _targetId;

  /// The target to shoot for this sample, or null when the wait is still open.
  int? evaluate({
    required DateTime now,
    required int? targetId,
    required double distanceDegrees,
    required double angularSpeedDegreesPerSecond,
    required bool alreadyCaptured,
  }) {
    final aligned =
        targetId != null &&
        !alreadyCaptured &&
        distanceDegrees < AppConstants.captureAlignDegrees &&
        angularSpeedDegreesPerSecond < AppConstants.captureMaxAngularSpeed;
    if (!aligned || targetId != _targetId) {
      _targetId = aligned ? targetId : null;
      _stableSince = aligned ? now : null;
      return null;
    }
    final since = _stableSince;
    if (since == null) {
      _stableSince = now;
      return null;
    }
    if (now.difference(since) >= AppConstants.captureDwell) {
      _stableSince = null;
      _targetId = null;
      return targetId;
    }
    return null;
  }
}

/// Which target each resumed shot already covered.
///
/// A shot claims the nearest free target inside [alignDegrees]. A shot
/// farther away claims nothing, so a restored session does not mark a dot
/// the phone never aimed at. The list lines up with [shots].
List<int?> matchShotsToTargets({
  required List<SphereTarget> targets,
  required List<({double yaw, double pitch})> shots,
  double alignDegrees = AppConstants.captureAlignDegrees,
}) {
  final claimed = <int>{};
  final matches = <int?>[];
  for (final shot in shots) {
    final aim = nearestUncapturedTarget(
      yaw: shot.yaw,
      pitch: shot.pitch,
      targets: targets,
      capturedIds: claimed,
    );
    if (aim != null && aim.distanceDegrees < alignDegrees) {
      claimed.add(aim.targetId);
      matches.add(aim.targetId);
    } else {
      matches.add(null);
    }
  }
  return matches;
}

/// True when a failed file write is the disk being full.
///
/// Android reports POSIX `ENOSPC` (28). Windows reports `ERROR_DISK_FULL` (112).
bool isDiskFull({int? osErrorCode, String message = ''}) {
  if (osErrorCode == 28 || osErrorCode == 112) return true;
  final text = message.toLowerCase();
  return text.contains('no space') ||
      text.contains('not enough space') ||
      text.contains('disk full');
}

/// The finish upload could not reach Supabase because the radio is down.
bool isOfflineError(Object error) {
  if (error is OfflineFailure) return true;
  final text = '$error'.toLowerCase();
  return text.contains('socketexception') ||
      text.contains('failed host lookup') ||
      text.contains('network is unreachable') ||
      text.contains('connection abort') ||
      text.contains('connection refused') ||
      text.contains('connection reset') ||
      text.contains('software caused connection abort');
}

/// Finish stitched locally, then found no network for the preview upload.
class OfflineFailure implements Exception {
  const OfflineFailure();

  @override
  String toString() =>
      'No connection. The panorama is ready on this phone. Finish again when you are back online.';
}
