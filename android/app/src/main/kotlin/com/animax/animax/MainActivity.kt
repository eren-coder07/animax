package com.animax.animax

import android.app.PictureInPictureParams
import android.content.Intent
import android.content.res.Configuration
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Build
import android.util.Rational
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
                    else -> result.notImplemented()
                }
            }
    }

    override fun onPictureInPictureModeChanged(active: Boolean, config: Configuration) {
        super.onPictureInPictureModeChanged(active, config)
    }
}
