package com.animax.animax

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.nio.ByteBuffer
import java.util.concurrent.ConcurrentHashMap

/**
 * Native helpers for the Dart DownloadManager:
 *  - [mux]: joins HLS pieces (fMP4 / MPEG-TS video + optional separate
 *    audio) into one regular MP4 with MediaExtractor + MediaMuxer.
 *  - [publish]: copies a finished file into the public Download/Animax
 *    folder (MediaStore on Android 10+, legacy storage + media scan below).
 *  - [open] / [delete]: act on the published content:// URI.
 */
object DownloadHelper {

    // ---------------------------------------------------------------------
    // Native progressive download (HttpURLConnection = the same network stack
    // ExoPlayer uses, so it honours network_security_config — e.g. the
    // bundled intermediate for Akwam's CDN with its incomplete TLS chain).
    // Dart starts a fetch, then polls [fetchStatus].
    // ---------------------------------------------------------------------

    class FetchState {
        @Volatile var received = 0L
        @Volatile var total = 0L
        @Volatile var done = false
        @Volatile var error: String? = null
        @Volatile var cancelled = false
        @Volatile var contentType = ""
    }

    private val fetches = ConcurrentHashMap<String, FetchState>()

    fun startFetch(id: String, url: String, headers: Map<String, String>, path: String) {
        val st = FetchState()
        fetches[id] = st
        Thread {
            var attempt = 0
            val file = File(path)
            file.parentFile?.mkdirs()
            while (!st.cancelled && !st.done && st.error == null) {
                var conn: HttpURLConnection? = null
                try {
                    val have = if (file.exists()) file.length() else 0L
                    conn = (URL(url).openConnection() as HttpURLConnection).apply {
                        connectTimeout = 30000
                        readTimeout = 60000
                        instanceFollowRedirects = true
                        headers.forEach { (k, v) -> setRequestProperty(k, v) }
                        if (have > 0) setRequestProperty("Range", "bytes=$have-")
                    }
                    val code = conn.responseCode
                    if (code == 416 && have > 0) { st.received = have; st.total = have; st.done = true; break }
                    if (code != 200 && code != 206) {
                        st.error = "HTTP $code"
                        break
                    }
                    st.contentType = conn.contentType ?: ""
                    val append = code == 206 && have > 0
                    val len = conn.contentLengthLong
                    st.total = if (len > 0) (if (append) have + len else len) else 0L
                    var got = if (append) have else 0L
                    st.received = got
                    conn.inputStream.use { input ->
                        FileOutputStream(file, append).use { out ->
                            val buf = ByteArray(1 shl 16)
                            while (true) {
                                if (st.cancelled) return@use
                                val n = input.read(buf)
                                if (n < 0) break
                                out.write(buf, 0, n)
                                got += n
                                st.received = got
                            }
                        }
                    }
                    if (st.cancelled) break
                    if (st.total == 0L || got >= st.total) { st.total = got; st.done = true; break }
                    // Connection dropped early: loop resumes with a Range request.
                } catch (e: Exception) {
                    attempt++
                    if (attempt > 6 || st.cancelled) {
                        st.error = e.javaClass.simpleName + ": " + (e.message ?: "")
                        break
                    }
                    try { Thread.sleep(1500L * attempt) } catch (_: InterruptedException) {}
                } finally {
                    try { conn?.disconnect() } catch (_: Exception) {}
                }
            }
        }.start()
    }

    fun fetchStatus(id: String): Map<String, Any?>? {
        val st = fetches[id] ?: return null
        val m = mapOf(
            "received" to st.received,
            "total" to st.total,
            "done" to st.done,
            "error" to st.error,
            "contentType" to st.contentType,
        )
        if (st.done || st.error != null || st.cancelled) fetches.remove(id)
        return m
    }

    fun cancelFetch(id: String) {
        fetches[id]?.cancelled = true
        fetches.remove(id)
    }

    /**
     * Cuts [startMs]..[endMs] (≤10 s clips) straight from a progressive
     * stream URL into an MP4 — no re-encode: the cut starts at the keyframe
     * just before [startMs]. Returns true when [output] was written.
     */
    fun cutClip(url: String, headers: Map<String, String>, startMs: Long,
                endMs: Long, output: String): Boolean {
        val ex = MediaExtractor()
        var muxer: MediaMuxer? = null
        try {
            File(output).delete()
            ex.setDataSource(url, headers)
            muxer = MediaMuxer(output, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            val map = HashMap<Int, Int>()
            var maxInput = 1 shl 20
            for (i in 0 until ex.trackCount) {
                val fmt = ex.getTrackFormat(i)
                val mime = fmt.getString(MediaFormat.KEY_MIME) ?: continue
                if (!mime.startsWith("video/") && !mime.startsWith("audio/")) continue
                val dst = try { muxer.addTrack(fmt) } catch (e: Exception) { continue }
                if (fmt.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE)) {
                    maxInput = maxOf(maxInput, fmt.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE))
                }
                ex.selectTrack(i)
                map[i] = dst
            }
            if (map.isEmpty()) return false
            val startUs = startMs * 1000
            val endUs = endMs * 1000
            ex.seekTo(startUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
            muxer.start()
            val buf = ByteBuffer.allocate(maxOf(maxInput, 2 shl 20))
            val info = MediaCodec.BufferInfo()
            var base = -1L
            while (true) {
                val track = ex.sampleTrackIndex
                if (track < 0) break
                val t = ex.sampleTime
                if (t > endUs) break
                val dst = map[track]
                if (dst != null) {
                    buf.clear()
                    val size = ex.readSampleData(buf, 0)
                    if (size < 0) break
                    if (base < 0) base = t
                    info.offset = 0
                    info.size = size
                    info.presentationTimeUs = maxOf(0L, t - base)
                    info.flags = if (ex.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC != 0)
                        MediaCodec.BUFFER_FLAG_KEY_FRAME else 0
                    muxer.writeSampleData(dst, buf, info)
                }
                ex.advance()
            }
            muxer.stop()
            return File(output).length() > 0
        } catch (e: Exception) {
            File(output).delete()
            return false
        } finally {
            try { muxer?.release() } catch (_: Exception) {}
            try { ex.release() } catch (_: Exception) {}
        }
    }

    /** Returns true when [output] was written with at least one track. */
    fun mux(inputs: List<String>, output: String): Boolean {
        val extractors = mutableListOf<MediaExtractor>()
        var muxer: MediaMuxer? = null
        try {
            File(output).delete()
            muxer = MediaMuxer(output, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            // (extractor, source track) → muxer track
            val plan = mutableListOf<Triple<MediaExtractor, Int, Int>>()
            var haveVideo = false
            var haveAudio = false
            var maxInput = 1 shl 20
            for (path in inputs) {
                val ex = MediaExtractor()
                ex.setDataSource(path)
                extractors.add(ex)
                for (i in 0 until ex.trackCount) {
                    val fmt = ex.getTrackFormat(i)
                    val mime = fmt.getString(MediaFormat.KEY_MIME) ?: continue
                    val isVideo = mime.startsWith("video/")
                    val isAudio = mime.startsWith("audio/")
                    if (isVideo && haveVideo) continue
                    if (isAudio && haveAudio) continue
                    if (!isVideo && !isAudio) continue
                    val dst = try {
                        muxer.addTrack(fmt)
                    } catch (e: Exception) {
                        continue // codec the MP4 muxer cannot hold
                    }
                    if (fmt.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE)) {
                        maxInput = maxOf(maxInput, fmt.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE))
                    }
                    ex.selectTrack(i)
                    plan.add(Triple(ex, i, dst))
                    if (isVideo) haveVideo = true
                    if (isAudio) haveAudio = true
                }
            }
            if (plan.isEmpty() || !haveVideo) return false
            muxer.start()
            val buf = ByteBuffer.allocate(maxOf(maxInput, 4 shl 20))
            val info = MediaCodec.BufferInfo()
            val active = extractors.filter { ex -> plan.any { it.first === ex } }.toMutableList()
            // Interleave by timestamp: always write the earliest pending sample.
            while (active.isNotEmpty()) {
                var ex: MediaExtractor? = null
                var best = Long.MAX_VALUE
                val iter = active.iterator()
                while (iter.hasNext()) {
                    val e = iter.next()
                    if (e.sampleTrackIndex < 0) {
                        iter.remove()
                        continue
                    }
                    if (e.sampleTime < best) {
                        best = e.sampleTime
                        ex = e
                    }
                }
                if (ex == null) break
                val src = ex.sampleTrackIndex
                val dst = plan.firstOrNull { it.first === ex && it.second == src }?.third
                if (dst == null) {
                    ex.advance()
                    continue
                }
                buf.clear()
                val size = ex.readSampleData(buf, 0)
                if (size < 0) {
                    active.remove(ex)
                    continue
                }
                info.offset = 0
                info.size = size
                info.presentationTimeUs = maxOf(0L, ex.sampleTime)
                var flags = 0
                if (ex.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC != 0) {
                    flags = flags or MediaCodec.BUFFER_FLAG_KEY_FRAME
                }
                info.flags = flags
                muxer.writeSampleData(dst, buf, info)
                ex.advance()
            }
            muxer.stop()
            return File(output).length() > 0
        } catch (e: Exception) {
            File(output).delete()
            return false
        } finally {
            try { muxer?.release() } catch (_: Exception) {}
            extractors.forEach { try { it.release() } catch (_: Exception) {} }
        }
    }

    /**
     * Copies [path] into Download/Animax/[folder]/[name].
     * Returns { uri, location } or throws.
     */
    fun publish(ctx: Context, path: String, name: String, mime: String,
                folder: String, done: (Map<String, String>?, String?) -> Unit) {
        val src = File(path)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = ctx.contentResolver
            val rel = "${Environment.DIRECTORY_DOWNLOADS}/Animax/$folder"
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, name)
                put(MediaStore.Downloads.MIME_TYPE, mime)
                put(MediaStore.Downloads.RELATIVE_PATH, rel)
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: return done(null, "MediaStore refused the file")
            try {
                resolver.openOutputStream(uri)!!.use { out ->
                    FileInputStream(src).use { it.copyTo(out, 1 shl 16) }
                }
                values.clear()
                values.put(MediaStore.Downloads.IS_PENDING, 0)
                resolver.update(uri, values, null, null)
                src.delete()
                done(mapOf("uri" to uri.toString(), "location" to "$rel/$name"), null)
            } catch (e: Exception) {
                try { resolver.delete(uri, null, null) } catch (_: Exception) {}
                done(null, e.message ?: "copy failed")
            }
            return
        }
        // Android 7–9: public folder + media scan (gives a content:// URI).
        @Suppress("DEPRECATION")
        val base = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        val dir = File(base, "Animax/$folder")
        dir.mkdirs()
        var dest = File(dir, name)
        var n = 1
        while (dest.exists()) {
            val dot = name.lastIndexOf('.')
            val stem = if (dot > 0) name.substring(0, dot) else name
            val ext = if (dot > 0) name.substring(dot) else ""
            dest = File(dir, "$stem ($n)$ext")
            n++
        }
        try {
            src.copyTo(dest, overwrite = true)
            src.delete()
        } catch (e: Exception) {
            return done(null, e.message ?: "copy failed")
        }
        MediaScannerConnection.scanFile(ctx, arrayOf(dest.absolutePath), arrayOf(mime)) { _, uri ->
            done(
                mapOf(
                    "uri" to (uri?.toString() ?: dest.absolutePath),
                    "location" to "Download/Animax/$folder/${dest.name}"
                ), null
            )
        }
    }

    fun open(ctx: Context, uriOrPath: String, mime: String): Boolean {
        val uri = if (uriOrPath.startsWith("content://")) Uri.parse(uriOrPath)
        else return false
        val view = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, mime.ifBlank { "*/*" })
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return try {
            ctx.startActivity(Intent.createChooser(view, "Open with").apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            })
            true
        } catch (e: Exception) {
            false
        }
    }

    /** Share sheet with the video/PDF file itself (WhatsApp, Telegram…). */
    fun shareFile(ctx: Context, uri: String, mime: String, text: String): Boolean {
        if (!uri.startsWith("content://")) return false
        val send = Intent(Intent.ACTION_SEND).apply {
            type = mime.ifBlank { "video/*" }
            putExtra(Intent.EXTRA_STREAM, Uri.parse(uri))
            if (text.isNotBlank()) putExtra(Intent.EXTRA_TEXT, text)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        return try {
            ctx.startActivity(Intent.createChooser(send, "مشاركة").apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            })
            true
        } catch (e: Exception) {
            false
        }
    }

    /** Share sheet with plain text (title + direct link). */
    fun shareText(ctx: Context, text: String): Boolean {
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, text)
        }
        return try {
            ctx.startActivity(Intent.createChooser(send, "مشاركة").apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            })
            true
        } catch (e: Exception) {
            false
        }
    }

    fun delete(ctx: Context, uri: String): Boolean = try {
        ctx.contentResolver.delete(Uri.parse(uri), null, null) > 0
    } catch (e: Exception) {
        false
    }
}
