# Sphere360

Android app for live 360° capture. You stand still and sweep the phone. The preview shows target dots on a sphere, and a steady aim captures a tile. Finished sessions are stored in Supabase and reopen as a 360° panorama.

The stitch uses the saved yaw and pitch of each tile. It does not match image features.

## Setup

1. Install Flutter stable and an Android SDK. The app targets Android only, with `minSdk` 24.
2. Copy `.env.example` to `.env` in the project root.
3. Set `SUPABASE_URL` to the project root, for example `https://YOUR_PROJECT_REF.supabase.co`. Do not append `/rest/v1` or `/auth/v1`.
4. Set `SUPABASE_ANON_KEY` to the project's anon or publishable key. `.env` is gitignored. `.env.example` stays as the template.
5. In the Supabase SQL editor, run `supabase/schema.sql`. That creates `sessions`, `captures`, `hotspots`, row level security, grants for signed-in users, and the private `panoramas` bucket.
6. If the tables already exist, run the `hotspots` table, its policy, and the three `grant` statements, then `notify pgrst, 'reload schema';`.
7. Run the app on a device. After any `.env` change, stop and start the app again. Hot reload does not reload that asset.

Sign up with email and password. If the project requires email confirmation, confirm the address, then sign in.

## Capture

Open live capture from the gallery camera button. Allow the camera when asked. Aim at the white dots until they turn green. Finish is available after about 80% of the dots are captured. The app then builds the panorama, uploads `preview.jpg` and `thumb.jpg`, and opens the viewer.

The place icon on the live screen is off until you turn it on. Turning it on explains the request, asks for location permission, and stores latitude and longitude on that session only.

Shots are queued on the phone. In airplane mode they stay queued and upload when the network returns. Settings can limit that queue to Wi-Fi. The same screen lists photos still waiting and retries them.

The panorama JPEG is 1600 pixels wide, or 2400 if you pick that in settings. Location stays off until you turn it on there or on the capture screen.

Rename and delete are on each gallery card and in the viewer. Delete removes the session row, its captures, its hotspots, and the files in that session folder. Long-press a card to select several, then delete them together.

## Viewing

Open a finished session and tap View 360°. The 360 view follows the phone. Little Planet is a stereographic view: pinch to zoom and drag to turn it.

Long-press the panorama to label a hotspot. Tap a pin to read it or delete it.

Save writes a 1080×1080 little-planet JPEG and the equirectangular JPEG to Pictures/Sphere360. Share sends those files through the share sheet, or a link to `preview.jpg` that expires in 24 hours or 7 days.

Settings has Compare seams. In the 360 view, Before blend shows the same photos with exposure matching and edge feathering turned off. After blend is the panorama the app saves.

## Release

The app id is `app.sphere360`. The name on the phone is Sphere360. The window opens on a dark splash with an amber ring, and the launcher icon is the same ring.

Release builds shrink Java code with R8. `android/app/proguard-rules.pro` keeps the Flutter embedding, the plugin classes `supabase_flutter` uses, and the activity that owns the device channel. drift loads `sqlite3` through Dart FFI, so those native libraries stay in the APK.

A store build is signed with `android/key.properties`, which is gitignored:

```properties
storePassword=YOUR_STORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=upload
storeFile=C:/path/to/upload-keystore.jks
```

`storeFile` is resolved from `android/app`. Create the key once, and do not commit the `.jks`:

```bash
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Without `key.properties`, `flutter build apk --release` and `flutter build appbundle --release` still run, signed with the debug key so the build can be installed for a check. Play Console needs the upload key.

```bash
flutter build appbundle --release
flutter build apk --release
```

The app bundle is `build/app/outputs/bundle/release/app-release.aab`. The APK is `build/app/outputs/flutter-apk/app-release.apk`.

## Troubleshooting

**Invalid path in the request URL.** `SUPABASE_URL` includes a path such as `/rest/v1`. Use only the project root and restart the app.

**Could not find the table `public.sessions`.** `supabase/schema.sql` has not been applied. Run it in the SQL editor. If the table is already there, run `notify pgrst, 'reload schema';`.

**Permission denied for table `sessions`.** The signed-in role has no table grant. Run:

```sql
grant select, insert, update, delete on table public.sessions to authenticated;
grant select, insert, update, delete on table public.captures to authenticated;
grant select, insert, update, delete on table public.hotspots to authenticated;
```

**Camera preview stays black or the permission screen returns.** Allow the camera. If Android already blocked it, use Open settings on that screen and enable the camera for Sphere360.

**Gallery or viewer keeps spinning.** Those screens stop waiting after 25 seconds and show a retry. Check that the device is online and that the schema grants above were applied.

**`dart.exe` was blocked by Device Guard.** Windows Smart App Control is blocking the Flutter SDK. That is outside the app. The project itself does not start that process.

**Finish does not open a panorama.** Finish needs the captured photos, either still on the phone or already uploaded. If stitching fails, the session stays in progress and Finish can be tried again.

**Uploads sit in Settings while the phone is online.** Upload on Wi-Fi only is turned on, and the phone is on mobile data. Turn that off, or use Retry uploads once Wi-Fi is back.

**Delete my panoramas left the login in place.** That action removes sessions, hotspots, stored photos, and the local queue, then signs out. The Supabase auth user remains so the same email can sign in again.
