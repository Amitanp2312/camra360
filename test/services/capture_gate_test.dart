import 'package:flutter_test/flutter_test.dart';
import 'package:sphere360/core/constants.dart';
import 'package:sphere360/services/capture_gate.dart';
import 'package:sphere360/services/target_planner.dart';

void main() {
  final start = DateTime.utc(2026, 1, 1);

  CaptureGate gate() => CaptureGate();

  test('fires after the aim stays inside the window and slow for the dwell', () {
    final capture = gate();
    final almost = AppConstants.captureDwell - const Duration(milliseconds: 1);
    expect(
      capture.evaluate(
        now: start,
        targetId: 1,
        distanceDegrees: AppConstants.captureAlignDegrees - 0.1,
        angularSpeedDegreesPerSecond: 10,
        alreadyCaptured: false,
      ),
      isNull,
    );
    expect(
      capture.evaluate(
        now: start.add(almost),
        targetId: 1,
        distanceDegrees: 1,
        angularSpeedDegreesPerSecond: 0,
        alreadyCaptured: false,
      ),
      isNull,
    );
    expect(
      capture.evaluate(
        now: start.add(AppConstants.captureDwell),
        targetId: 1,
        distanceDegrees: AppConstants.captureAlignDegrees - 0.1,
        angularSpeedDegreesPerSecond: AppConstants.captureMaxAngularSpeed - 0.1,
        alreadyCaptured: false,
      ),
      1,
    );
  });

  test('a miss at the align limit or the speed limit keeps the shutter closed', () {
    final tooFar = gate();
    tooFar.evaluate(
      now: start,
      targetId: 1,
      distanceDegrees: AppConstants.captureAlignDegrees,
      angularSpeedDegreesPerSecond: 0,
      alreadyCaptured: false,
    );
    expect(
      tooFar.evaluate(
        now: start.add(AppConstants.captureDwell),
        targetId: 1,
        distanceDegrees: AppConstants.captureAlignDegrees,
        angularSpeedDegreesPerSecond: 0,
        alreadyCaptured: false,
      ),
      isNull,
    );

    final tooFast = gate();
    tooFast.evaluate(
      now: start,
      targetId: 1,
      distanceDegrees: 0,
      angularSpeedDegreesPerSecond: AppConstants.captureMaxAngularSpeed,
      alreadyCaptured: false,
    );
    expect(
      tooFast.evaluate(
        now: start.add(AppConstants.captureDwell),
        targetId: 1,
        distanceDegrees: 0,
        angularSpeedDegreesPerSecond: AppConstants.captureMaxAngularSpeed,
        alreadyCaptured: false,
      ),
      isNull,
    );
  });

  test('switching targets or leaving the aim restarts the wait', () {
    final capture = gate();
    final switchedAt = start.add(const Duration(milliseconds: 100));
    capture.evaluate(
      now: start,
      targetId: 1,
      distanceDegrees: 1,
      angularSpeedDegreesPerSecond: 0,
      alreadyCaptured: false,
    );
    capture.evaluate(
      now: switchedAt,
      targetId: 2,
      distanceDegrees: 1,
      angularSpeedDegreesPerSecond: 0,
      alreadyCaptured: false,
    );
    expect(
      capture.evaluate(
        now: switchedAt.add(
          AppConstants.captureDwell - const Duration(milliseconds: 1),
        ),
        targetId: 2,
        distanceDegrees: 1,
        angularSpeedDegreesPerSecond: 0,
        alreadyCaptured: false,
      ),
      isNull,
    );
    expect(
      capture.evaluate(
        now: switchedAt.add(AppConstants.captureDwell),
        targetId: 2,
        distanceDegrees: 1,
        angularSpeedDegreesPerSecond: 0,
        alreadyCaptured: false,
      ),
      2,
    );

    final lost = gate();
    lost.evaluate(
      now: start,
      targetId: 4,
      distanceDegrees: 1,
      angularSpeedDegreesPerSecond: 0,
      alreadyCaptured: false,
    );
    lost.evaluate(
      now: start.add(const Duration(milliseconds: 200)),
      targetId: 4,
      distanceDegrees: 12,
      angularSpeedDegreesPerSecond: 0,
      alreadyCaptured: false,
    );
    expect(
      lost.evaluate(
        now: start.add(const Duration(milliseconds: 500)),
        targetId: 4,
        distanceDegrees: 1,
        angularSpeedDegreesPerSecond: 0,
        alreadyCaptured: false,
      ),
      isNull,
    );
  });

  test('an already captured target does not fire', () {
    expect(
      gate().evaluate(
        now: start.add(AppConstants.captureDwell),
        targetId: 1,
        distanceDegrees: 0,
        angularSpeedDegreesPerSecond: 0,
        alreadyCaptured: true,
      ),
      isNull,
    );
  });

  test('nearest uncaptured target is the smallest angular separation', () {
    const targets = [
      SphereTarget(id: 0, yaw: 0, pitch: 0),
      SphereTarget(id: 1, yaw: 36, pitch: 0),
    ];
    final aimed = nearestUncapturedTarget(
      yaw: 20,
      pitch: 0,
      targets: targets,
      capturedIds: const {},
    );
    expect(aimed?.targetId, 1);

    final remaining = nearestUncapturedTarget(
      yaw: 20,
      pitch: 0,
      targets: targets,
      capturedIds: const {1},
    );
    expect(remaining?.targetId, 0);
    expect(remaining!.distanceDegrees, closeTo(20, 0.01));
  });

  test('sweep cue names the larger turn toward the target', () {
    const target = SphereTarget(id: 1, yaw: 40, pitch: 5);
    expect(sweepCue(yaw: 0, pitch: 0, target: target), 'Turn right 40°');
    expect(
      sweepCue(yaw: 0, pitch: 0, target: const SphereTarget(id: 2, yaw: -30, pitch: 4)),
      'Turn left 30°',
    );
    expect(
      sweepCue(yaw: 0, pitch: 0, target: const SphereTarget(id: 3, yaw: 2, pitch: 18)),
      'Look up 18°',
    );
    expect(
      sweepCue(yaw: 0, pitch: 10, target: const SphereTarget(id: 4, yaw: 1, pitch: -12)),
      'Look down 22°',
    );
    expect(
      sweepCue(yaw: 170, pitch: 0, target: const SphereTarget(id: 5, yaw: -170, pitch: 0)),
      'Turn right 20°',
    );
    expect(
      sweepCue(yaw: 0, pitch: 0, target: const SphereTarget(id: 6, yaw: 1, pitch: 1)),
      'On the dot',
    );
  });

  test('resumed shots claim the nearest free dot inside the align window', () {
    const targets = [
      SphereTarget(id: 0, yaw: 0, pitch: 0),
      SphereTarget(id: 1, yaw: 40, pitch: 0),
    ];
    expect(
      matchShotsToTargets(
        targets: targets,
        shots: [
          (yaw: 1, pitch: 0),
          (yaw: 40, pitch: 1),
          (yaw: 0, pitch: 0),
          (yaw: 90, pitch: 0),
        ],
      ),
      [0, 1, null, null],
    );
  });

  test('a full disk is recognized from the error code or the message', () {
    expect(isDiskFull(osErrorCode: 28), isTrue);
    expect(isDiskFull(osErrorCode: 112), isTrue);
    expect(isDiskFull(message: 'No space left on device'), isTrue);
    expect(isDiskFull(osErrorCode: 13, message: 'Permission denied'), isFalse);
  });

  test('a down radio is an offline finish failure', () {
    expect(isOfflineError(const OfflineFailure()), isTrue);
    expect(
      isOfflineError(Exception('SocketException: Failed host lookup')),
      isTrue,
    );
    expect(isOfflineError(Exception('permission denied')), isFalse);
  });
}
