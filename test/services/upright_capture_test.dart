import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sphere360/services/preview_bitmap.dart';

void main() {
  test('a sideways landscape photo is turned upright', () {
    final rgba = Uint8List.fromList([
      10, 0, 0, 255, // left
      20, 0, 0, 255, // right
    ]);
    final upright = uprightCapturePixels(rgba: rgba, width: 2, height: 1);
    expect(upright.width, 1);
    expect(upright.height, 2);
    expect(upright.rgba[0], 20);
    expect(upright.rgba[4], 10);
  });

  test('a portrait photo stays as it was captured', () {
    final rgba = Uint8List(1 * 2 * 4);
    rgba[0] = 30;
    final upright = uprightCapturePixels(rgba: rgba, width: 1, height: 2);
    expect(upright.width, 1);
    expect(upright.height, 2);
    expect(upright.rgba[0], 30);
  });

  test('a landscape jpeg is decoded upright off the caller', () {
    final source = img.Image(width: 4, height: 2);
    img.fill(source, color: img.ColorRgb8(12, 34, 56));
    final tile = decodeStitchTileSync(
      StitchDecodeRequest(
        jpeg: Uint8List.fromList(img.encodeJpg(source)),
        yaw: 10,
        pitch: -3,
        roll: 1,
        fov: 60,
      ),
    );
    expect(tile.width, 2);
    expect(tile.height, 4);
    expect(tile.yaw, 10);
    expect(tile.rgba.length, 2 * 4 * 4);
  });

  test('a corrupt jpeg throws instead of being skipped', () {
    expect(
      () => decodeStitchTileSync(
        StitchDecodeRequest(
          jpeg: Uint8List(0),
          yaw: 0,
          pitch: 0,
          roll: 0,
          fov: 60,
        ),
      ),
      throwsA(isA<StateError>()),
    );
  });
}
