import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:sphere360/core/constants.dart';
import 'package:sphere360/services/preview_composite.dart';

/// JPEG bytes for `preview.jpg` and `thumb.jpg`.
class StitchResult {
  const StitchResult({required this.preview, required this.thumb});

  final Uint8List preview;
  final Uint8List thumb;
}

/// One tile already decoded to packed RGBA.
class StitchTileBytes {
  const StitchTileBytes({
    required this.rgba,
    required this.width,
    required this.height,
    required this.yaw,
    required this.pitch,
    this.roll = 0,
    required this.fov,
  });

  final Uint8List rgba;
  final int width;
  final int height;
  final double yaw;
  final double pitch;
  final double roll;
  final double fov;
}

/// Tiles and output size for [stitchPanorama].
///
/// [outputWidth] is the equirectangular width. Height is half of that.
class StitchRequest {
  const StitchRequest({
    required this.tiles,
    this.outputWidth = AppConstants.previewWidthStandard,
    this.previewQuality = AppConstants.stitchPreviewQuality,
    this.thumbWidth = AppConstants.stitchThumbWidth,
    this.blend = true,
  });

  final List<StitchTileBytes> tiles;
  final int outputWidth;
  final int previewQuality;
  final int thumbWidth;

  /// Exposure match and edge feather. Off is the unblended seam comparison.
  final bool blend;
}

/// Builds one equirectangular panorama from oriented tiles.
///
/// For each covered output pixel, the direction on the sphere is projected
/// into the tile. Samples are bilinear. Overlap blends by a weight that is
/// strongest on the optical axis and falls off at the photo edge. Each tile
/// is scaled so its center brightness matches the session average.
///
/// Call this through [stitchPanoramaInBackground] so the pixel loop stays
/// off the UI isolate. [onProgress] receives `0` to `1` as rows are painted
/// and the JPEG is encoded.
StitchResult stitchPanorama(
  StitchRequest request, {
  void Function(double progress)? onProgress,
}) {
  final tiles = <_StitchTile>[];
  for (final tile in request.tiles) {
    if (tile.width < 2 || tile.height < 2) continue;
    if (tile.rgba.length < tile.width * tile.height * 4) continue;
    final aspect = tile.height / tile.width;
    final horizontalFov = tile.fov;
    final basis = cameraBasis(tile.yaw, tile.pitch, tile.roll);
    tiles.add(
      _StitchTile(
        rgba: tile.rgba,
        width: tile.width,
        height: tile.height,
        basis: basis,
        yaw: tile.yaw,
        pitch: tile.pitch,
        horizontalFov: horizontalFov,
        verticalFov: verticalFovDegrees(horizontalFov, aspect),
        luma: _centerLuma(tile.rgba, tile.width, tile.height),
        halfWidth: tile.width / 2,
        halfHeight: tile.height / 2,
        feather: request.blend,
      ),
    );
  }
  if (tiles.isEmpty) {
    throw StateError('No capture images could be decoded.');
  }

  final reference =
      tiles.fold<double>(0, (sum, tile) => sum + tile.luma) / tiles.length;
  for (final tile in tiles) {
    final safe = tile.luma < 1 ? 1.0 : tile.luma;
    tile.gain = request.blend ? (reference / safe).clamp(0.55, 1.8) : 1;
    final horizontal = tile.horizontalFov * math.pi / 180;
    final vertical = tile.verticalFov * math.pi / 180;
    tile.focalX = tile.halfWidth / math.tan(horizontal / 2);
    tile.focalY = tile.halfHeight / math.tan(vertical / 2);
  }

  final width = request.outputWidth < 2 ? 2 : request.outputWidth;
  final height = width ~/ 2;
  final canvas = Uint8List(width * height * 3);
  const stripHeight = 64;
  final stripPixels = stripHeight * width;
  final sumR = Float32List(stripPixels);
  final sumG = Float32List(stripPixels);
  final sumB = Float32List(stripPixels);
  final sumW = Float32List(stripPixels);

  for (var y0 = 0; y0 < height; y0 += stripHeight) {
    final rows = math.min(stripHeight, height - y0);
    final count = rows * width;
    sumR.fillRange(0, count, 0);
    sumG.fillRange(0, count, 0);
    sumB.fillRange(0, count, 0);
    sumW.fillRange(0, count, 0);
    for (final tile in tiles) {
      _accumulateTile(
        tile: tile,
        width: width,
        height: height,
        y0: y0,
        rows: rows,
        sumR: sumR,
        sumG: sumG,
        sumB: sumB,
        sumW: sumW,
      );
    }
    for (var row = 0; row < rows; row++) {
      final y = y0 + row;
      final canvasRow = y * width * 3;
      final stripRow = row * width;
      for (var x = 0; x < width; x++) {
        final weight = sumW[stripRow + x];
        if (weight <= 1e-4) continue;
        final offset = canvasRow + x * 3;
        canvas[offset] = (sumR[stripRow + x] / weight).round().clamp(0, 255);
        canvas[offset + 1] = (sumG[stripRow + x] / weight).round().clamp(0, 255);
        canvas[offset + 2] = (sumB[stripRow + x] / weight).round().clamp(0, 255);
      }
    }
    onProgress?.call((y0 + rows) / height * 0.9);
  }

  onProgress?.call(0.9);
  final encoded = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: canvas.buffer,
    numChannels: 3,
  );
  final preview = img.encodeJpg(encoded, quality: request.previewQuality);
  final thumbWidth = math.min(request.thumbWidth, width);
  final thumb = img.copyResize(
    encoded,
    width: thumbWidth,
    height: math.max(1, thumbWidth ~/ 2),
    interpolation: img.Interpolation.linear,
  );
  final result = StitchResult(
    preview: preview,
    thumb: img.encodeJpg(thumb, quality: request.previewQuality),
  );
  onProgress?.call(1);
  return result;
}

/// The caller left the screen, or asked the stitch to stop.
class StitchCancelled implements Exception {
  const StitchCancelled();
}

/// Runs [stitchPanorama] on a background isolate and reports progress.
///
/// The isolate is killed when this future ends, including when [isCancelled]
/// reports that the screen is gone.
Future<StitchResult> stitchPanoramaInBackground(
  StitchRequest request,
  void Function(double progress) onProgress, {
  bool Function()? isCancelled,
}) async {
  if (isCancelled?.call() == true) throw const StitchCancelled();
  final receive = ReceivePort();
  Isolate? isolate;
  try {
    isolate = await Isolate.spawn(_stitchPanoramaEntry, <Object>[
      receive.sendPort,
      request,
    ]);
    await for (final message in receive) {
      if (isCancelled?.call() == true) throw const StitchCancelled();
      if (message is double) {
        onProgress(message.clamp(0, 1).toDouble());
        continue;
      }
      if (message is StitchResult) return message;
      throw StateError('$message');
    }
  } on StitchCancelled {
    rethrow;
  } catch (error) {
    if (isCancelled?.call() == true) throw const StitchCancelled();
    rethrow;
  } finally {
    isolate?.kill(priority: Isolate.immediate);
    receive.close();
  }
  throw StateError('The preview stitch stopped before it finished.');
}

void _stitchPanoramaEntry(List<Object> message) {
  final send = message[0] as SendPort;
  final request = message[1] as StitchRequest;
  try {
    final result = stitchPanorama(
      request,
      onProgress: (progress) => send.send(progress),
    );
    send.send(result);
  } catch (error) {
    send.send('$error');
  }
}

class _StitchTile {
  _StitchTile({
    required this.rgba,
    required this.width,
    required this.height,
    required this.basis,
    required this.yaw,
    required this.pitch,
    required this.horizontalFov,
    required this.verticalFov,
    required this.luma,
    required this.halfWidth,
    required this.halfHeight,
    required this.feather,
  });

  final Uint8List rgba;
  final int width;
  final int height;
  final CameraBasis basis;
  final double yaw;
  final double pitch;
  final double horizontalFov;
  final double verticalFov;
  final double luma;
  final double halfWidth;
  final double halfHeight;
  final bool feather;
  double gain = 1;
  double focalX = 1;
  double focalY = 1;
}

/// Mean luminance of the middle of the photo, sampled on a coarse grid.
double _centerLuma(Uint8List rgba, int width, int height) {
  final x0 = width ~/ 4;
  final x1 = math.max(x0 + 1, width * 3 ~/ 4);
  final y0 = height ~/ 4;
  final y1 = math.max(y0 + 1, height * 3 ~/ 4);
  final stepX = math.max(1, (x1 - x0) ~/ 16);
  final stepY = math.max(1, (y1 - y0) ~/ 16);
  var sum = 0.0;
  var count = 0;
  for (var y = y0; y < y1; y += stepY) {
    for (var x = x0; x < x1; x += stepX) {
      final index = (y * width + x) * 4;
      sum += 0.2126 * rgba[index] + 0.7152 * rgba[index + 1] + 0.0722 * rgba[index + 2];
      count++;
    }
  }
  return count == 0 ? 1 : sum / count;
}

/// 1 across the middle of the frame, easing to 0 at the border.
///
/// The faded rim is the outer part of the frame, inside the planned overlap,
/// so a neighbor's center covers the seam.
double _edgeFeather(double x, double y, int width, int height) {
  final nx = ((x / (width - 1)) * 2 - 1).abs();
  final ny = ((y / (height - 1)) * 2 - 1).abs();
  final edge = math.max(nx, ny);
  const start = 0.6;
  if (edge <= start) return 1;
  if (edge >= 1) return 0;
  final t = (edge - start) / (1 - start);
  return 1 - (t * t * (3 - 2 * t));
}

void _accumulateTile({
  required _StitchTile tile,
  required int width,
  required int height,
  required int y0,
  required int rows,
  required Float32List sumR,
  required Float32List sumG,
  required Float32List sumB,
  required Float32List sumW,
}) {
  final halfDiagonal = math.atan(
    math.sqrt(
      math.pow(math.tan(tile.horizontalFov * math.pi / 360), 2) +
          math.pow(math.tan(tile.verticalFov * math.pi / 360), 2),
    ),
  );
  final pitchScale = math.max(0.2, math.cos(tile.pitch * math.pi / 180));
  final yawHalf = (halfDiagonal * 180 / math.pi) / pitchScale;
  final pitchHalf = halfDiagonal * 180 / math.pi;
  final centerX = ((tile.yaw + 180) / 360) * width;
  final centerY = ((90 - tile.pitch) / 180) * height;
  final halfPixelsX = yawHalf / 360 * width + 1;
  final halfPixelsY = pitchHalf / 180 * height + 1;
  final tileY0 = math.max(0, (centerY - halfPixelsY).floor());
  final tileY1 = math.min(height, (centerY + halfPixelsY).ceil());
  final yStart = math.max(y0, tileY0);
  final yEnd = math.min(y0 + rows, tileY1);
  if (yStart >= yEnd) return;

  final x0 = (centerX - halfPixelsX).floor();
  final x1 = (centerX + halfPixelsX).ceil();
  final yawScale = math.pi * 2 / width;
  final pitchScaleY = math.pi / height;

  void paintColumns(int start, int end) {
    for (var y = yStart; y < yEnd; y++) {
      final pitch = math.pi / 2 - y * pitchScaleY;
      final cp = math.cos(pitch);
      final sp = math.sin(pitch);
      for (var x = start; x < end; x++) {
        _accumulatePixel(
          tile: tile,
          width: width,
          x: x,
          y: y,
          stripY: y0,
          cp: cp,
          sp: sp,
          yawScale: yawScale,
          sumR: sumR,
          sumG: sumG,
          sumB: sumB,
          sumW: sumW,
        );
      }
    }
  }

  if (x0 < 0) {
    paintColumns(0, math.min(width, x1));
    paintColumns(width + x0, width);
  } else if (x1 > width) {
    paintColumns(math.max(0, x0), width);
    paintColumns(0, x1 - width);
  } else {
    paintColumns(math.max(0, x0), math.min(width, x1));
  }
}

void _accumulatePixel({
  required _StitchTile tile,
  required int width,
  required int x,
  required int y,
  required int stripY,
  required double cp,
  required double sp,
  required double yawScale,
  required Float32List sumR,
  required Float32List sumG,
  required Float32List sumB,
  required Float32List sumW,
}) {
  final wrapped = x % width;
  final yaw = wrapped * yawScale - math.pi;
  final sy = math.sin(yaw);
  final cy = math.cos(yaw);
  final dx = cp * sy;
  final dy = sp;
  final dz = cp * cy;
  final right = tile.basis.right;
  final up = tile.basis.up;
  final forward = tile.basis.forward;
  final localX = dx * right.x + dy * right.y + dz * right.z;
  final localY = dx * up.x + dy * up.y + dz * up.z;
  final localZ = dx * forward.x + dy * forward.y + dz * forward.z;
  if (localZ <= 1e-4) return;

  final projectedX = tile.halfWidth + (localX / localZ) * tile.focalX;
  final projectedY = tile.halfHeight - (localY / localZ) * tile.focalY;
  final maxX = tile.width - 1;
  final maxY = tile.height - 1;
  if (projectedX < 0 || projectedY < 0 || projectedX >= maxX || projectedY >= maxY) {
    return;
  }

  final weight = localZ *
      (tile.feather
          ? _edgeFeather(projectedX, projectedY, tile.width, tile.height)
          : 1.0);
  if (weight <= 1e-4) return;

  final x0 = projectedX.floor();
  final y0 = projectedY.floor();
  final x1 = x0 + 1;
  final y1 = y0 + 1;
  final fx = projectedX - x0;
  final fy = projectedY - y0;
  final row0 = y0 * tile.width;
  final row1 = y1 * tile.width;
  final i00 = (row0 + x0) * 4;
  final i10 = (row0 + x1) * 4;
  final i01 = (row1 + x0) * 4;
  final i11 = (row1 + x1) * 4;
  final rgba = tile.rgba;
  final w00 = (1 - fx) * (1 - fy);
  final w10 = fx * (1 - fy);
  final w01 = (1 - fx) * fy;
  final w11 = fx * fy;
  final red =
      rgba[i00] * w00 + rgba[i10] * w10 + rgba[i01] * w01 + rgba[i11] * w11;
  final green =
      rgba[i00 + 1] * w00 +
      rgba[i10 + 1] * w10 +
      rgba[i01 + 1] * w01 +
      rgba[i11 + 1] * w11;
  final blue =
      rgba[i00 + 2] * w00 +
      rgba[i10 + 2] * w10 +
      rgba[i01 + 2] * w01 +
      rgba[i11 + 2] * w11;
  final gainWeight = tile.gain * weight;
  final index = (y - stripY) * width + wrapped;
  sumR[index] += red * gainWeight;
  sumG[index] += green * gainWeight;
  sumB[index] += blue * gainWeight;
  sumW[index] += weight;
}

/// One oriented photo plus the map it should be stamped onto.
class LiveTilePaintRequest {
  const LiveTilePaintRequest({
    required this.tile,
    this.rgba,
    this.bestForward,
    this.width = AppConstants.livePreviewWidth,
  });

  final StitchTileBytes tile;

  /// Previous map, packed RGBA. Null starts a black map.
  final Uint8List? rgba;

  /// How close each pixel's current sample is to that photo's center.
  final Float32List? bestForward;
  final int width;
}

/// Updated live map after [paintLiveTile]. Not JPEG-encoded.
class LiveTilePaintResult {
  const LiveTilePaintResult({
    required this.rgba,
    required this.bestForward,
    required this.width,
    required this.height,
  });

  final Uint8List rgba;
  final Float32List bestForward;
  final int width;
  final int height;
}

/// Stamps [LiveTilePaintRequest.tile] onto the equirectangular live map.
///
/// Only that photo's footprint is visited. On overlap, the sample closer to
/// its optical axis replaces the older one. Call through `compute`.
LiveTilePaintResult paintLiveTile(LiveTilePaintRequest request) {
  final width = request.width < 2 ? 2 : request.width;
  final height = width ~/ 2;
  final pixels = width * height;
  final canvas = Uint8List(pixels * 4);
  final best = Float32List(pixels);
  final previous = request.rgba;
  if (previous != null && previous.length >= canvas.length) {
    canvas.setRange(0, canvas.length, previous);
  } else {
    for (var i = 3; i < canvas.length; i += 4) {
      canvas[i] = 255;
    }
  }
  final previousBest = request.bestForward;
  if (previousBest != null && previousBest.length >= best.length) {
    best.setRange(0, best.length, previousBest);
  }

  final tile = request.tile;
  if (tile.width < 2 || tile.height < 2) {
    return LiveTilePaintResult(
      rgba: canvas,
      bestForward: best,
      width: width,
      height: height,
    );
  }
  final aspect = tile.height / tile.width;
  final verticalFov = verticalFovDegrees(tile.fov, aspect);
  final basis = cameraBasis(tile.yaw, tile.pitch, tile.roll);
  final halfWidth = tile.width / 2;
  final halfHeight = tile.height / 2;
  final focalX = halfWidth / math.tan(tile.fov * math.pi / 360);
  final focalY = halfHeight / math.tan(verticalFov * math.pi / 360);
  final halfDiagonal = math.atan(
    math.sqrt(
      math.pow(math.tan(tile.fov * math.pi / 360), 2) +
          math.pow(math.tan(verticalFov * math.pi / 360), 2),
    ),
  );
  final pitchScale = math.max(0.2, math.cos(tile.pitch * math.pi / 180));
  final yawHalf = (halfDiagonal * 180 / math.pi) / pitchScale;
  final pitchHalf = halfDiagonal * 180 / math.pi;
  final centerX = ((tile.yaw + 180) / 360) * width;
  final centerY = ((90 - tile.pitch) / 180) * height;
  final halfPixelsX = yawHalf / 360 * width + 1;
  final halfPixelsY = pitchHalf / 180 * height + 1;
  final y0 = math.max(0, (centerY - halfPixelsY).floor());
  final y1 = math.min(height, (centerY + halfPixelsY).ceil());
  final x0 = (centerX - halfPixelsX).floor();
  final x1 = (centerX + halfPixelsX).ceil();

  void paintColumns(int start, int end) {
    for (var y = y0; y < y1; y++) {
      for (var x = start; x < end; x++) {
        _stampLivePixel(
          canvas: canvas,
          best: best,
          canvasWidth: width,
          canvasHeight: height,
          tile: tile,
          basis: basis,
          halfWidth: halfWidth,
          halfHeight: halfHeight,
          focalX: focalX,
          focalY: focalY,
          x: x,
          y: y,
        );
      }
    }
  }

  if (y0 < y1) {
    if (x0 < 0) {
      paintColumns(0, math.min(width, x1));
      paintColumns(width + x0, width);
    } else if (x1 > width) {
      paintColumns(math.max(0, x0), width);
      paintColumns(0, x1 - width);
    } else {
      paintColumns(math.max(0, x0), math.min(width, x1));
    }
  }

  return LiveTilePaintResult(
    rgba: canvas,
    bestForward: best,
    width: width,
    height: height,
  );
}

void _stampLivePixel({
  required Uint8List canvas,
  required Float32List best,
  required int canvasWidth,
  required int canvasHeight,
  required StitchTileBytes tile,
  required CameraBasis basis,
  required double halfWidth,
  required double halfHeight,
  required double focalX,
  required double focalY,
  required int x,
  required int y,
}) {
  final wrapped = x % canvasWidth;
  final yaw = (wrapped / canvasWidth) * math.pi * 2 - math.pi;
  final pitch = math.pi / 2 - (y / canvasHeight) * math.pi;
  final cp = math.cos(pitch);
  final sp = math.sin(pitch);
  final sy = math.sin(yaw);
  final cy = math.cos(yaw);
  final dx = cp * sy;
  final dy = sp;
  final dz = cp * cy;
  final localX = dx * basis.right.x + dy * basis.right.y + dz * basis.right.z;
  final localY = dx * basis.up.x + dy * basis.up.y + dz * basis.up.z;
  final localZ =
      dx * basis.forward.x + dy * basis.forward.y + dz * basis.forward.z;
  if (localZ <= 1e-4) return;
  final projectedX = halfWidth + (localX / localZ) * focalX;
  final projectedY = halfHeight - (localY / localZ) * focalY;
  if (projectedX < 0 ||
      projectedY < 0 ||
      projectedX >= tile.width - 1 ||
      projectedY >= tile.height - 1) {
    return;
  }
  final index = y * canvasWidth + wrapped;
  if (localZ <= best[index]) return;

  final x0 = projectedX.floor();
  final y0 = projectedY.floor();
  final fx = projectedX - x0;
  final fy = projectedY - y0;
  final row0 = y0 * tile.width;
  final row1 = (y0 + 1) * tile.width;
  final i00 = (row0 + x0) * 4;
  final i10 = (row0 + x0 + 1) * 4;
  final i01 = (row1 + x0) * 4;
  final i11 = (row1 + x0 + 1) * 4;
  final rgba = tile.rgba;
  final w00 = (1 - fx) * (1 - fy);
  final w10 = fx * (1 - fy);
  final w01 = (1 - fx) * fy;
  final w11 = fx * fy;
  final dst = index * 4;
  canvas[dst] =
      (rgba[i00] * w00 + rgba[i10] * w10 + rgba[i01] * w01 + rgba[i11] * w11)
          .round()
          .clamp(0, 255)
          .toInt();
  canvas[dst + 1] =
      (rgba[i00 + 1] * w00 +
              rgba[i10 + 1] * w10 +
              rgba[i01 + 1] * w01 +
              rgba[i11 + 1] * w11)
          .round()
          .clamp(0, 255)
          .toInt();
  canvas[dst + 2] =
      (rgba[i00 + 2] * w00 +
              rgba[i10 + 2] * w10 +
              rgba[i01 + 2] * w01 +
              rgba[i11 + 2] * w11)
          .round()
          .clamp(0, 255)
          .toInt();
  canvas[dst + 3] = 255;
  best[index] = localZ;
}

/// RGBA live map to encode as `preview.jpg` and `thumb.jpg`.
class LivePreviewEncodeRequest {
  const LivePreviewEncodeRequest({
    required this.rgba,
    this.width = AppConstants.livePreviewWidth,
    this.previewQuality = AppConstants.stitchPreviewQuality,
    this.thumbWidth = AppConstants.stitchThumbWidth,
  });

  final Uint8List rgba;
  final int width;
  final int previewQuality;
  final int thumbWidth;
}

/// Encodes a map that [paintLiveTile] already finished. Call through `compute`.
StitchResult encodeLivePreview(LivePreviewEncodeRequest request) {
  final width = request.width < 2 ? 2 : request.width;
  final height = width ~/ 2;
  final pixels = width * height;
  if (request.rgba.length < pixels * 4) {
    throw StateError('Live preview is incomplete.');
  }
  final rgb = Uint8List(pixels * 3);
  var source = 0;
  var dest = 0;
  for (var i = 0; i < pixels; i++) {
    rgb[dest++] = request.rgba[source++];
    rgb[dest++] = request.rgba[source++];
    rgb[dest++] = request.rgba[source++];
    source++;
  }
  final encoded = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: rgb.buffer,
    numChannels: 3,
  );
  final preview = img.encodeJpg(encoded, quality: request.previewQuality);
  final thumbWidth = math.min(request.thumbWidth, width);
  final thumb = img.copyResize(
    encoded,
    width: thumbWidth,
    height: math.max(1, thumbWidth ~/ 2),
    interpolation: img.Interpolation.linear,
  );
  return StitchResult(
    preview: preview,
    thumb: img.encodeJpg(thumb, quality: request.previewQuality),
  );
}
