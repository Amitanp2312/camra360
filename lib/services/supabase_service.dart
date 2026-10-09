import 'dart:typed_data';

import 'package:sphere360/core/constants.dart';
import 'package:sphere360/models/capture.dart';
import 'package:sphere360/models/hotspot.dart';
import 'package:sphere360/models/session.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Failure from Postgres or Storage, with the server message preserved.
class SupabaseServiceException implements Exception {
  SupabaseServiceException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

/// Typed access to sessions, captures, and the private panoramas bucket.
///
/// Object keys are `{userId}/{sessionId}/{captureId}.jpg`, with
/// `preview.jpg` and `thumb.jpg` beside the tiles.
class SupabaseService {
  SupabaseService(this._client);

  final SupabaseClient _client;

  static String capturePath({
    required String userId,
    required String sessionId,
    required String captureId,
  }) {
    return '$userId/$sessionId/$captureId.jpg';
  }

  static String previewPath({
    required String userId,
    required String sessionId,
  }) {
    return '$userId/$sessionId/preview.jpg';
  }

  static String thumbPath({required String userId, required String sessionId}) {
    return '$userId/$sessionId/thumb.jpg';
  }

  Future<List<CaptureSession>> fetchSessions() {
    return _guard(() async {
      final userId = _requireUserId();
      final rows = await _client
          .from(AppConstants.sessionsTable)
          .select()
          .eq('user_id', userId)
          .order('started_at', ascending: false);
      return [for (final row in rows) CaptureSession.fromJson(_asMap(row))];
    });
  }

  Future<CaptureSession> fetchSession(String id) {
    return _guard(() async {
      final userId = _requireUserId();
      final row = await _client
          .from(AppConstants.sessionsTable)
          .select()
          .eq('id', id)
          .eq('user_id', userId)
          .single();
      return CaptureSession.fromJson(_asMap(row));
    });
  }

  Future<CaptureSession> createSession({
    String? title,
    String? deviceModel,
    double? latitude,
    double? longitude,
  }) {
    return _guard(() async {
      final userId = _requireUserId();
      final row = await _client
          .from(AppConstants.sessionsTable)
          .insert({
            'user_id': userId,
            'title': title,
            'status': SessionStatus.capturing.wire,
            'device_model': deviceModel,
            'latitude': latitude,
            'longitude': longitude,
          })
          .select()
          .single();
      return CaptureSession.fromJson(_asMap(row));
    });
  }

  Future<CaptureSession> updateSession(
    String id, {
    String? title,
    SessionStatus? status,
    DateTime? completedAt,
    String? deviceModel,
    double? latitude,
    double? longitude,
    String? previewPath,
    String? thumbPath,
  }) {
    return _guard(() async {
      final userId = _requireUserId();
      final patch = <String, dynamic>{
        'title': ?title,
        if (status != null) 'status': status.wire,
        if (completedAt != null)
          'completed_at': completedAt.toUtc().toIso8601String(),
        'device_model': ?deviceModel,
        'latitude': ?latitude,
        'longitude': ?longitude,
        'preview_path': ?previewPath,
        'thumb_path': ?thumbPath,
      };
      if (patch.isEmpty) return fetchSession(id);

      final row = await _client
          .from(AppConstants.sessionsTable)
          .update(patch)
          .eq('id', id)
          .eq('user_id', userId)
          .select()
          .single();
      return CaptureSession.fromJson(_asMap(row));
    });
  }

  /// Removes every session this user owns, including captures, hotspots, and
  /// the files in those session folders. The auth user stays.
  Future<void> deleteOwnedData() async {
    final sessions = await fetchSessions();
    for (final session in sessions) {
      await deleteSession(session.id);
    }
  }

  /// Removes the session row (captures cascade) and every object under
  /// `{userId}/{sessionId}/`.
  Future<void> deleteSession(String sessionId) {
    return _guard(() async {
      final userId = _requireUserId();
      final prefix = '$userId/$sessionId';
      final objects = await _bucket.list(
        path: prefix,
        searchOptions: const SearchOptions(limit: 1000),
      );
      final paths = [
        for (final object in objects)
          if (object.id != null) '$prefix/${object.name}',
      ];
      if (paths.isNotEmpty) {
        await _bucket.remove(paths);
      }
      await _client
          .from(AppConstants.sessionsTable)
          .delete()
          .eq('id', sessionId)
          .eq('user_id', userId);
    });
  }

  Future<List<Capture>> fetchCaptures(String sessionId) {
    return _guard(() async {
      final userId = _requireUserId();
      final rows = await _client
          .from(AppConstants.capturesTable)
          .select()
          .eq('session_id', sessionId)
          .eq('user_id', userId)
          .order('captured_at', ascending: true);
      return [for (final row in rows) Capture.fromJson(_asMap(row))];
    });
  }

  Future<int> countCaptures(String sessionId) {
    return _guard(() async {
      final userId = _requireUserId();
      return _client
          .from(AppConstants.capturesTable)
          .count()
          .eq('session_id', sessionId)
          .eq('user_id', userId);
    });
  }

  /// Capture counts for the given sessions, in one query.
  Future<Map<String, int>> fetchCaptureCounts(List<String> sessionIds) {
    return _guard(() async {
      if (sessionIds.isEmpty) return {};
      final userId = _requireUserId();
      final rows = await _client
          .from(AppConstants.capturesTable)
          .select('session_id')
          .eq('user_id', userId)
          .inFilter('session_id', sessionIds);
      final counts = <String, int>{};
      for (final row in rows) {
        final sessionId = _asMap(row)['session_id'];
        if (sessionId is! String) continue;
        counts[sessionId] = (counts[sessionId] ?? 0) + 1;
      }
      return counts;
    });
  }

  Future<Capture> insertCapture({
    required String sessionId,
    required String storagePath,
    required double yaw,
    required double pitch,
    double? roll,
    double? fov,
    int? width,
    int? height,
    String? id,
  }) {
    return _guard(() async {
      final userId = _requireUserId();
      final row = await _client
          .from(AppConstants.capturesTable)
          .insert({
            'id': ?id,
            'session_id': sessionId,
            'user_id': userId,
            'storage_path': storagePath,
            'yaw': yaw,
            'pitch': pitch,
            'roll': roll,
            'fov': fov,
            'width': width,
            'height': height,
          })
          .select()
          .single();
      return Capture.fromJson(_asMap(row));
    });
  }

  Future<void> uploadJpeg({required String path, required Uint8List bytes}) {
    return _guard(() async {
      _requireUserId();
      await _bucket.uploadBinary(
        path,
        bytes,
        fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
      );
    });
  }

  Future<Uint8List> downloadObject(String path) {
    return _guard(() {
      _requireUserId();
      return _bucket.download(path);
    });
  }

  Future<String> createSignedUrl(String path, {int? ttlSeconds}) {
    return _guard(() {
      _requireUserId();
      return _bucket.createSignedUrl(
        path,
        ttlSeconds ?? AppConstants.signedUrlTtlSeconds,
      );
    });
  }

  /// Signs every path in one Storage request.
  ///
  /// Calls [StorageFileApi.createSignedUrlsResult] so a missing object comes
  /// back as [SignedUrlFailure] instead of being omitted.
  Future<List<SignedUrlResult>> createSignedUrls(List<String> paths) {
    return _guard(() async {
      if (paths.isEmpty) return const [];
      _requireUserId();
      return _bucket.createSignedUrlsResult(
        paths,
        AppConstants.signedUrlTtlSeconds,
      );
    });
  }

  Future<List<CaptureHotspot>> fetchHotspots(String sessionId) {
    return _guard(() async {
      final userId = _requireUserId();
      final rows = await _client
          .from(AppConstants.hotspotsTable)
          .select()
          .eq('session_id', sessionId)
          .eq('user_id', userId)
          .order('created_at', ascending: true);
      return [for (final row in rows) CaptureHotspot.fromJson(_asMap(row))];
    });
  }

  Future<CaptureHotspot> insertHotspot({
    required String sessionId,
    required double yaw,
    required double pitch,
    required String label,
  }) {
    return _guard(() async {
      final userId = _requireUserId();
      final row = await _client
          .from(AppConstants.hotspotsTable)
          .insert({
            'session_id': sessionId,
            'user_id': userId,
            'yaw': yaw,
            'pitch': pitch,
            'label': label,
          })
          .select()
          .single();
      return CaptureHotspot.fromJson(_asMap(row));
    });
  }

  Future<void> deleteHotspot(String id) {
    return _guard(() async {
      final userId = _requireUserId();
      await _client
          .from(AppConstants.hotspotsTable)
          .delete()
          .eq('id', id)
          .eq('user_id', userId);
    });
  }

  Future<void> deleteObjects(List<String> paths) {
    return _guard(() async {
      if (paths.isEmpty) return;
      _requireUserId();
      await _bucket.remove(paths);
    });
  }

  /// Removes one capture row and its JPEG.
  ///
  /// A missing object is ignored so undo still works when the upload never
  /// left the phone, or already deleted the file.
  Future<void> deleteCapture({
    required String id,
    required String storagePath,
  }) {
    return _guard(() async {
      final userId = _requireUserId();
      await _removeIfPresent([storagePath]);
      await _client
          .from(AppConstants.capturesTable)
          .delete()
          .eq('id', id)
          .eq('user_id', userId);
    });
  }

  Future<void> _removeIfPresent(List<String> paths) async {
    if (paths.isEmpty) return;
    try {
      await _bucket.remove(paths);
    } on StorageException catch (error) {
      if (_missingObject(error)) return;
      rethrow;
    }
  }

  StorageFileApi get _bucket =>
      _client.storage.from(AppConstants.panoramasBucket);

  bool _missingObject(StorageException error) {
    if ('${error.statusCode}' == '404') return true;
    final message = error.message.toLowerCase();
    return message.contains('not found') || message.contains('not_found');
  }

  String _requireUserId() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw SupabaseServiceException('Sign in before using sessions.');
    }
    return userId;
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on SupabaseServiceException {
      rethrow;
    } on PostgrestException catch (error) {
      throw SupabaseServiceException(error.message, cause: error);
    } on StorageException catch (error) {
      throw SupabaseServiceException(error.message, cause: error);
    }
  }
}

Map<String, dynamic> _asMap(Object? row) {
  if (row is Map<String, dynamic>) return row;
  if (row is Map) return Map<String, dynamic>.from(row);
  throw SupabaseServiceException('Unexpected row from Supabase.');
}
