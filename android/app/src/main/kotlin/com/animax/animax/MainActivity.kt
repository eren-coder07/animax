package com.animax.animax

import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
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
                    "getCookies" -> {
                        // Full cookie jar for [url] — includes HttpOnly cookies
                        // (cf_clearance) that document.cookie hides. Used by the
                        // EgyDead Cloudflare gate to hand cookies to EgyApi.
                        val url = call.argument<String>("url") ?: ""
                        try {
                            val cm = android.webkit.CookieManager.getInstance()
                            cm.setAcceptCookie(true)
                            cm.flush()
                            result.success(cm.getCookie(url) ?: "")
                        } catch (e: Exception) {
                            result.error("cookie_error", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
