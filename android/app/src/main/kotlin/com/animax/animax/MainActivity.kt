package com.animax.animax

import android.Manifest
import android.app.PictureInPictureParams
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.content.Intent
import android.content.res.Configuration
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.util.Rational
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingStorageResult: MethodChannel.Result? = null
    private var pendingNearbyResult: MethodChannel.Result? = null
    private var nearby: NearbyHelper? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private val main = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val nearbyChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "animax/nearby")
        nearbyChannel.setMethodCallHandler { call, result ->
            try {
                val nb = nearby ?: NearbyHelper(applicationContext, nearbyChannel).also { nearby = it }
                when (call.method) {
                    "permissions" -> requestNearbyPermissions(result)
                    "send" -> {
                        @Suppress("UNCHECKED_CAST")
                        val meta = (call.argument<Map<String, Any?>>("meta") ?: emptyMap())
                        nb.startSending(
                            call.argument<String>("name") ?: "Animax",
                            call.argument<String>("uri") ?: "",
                            meta, result
                        )
                    }
                    "receive" -> nb.startReceiving(result)
                    "connect" -> nb.connect(
                        call.argument<String>("name") ?: "Animax",
                        call.argument<String>("id") ?: "", result
                    )
                    "accept" -> nb.accept(call.argument<String>("id") ?: "", result)
                    "reject" -> { nb.reject(call.argument<String>("id") ?: ""); result.success(true) }
                    "stop" -> { nb.stop(); result.success(true) }
                    else -> result.notImplemented()
                }
            } catch (e: Throwable) {
                // e.g. Google Play services missing on this device.
                result.error("nearby", "خدمات Google Play غير متوفرة: ${e.message}", null)
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "animax/app")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openUrl" -> {
                        val url = call.argument<String>("url")
                        if (url.isNullOrBlank()) {
                            result.error("bad_args", "url is required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("no_handler", e.message, null)
                        }
                    }
                    "setKeepScreenOn" -> {
                        val keep = call.argument<Boolean>("keep") ?: false
                        runOnUiThread {
                            if (keep) {
                                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            } else {
                                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            }
                            result.success(true)
                        }
                    }
                    "setBrightness" -> {
                        // value: 0.01..1.0 (dimmed player), null = system default
                        val value = call.argument<Double>("value")
                        runOnUiThread {
                            val lp = window.attributes
                            lp.screenBrightness = if (value == null || value <= 0.0) {
                                WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
                            } else {
                                value.toFloat().coerceIn(0.01f, 1.0f)
                            }
                            window.attributes = lp
                            result.success(true)
                        }
                    }
                    "getBrightness" -> {
                        val b = window.attributes.screenBrightness
                        result.success(if (b < 0f) null else b.toDouble())
                    }
                    "enterPip" -> {
                        // Picture-in-Picture (Android 8+) for the video players.
                        try {
                            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                                result.success(false)
                                return@setMethodCallHandler
                            }
                            val params = PictureInPictureParams.Builder()
                                .setAspectRatio(Rational(16, 9))
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                                params.setSeamlessResizeEnabled(true)
                            }
                            enterPictureInPictureMode(params.build())
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("pip_error", e.message, null)
                        }
                    }
                    "netSpeedKbps" -> {
                        // Estimated downstream bandwidth of the active network.
                        try {
                            val cm = getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager
                            val caps = cm.getNetworkCapabilities(cm.activeNetwork)
                            result.success(caps?.linkDownstreamBandwidthKbps ?: -1)
                        } catch (e: Exception) {
                            result.success(-1)
                        }
                    }
                    "networkType" -> {
                        // Wi-Fi / cellular / none — used by the bandwidth-based
                        // auto quality picker (hls_quality.dart).
                        try {
                            val cm = getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager
                            val caps = cm.getNetworkCapabilities(cm.activeNetwork)
                            val type = when {
                                caps == null -> "none"
                                caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
                                caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
                                else -> "other"
                            }
                            result.success(type)
                        } catch (e: Exception) {
                            result.error("net_error", e.message, null)
                        }
                    }
                    // ---- Downloads (see DownloadHelper / download_manager.dart) ----
                    "dlMux" -> {
                        val inputs = call.argument<List<String>>("inputs") ?: emptyList()
                        val output = call.argument<String>("output") ?: ""
                        Thread {
                            val ok = DownloadHelper.mux(inputs, output)
                            main.post { result.success(ok) }
                        }.start()
                    }
                    "dlPublish" -> {
                        val path = call.argument<String>("path") ?: ""
                        val name = call.argument<String>("name") ?: "animax"
                        val mime = call.argument<String>("mime") ?: "application/octet-stream"
                        val folder = call.argument<String>("folder") ?: "Files"
                        Thread {
                            DownloadHelper.publish(applicationContext, path, name, mime, folder) { map, err ->
                                main.post {
                                    if (map != null) result.success(map)
                                    else result.error("publish_failed", err, null)
                                }
                            }
                        }.start()
                    }
                    "dlOpen" -> {
                        val uri = call.argument<String>("uri") ?: ""
                        val mime = call.argument<String>("mime") ?: ""
                        result.success(DownloadHelper.open(this, uri, mime))
                    }
                    "dlShareFile" -> {
                        result.success(DownloadHelper.shareFile(
                            this,
                            call.argument<String>("uri") ?: "",
                            call.argument<String>("mime") ?: "",
                            call.argument<String>("text") ?: ""))
                    }
                    "shareText" -> {
                        result.success(DownloadHelper.shareText(
                            this, call.argument<String>("text") ?: ""))
                    }
                    "dlDelete" -> {
                        val uri = call.argument<String>("uri") ?: ""
                        result.success(DownloadHelper.delete(applicationContext, uri))
                    }
                    "dlEnsureStorage" -> {
                        // Only Android 9 and older need a permission to write
                        // into the public Download folder.
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q ||
                            checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) ==
                            PackageManager.PERMISSION_GRANTED
                        ) {
                            result.success(true)
                        } else if (pendingStorageResult != null) {
                            result.success(false)
                        } else {
                            pendingStorageResult = result
                            requestPermissions(
                                arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), 4711
                            )
                        }
                    }
                    "clipCut" -> {
                        val url = call.argument<String>("url") ?: ""
                        val headers = call.argument<Map<String, String>>("headers") ?: emptyMap()
                        val start = (call.argument<Number>("startMs") ?: 0).toLong()
                        val end = (call.argument<Number>("endMs") ?: 0).toLong()
                        val out = call.argument<String>("output") ?: ""
                        Thread {
                            val ok = DownloadHelper.cutClip(url, headers, start, end, out)
                            main.post { result.success(ok) }
                        }.start()
                    }
                    "dlFetch" -> {
                        val id = call.argument<String>("id") ?: ""
                        val url = call.argument<String>("url") ?: ""
                        val path = call.argument<String>("path") ?: ""
                        val headers = call.argument<Map<String, String>>("headers") ?: emptyMap()
                        DownloadHelper.startFetch(id, url, headers, path)
                        result.success(true)
                    }
                    "dlFetchStatus" -> {
                        result.success(DownloadHelper.fetchStatus(call.argument<String>("id") ?: ""))
                    }
                    "dlFetchCancel" -> {
                        DownloadHelper.cancelFetch(call.argument<String>("id") ?: "")
                        result.success(true)
                    }
                    "dlFreeSpace" -> {
                        try {
                            val st = android.os.StatFs(
                                Environment.getExternalStorageDirectory().absolutePath
                            )
                            result.success(st.availableBytes)
                        } catch (e: Exception) {
                            result.success(-1L)
                        }
                    }
                    "trafficBytes" -> {
                        // Cumulative bytes this app sent + received since boot
                        // (monthly data budget, data_budget.dart).
                        try {
                            val uid = android.os.Process.myUid()
                            val rx = android.net.TrafficStats.getUidRxBytes(uid)
                            val tx = android.net.TrafficStats.getUidTxBytes(uid)
                            if (rx < 0 || tx < 0) result.success(-1L) else result.success(rx + tx)
                        } catch (e: Exception) {
                            result.success(-1L)
                        }
                    }
                    "audioKeepAlive" -> {
                        val on = call.argument<Boolean>("on") ?: false
                        val i = Intent(this, AudioKeepService::class.java)
                        try {
                            if (on) {
                                i.putExtra("title", call.argument<String>("title") ?: "")
                                if (Build.VERSION.SDK_INT >= 26) startForegroundService(i) else startService(i)
                            } else {
                                stopService(i)
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    "dlKeepAlive" -> {
                        // Partial wake lock so a running download survives the
                        // screen turning off.
                        val on = call.argument<Boolean>("on") ?: false
                        try {
                            if (on) {
                                if (wakeLock == null) {
                                    val pm = getSystemService(POWER_SERVICE) as PowerManager
                                    wakeLock = pm.newWakeLock(
                                        PowerManager.PARTIAL_WAKE_LOCK, "animax:download"
                                    ).apply { setReferenceCounted(false) }
                                }
                                wakeLock?.acquire(3 * 60 * 60 * 1000L)
                            } else {
                                wakeLock?.let { if (it.isHeld) it.release() }
                            }
                        } catch (_: Exception) {}
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /** Runtime permissions Nearby Connections needs on this Android version. */
    private fun nearbyPermissionList(): Array<String> {
        val l = ArrayList<String>()
        if (Build.VERSION.SDK_INT >= 31) {
            l.add(Manifest.permission.BLUETOOTH_ADVERTISE)
            l.add(Manifest.permission.BLUETOOTH_CONNECT)
            l.add(Manifest.permission.BLUETOOTH_SCAN)
        }
        if (Build.VERSION.SDK_INT >= 33) {
            l.add(Manifest.permission.NEARBY_WIFI_DEVICES)
        } else if (Build.VERSION.SDK_INT >= 29) {
            l.add(Manifest.permission.ACCESS_FINE_LOCATION)
        } else {
            l.add(Manifest.permission.ACCESS_COARSE_LOCATION)
        }
        return l.toTypedArray()
    }

    private fun requestNearbyPermissions(result: MethodChannel.Result) {
        val missing = nearbyPermissionList().filter {
            checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isEmpty()) {
            result.success(true)
            return
        }
        if (pendingNearbyResult != null) {
            result.success(false)
            return
        }
        pendingNearbyResult = result
        requestPermissions(missing.toTypedArray(), 4713)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<out String>, grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 4713) {
            val ok = grantResults.isNotEmpty() &&
                grantResults.all { it == PackageManager.PERMISSION_GRANTED }
            pendingNearbyResult?.success(ok)
            pendingNearbyResult = null
            return
        }
        if (requestCode == 4711) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingStorageResult?.success(granted)
            pendingStorageResult = null
        }
    }

    override fun onDestroy() {
        try { nearby?.stop() } catch (_: Throwable) {}
        try { stopService(Intent(this, AudioKeepService::class.java)) } catch (_: Exception) {}
        wakeLock?.let { if (it.isHeld) it.release() }
        super.onDestroy()
    }

    override fun onPictureInPictureModeChanged(active: Boolean, config: Configuration) {
        super.onPictureInPictureModeChanged(active, config)
    }
}
