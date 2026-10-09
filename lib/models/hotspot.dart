/// A labeled look direction stored on a finished session.
class CaptureHotspot {
  const CaptureHotspot({
    required this.id,
    required this.sessionId,
    required this.userId,
    required this.yaw,
    required this.pitch,
    required this.label,
    this.createdAt,
  });

  final String id;
  final String sessionId;
  final String userId;

  /// Degrees. Zero looks along the panorama's forward axis.
  final double yaw;

  /// Degrees. Zero is the horizon. Positive looks up.
  final double pitch;

  final String label;
  final DateTime? createdAt;

  factory CaptureHotspot.fromJson(Map<String, dynamic> json) {
    return CaptureHotspot(
      id: _requireString(json, 'id'),
      sessionId: _requireString(json, 'session_id'),
      userId: _requireString(json, 'user_id'),
      yaw: _requireDouble(json, 'yaw'),
      pitch: _requireDouble(json, 'pitch'),
      label: _requireString(json, 'label'),
      createdAt: _optionalDateTime(json['created_at']),
    );
  }
}

String _requireString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String && value.isNotEmpty) return value;
  throw FormatException('Hotspot field $key must be a non-empty string');
}

double _requireDouble(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is num) return value.toDouble();
  throw FormatException('Hotspot field $key must be a number');
}

DateTime? _optionalDateTime(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value.toUtc();
  if (value is String && value.isNotEmpty) return DateTime.parse(value).toUtc();
  throw FormatException('Expected a timestamp, got $value');
}
