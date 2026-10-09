import 'package:flutter_test/flutter_test.dart';
import 'package:sphere360/services/device_location.dart';

void main() {
  test('parses a latitude and longitude map', () {
    final location = parseDeviceLocation({
      'latitude': 12.5,
      'longitude': 77,
    });

    expect(location, isNotNull);
    expect(location!.latitude, 12.5);
    expect(location.longitude, 77);
  });

  test('rejects a missing or non-numeric location', () {
    expect(parseDeviceLocation(null), isNull);
    expect(parseDeviceLocation({'latitude': '12'}), isNull);
    expect(parseDeviceLocation({'latitude': 1}), isNull);
  });
}
