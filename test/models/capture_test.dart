import 'package:flutter_test/flutter_test.dart';
import 'package:sphere360/models/capture.dart';

void main() {
  test('Capture round-trips json', () {
    final capture = Capture(
      id: 'c1',
      sessionId: 's1',
      userId: 'u1',
      storagePath: 'u1/s1/c1.jpg',
      yaw: 36,
      pitch: -40,
      roll: 1.5,
      fov: 70,
      width: 1600,
      height: 1200,
      capturedAt: DateTime.utc(2026, 10, 8, 4, 1),
    );

    final decoded = Capture.fromJson(capture.toJson());

    expect(decoded.id, capture.id);
    expect(decoded.sessionId, capture.sessionId);
    expect(decoded.userId, capture.userId);
    expect(decoded.storagePath, capture.storagePath);
    expect(decoded.yaw, capture.yaw);
    expect(decoded.pitch, capture.pitch);
    expect(decoded.roll, capture.roll);
    expect(decoded.fov, capture.fov);
    expect(decoded.width, capture.width);
    expect(decoded.height, capture.height);
    expect(decoded.capturedAt, capture.capturedAt);
  });

  test('Capture accepts whole-number yaw and pitch', () {
    final capture = Capture.fromJson({
      'id': 'c1',
      'session_id': 's1',
      'user_id': 'u1',
      'storage_path': 'u1/s1/c1.jpg',
      'yaw': 10,
      'pitch': 0,
    });

    expect(capture.yaw, 10);
    expect(capture.pitch, 0);
    expect(capture.roll, isNull);
    expect(capture.width, isNull);
  });

  test('Capture rejects a missing storage path', () {
    expect(
      () => Capture.fromJson({
        'id': 'c1',
        'session_id': 's1',
        'user_id': 'u1',
        'yaw': 0,
        'pitch': 0,
      }),
      throwsFormatException,
    );
  });
}
