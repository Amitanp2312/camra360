import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sphere360/services/little_planet.dart';

void main() {
  test('looking straight down puts the south pole at the center', () {
    final direction = planetDirection(
      nx: 0,
      ny: 0,
      zoom: 1,
      yaw: 0,
      pitch: -math.pi / 2,
    );
    expect(direction.y, closeTo(-1, 0.001));
    expect(direction.x.abs(), lessThan(0.001));
    expect(direction.z.abs(), lessThan(0.001));
  });

  test('a wider zoom keeps a side point closer to the look axis', () {
    final look = planetDirection(
      nx: 0,
      ny: 0,
      zoom: 1,
      yaw: 0,
      pitch: 0,
    );
    final tight = planetDirection(nx: 0.4, ny: 0, zoom: 2, yaw: 0, pitch: 0);
    final wide = planetDirection(nx: 0.4, ny: 0, zoom: 0.6, yaw: 0, pitch: 0);
    expect(tight.dot(look), greaterThan(wide.dot(look)));
  });

  test('the center of the view projects back to the middle of the screen', () {
    const yaw = 0.4;
    const pitch = -0.8;
    final direction = planetDirection(
      nx: 0,
      ny: 0,
      zoom: 1.2,
      yaw: yaw,
      pitch: pitch,
    );
    final point = planetScreenPoint(
      direction: direction,
      yaw: yaw,
      pitch: pitch,
      zoom: 1.2,
      width: 200,
      height: 100,
    );
    expect(point, isNotNull);
    expect(point!.$1, closeTo(100, 0.5));
    expect(point.$2, closeTo(50, 0.5));
  });

  test('a red panorama stays red at the center of a downward planet', () {
    final source = img.Image(width: 8, height: 4);
    img.fill(source, color: img.ColorRgb8(210, 20, 20));
    final jpeg = renderPlanetJpeg(
      PlanetExportRequest(
        equirectJpeg: Uint8List.fromList(img.encodeJpg(source)),
        yaw: 0,
        pitch: -math.pi / 2,
        zoom: 1,
        size: 8,
        quality: 95,
      ),
    );
    final planet = img.decodeJpg(jpeg)!;
    expect(planet.getPixel(4, 4).r, greaterThan(150));
  });
}
