import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:sphere360/core/constants.dart';

/// One capture tile passed into [compositePreview].
class CompositeTile {
  const CompositeTile({
    required this.bytes,
    required this.yaw,
    required this.pitch,
    this.roll = 0,
    this.fov,
    this.width,
    this.height,
  });

  final Uint8List bytes;

  /// Degrees. Zero looks along +Z. Positive yaw turns toward +X.
  final double yaw;

  /// Degrees. Zero is the horizon. Positive pitch looks up.
  final double pitch;

  /// Degrees about the view direction, right-hand rule.
  final double roll;

  /// Horizontal field of view in degrees.
  final double? fov;
  final int? width;
  final int? height;
}

class CompositeRequest {
  const CompositeRequest({
    required this.tiles,
    this.outputWidth = AppConstants.fallbackPreviewWidth,
  });

  final List<CompositeTile> tiles;
  final int outputWidth;
}

class Vec3 {
  const Vec3(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;

  double dot(Vec3 other) => x * other.x + y * other.y + z * other.z;

  Vec3 cross(Vec3 other) {
    return Vec3(
      y * other.z - z * other.y,
      z * other.x - x * other.z,
      x * other.y - y * other.x,
    );
  }

  double get length => math.sqrt(x * x + y * y + z * z);

  Vec3 normalized() {
    final magnitude = length;
    if (magnitude == 0) return const Vec3(0, 0, 0);
    return this * (1 / magnitude);
  }

  Vec3 operator +(Vec3 other) => Vec3(x + other.x, y + other.y, z + other.z);

  Vec3 operator -(Vec3 other) => Vec3(x - other.x, y - other.y, z - other.z);

  Vec3 operator *(double scale) => Vec3(x * scale, y * scale, z * scale);
}

class CameraBasis {
  const CameraBasis({
    required this.right,
    required this.up,
    required this.forward,
  });

  final Vec3 right;
  final Vec3 up;
  final Vec3 forward;
}

/// Unit direction for a yaw/pitch pair.
///
/// Yaw is applied around the world up axis. Pitch then lifts the ray off
/// the horizon. `(yaw: 0, pitch: 0)` is `(0, 0, 1)`.
Vec3 directionFromYawPitch(double yawDegrees, double pitchDegrees) {
  final yaw = yawDegrees * math.pi / 180;
  final pitch = pitchDegrees * math.pi / 180;
  final cosPitch = math.cos(pitch);
  return Vec3(
    cosPitch * math.sin(yaw),
    math.sin(pitch),
    cosPitch * math.cos(yaw),
  );
}

/// Angle in radians between two directions, in `[0, pi]`.
double angularDistance(Vec3 a, Vec3 b) {
  final cosine = a.dot(b).clamp(-1.0, 1.0);
  return math.acos(cosine);
}

/// Camera axes for a yaw/pitch/roll pose.
///
/// Near the poles, forward is almost parallel to world up and
/// `cross(worldUp, forward)` collapses. The reference axis switches to
/// world forward so right and up stay defined.
CameraBasis cameraBasis(
  double yawDegrees,
  double pitchDegrees,
  double rollDegrees,
) {
  final forward = directionFromYawPitch(yawDegrees, pitchDegrees);
  final reference = forward.y.abs() > 0.98
      ? const Vec3(0, 0, 1)
      : const Vec3(0, 1, 0);
  var right = reference.cross(forward).normalized();
  var up = forward.cross(right).normalized();
  if (rollDegrees != 0) {
    final roll = rollDegrees * math.pi / 180;
    final cosine = math.cos(roll);
    final sine = math.sin(roll);
    final rolledRight = right * cosine + up * sine;
    final rolledUp = up * cosine - right * sine;
    right = rolledRight;
    up = rolledUp;
  }
  return CameraBasis(right: right, up: up, forward: forward);
}

/// A pinhole projection of [direction] onto a viewport.
///
/// [x] and [y] are pixel coordinates even when the ray misses the frame.
/// [localZ] is the component along the optical axis: positive is in front.
class ViewportProjection {
  const ViewportProjection({
    required this.x,
    required this.y,
    required this.localX,
    required this.localY,
    required this.localZ,
  });

  final double x;
  final double y;
  final double localX;
  final double localY;
  final double localZ;

  bool get inFront => localZ > 1e-4;

  bool inside(int width, int height) {
    return inFront && x >= 0 && y >= 0 && x < width - 1 && y < height - 1;
  }
}

/// Projects [direction] through the camera. The optical axis lands on the
/// viewport center. [y] grows downward, matching the screen.
ViewportProjection projectToViewport({
  required Vec3 direction,
  required CameraBasis basis,
  required double horizontalFovDegrees,
  required double verticalFovDegrees,
  required int imageWidth,
  required int imageHeight,
}) {
  final localX = direction.dot(basis.right);
  final localY = direction.dot(basis.up);
  final localZ = direction.dot(basis.forward);
  final depth = localZ.abs() < 1e-4
      ? (localZ.isNegative ? -1e-4 : 1e-4)
      : localZ;
  final halfWidth = imageWidth / 2;
  final halfHeight = imageHeight / 2;
  final focalX = halfWidth / math.tan(_radians(horizontalFovDegrees) / 2);
  final focalY = halfHeight / math.tan(_radians(verticalFovDegrees) / 2);
  return ViewportProjection(
    x: halfWidth + (localX / depth) * focalX,
    y: halfHeight - (localY / depth) * focalY,
    localX: localX,
    localY: localY,
    localZ: localZ,
  );
}

/// Projects [direction] into a rectilinear photo.
///
/// Returns pixel coordinates, or null when the ray is behind the camera or
/// outside the frame. The optical axis lands on the image center.
({double x, double y})? projectOntoTile({
  required Vec3 direction,
  required CameraBasis basis,
  required double horizontalFovDegrees,
  required double verticalFovDegrees,
  required int imageWidth,
  required int imageHeight,
}) {
  final projected = projectToViewport(
    direction: direction,
    basis: basis,
    horizontalFovDegrees: horizontalFovDegrees,
    verticalFovDegrees: verticalFovDegrees,
    imageWidth: imageWidth,
    imageHeight: imageHeight,
  );
  if (!projected.inside(imageWidth, imageHeight)) return null;
  return (x: projected.x, y: projected.y);
}

/// Equirectangular JPEG for sessions that have captures but no `preview.jpg`.
///
/// Each tile is projected with its stored orientation. On overlap, the sample
/// closer to that tile's optical axis (larger forward component) is kept.
/// Run this with [compute] so the decode and pixel loop stay off the UI isolate.
Uint8List compositePreview(CompositeRequest request) {
  final decoded = <_DecodedTile>[];
  for (final tile in request.tiles) {
    final image = img.decodeJpg(tile.bytes);
    if (image == null) continue;
    final horizontalFov = tile.fov ?? AppConstants.fallbackHorizontalFov;
    final aspect = image.height / image.width;
    final verticalFov = verticalFovDegrees(horizontalFov, aspect);
    decoded.add(
      _DecodedTile(
        image: image,
        basis: cameraBasis(tile.yaw, tile.pitch, tile.roll),
        yaw: tile.yaw,
        pitch: tile.pitch,
        horizontalFov: horizontalFov,
        verticalFov: verticalFov,
      ),
    );
  }
  if (decoded.isEmpty) {
    throw StateError('No capture images could be decoded.');
  }

  final width = request.outputWidth;
  final height = width ~/ 2;
  final canvas = img.Image(width: width, height: height);
  final bestForward = List<double>.filled(width * height, 0);

  for (final tile in decoded) {
    _paintTile(canvas, bestForward, tile);
  }
  return img.encodeJpg(canvas, quality: 85);
}

class _DecodedTile {
  const _DecodedTile({
    required this.image,
    required this.basis,
    required this.yaw,
    required this.pitch,
    required this.horizontalFov,
    required this.verticalFov,
  });

  final img.Image image;
  final CameraBasis basis;
  final double yaw;
  final double pitch;
  final double horizontalFov;
  final double verticalFov;
}

void _paintTile(img.Image canvas, List<double> bestForward, _DecodedTile tile) {
  final width = canvas.width;
  final height = canvas.height;
  final halfDiagonal = math.atan(
    math.sqrt(
      math.pow(math.tan(_radians(tile.horizontalFov) / 2), 2) +
          math.pow(math.tan(_radians(tile.verticalFov) / 2), 2),
    ),
  );
  final pitchScale = math.max(0.2, math.cos(_radians(tile.pitch)));
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

  void paintColumnRange(int start, int end) {
    for (var y = y0; y < y1; y++) {
      for (var x = start; x < end; x++) {
        _sample(canvas, bestForward, tile, x, y);
      }
    }
  }

  if (x0 < 0) {
    paintColumnRange(0, math.min(width, x1));
    paintColumnRange(width + x0, width);
  } else if (x1 > width) {
    paintColumnRange(math.max(0, x0), width);
    paintColumnRange(0, x1 - width);
  } else {
    paintColumnRange(x0, x1);
  }
}

void _sample(
  img.Image canvas,
  List<double> bestForward,
  _DecodedTile tile,
  int x,
  int y,
) {
  final yaw = (x / canvas.width) * 360 - 180;
  final pitch = 90 - (y / canvas.height) * 180;
  final direction = directionFromYawPitch(yaw, pitch);
  final projected = projectOntoTile(
    direction: direction,
    basis: tile.basis,
    horizontalFovDegrees: tile.horizontalFov,
    verticalFovDegrees: tile.verticalFov,
    imageWidth: tile.image.width,
    imageHeight: tile.image.height,
  );
  if (projected == null) return;

  final forward = direction.dot(tile.basis.forward);
  final index = y * canvas.width + x;
  if (forward <= bestForward[index]) return;

  final color = tile.image.getPixelLinear(projected.x, projected.y);
  canvas.setPixelRgb(x, y, color.r, color.g, color.b);
  bestForward[index] = forward;
}

/// Rectilinear vertical field of view from the horizontal field of view
/// and the image aspect ratio (`height / width`).
double verticalFovDegrees(double horizontalFovDegrees, double heightOverWidth) {
  final half = math.tan(_radians(horizontalFovDegrees) / 2) * heightOverWidth;
  return _degrees(2 * math.atan(half));
}

double _radians(double degrees) => degrees * math.pi / 180;

double _degrees(double radians) => radians * 180 / math.pi;
