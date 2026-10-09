import 'package:flutter_test/flutter_test.dart';
import 'package:sphere360/models/session.dart';

void main() {
  test('CaptureSession round-trips json', () {
    final session = CaptureSession(
      id: '11111111-1111-1111-1111-111111111111',
      userId: '22222222-2222-2222-2222-222222222222',
      title: 'Roof',
      startedAt: DateTime.utc(2026, 10, 8, 4),
      completedAt: DateTime.utc(2026, 10, 8, 4, 5),
      status: SessionStatus.complete,
      deviceModel: 'Pixel',
      latitude: 12.5,
      longitude: 77,
      previewPath: 'user/session/preview.jpg',
      thumbPath: 'user/session/thumb.jpg',
    );

    final decoded = CaptureSession.fromJson(session.toJson());

    expect(decoded.id, session.id);
    expect(decoded.userId, session.userId);
    expect(decoded.title, session.title);
    expect(decoded.startedAt, session.startedAt);
    expect(decoded.completedAt, session.completedAt);
    expect(decoded.status, SessionStatus.complete);
    expect(decoded.deviceModel, session.deviceModel);
    expect(decoded.latitude, session.latitude);
    expect(decoded.longitude, 77);
    expect(decoded.previewPath, session.previewPath);
    expect(decoded.thumbPath, session.thumbPath);
  });

  test('CaptureSession accepts integer coordinates from json', () {
    final session = CaptureSession.fromJson({
      'id': 'a',
      'user_id': 'b',
      'status': 'capturing',
      'latitude': 1,
      'longitude': 2,
    });

    expect(session.latitude, 1);
    expect(session.longitude, 2);
    expect(session.status, SessionStatus.capturing);
    expect(session.title, isNull);
  });

  test('CaptureSession rejects an unknown status', () {
    expect(
      () => CaptureSession.fromJson({
        'id': 'a',
        'user_id': 'b',
        'status': 'draft',
      }),
      throwsFormatException,
    );
  });
}
