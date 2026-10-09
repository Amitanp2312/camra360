import 'package:flutter_test/flutter_test.dart';
import 'package:sphere360/models/hotspot.dart';

void main() {
  test('CaptureHotspot reads a row', () {
    final hotspot = CaptureHotspot.fromJson({
      'id': 'h1',
      'session_id': 's1',
      'user_id': 'u1',
      'yaw': 12,
      'pitch': -4.5,
      'label': 'Door',
      'created_at': '2026-01-02T03:04:05Z',
    });
    expect(hotspot.yaw, 12);
    expect(hotspot.pitch, -4.5);
    expect(hotspot.label, 'Door');
    expect(hotspot.createdAt, DateTime.utc(2026, 1, 2, 3, 4, 5));
  });

  test('CaptureHotspot rejects an empty label', () {
    expect(
      () => CaptureHotspot.fromJson({
        'id': 'h1',
        'session_id': 's1',
        'user_id': 'u1',
        'yaw': 0,
        'pitch': 0,
        'label': '',
      }),
      throwsFormatException,
    );
  });
}
