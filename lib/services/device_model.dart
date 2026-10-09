import 'dart:async';

import 'package:flutter/services.dart';

const deviceModelChannel = MethodChannel('sphere360/device');

/// `MANUFACTURER MODEL` from Android, or null when the channel is unavailable.
Future<String?> readDeviceModel() async {
  try {
    final model = await deviceModelChannel.invokeMethod<String>('model');
    final trimmed = model?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  } on MissingPluginException {
    return null;
  } on PlatformException {
    return null;
  }
}

/// Horizontal field of view, in degrees, of a photo taken in the phone's
/// current orientation.
///
/// Camera2 reports the sensor's landscape field of view. A portrait capture
/// swaps the axes when the sensor is mounted at 90° or 270°.
double imageHorizontalFov({
  required double sensorHorizontal,
  required double sensorVertical,
  required int sensorOrientation,
}) {
  final swapped = sensorOrientation % 180 != 0;
  return swapped ? sensorVertical : sensorHorizontal;
}

/// Lens field of view for [cameraId], or null when the phone cannot report it.
Future<double?> readImageHorizontalFov({
  required String cameraId,
  required int sensorOrientation,
}) async {
  try {
    final raw = await deviceModelChannel
        .invokeMethod<Object>('fov', {'cameraId': cameraId})
        .timeout(const Duration(seconds: 2));
    if (raw is! Map) return null;
    final horizontal = (raw['horizontal'] as num?)?.toDouble();
    final vertical = (raw['vertical'] as num?)?.toDouble();
    if (horizontal == null || vertical == null) return null;
    final fov = imageHorizontalFov(
      sensorHorizontal: horizontal,
      sensorVertical: vertical,
      sensorOrientation: sensorOrientation,
    );
    if (fov < 35 || fov > 110) return null;
    return fov;
  } on MissingPluginException {
    return null;
  } on PlatformException {
    return null;
  } on TimeoutException {
    return null;
  }
}
