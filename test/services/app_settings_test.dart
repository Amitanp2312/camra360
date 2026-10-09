import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sphere360/core/constants.dart';
import 'package:sphere360/services/app_settings.dart';
import 'package:sphere360/services/upload_queue.dart';

void main() {
  test('settings keep the two preview widths and default the rest off', () {
    final settings = AppSettings.fromJson({
      'previewWidth': AppConstants.previewWidthHigh,
      'wifiOnly': true,
      'saveLocation': true,
      'seamDebug': true,
    });
    expect(settings.previewWidth, AppConstants.previewWidthHigh);
    expect(settings.wifiOnly, isTrue);
    final again = AppSettings.fromJson(settings.toJson());
    expect(again.seamDebug, isTrue);

    final unknown = AppSettings.fromJson({'previewWidth': 1280});
    expect(unknown.previewWidth, AppConstants.previewWidthStandard);
    expect(unknown.saveLocation, isFalse);
    expect(unknown.wifiOnly, isFalse);
  });

  test('wifi-only uploads wait unless the radio is Wi-Fi', () {
    expect(
      uploadAllowed(const [ConnectivityResult.mobile], wifiOnly: false),
      isTrue,
    );
    expect(
      uploadAllowed(const [ConnectivityResult.mobile], wifiOnly: true),
      isFalse,
    );
    expect(
      uploadAllowed(const [ConnectivityResult.wifi], wifiOnly: true),
      isTrue,
    );
    expect(
      uploadAllowed(
        const [ConnectivityResult.wifi, ConnectivityResult.vpn],
        wifiOnly: true,
      ),
      isTrue,
    );
    expect(
      uploadAllowed(const [ConnectivityResult.none], wifiOnly: false),
      isFalse,
    );
  });
}
