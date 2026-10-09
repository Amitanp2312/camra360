import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Bytes for [resizeJpeg], which runs in an isolate via `compute`.
class JpegResizeRequest {
  const JpegResizeRequest({
    required this.bytes,
    required this.maxEdge,
    required this.quality,
  });

  final Uint8List bytes;
  final int maxEdge;
  final int quality;
}

class JpegResizeResult {
  const JpegResizeResult({
    required this.bytes,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final int width;
  final int height;
}

/// Width and height from a JPEG header, without decoding the pixels.
(int, int)? jpegSize(Uint8List bytes) {
  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) return null;
  var index = 2;
  while (index + 9 < bytes.length) {
    if (bytes[index] != 0xFF) {
      index++;
      continue;
    }
    while (index < bytes.length && bytes[index] == 0xFF) {
      index++;
    }
    if (index >= bytes.length) return null;
    final marker = bytes[index];
    if (marker == 0xD9 || marker == 0xDA) return null;
    if (index + 2 >= bytes.length) return null;
    final length = (bytes[index + 1] << 8) | bytes[index + 2];
    if (length < 2) return null;
    final isStartOfFrame =
        marker == 0xC0 ||
        marker == 0xC1 ||
        marker == 0xC2 ||
        marker == 0xC3;
    if (isStartOfFrame) {
      if (index + 7 >= bytes.length) return null;
      final height = (bytes[index + 4] << 8) | bytes[index + 5];
      final width = (bytes[index + 6] << 8) | bytes[index + 7];
      if (width <= 0 || height <= 0) return null;
      return (width, height);
    }
    index += 1 + length;
  }
  return null;
}

/// Shrinks a JPEG so its longest edge is at most [JpegResizeRequest.maxEdge].
///
/// A photo that already fits is returned unchanged, so the camera JPEG is not
/// compressed a second time. The size check reads the header only.
JpegResizeResult resizeJpeg(JpegResizeRequest request) {
  final size = jpegSize(request.bytes);
  if (size != null && math.max(size.$1, size.$2) <= request.maxEdge) {
    return JpegResizeResult(
      bytes: request.bytes,
      width: size.$1,
      height: size.$2,
    );
  }
  final decoded = img.decodeImage(request.bytes);
  if (decoded == null) {
    throw StateError('Could not read the photo.');
  }
  final longest = math.max(decoded.width, decoded.height);
  if (longest <= request.maxEdge) {
    return JpegResizeResult(
      bytes: request.bytes,
      width: decoded.width,
      height: decoded.height,
    );
  }
  final image = img.copyResize(
    decoded,
    width: (decoded.width * request.maxEdge / longest).round(),
    height: (decoded.height * request.maxEdge / longest).round(),
    interpolation: img.Interpolation.cubic,
  );
  return JpegResizeResult(
    bytes: img.encodeJpg(image, quality: request.quality),
    width: image.width,
    height: image.height,
  );
}
