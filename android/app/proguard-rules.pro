# Flutter embedding and plugins. R8 must keep these or release builds
# crash before Dart starts. supabase_flutter talks to its plugins through
# these channels. drift's sqlite3 library is a Dart FFI .so, not a Java class;
# shrinking resources must not drop native libraries the loader opens by name.
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.embedding.**

-keep class com.example.camra360.MainActivity { *; }

-keep class dev.fluttercommunity.plus.connectivity.** { *; }
-keep class com.tekartik.sqflite.** { *; }

-dontwarn com.google.android.play.core.**
