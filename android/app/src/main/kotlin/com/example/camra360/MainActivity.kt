package com.example.camra360

import android.Manifest
import android.annotation.SuppressLint
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.hardware.camera2.CameraAccessException
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import kotlin.math.atan
import kotlin.math.abs
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var locationManager: LocationManager? = null
    private var locationListener: LocationListener? = null
    private var locationTimeout: Runnable? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sphere360/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "model" -> result.success("${Build.MANUFACTURER} ${Build.MODEL}".trim())
                    "location" -> readLocation(result)
                    "fov" -> result.success(lensFov(call.argument<String>("cameraId")))
                    "saveJpegs" -> saveJpegs(call, result)
                    "shareJpegs" -> shareJpegs(call, result)
                    "shareText" -> shareText(call, result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun saveJpegs(call: MethodCall, result: MethodChannel.Result) {
        val files = jpegFiles(call)
        if (files.isEmpty()) {
            result.error("empty", "Nothing to save.", null)
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q &&
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.WRITE_EXTERNAL_STORAGE,
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            result.error("permission", "Storage permission is not granted.", null)
            return
        }
        try {
            for ((name, bytes) in files) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    saveWithMediaStore(name, bytes)
                } else {
                    saveToPictures(name, bytes)
                }
            }
            result.success(null)
        } catch (error: Exception) {
            result.error("save", error.message ?: "Could not save the photos.", null)
        }
    }

    private fun saveWithMediaStore(name: String, bytes: ByteArray) {
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, name)
            put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
            put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/Sphere360")
            put(MediaStore.Images.Media.IS_PENDING, 1)
        }
        val uri = contentResolver.insert(
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            values,
        ) ?: throw IllegalStateException("The gallery did not accept the photo.")
        val stream = contentResolver.openOutputStream(uri)
            ?: throw IllegalStateException("The gallery did not accept the photo.")
        stream.use { it.write(bytes) }
        values.clear()
        values.put(MediaStore.Images.Media.IS_PENDING, 0)
        contentResolver.update(uri, values, null, null)
    }

    private fun saveToPictures(name: String, bytes: ByteArray) {
        val dir = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES),
            "Sphere360",
        )
        if (!dir.exists() && !dir.mkdirs()) {
            throw IllegalStateException("Could not create the Pictures folder.")
        }
        val file = File(dir, name)
        file.writeBytes(bytes)
        MediaScannerConnection.scanFile(this, arrayOf(file.absolutePath), arrayOf("image/jpeg"), null)
    }

    private fun shareJpegs(call: MethodCall, result: MethodChannel.Result) {
        val files = jpegFiles(call)
        if (files.isEmpty()) {
            result.error("empty", "Nothing to share.", null)
            return
        }
        try {
            val folder = File(cacheDir, "share")
            if (!folder.exists()) folder.mkdirs()
            folder.listFiles()?.forEach { it.delete() }
            val uris = ArrayList<Uri>()
            val authority = "$packageName.fileprovider"
            for ((name, bytes) in files) {
                val file = File(folder, name)
                file.writeBytes(bytes)
                uris.add(FileProvider.getUriForFile(this, authority, file))
            }
            val send = Intent(Intent.ACTION_SEND_MULTIPLE).apply {
                type = "image/jpeg"
                putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            val chooser = Intent.createChooser(send, "Share panorama")
            chooser.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            startActivity(chooser)
            result.success(null)
        } catch (error: Exception) {
            result.error("share", error.message ?: "Could not share the photos.", null)
        }
    }

    private fun shareText(call: MethodCall, result: MethodChannel.Result) {
        val text = call.argument<String>("text")
        if (text.isNullOrBlank()) {
            result.error("empty", "Nothing to share.", null)
            return
        }
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, text)
        }
        startActivity(Intent.createChooser(send, "Share link"))
        result.success(null)
    }

    private fun jpegFiles(call: MethodCall): List<Pair<String, ByteArray>> {
        val raw = call.argument<List<*>>("files") ?: return emptyList()
        val files = ArrayList<Pair<String, ByteArray>>()
        for (item in raw) {
            val map = item as? Map<*, *> ?: continue
            val name = map["name"] as? String ?: continue
            val bytes = map["bytes"] as? ByteArray ?: continue
            files.add(safeJpegName(name) to bytes)
        }
        return files
    }

    private fun safeJpegName(name: String): String {
        val cleaned = name.replace(Regex("[^A-Za-z0-9._-]"), "_")
        val base = cleaned.ifBlank { "sphere360.jpg" }
        return if (base.endsWith(".jpg", ignoreCase = true)) base else "$base.jpg"
    }

    private fun lensFov(cameraId: String?): Map<String, Double>? {
        return try {
            val manager = getSystemService(CAMERA_SERVICE) as CameraManager
            val ids = manager.cameraIdList
            val id = cameraId?.takeIf { it in ids }
                ?: ids.firstOrNull { facingBack(manager, it) }
                ?: return null
            val chars = manager.getCameraCharacteristics(id)
            val focals = chars.get(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS)
                ?: return null
            val physical = chars.get(CameraCharacteristics.SENSOR_INFO_PHYSICAL_SIZE)
                ?: return null
            val pixels = chars.get(CameraCharacteristics.SENSOR_INFO_PIXEL_ARRAY_SIZE)
                ?: return null
            val active = chars.get(CameraCharacteristics.SENSOR_INFO_ACTIVE_ARRAY_SIZE)
                ?: return null
            if (pixels.width <= 0 || pixels.height <= 0) return null
            val activeWidth = active.width() * physical.width / pixels.width
            val activeHeight = active.height() * physical.height / pixels.height
            val focal = focals.minByOrNull { candidate ->
                abs(fieldOfView(activeWidth, candidate) - 70.0)
            } ?: return null
            mapOf(
                "horizontal" to fieldOfView(activeWidth, focal),
                "vertical" to fieldOfView(activeHeight, focal),
            )
        } catch (_: CameraAccessException) {
            null
        } catch (_: IllegalArgumentException) {
            null
        }
    }

    private fun facingBack(manager: CameraManager, cameraId: String): Boolean {
        val facing = manager
            .getCameraCharacteristics(cameraId)
            .get(CameraCharacteristics.LENS_FACING)
        return facing == CameraCharacteristics.LENS_FACING_BACK
    }

    private fun fieldOfView(sizeMm: Float, focalMm: Float): Double {
        if (sizeMm <= 0f || focalMm <= 0f) return 0.0
        return Math.toDegrees(2.0 * atan((sizeMm / (2f * focalMm)).toDouble()))
    }

    override fun onDestroy() {
        stopLocationUpdates()
        super.onDestroy()
    }

    @SuppressLint("MissingPermission")
    private fun readLocation(result: MethodChannel.Result) {
        val fine = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.ACCESS_FINE_LOCATION,
        )
        val coarse = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.ACCESS_COARSE_LOCATION,
        )
        if (fine != PackageManager.PERMISSION_GRANTED &&
            coarse != PackageManager.PERMISSION_GRANTED
        ) {
            result.error("permission", "Location permission is not granted.", null)
            return
        }

        stopLocationUpdates()
        val manager = getSystemService(LOCATION_SERVICE) as LocationManager
        locationManager = manager
        val best = newestKnownLocation(manager)
        val fresh = best != null && System.currentTimeMillis() - best.time < 5 * 60 * 1000
        if (best != null && fresh) {
            result.success(locationMap(best))
            return
        }

        val provider = listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)
            .firstOrNull { manager.isProviderEnabled(it) }
        if (provider == null) {
            if (best != null) {
                result.success(locationMap(best))
            } else {
                result.error("unavailable", "Location is turned off on this phone.", null)
            }
            return
        }

        var finished = false
        fun finish(value: Map<String, Double>?) {
            if (finished) return
            finished = true
            stopLocationUpdates()
            result.success(value)
        }

        val listener = LocationListener { location ->
            finish(locationMap(location))
        }
        val timeout = Runnable {
            finish(best?.let { locationMap(it) })
        }
        locationListener = listener
        locationTimeout = timeout
        mainHandler.postDelayed(timeout, 12_000)
        try {
            manager.requestLocationUpdates(provider, 0L, 0f, listener, Looper.getMainLooper())
        } catch (_: SecurityException) {
            finished = true
            stopLocationUpdates()
            result.error("permission", "Location permission is not granted.", null)
        }
    }

    @SuppressLint("MissingPermission")
    private fun newestKnownLocation(manager: LocationManager): Location? {
        var best: Location? = null
        for (provider in listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)) {
            val known = try {
                manager.getLastKnownLocation(provider)
            } catch (_: SecurityException) {
                null
            } ?: continue
            if (best == null || known.time > best.time) best = known
        }
        return best
    }

    private fun stopLocationUpdates() {
        locationListener?.let { listener ->
            try {
                locationManager?.removeUpdates(listener)
            } catch (_: SecurityException) {
            }
        }
        locationTimeout?.let { mainHandler.removeCallbacks(it) }
        locationListener = null
        locationTimeout = null
    }

    private fun locationMap(location: Location): Map<String, Double> {
        return mapOf(
            "latitude" to location.latitude,
            "longitude" to location.longitude,
        )
    }
}
