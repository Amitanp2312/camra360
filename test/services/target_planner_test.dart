import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sphere360/services/orientation_service.dart';
import 'package:sphere360/services/preview_composite.dart';
import 'package:sphere360/services/target_planner.dart';

void main() {
  const planner = TargetPlanner();

  test('reference field of view places 30 dots on the specified rings', () {
    final targets = planner.plan(
      horizontalFovDegrees: TargetPlanner.referenceHorizontalFov,
    );

    expect(planner.alongTrackSpacing(45), 36);
    expect(targets, hasLength(30));
    expect(_countAt(targets, 0), 10);
    expect(_countAt(targets, 40), 8);
    expect(_countAt(targets, -40), 8);
    expect(_countAt(targets, 75), 2);
    expect(_countAt(targets, -75), 2);
  });

  test(
    'equator dots are evenly spaced and a wider lens uses fewer of them',
    () {
      final reference = planner.plan(horizontalFovDegrees: 45);
      final equator = [
        for (final target in reference)
          if (target.pitch == 0) target,
      ];
      expect(equator.first.yaw, 0);
      expect(equator[1].yaw - equator.first.yaw, closeTo(36, 1e-9));

      final wide = planner.plan(horizontalFovDegrees: 90);
      expect(_countAt(wide, 0), 5);
      expect(wide.length, lessThan(reference.length));
    },
  );

  test('quaternion pose matches the camera basis', () {
    const yaw = 30.0;
    const pitch = 20.0;
    const roll = 10.0;
    final basis = cameraBasis(yaw, pitch, roll);
    final quaternion = Quat.fromBasis(basis.right, basis.up, basis.forward);
    final forward = quaternion.rotate(const Vec3(0, 0, 1));
    final expected = directionFromYawPitch(yaw, pitch);

    expect(forward.x, closeTo(expected.x, 1e-6));
    expect(forward.y, closeTo(expected.y, 1e-6));
    expect(forward.z, closeTo(expected.z, 1e-6));
    expect(quaternion.rotate(const Vec3(0, 1, 0)).y, closeTo(basis.up.y, 1e-6));
  });

  test('tilting the top of the phone toward the user looks up', () {
    final fuser = OrientationFuser(smoothingSeconds: 0.0001);
    final start = DateTime.utc(2026, 10, 8);
    fuser.addAccelerometer(0, 9.8, 0, start);
    fuser.consume();
    fuser.addGyroscope(0.5, 0, 0, start);
    fuser.addGyroscope(0.5, 0, 0, start.add(const Duration(milliseconds: 100)));
    final sample = fuser.consume();

    expect(sample, isNotNull);
    expect(sample!.pitch, greaterThan(1));
  });

  test('heading is held when pitch is near the pole', () {
    final basis = cameraBasis(12, 89, 0);
    final quaternion = Quat.fromBasis(basis.right, basis.up, basis.forward);
    final euler = eulerFromQuaternion(quaternion, heldYaw: 12);

    expect(euler.pitch, closeTo(89, 0.2));
    expect(euler.yaw, 12);
    expect(euler.yaw.isFinite, isTrue);
    expect(euler.pitch.isFinite, isTrue);
  });

  test('a still upright phone reports a level horizon', () {
    final fuser = OrientationFuser();
    final time = DateTime.utc(2026, 10, 8);
    fuser.addAccelerometer(0, 9.8, 0, time);
    final sample = fuser.consume();

    expect(sample, isNotNull);
    expect(sample!.pitch, closeTo(0, 1));
    expect(sample.roll.abs(), lessThan(5));
    expect(sample.yaw.abs(), lessThan(5));
  });

  test('adjacent equator targets are one along-track step apart', () {
    final spacing = planner.alongTrackSpacing(45);
    final left = directionFromYawPitch(0, 0);
    final right = directionFromYawPitch(spacing, 0);
    expect(
      angularDistance(left, right) * 180 / math.pi,
      closeTo(spacing, 1e-6),
    );
  });
}

int _countAt(List<SphereTarget> targets, double pitch) {
  return targets.where((target) => target.pitch == pitch).length;
}
