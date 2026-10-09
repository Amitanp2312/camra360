import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sphere360/services/stitch_service.dart';

Uint8List _rgba(img.Image image) {
  final bytes = Uint8List(image.width * image.height * 4);
  var offset = 0;
  for (final pixel in image) {
    bytes[offset++] = pixel.r.toInt();
    bytes[offset++] = pixel.g.toInt();
    bytes[offset++] = pixel.b.toInt();
    bytes[offset++] = 255;
  }
  return bytes;
}

StitchTileBytes _tile(img.Image image, {required double yaw, required double fov}) {
  return StitchTileBytes(
    rgba: _rgba(image),
    width: image.width,
    height: image.height,
    yaw: yaw,
    pitch: 0,
    fov: fov,
  );
}

void main() {
  test('a forward tile paints the equirectangular center and a thumb', () {
    final source = img.Image(width: 32, height: 24);
    img.fill(source, color: img.ColorRgb8(210, 30, 20));
    final progress = <double>[];
    final result = stitchPanorama(
      StitchRequest(
        outputWidth: 64,
        thumbWidth: 16,
        tiles: [_tile(source, yaw: 0, fov: 80)],
      ),
      onProgress: progress.add,
    );
    expect(progress, isNotEmpty);
    expect(progress.last, 1);
    expect(progress.first, greaterThan(0));

    final preview = img.decodeJpg(result.preview);
    final thumb = img.decodeJpg(result.thumb);
    expect(preview, isNotNull);
    expect(preview!.width, 64);
    expect(preview.height, 32);
    expect(preview.getPixel(32, 16).r, greaterThan(100));
    expect(preview.getPixel(0, 0).r, lessThan(20));
    expect(thumb, isNotNull);
    expect(thumb!.width, 16);
    expect(thumb.height, 8);
  });

  test('a brighter tile is pulled toward the darker one', () {
    final dark = img.Image(width: 24, height: 18);
    final bright = img.Image(width: 24, height: 18);
    img.fill(dark, color: img.ColorRgb8(40, 40, 40));
    img.fill(bright, color: img.ColorRgb8(220, 220, 220));
    final result = stitchPanorama(
      StitchRequest(
        outputWidth: 96,
        thumbWidth: 8,
        tiles: [
          _tile(dark, yaw: -20, fov: 50),
          _tile(bright, yaw: 20, fov: 50),
        ],
      ),
    );
    final preview = img.decodeJpg(result.preview)!;
    final left = preview.getPixel(43, 24);
    final right = preview.getPixel(53, 24);
    expect(left.r, greaterThan(20));
    expect(right.r, lessThan(200));
    expect(right.r, greaterThan(left.r));
  });

  test('turning blend off leaves the bright tile brighter', () {
    final dark = img.Image(width: 24, height: 18);
    final bright = img.Image(width: 24, height: 18);
    img.fill(dark, color: img.ColorRgb8(40, 40, 40));
    img.fill(bright, color: img.ColorRgb8(220, 220, 220));
    final tiles = [
      _tile(dark, yaw: -20, fov: 50),
      _tile(bright, yaw: 20, fov: 50),
    ];
    final blended = img.decodeJpg(
      stitchPanorama(
        StitchRequest(outputWidth: 96, thumbWidth: 8, tiles: tiles),
      ).preview,
    )!;
    final raw = img.decodeJpg(
      stitchPanorama(
        StitchRequest(
          outputWidth: 96,
          thumbWidth: 8,
          tiles: tiles,
          blend: false,
        ),
      ).preview,
    )!;
    expect(raw.getPixel(53, 24).r, greaterThan(blended.getPixel(53, 24).r));
  });

  test('a live tile paints its place and keeps an older photo', () {
    final red = img.Image(width: 32, height: 24);
    img.fill(red, color: img.ColorRgb8(210, 20, 20));
    final first = paintLiveTile(
      LiveTilePaintRequest(
        width: 64,
        tile: _tile(red, yaw: 0, fov: 80),
      ),
    );
    final center = (16 * first.width + 32) * 4;
    expect(first.rgba[center], greaterThan(100));
    expect(first.rgba[3], 255);
    expect(first.rgba[0], lessThan(20));

    final blue = img.Image(width: 32, height: 24);
    img.fill(blue, color: img.ColorRgb8(20, 20, 210));
    final second = paintLiveTile(
      LiveTilePaintRequest(
        width: 64,
        rgba: first.rgba,
        bestForward: first.bestForward,
        tile: _tile(blue, yaw: 90, fov: 50),
      ),
    );
    expect(second.rgba[center], greaterThan(100));
    expect(second.rgba[center + 2], lessThan(80));
  });

  test('a finished live map encodes once and keeps the painted center', () {
    final red = img.Image(width: 32, height: 24);
    img.fill(red, color: img.ColorRgb8(210, 20, 20));
    final painted = paintLiveTile(
      LiveTilePaintRequest(
        width: 64,
        tile: _tile(red, yaw: 0, fov: 80),
      ),
    );
    final encoded = encodeLivePreview(
      LivePreviewEncodeRequest(rgba: painted.rgba, width: painted.width),
    );
    final preview = img.decodeJpg(encoded.preview)!;
    final thumb = img.decodeJpg(encoded.thumb)!;
    expect(preview.getPixel(32, 16).r, greaterThan(100));
    expect(thumb.width, 64);
  });

  test('a cancelled stitch stops before the isolate starts', () {
    expect(
      stitchPanoramaInBackground(
        const StitchRequest(tiles: []),
        (_) {},
        isCancelled: () => true,
      ),
      throwsA(isA<StitchCancelled>()),
    );
  });
}
