import 'dart:async';
import 'dart:math' as math;

import 'package:sensors_plus/sensors_plus.dart';
import 'package:sphere360/services/preview_composite.dart';

/// Smoothed device pose, in degrees, plus how fast it is turning.
class OrientationSample {
  const OrientationSample({
    required this.yaw,
    required this.pitch,
    required this.roll,
    required this.angularSpeed,
  });

  final double yaw;
  final double pitch;
  final double roll;

  /// Magnitude of the gyroscope reading, in degrees per second.
  final double angularSpeed;
}

/// Rotation that takes camera-frame vectors into the world frame.
///
/// Camera axes are right, up, and forward. The device frame used by the
/// Android sensors is right, up, and out of the screen, so the back camera
/// looks along negative device Z.
class Quat {
  const Quat(this.w, this.x, this.y, this.z);

  final double w;
  final double x;
  final double y;
  final double z;

  static const identity = Quat(1, 0, 0, 0);

  Quat normalized() {
    final magnitude = math.sqrt(w * w + x * x + y * y + z * z);
    if (magnitude == 0) return identity;
    return Quat(w / magnitude, x / magnitude, y / magnitude, z / magnitude);
  }

  Quat conjugate() => Quat(w, -x, -y, -z);

  Quat operator *(Quat other) {
    return Quat(
      w * other.w - x * other.x - y * other.y - z * other.z,
      w * other.x + x * other.w + y * other.z - z * other.y,
      w * other.y - x * other.z + y * other.w + z * other.x,
      w * other.z + x * other.y - y * other.x + z * other.w,
    );
  }

  Vec3 rotate(Vec3 vector) {
    final rotated = this * Quat(0, vector.x, vector.y, vector.z) * conjugate();
    return Vec3(rotated.x, rotated.y, rotated.z);
  }

  static Quat fromAxisAngle(Vec3 axis, double radians) {
    final normal = axis.normalized();
    final half = radians / 2;
    final scale = math.sin(half);
    return Quat(
      math.cos(half),
      normal.x * scale,
      normal.y * scale,
      normal.z * scale,
    );
  }

  /// [right], [up], and [forward] are the camera axes in world coordinates.
  static Quat fromBasis(Vec3 right, Vec3 up, Vec3 forward) {
    final m00 = right.x;
    final m01 = up.x;
    final m02 = forward.x;
    final m10 = right.y;
    final m11 = up.y;
    final m12 = forward.y;
    final m20 = right.z;
    final m21 = up.z;
    final m22 = forward.z;
    final trace = m00 + m11 + m22;
    if (trace > 0) {
      final scale = math.sqrt(trace + 1.0) * 2;
      return Quat(
        0.25 * scale,
        (m21 - m12) / scale,
        (m02 - m20) / scale,
        (m10 - m01) / scale,
      ).normalized();
    }
    if (m00 > m11 && m00 > m22) {
      final scale = math.sqrt(1.0 + m00 - m11 - m22) * 2;
      return Quat(
        (m21 - m12) / scale,
        0.25 * scale,
        (m01 + m10) / scale,
        (m02 + m20) / scale,
      ).normalized();
    }
    if (m11 > m22) {
      final scale = math.sqrt(1.0 + m11 - m00 - m22) * 2;
      return Quat(
        (m02 - m20) / scale,
        (m01 + m10) / scale,
        0.25 * scale,
        (m12 + m21) / scale,
      ).normalized();
    }
    final scale = math.sqrt(1.0 + m22 - m00 - m11) * 2;
    return Quat(
      (m10 - m01) / scale,
      (m02 + m20) / scale,
      (m12 + m21) / scale,
      0.25 * scale,
    ).normalized();
  }
}

/// Yaw, pitch, and roll from a camera-to-world quaternion.
///
/// Near ±90° pitch the usual `atan2(forward.x, forward.z)` yaw flips when
/// those components pass through zero. [heldYaw] keeps the last stable
/// heading through that region.
({double yaw, double pitch, double roll, double? heldYaw}) eulerFromQuaternion(
  Quat quaternion, {
  double? heldYaw,
}) {
  final forward = quaternion.rotate(const Vec3(0, 0, 1));
  final up = quaternion.rotate(const Vec3(0, 1, 0));
  final pitch = math.asin(forward.y.clamp(-1.0, 1.0)) * 180 / math.pi;
  final nearPole = forward.y.abs() > math.sin(85 * math.pi / 180);
  final geometricYaw = math.atan2(forward.x, forward.z) * 180 / math.pi;
  final yaw = nearPole && heldYaw != null ? heldYaw : geometricYaw;
  final level = cameraBasis(yaw, pitch, 0);
  final sine = level.up.cross(up).dot(forward);
  final cosine = level.up.dot(up);
  final roll = nearPole ? 0.0 : math.atan2(sine, cosine) * 180 / math.pi;
  return (yaw: yaw, pitch: pitch, roll: roll, heldYaw: yaw);
}

/// Fuses gyroscope and accelerometer into a low-pass filtered pose.
///
/// Samples are produced about every [sampleInterval]. Pitch and roll are
/// pulled toward gravity. Yaw comes from the gyro because the accelerometer
/// cannot see it. Heading is held across the poles so it does not spin.
class OrientationFuser {
  OrientationFuser({
    this.sampleInterval = const Duration(milliseconds: 33),
    this.smoothingSeconds = 0.12,
  });

  final Duration sampleInterval;
  final double smoothingSeconds;

  Quat _orientation = Quat.identity;
  DateTime? _lastGyro;
  DateTime? _lastEmit;
  Vec3? _accel;
  double? _heldYaw;
  double? _yaw;
  double? _pitch;
  double? _roll;
  double? _speed;
  OrientationSample? _pending;
  var _snappedGravity = false;

  OrientationSample? consume() {
    final sample = _pending;
    _pending = null;
    return sample;
  }

  void addAccelerometer(double x, double y, double z, DateTime timestamp) {
    _accel = Vec3(x, y, -z);
    _correctGravity();
    _emit(timestamp);
  }

  void addGyroscope(double x, double y, double z, DateTime timestamp) {
    final previous = _lastGyro;
    _lastGyro = timestamp;
    if (previous != null) {
      final dt = timestamp.difference(previous).inMicroseconds / 1e6;
      if (dt > 0 && dt < 0.2) {
        // Device +X tilts the top of the phone toward the user, which points
        // the back camera up. The body-frame increment treats +X as pitching
        // down, so that rate is negated. Device Z points out of the screen,
        // opposite the camera's forward axis.
        _integrate(-x, y, -z, dt);
        final speed = math.sqrt(x * x + y * y + z * z) * 180 / math.pi;
        _speed = _speed == null ? speed : _speed! + 0.35 * (speed - _speed!);
      }
    }
    _emit(timestamp);
  }

  void _integrate(double wx, double wy, double wz, double dt) {
    final forward = _orientation.rotate(const Vec3(0, 0, 1));
    final nearPole = forward.y.abs() > math.sin(85 * math.pi / 180);
    final speed = math.sqrt(wx * wx + wy * wy + wz * wz);
    if (speed > 1e-8) {
      final axis = Vec3(wx / speed, wy / speed, wz / speed);
      _orientation = (_orientation * Quat.fromAxisAngle(axis, speed * dt))
          .normalized();
    }
    if (nearPole && _heldYaw != null) {
      final worldRate = _orientation.rotate(Vec3(wx, wy, wz));
      _heldYaw = _wrap(_heldYaw! + worldRate.y * dt * 180 / math.pi);
    }
  }

  void _correctGravity() {
    final measured = _accel;
    if (measured == null) return;
    final magnitude = measured.length;
    if (magnitude < 5 || magnitude > 15) return;
    final measuredUp = measured.normalized();
    final expectedUp = _orientation.conjugate().rotate(const Vec3(0, 1, 0));
    final error = expectedUp.cross(measuredUp);
    final sine = error.length;
    if (sine < 1e-6) {
      _snappedGravity = true;
      return;
    }
    final cosine = expectedUp.dot(measuredUp).clamp(-1.0, 1.0);
    final gain = _snappedGravity ? 0.03 : 1.0;
    _snappedGravity = true;
    final correction = Quat.fromAxisAngle(
      error,
      math.atan2(sine, cosine) * gain,
    );
    _orientation = (_orientation * correction).normalized();
  }

  void _emit(DateTime timestamp) {
    if (!_snappedGravity) return;
    if (_lastEmit != null &&
        timestamp.difference(_lastEmit!) < sampleInterval) {
      return;
    }
    _lastEmit = timestamp;
    final euler = eulerFromQuaternion(_orientation, heldYaw: _heldYaw);
    _heldYaw = euler.heldYaw;
    final alpha = _alpha();
    _yaw = _smoothAngle(_yaw, euler.yaw, alpha);
    _pitch = _smooth(_pitch, euler.pitch, alpha);
    _roll = _smoothAngle(_roll, euler.roll, alpha);
    _pending = OrientationSample(
      yaw: _yaw!,
      pitch: _pitch!,
      roll: _roll!,
      angularSpeed: _speed ?? 0,
    );
  }

  double _alpha() {
    final dt = sampleInterval.inMicroseconds / 1e6;
    return dt / (dt + smoothingSeconds);
  }

  double _smooth(double? current, double sample, double alpha) {
    if (current == null) return sample;
    return current + alpha * (sample - current);
  }

  double _smoothAngle(double? current, double sample, double alpha) {
    if (current == null) return _wrap(sample);
    return _wrap(current + alpha * _wrap(sample - current));
  }

  double _wrap(double degrees) {
    var value = degrees % 360;
    if (value > 180) value -= 360;
    if (value <= -180) value += 360;
    return value;
  }
}

/// Sensor streams in, smoothed [OrientationSample]s out, at about 30 Hz.
class OrientationService {
  OrientationService({OrientationFuser? fuser})
    : _fuser = fuser ?? OrientationFuser();

  final OrientationFuser _fuser;
  final _samples = StreamController<OrientationSample>.broadcast();
  StreamSubscription<AccelerometerEvent>? _accelerometer;
  StreamSubscription<GyroscopeEvent>? _gyroscope;
  var _started = false;
  var _disposed = false;

  Stream<OrientationSample> get samples => _samples.stream;

  void start() {
    if (_started || _disposed) return;
    _started = true;
    const period = Duration(milliseconds: 33);
    _accelerometer = accelerometerEventStream(samplingPeriod: period)
        .listen((event) {
          _fuser.addAccelerometer(event.x, event.y, event.z, event.timestamp);
          _publish();
        }, onError: _samples.addError);
    _gyroscope = gyroscopeEventStream(samplingPeriod: period).listen((event) {
      _fuser.addGyroscope(event.x, event.y, event.z, event.timestamp);
      _publish();
    }, onError: _samples.addError);
  }

  void _publish() {
    if (_disposed) return;
    final sample = _fuser.consume();
    if (sample != null) _samples.add(sample);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _accelerometer?.cancel();
    _gyroscope?.cancel();
    _samples.close();
  }
}
