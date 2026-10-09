import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:sphere360/core/constants.dart';
import 'package:sphere360/services/preview_composite.dart';

/// JPEG plus the view used by [renderPlanetJpeg].
///
/// [yaw] and [pitch] are radians. Pitch `0` is the horizon and positive looks
/// up. A pitch of `-pi / 2` looks straight down, which is the little planet.
class PlanetExportRequest {
  const PlanetExportRequest({
    required this.equirectJpeg,
    required this.yaw,
    required this.pitch,
    required this.zoom,
    this.size = AppConstants.planetExportSize,
    this.quality = 90,
  });

  final Uint8List equirectJpeg;
  final double yaw;
  final double pitch;
  final double zoom;
  final int size;
  final int quality;
}

/// World direction seen through one little-planet pixel.
///
/// [nx] and [ny] are plane coordinates with y up, after the screen's aspect
/// correction. Stereographic projection maps distance `ρ` from the origin to
/// polar angle `2 * atan(ρ / zoom)` away from the look axis, so the center of
/// the picture is the view direction and the rim wraps toward the opposite
/// pole. [zoom] larger than 1 shows a smaller patch of the sphere.
///
/// [yaw] turns that axis around world up. [pitch] then lifts it off the
/// horizon. The result is a unit vector: x right, y up, z forward.
Vec3 planetDirection({
  required double nx,
  required double ny,
  required double zoom,
  required double yaw,
  required double pitch,
}) {
  final rho = math.sqrt(nx * nx + ny * ny) / math.max(zoom, 0.05);
  final theta = 2 * math.atan(rho);
  final azimuth = math.atan2(ny, nx);
  final view = Vec3(
    math.sin(theta) * math.cos(azimuth),
    math.sin(theta) * math.sin(azimuth),
    math.cos(theta),
  );
  final cosPitch = math.cos(pitch);
  final sinPitch = math.sin(pitch);
  final pitched = Vec3(
    view.x,
    view.y * cosPitch + view.z * sinPitch,
    -view.y * sinPitch + view.z * cosPitch,
  );
  final cosYaw = math.cos(yaw);
  final sinYaw = math.sin(yaw);
  return Vec3(
    pitched.x * cosYaw + pitched.z * sinYaw,
    pitched.y,
    -pitched.x * sinYaw + pitched.z * cosYaw,
  );
}

/// Yaw and pitch, in degrees, of a world direction.
///
/// This is the inverse of [directionFromYawPitch].
({double yaw, double pitch}) yawPitchFromDirection(Vec3 direction) {
  final yaw = math.atan2(direction.x, direction.z) * 180 / math.pi;
  final pitch =
      math.asin(direction.y.clamp(-1.0, 1.0)) * 180 / math.pi;
  return (yaw: yaw, pitch: pitch);
}

/// Screen point for [direction], or null when it sits on the back of the view.
///
/// The mapping is the inverse of [planetDirection], including the y flip used
/// by `shaders/planet.frag`.
(double x, double y)? planetScreenPoint({
  required Vec3 direction,
  required double yaw,
  required double pitch,
  required double zoom,
  required double width,
  required double height,
}) {
  if (width < 2 || height < 2) return null;
  final cosYaw = math.cos(yaw);
  final sinYaw = math.sin(yaw);
  final unyawed = Vec3(
    direction.x * cosYaw - direction.z * sinYaw,
    direction.y,
    direction.x * sinYaw + direction.z * cosYaw,
  );
  final cosPitch = math.cos(pitch);
  final sinPitch = math.sin(pitch);
  final view = Vec3(
    unyawed.x,
    unyawed.y * cosPitch - unyawed.z * sinPitch,
    unyawed.y * sinPitch + unyawed.z * cosPitch,
  );
  if (view.z <= 0.02) return null;
  final theta = math.acos(view.z.clamp(-1.0, 1.0));
  final rho = math.tan(theta / 2) * math.max(zoom, 0.05);
  final azimuth = math.atan2(view.y, view.x);
  final nx = rho * math.cos(azimuth);
  final ny = rho * math.sin(azimuth);
  final aspect = width / height;
  final px = nx / aspect;
  final py = -ny;
  final x = (px + 1) / 2 * width;
  final y = (py + 1) / 2 * height;
  if (x < 0 || y < 0 || x > width || y > height) return null;
  return (x, y);
}

/// Square little-planet JPEG for the current view.
///
/// Call this through `compute`. The equirectangular source is sampled with
/// [planetDirection], the same map as the fragment shader.
Uint8List renderPlanetJpeg(PlanetExportRequest request) {
  final img.Image source;
  try {
    final decoded = img.decodeJpg(request.equirectJpeg);
    if (decoded == null) {
      throw StateError('Could not read the panorama.');
    }
    source = decoded;
  } on img.ImageException {
    throw StateError('Could not read the panorama.');
  }
  final size = request.size < 2 ? 2 : request.size;
  final rgb = Uint8List(size * size * 3);
  var offset = 0;
  for (var y = 0; y < size; y++) {
    final py = -((y + 0.5) / size * 2 - 1);
    for (var x = 0; x < size; x++) {
      final px = (x + 0.5) / size * 2 - 1;
      final direction = planetDirection(
        nx: px,
        ny: py,
        zoom: request.zoom,
        yaw: request.yaw,
        pitch: request.pitch,
      );
      final pixel = _sample(source, direction);
      rgb[offset++] = pixel.$1;
      rgb[offset++] = pixel.$2;
      rgb[offset++] = pixel.$3;
    }
  }
  final image = img.Image.fromBytes(
    width: size,
    height: size,
    bytes: rgb.buffer,
    numChannels: 3,
  );
  return Uint8List.fromList(img.encodeJpg(image, quality: request.quality));
}

(int, int, int) _sample(img.Image image, Vec3 direction) {
  final longitude = math.atan2(direction.x, direction.z);
  final latitude = math.asin(direction.y.clamp(-1.0, 1.0));
  final u = longitude / (2 * math.pi) + 0.5;
  final v = 0.5 - latitude / math.pi;
  var x = u * image.width;
  x = x % image.width;
  if (x < 0) x += image.width;
  final y = (v * (image.height - 1)).clamp(0, image.height - 1).toDouble();
  final pixel = image.getPixel(x.floor() % image.width, y.floor());
  return (pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt());
}
