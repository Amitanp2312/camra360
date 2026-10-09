import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sphere360/services/jpeg_resize.dart';

void main() {
  test('a photo that already fits is returned without a second encode', () {
    final source = img.Image(width: 16, height: 10);
    img.fill(source, color: img.ColorRgb8(20, 40, 60));
    final bytes = img.encodeJpg(source, quality: 90);

    final result = resizeJpeg(
      JpegResizeRequest(bytes: bytes, maxEdge: 2048, quality: 80),
    );

    expect(result.bytes, bytes);
    expect(result.width, 16);
    expect(result.height, 10);
    expect(jpegSize(bytes), (16, 10));
  });
}
