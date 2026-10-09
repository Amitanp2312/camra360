/// One still aimed at a sphere target. Orientation is in degrees.
class Capture {
  const Capture({
    required this.id,
    required this.sessionId,
    required this.userId,
    required this.storagePath,
    required this.yaw,
    required this.pitch,
    this.roll,
    this.fov,
    this.width,
    this.height,
    this.capturedAt,
  });

  final String id;
  final String sessionId;
  final String userId;
  final String storagePath;
  final double yaw;
  final double pitch;
  final double? roll;
  final double? fov;
  final int? width;
  final int? height;
  final DateTime? capturedAt;

  factory Capture.fromJson(Map<String, dynamic> json) {
    return Capture(
      id: _requireString(json, 'id'),
      sessionId: _requireString(json, 'session_id'),
      userId: _requireString(json, 'user_id'),
      storagePath: _requireString(json, 'storage_path'),
      yaw: _requireDouble(json, 'yaw'),
      pitch: _requireDouble(json, 'pitch'),
      roll: _optionalDouble(json['roll'], 'roll'),
      fov: _optionalDouble(json['fov'], 'fov'),
      width: _optionalInt(json['width'], 'width'),
      height: _optionalInt(json['height'], 'height'),
      capturedAt: _optionalDateTime(json['captured_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'session_id': sessionId,
      'user_id': userId,
      'storage_path': storagePath,
      'yaw': yaw,
      'pitch': pitch,
      'roll': roll,
      'fov': fov,
      'width': width,
      'height': height,
      'captured_at': capturedAt?.toUtc().toIso8601String(),
    };
  }
}

String _requireString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String && value.isNotEmpty) return value;
  throw FormatException('Capture field $key must be a non-empty string');
}

double _requireDouble(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is num) return value.toDouble();
  throw FormatException('Capture field $key must be a number');
}

double? _optionalDouble(Object? value, String field) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  throw FormatException('Capture field $field must be a number');
}

int? _optionalInt(Object? value, String field) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  throw FormatException('Capture field $field must be an integer');
}

DateTime? _optionalDateTime(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value.toUtc();
  if (value is String && value.isNotEmpty) return DateTime.parse(value).toUtc();
  throw FormatException('Expected a timestamp, got $value');
}
