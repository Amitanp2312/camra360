import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:sphere360/core/constants.dart';
import 'package:sphere360/services/stitch_service.dart';

/// JPEG plus the orientation [decodeStitchTile] paints into a tile.
class StitchDecodeRequest {
  const StitchDecodeRequest({
    required this.jpeg,
    required this.yaw,
    required this.pitch,
    required this.roll,
    required this.fov,
    this.maxEdge = AppConstants.stitchSourceMaxEdge,
  });

  final Uint8List jpeg;
  final double yaw;
  final double pitch;
  final double roll;
  final double fov;
  final int maxEdge;
}

/// Decodes a capture JPEG into a small RGBA tile for [stitchPanorama].
///
/// The stored capture stays at camera resolution. Decoding and the upright
/// turn run in a helper isolate so the live overlay keeps drawing.
Future<StitchTileBytes> decodeStitchTile({
  required Uint8List jpeg,
  required double yaw,
  required double pitch,
  required double roll,
  required double fov,
  int maxEdge = AppConstants.stitchSourceMaxEdge,
}) {
  return compute(
    decodeStitchTileSync,
    StitchDecodeRequest(
      jpeg: jpeg,
      yaw: yaw,
      pitch: pitch,
      roll: roll,
      fov: fov,
      maxEdge: maxEdge,
    ),
  );
}

/// Same work as [decodeStitchTile], on the isolate that calls it.
StitchTileBytes decodeStitchTileSync(StitchDecodeRequest request) {
  return _decodeWithDart(
    request.jpeg,
    request.yaw,
    request.pitch,
    request.roll,
    request.fov,
    request.maxEdge,
  );
}

StitchTileBytes _decodeWithDart(
  Uint8List jpeg,
  double yaw,
  double pitch,
  double roll,
  double fov,
  int maxEdge,
) {
  final img.Image decoded;
  try {
    final image = img.decodeJpg(jpeg);
    if (image == null) {
      throw StateError('Could not read the photo.');
    }
    decoded = image;
  } on img.ImageException {
    throw StateError('Could not read the photo.');
  }
  final longest = decoded.width > decoded.height
      ? decoded.width
      : decoded.height;
  final image = longest <= maxEdge
      ? decoded
      : img.copyResize(
          decoded,
          width: (decoded.width * maxEdge / longest).round(),
          height: (decoded.height * maxEdge / longest).round(),
          interpolation: img.Interpolation.linear,
        );
  final rgba = Uint8List(image.width * image.height * 4);
  var offset = 0;
  for (final pixel in image) {
    rgba[offset++] = pixel.r.toInt();
    rgba[offset++] = pixel.g.toInt();
    rgba[offset++] = pixel.b.toInt();
    rgba[offset++] = 255;
  }
  final upright = uprightCapturePixels(
    rgba: rgba,
    width: image.width,
    height: image.height,
  );
  return StitchTileBytes(
    rgba: upright.rgba,
    width: upright.width,
    height: upright.height,
    yaw: yaw,
    pitch: pitch,
    roll: roll,
    fov: fov,
  );
}

/// Packed RGBA for a capture, turned so a portrait shot stands upright.
class UprightPixels {
  const UprightPixels({
    required this.rgba,
    required this.width,
    required this.height,
  });

  final Uint8List rgba;
  final int width;
  final int height;
}

/// The back camera stores a portrait photo on its side, wider than it is tall.
///
/// Turn that buffer 90° counter-clockwise before it is painted into the
/// panorama, so the top of the scene stays at the top of the sphere.
/// A photo that is already taller than it is wide is left as it is.
UprightPixels uprightCapturePixels({
  required Uint8List rgba,
  required int width,
  required int height,
}) {
  if (width < 1 || height < 1 || height >= width) {
    return UprightPixels(rgba: rgba, width: width, height: height);
  }
  final turned = Uint8List(rgba.length);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final nx = y;
      final ny = width - 1 - x;
      final source = (y * width + x) * 4;
      final dest = (ny * height + nx) * 4;
      turned[dest] = rgba[source];
      turned[dest + 1] = rgba[source + 1];
      turned[dest + 2] = rgba[source + 2];
      turned[dest + 3] = rgba[source + 3];
    }
  }
  return UprightPixels(rgba: turned, width: height, height: width);
}
