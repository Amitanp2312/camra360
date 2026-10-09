import 'package:flutter_test/flutter_test.dart';
import 'package:sphere360/services/upload_backoff.dart';

void main() {
  test('backoff doubles and stops growing at 256 seconds', () {
    expect(uploadBackoff(1), const Duration(seconds: 2));
    expect(uploadBackoff(2), const Duration(seconds: 4));
    expect(uploadBackoff(3), const Duration(seconds: 8));
    expect(uploadBackoff(8), const Duration(seconds: 256));
    expect(uploadBackoff(9), const Duration(seconds: 256));
    expect(uploadBackoff(0), const Duration(seconds: 2));
  });
}
