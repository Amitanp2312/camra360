import 'dart:convert';
import 'dart:io';

import 'package:sphere360/core/constants.dart';

/// Choices stored on the phone. Location and seam comparison start off.
class AppSettings {
  const AppSettings({
    this.previewWidth = AppConstants.previewWidthStandard,
    this.wifiOnly = false,
    this.saveLocation = false,
    this.seamDebug = false,
  });

  /// Equirectangular width: [AppConstants.previewWidthStandard] or
  /// [AppConstants.previewWidthHigh].
  final int previewWidth;

  /// Pending photos wait until the phone is on Wi-Fi.
  final bool wifiOnly;

  /// A new capture may store a place. The live screen still asks permission.
  final bool saveLocation;

  /// The viewer can show the panorama with seam blending turned off.
  final bool seamDebug;

  AppSettings copyWith({
    int? previewWidth,
    bool? wifiOnly,
    bool? saveLocation,
    bool? seamDebug,
  }) {
    return AppSettings(
      previewWidth: previewWidth ?? this.previewWidth,
      wifiOnly: wifiOnly ?? this.wifiOnly,
      saveLocation: saveLocation ?? this.saveLocation,
      seamDebug: seamDebug ?? this.seamDebug,
    );
  }

  Map<String, Object> toJson() {
    return {
      'previewWidth': previewWidth,
      'wifiOnly': wifiOnly,
      'saveLocation': saveLocation,
      'seamDebug': seamDebug,
    };
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final width = json['previewWidth'];
    return AppSettings(
      previewWidth: width == AppConstants.previewWidthHigh
          ? AppConstants.previewWidthHigh
          : AppConstants.previewWidthStandard,
      wifiOnly: json['wifiOnly'] == true,
      saveLocation: json['saveLocation'] == true,
      seamDebug: json['seamDebug'] == true,
    );
  }
}

/// `settings.json` beside the upload database.
class SettingsStore {
  SettingsStore(this._file);

  final File _file;
  AppSettings current = const AppSettings();

  Future<void> load() async {
    if (!await _file.exists()) return;
    try {
      final decoded = jsonDecode(await _file.readAsString());
      if (decoded is Map) {
        current = AppSettings.fromJson(Map<String, dynamic>.from(decoded));
      }
    } on FormatException {
      current = const AppSettings();
    } on FileSystemException {
      current = const AppSettings();
    }
  }

  Future<void> save(AppSettings settings) async {
    current = settings;
    await _file.parent.create(recursive: true);
    await _file.writeAsString(jsonEncode(settings.toJson()));
  }
}
