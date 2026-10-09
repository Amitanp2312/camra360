/// Lifecycle stored in `sessions.status`.
enum SessionStatus {
  capturing,
  complete;

  static SessionStatus parse(Object? value) {
    return switch (value) {
      'capturing' => SessionStatus.capturing,
      'complete' => SessionStatus.complete,
      _ => throw FormatException('Unknown session status: $value'),
    };
  }

  String get wire => name;
}

/// One 360° sweep. Named [CaptureSession] so it does not clash with the
/// Supabase auth session type.
class CaptureSession {
  const CaptureSession({
    required this.id,
    required this.userId,
    required this.status,
    this.title,
    this.startedAt,
    this.completedAt,
    this.deviceModel,
    this.latitude,
    this.longitude,
    this.previewPath,
    this.thumbPath,
  });

  final String id;
  final String userId;
  final String? title;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final SessionStatus status;
  final String? deviceModel;
  final double? latitude;
  final double? longitude;
  final String? previewPath;
  final String? thumbPath;

  CaptureSession withTitle(String title) {
    return CaptureSession(
      id: id,
      userId: userId,
      status: status,
      title: title,
      startedAt: startedAt,
      completedAt: completedAt,
      deviceModel: deviceModel,
      latitude: latitude,
      longitude: longitude,
      previewPath: previewPath,
      thumbPath: thumbPath,
    );
  }

  factory CaptureSession.fromJson(Map<String, dynamic> json) {
    return CaptureSession(
      id: _requireString(json, 'id'),
      userId: _requireString(json, 'user_id'),
      title: _optionalString(json['title']),
      startedAt: _optionalDateTime(json['started_at']),
      completedAt: _optionalDateTime(json['completed_at']),
      status: SessionStatus.parse(json['status']),
      deviceModel: _optionalString(json['device_model']),
      latitude: _optionalDouble(json['latitude'], 'latitude'),
      longitude: _optionalDouble(json['longitude'], 'longitude'),
      previewPath: _optionalString(json['preview_path']),
      thumbPath: _optionalString(json['thumb_path']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'title': title,
      'started_at': startedAt?.toUtc().toIso8601String(),
      'completed_at': completedAt?.toUtc().toIso8601String(),
      'status': status.wire,
      'device_model': deviceModel,
      'latitude': latitude,
      'longitude': longitude,
      'preview_path': previewPath,
      'thumb_path': thumbPath,
    };
  }
}

String _requireString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String && value.isNotEmpty) return value;
  throw FormatException('Session field $key must be a non-empty string');
}

String? _optionalString(Object? value) {
  if (value == null) return null;
  if (value is String) return value;
  throw FormatException('Expected a string, got ${value.runtimeType}');
}

double? _optionalDouble(Object? value, String field) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  throw FormatException('Session field $field must be a number');
}

DateTime? _optionalDateTime(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value.toUtc();
  if (value is String && value.isNotEmpty) return DateTime.parse(value).toUtc();
  throw FormatException('Expected a timestamp, got $value');
}
