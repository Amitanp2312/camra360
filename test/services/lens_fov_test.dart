import 'package:flutter_test/flutter_test.dart';
import 'package:sphere360/services/device_model.dart';

void main() {
  test('a portrait sensor uses the vertical field of view across the photo', () {
    final fov = imageHorizontalFov(
      sensorHorizontal: 70,
      sensorVertical: 55,
      sensorOrientation: 90,
    );
    expect(fov, 55);
  });

  test('a landscape sensor keeps its horizontal field of view', () {
    final fov = imageHorizontalFov(
      sensorHorizontal: 70,
      sensorVertical: 55,
      sensorOrientation: 0,
    );
    expect(fov, 70);
  });
}
