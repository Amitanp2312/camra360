import 'dart:async';

import 'package:flutter/services.dart';
import 'package:sphere360/services/device_model.dart';

/// A single latitude and longitude reading from the phone.
class DeviceLocation {
  const DeviceLocation({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;
}

/// Reads the map returned by the Android `location` channel method.
DeviceLocation? parseDeviceLocation(Object? raw) {
  if (raw is! Map) return null;
  final latitude = raw['latitude'];
  final longitude = raw['longitude'];
  if (latitude is! num || longitude is! num) return null;
  return DeviceLocation(
    latitude: latitude.toDouble(),
    longitude: longitude.toDouble(),
  );
}

/// One location fix, or null when the platform has no reading.
///
/// Throws [PlatformException] when location is off or permission is missing.
/// Throws [TimeoutException] when the channel does not answer.
Future<DeviceLocation?> readDeviceLocation() async {
  try {
    final raw = await deviceModelChannel
        .invokeMethod<Object?>('location')
        .timeout(const Duration(seconds: 15));
    return parseDeviceLocation(raw);
  } on MissingPluginException {
    return null;
  }
}
