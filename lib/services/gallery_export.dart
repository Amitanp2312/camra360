import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sphere360/services/device_model.dart';

/// Saves JPEGs into the device gallery, under Pictures/Sphere360.
///
/// Android 10 and later use MediaStore and do not need a storage permission.
/// Older phones are asked once if the platform reports that permission is missing.
Future<void> saveJpegsToGallery(
  List<({String name, Uint8List bytes})> files,
) async {
  if (files.isEmpty) return;
  try {
    await _invokeSave(files);
  } on PlatformException catch (error) {
    if (error.code != 'permission') {
      throw StateError(error.message ?? 'Could not save the photos.');
    }
    final status = await Permission.storage.request();
    if (!status.isGranted) {
      throw StateError(
        status.isPermanentlyDenied
            ? 'Storage is blocked. Allow it in settings to save photos.'
            : 'Allow storage to save photos to the gallery.',
      );
    }
    try {
      await _invokeSave(files);
    } on PlatformException catch (retry) {
      throw StateError(retry.message ?? 'Could not save the photos.');
    }
  } on MissingPluginException {
    throw StateError('Saving to the gallery is only available on Android.');
  }
}

/// Opens the Android share sheet with these JPEGs.
Future<void> shareJpegs(
  List<({String name, Uint8List bytes})> files,
) async {
  if (files.isEmpty) return;
  try {
    await deviceModelChannel.invokeMethod<void>('shareJpegs', {
      'files': [
        for (final file in files) {'name': file.name, 'bytes': file.bytes},
      ],
    });
  } on PlatformException catch (error) {
    throw StateError(error.message ?? 'Could not share the photos.');
  } on MissingPluginException {
    throw StateError('Sharing is only available on Android.');
  }
}

/// Opens the Android share sheet with a text link.
Future<void> shareText(String text) async {
  try {
    await deviceModelChannel.invokeMethod<void>('shareText', {'text': text});
  } on PlatformException catch (error) {
    throw StateError(error.message ?? 'Could not share the link.');
  } on MissingPluginException {
    throw StateError('Sharing is only available on Android.');
  }
}

Future<void> _invokeSave(List<({String name, Uint8List bytes})> files) {
  return deviceModelChannel.invokeMethod<void>('saveJpegs', {
    'files': [
      for (final file in files) {'name': file.name, 'bytes': file.bytes},
    ],
  });
}
