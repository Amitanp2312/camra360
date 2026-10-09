/// Shared names for env vars, tables, and the private panoramas bucket.
abstract final class AppConstants {
  static const appName = 'Sphere360';

  static const supabaseUrlKey = 'SUPABASE_URL';
  static const supabaseAnonKeyKey = 'SUPABASE_ANON_KEY';

  static const sessionsTable = 'sessions';
  static const capturesTable = 'captures';
  static const hotspotsTable = 'hotspots';
  static const panoramasBucket = 'panoramas';

  /// Signed URLs used by the gallery and viewer. One hour is long enough
  /// for a viewing session and short enough that a leaked link expires.
  static const signedUrlTtlSeconds = 3600;

  /// Choices shown when someone shares `preview.jpg`.
  static const shareLinkDaySeconds = 24 * 60 * 60;
  static const shareLinkWeekSeconds = 7 * 24 * 60 * 60;

  /// Square little-planet JPEG written to the gallery.
  static const planetExportSize = 1080;

  static const minPasswordLength = 6;

  /// Equirectangular size used when a session has no `preview.jpg` yet.
  static const fallbackPreviewWidth = 1024;

  /// Horizontal field of view assumed when a capture row has no `fov`.
  static const fallbackHorizontalFov = 70.0;

  /// A target is aimed when the look direction is closer than this, in degrees.
  ///
  /// Wide enough that a steady handheld aim can land, and still inside one tile.
  static const captureAlignDegrees = 7.0;

  /// Turn rate, in degrees per second, below which a held aim can capture.
  static const captureMaxAngularSpeed = 45.0;

  /// How long the aim and turn-rate conditions must hold before the shutter fires.
  static const captureDwell = Duration(milliseconds: 220);

  /// Longest edge of a stored tile, in pixels.
  static const captureMaxEdge = 2048;

  static const captureJpegQuality = 93;

  /// Finish is available once this fraction of the targets has been shot.
  static const finishCoverage = 0.8;

  /// Equirectangular widths offered in settings. The stitch paints in strips,
  /// so neither width allocates a full-frame float buffer.
  static const previewWidthStandard = 1600;
  static const previewWidthHigh = 2400;

  /// Longest edge of a tile while it is being projected into the preview.
  ///
  /// The short edge stays in proportion, so a portrait photo is not stretched.
  static const stitchSourceMaxEdge = 512;

  static const stitchPreviewQuality = 80;

  /// Longest edge of `thumb.jpg`.
  static const stitchThumbWidth = 400;

  /// Equirectangular map updated on the capture screen after each shot.
  static const livePreviewWidth = 640;

  /// Longest edge of a photo while it is stamped onto the live map.
  static const livePreviewSourceMaxEdge = 256;

  /// Bound for gallery, viewer, and other Supabase calls that can hang.
  static const networkTimeout = Duration(seconds: 25);

  /// A full photo download on a slow connection. Longer than [networkTimeout]
  /// because these files are much larger than a session list.
  static const imageDownloadTimeout = Duration(seconds: 90);
}
