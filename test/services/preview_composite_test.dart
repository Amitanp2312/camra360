import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sphere360/services/preview_composite.dart';

void main() {
  test(
    'angular distance is zero for the same direction and 90 degrees apart',
    () {
      final forward = directionFromYawPitch(0, 0);
      final right = directionFromYawPitch(90, 0);

      expect(angularDistance(forward, forward), closeTo(0, 1e-9));
      expect(angularDistance(forward, right), closeTo(math.pi / 2, 1e-9));
    },
  );

  test('the optical axis projects to the image center', () {
    const width = 800;
    const height = 600;
    final basis = cameraBasis(20, -10, 15);
    final projected = projectOntoTile(
      direction: basis.forward,
      basis: basis,
      horizontalFovDegrees: 70,
      verticalFovDegrees: 55,
      imageWidth: width,
      imageHeight: height,
    );

    expect(projected, isNotNull);
    expect(projected!.x, closeTo(width / 2, 1e-6));
    expect(projected.y, closeTo(height / 2, 1e-6));
  });

  test('a ray behind the camera is not projected', () {
    final basis = cameraBasis(0, 0, 0);
    final behind = basis.forward * -1;

    expect(
      projectOntoTile(
        direction: behind,
        basis: basis,
        horizontalFovDegrees: 70,
        verticalFovDegrees: 50,
        imageWidth: 200,
        imageHeight: 150,
      ),
      isNull,
    );
  });

  test('camera axes stay perpendicular at the pole', () {
    final basis = cameraBasis(0, 90, 0);

    expect(basis.forward.y, closeTo(1, 1e-9));
    expect(basis.forward.dot(basis.right), closeTo(0, 1e-9));
    expect(basis.forward.dot(basis.up), closeTo(0, 1e-9));
    expect(basis.right.dot(basis.up), closeTo(0, 1e-9));
    expect(basis.right.length, closeTo(1, 1e-9));
    expect(basis.up.length, closeTo(1, 1e-9));
  });

  test('composite paints a forward tile at the equirectangular center', () {
    final source = img.Image(width: 16, height: 12);
    img.fill(source, color: img.ColorRgb8(220, 20, 20));
    final jpeg = compositePreview(
      CompositeRequest(
        outputWidth: 64,
        tiles: [
          CompositeTile(
            bytes: img.encodeJpg(source),
            yaw: 0,
            pitch: 0,
            fov: 80,
          ),
        ],
      ),
    );

    final decoded = img.decodeJpg(jpeg);
    expect(decoded, isNotNull);
    final center = decoded!.getPixel(32, 16);
    final corner = decoded.getPixel(0, 0);
    expect(center.r, greaterThan(100));
    expect(corner.r, lessThan(20));
  });
}
