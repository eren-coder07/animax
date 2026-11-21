package com.animax.animax

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import com.google.android.gms.nearby.Nearby
import com.google.android.gms.nearby.connection.AdvertisingOptions
import com.google.android.gms.nearby.connection.ConnectionInfo
import com.google.android.gms.nearby.connection.ConnectionLifecycleCallback
import com.google.android.gms.nearby.connection.ConnectionResolution
import com.google.android.gms.nearby.connection.ConnectionsClient
import com.google.android.gms.nearby.connection.ConnectionsStatusCodes
import com.google.android.gms.nearby.connection.DiscoveredEndpointInfo
import com.google.android.gms.nearby.connection.DiscoveryOptions
import com.google.android.gms.nearby.connection.EndpointDiscoveryCallback
import com.google.android.gms.nearby.connection.Payload
import com.google.android.gms.nearby.connection.PayloadCallback
import com.google.android.gms.nearby.connection.PayloadTransferUpdate
import com.google.android.gms.nearby.connection.Strategy
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.io.FileInputStream

/**
 * Offline phone-to-phone transfer of a downloaded file over Google Nearby
 * Connections (Bluetooth + Wi-Fi Direct / hotspot, no internet needed).
 *
 * Sender advertises, receiver discovers and picks the sender. Both sides
 * see the same 4-digit code and must accept. The sender then sends a small
 * BYTES payload with the file's metadata followed by the FILE payload; the
 * receiver saves it to Download/Animax/Videos (or Clips / Comics).
 *
 * Events go to Dart over [events] ("animax/nearby"): found, lost, auth,
 * connected, progress, received, sent, error, disconnected.
 */
class NearbyHelper(private val ctx: Context, private val events: MethodChannel) {
    private val main = Handler(Looper.getMainLooper())
    private val client: ConnectionsClient = Nearby.getConnectionsClient(ctx)
    private val strategy = Strategy.P2P_POINT_TO_POINT

    // Sender state.
    private var sendUri: String = ""
    private var sendMeta: JSONObject? = null
    private var sendPfd: ParcelFileDescriptor? = null
    private var filePayloadId: Long = 0L

    // Receiver state.
    private var incomingMeta: JSONObject? = null
    private val incoming = HashMap<Long, Payload>()
    private var connectedTo: String? = null

    private fun emit(name: String, args: Map<String, Any?>) {
        main.post { try { events.invokeMethod(name, args) } catch (_: Exception) {} }
    }

    // ---------------------------------------------------------------- sender

    fun startSending(myName: String, uri: String, meta: Map<String, Any?>, result: MethodChannel.Result) {
        stop()
        sendUri = uri
        sendMeta = JSONObject(meta)
        client.startAdvertising(
            myName, SERVICE_ID, lifecycle,
            AdvertisingOptions.Builder().setStrategy(strategy).build()
        ).addOnSuccessListener { result.success(true) }
            .addOnFailureListener { e -> result.error("nearby", errorText(e), null) }
    }

    // -------------------------------------------------------------- receiver

    fun startReceiving(result: MethodChannel.Result) {
        stop()
        client.startDiscovery(
            SERVICE_ID, discovery,
            DiscoveryOptions.Builder().setStrategy(strategy).build()
        ).addOnSuccessListener { result.success(true) }
            .addOnFailureListener { e -> result.error("nearby", errorText(e), null) }
    }

    fun connect(myName: String, endpointId: String, result: MethodChannel.Result) {
        client.requestConnection(myName, endpointId, lifecycle)
            .addOnSuccessListener { result.success(true) }
            .addOnFailureListener { e -> result.error("nearby", errorText(e), null) }
    }

    // ---------------------------------------------------------------- common

    fun accept(endpointId: String, result: MethodChannel.Result) {
        client.acceptConnection(endpointId, payloads)
            .addOnSuccessListener { result.success(true) }
            .addOnFailureListener { e -> result.error("nearby", errorText(e), null) }
    }

    fun reject(endpointId: String) {
        try { client.rejectConnection(endpointId) } catch (_: Exception) {}
    }

    fun stop() {
        try { client.stopAdvertising() } catch (_: Exception) {}
        try { client.stopDiscovery() } catch (_: Exception) {}
        try { client.stopAllEndpoints() } catch (_: Exception) {}
        try { sendPfd?.close() } catch (_: Exception) {}
        sendPfd = null
        connectedTo = null
        incomingMeta = null
        incoming.clear()
    }

    private val discovery = object : EndpointDiscoveryCallback() {
        override fun onEndpointFound(endpointId: String, info: DiscoveredEndpointInfo) {
            emit("found", mapOf("id" to endpointId, "name" to info.endpointName))
        }

        override fun onEndpointLost(endpointId: String) {
            emit("lost", mapOf("id" to endpointId))
        }
    }

    private val lifecycle = object : ConnectionLifecycleCallback() {
        override fun onConnectionInitiated(endpointId: String, info: ConnectionInfo) {
            emit(
                "auth", mapOf(
                    "id" to endpointId,
                    "name" to info.endpointName,
                    "code" to info.authenticationDigits,
                    "incoming" to info.isIncomingConnection
                )
            )
        }

        override fun onConnectionResult(endpointId: String, result: ConnectionResolution) {
            if (result.status.statusCode != ConnectionsStatusCodes.STATUS_OK) {
                emit("error", mapOf("message" to "رفض الجهاز الآخر الاتصال أو انقطع."))
                return
            }
            connectedTo = endpointId
            try { client.stopDiscovery() } catch (_: Exception) {}
            try { client.stopAdvertising() } catch (_: Exception) {}
            emit("connected", mapOf("id" to endpointId))
            if (sendMeta != null) sendFile(endpointId)
        }

        override fun onDisconnected(endpointId: String) {
            emit("disconnected", mapOf("id" to endpointId))
        }
    }

    private fun sendFile(endpointId: String) {
        try {
            val filePayload: Payload = if (sendUri.startsWith("content://")) {
                val pfd = ctx.contentResolver.openFileDescriptor(Uri.parse(sendUri), "r")
                    ?: throw IllegalStateException("cannot open file")
                sendPfd = pfd
                Payload.fromFile(pfd)
            } else {
                Payload.fromFile(File(sendUri))
            }
            filePayloadId = filePayload.id
            val meta = sendMeta!!
            meta.put("payloadId", filePayload.id)
            client.sendPayload(endpointId, Payload.fromBytes(meta.toString().toByteArray(Charsets.UTF_8)))
            client.sendPayload(endpointId, filePayload)
        } catch (e: Exception) {
            emit("error", mapOf("message" to "تعذّر فتح الملف للإرسال: ${e.message}"))
        }
    }

    private val payloads = object : PayloadCallback() {
        override fun onPayloadReceived(endpointId: String, payload: Payload) {
            when (payload.type) {
                Payload.Type.BYTES -> {
                    try {
                        incomingMeta = JSONObject(String(payload.asBytes()!!, Charsets.UTF_8))
                        emit("meta", jsonToMap(incomingMeta!!))
                    } catch (_: Exception) {}
                }
                Payload.Type.FILE -> incoming[payload.id] = payload
                else -> {}
            }
        }

        override fun onPayloadTransferUpdate(endpointId: String, update: PayloadTransferUpdate) {
            val isFile = update.payloadId == filePayloadId || incoming.containsKey(update.payloadId)
            if (!isFile) return
            when (update.status) {
                PayloadTransferUpdate.Status.IN_PROGRESS -> emit(
                    "progress",
                    mapOf("bytes" to update.bytesTransferred, "total" to update.totalBytes)
                )
                PayloadTransferUpdate.Status.SUCCESS -> {
                    if (update.payloadId == filePayloadId) {
                        emit("sent", mapOf("bytes" to update.totalBytes))
                    } else {
                        val p = incoming.remove(update.payloadId) ?: return
                        saveIncoming(p)
                    }
                }
                PayloadTransferUpdate.Status.FAILURE,
                PayloadTransferUpdate.Status.CANCELED -> {
                    incoming.remove(update.payloadId)
                    emit("error", mapOf("message" to "انقطع النقل — قرّب الجهازين وحاول مجددًا."))
                }
                else -> {}
            }
        }
    }

    /** Copies a finished incoming file into Download/Animax/… */
    private fun saveIncoming(p: Payload) {
        val meta = incomingMeta ?: JSONObject()
        val name = meta.optString("name").ifBlank { "Animax ${System.currentTimeMillis()}.mp4" }
        val mime = meta.optString("mime").ifBlank { "video/mp4" }
        val folder = when {
            mime.startsWith("image/") -> "Clips"
            mime == "application/pdf" -> "Comics"
            else -> "Videos"
        }
        Thread {
            val tmp = File(ctx.cacheDir, "nearby_${System.currentTimeMillis()}")
            try {
                val f = p.asFile() ?: throw IllegalStateException("no file")
                val pfd = f.asParcelFileDescriptor()
                FileInputStream(pfd.fileDescriptor).use { inp ->
                    tmp.outputStream().use { out -> inp.copyTo(out, 1 shl 16) }
                }
                try { pfd.close() } catch (_: Exception) {}
                // Nearby leaves its own copy behind — remove it.
                try { f.asUri()?.let { ctx.contentResolver.delete(it, null, null) } } catch (_: Exception) {}
                @Suppress("DEPRECATION")
                try { f.asJavaFile()?.delete() } catch (_: Exception) {}
                DownloadHelper.publish(ctx, tmp.absolutePath, name, mime, folder) { res, err ->
                    if (res == null) {
                        emit("error", mapOf("message" to "تعذّر حفظ الملف: ${err ?: ""}"))
                    } else {
                        val out = HashMap<String, Any?>(jsonToMap(meta))
                        out["uri"] = res["uri"]
                        out["location"] = res["location"]
                        out["size"] = tmp.length().takeIf { it > 0 } ?: meta.optLong("size")
                        emit("received", out)
                    }
                }
            } catch (e: Exception) {
                emit("error", mapOf("message" to "تعذّر حفظ الملف المستلم: ${e.message}"))
            }
        }.start()
    }

    private fun jsonToMap(j: JSONObject): Map<String, Any?> {
        val m = HashMap<String, Any?>()
        val it = j.keys()
        while (it.hasNext()) {
            val k = it.next()
            m[k] = j.opt(k)
        }
        return m
    }

    private fun errorText(e: Exception): String {
        val msg = e.message ?: ""
        return when {
            msg.contains("8038") || msg.contains("MISSING_PERMISSION") ->
                "يلزم السماح بأذونات الأجهزة القريبة/الموقع."
            msg.contains("8001") || msg.contains("ALREADY") -> "العملية تعمل بالفعل."
            msg.contains("SERVICE_INVALID") || msg.contains("API_UNAVAILABLE") ||
                msg.contains("SERVICE_MISSING") ->
                "خدمات Google Play غير متوفرة على هذا الجهاز."
            else -> "تعذّر بدء الاتصال القريب: $msg"
        }
    }

    companion object {
        const val SERVICE_ID = "com.animax.animax.share"
    }
}
