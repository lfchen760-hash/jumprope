package com.jumprope

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.provider.MediaStore
import androidx.annotation.OptIn
import androidx.media3.common.MediaItem
import androidx.media3.common.Effect
import androidx.media3.common.MimeTypes
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.util.Size
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.BitmapOverlay
import androidx.media3.effect.OverlayEffect
import androidx.media3.effect.OverlaySettings
import androidx.media3.effect.TextureOverlay
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import com.google.common.collect.ImmutableList
import java.io.File
import java.util.concurrent.Executors

/**
 * 把计数/倒计时烧进已录好的干净视频。
 *
 * 原始 MP4 + jumps + startOffset 是唯一输入，所以换样式只需要重新导出。
 */
@OptIn(UnstableApi::class)
class VideoExporter(private val context: Context) {
    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()
    private var transformer: Transformer? = null
    private var running = false
    private var progressRunnable: Runnable? = null
    private var outputFile: File? = null

    val isRunning: Boolean
        get() = running

    fun start(
        rawPath: String,
        jumps: IntArray,
        startOffsetMs: Long,
        durationSec: Int,
        onProgress: (Float) -> Unit,
        onDone: (String, String) -> Unit,
        onError: (String) -> Unit,
    ) {
        try {
            startInternal(rawPath, jumps, startOffsetMs, durationSec, onProgress, onDone, onError)
        } catch (t: Throwable) {
            running = false
            stopProgress()
            Log.e("VideoExporter", "export failed", t)
            onError("${t.javaClass.simpleName}: ${t.message ?: ""}")
        }
    }

    private fun startInternal(
        rawPath: String,
        jumps: IntArray,
        startOffsetMs: Long,
        durationSec: Int,
        onProgress: (Float) -> Unit,
        onDone: (String, String) -> Unit,
        onError: (String) -> Unit,
    ) {
        if (running) {
            onError("正在导出另一个视频")
            return
        }
        val input = File(rawPath)
        if (!input.exists()) {
            onError("原始录像不存在")
            return
        }
        val dir = File(context.cacheDir, "exports").apply { mkdirs() }
        val out = File(dir, "overlay-${System.currentTimeMillis()}.mp4")
        outputFile = out
        running = true

        val overlay = CountOverlay(
            jumps = jumps,
            startOffsetMs = startOffsetMs,
            plannedMs = durationSec.toLong() * 1000,
        )
        val effect = OverlayEffect(ImmutableList.of<TextureOverlay>(overlay))
        val effects = Effects(
            emptyList<AudioProcessor>(),
            listOf<Effect>(effect),
        )
        val item = EditedMediaItem.Builder(MediaItem.fromUri(Uri.fromFile(input)))
            .setEffects(effects)
            .build()

        val t = Transformer.Builder(context)
            .setVideoMimeType(MimeTypes.VIDEO_H264)
            .setAudioMimeType(MimeTypes.AUDIO_AAC)
            .addListener(object : Transformer.Listener {
                override fun onCompleted(
                    composition: Composition,
                    exportResult: ExportResult,
                ) {
                    running = false
                    stopProgress()
                    io.execute {
                        val uri = runCatching { saveToGallery(out) }.getOrNull()
                        main.post { onDone(out.absolutePath, uri ?: "") }
                    }
                }

                override fun onError(
                    composition: Composition,
                    exportResult: ExportResult,
                    exportException: ExportException,
                ) {
                    running = false
                    stopProgress()
                    main.post { onError(exportException.message ?: "导出失败") }
                }
            })
            .build()
        transformer = t
        try {
            t.start(item, out.absolutePath)
        } catch (e: Exception) {
            running = false
            onError(e.message ?: "导出启动失败")
            return
        }

        val holder = ProgressHolder()
        progressRunnable = object : Runnable {
            override fun run() {
                if (!running) return
                val state = t.getProgress(holder)
                if (state == Transformer.PROGRESS_STATE_AVAILABLE) {
                    onProgress(holder.progress / 100f)
                }
                main.postDelayed(this, 500)
            }
        }
        main.post(progressRunnable!!)
    }

    fun cancel() {
        runCatching { transformer?.cancel() }
        transformer = null
        running = false
        stopProgress()
    }

    fun share(uriString: String) {
        val uri = Uri.parse(uriString)
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "video/mp4"
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(
            Intent.createChooser(intent, "分享跳绳视频")
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
    }

    private fun stopProgress() {
        progressRunnable?.let { main.removeCallbacks(it) }
        progressRunnable = null
    }

    /** API 29+ 直接写系统相册；低版本返回空，由 Dart 提示只保留在 App 内。 */
    private fun saveToGallery(file: File): String? {
        if (Build.VERSION.SDK_INT < 29) return null
        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Video.Media.DISPLAY_NAME, "jumprope-${System.currentTimeMillis()}.mp4")
            put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
            put(MediaStore.Video.Media.RELATIVE_PATH, "Movies/跳绳")
            put(MediaStore.Video.Media.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, values)
            ?: return null
        resolver.openOutputStream(uri)?.use { out ->
            file.inputStream().use { it.copyTo(out) }
        }
        values.clear()
        values.put(MediaStore.Video.Media.IS_PENDING, 0)
        resolver.update(uri, values, null, null)
        return uri.toString()
    }
}

/** 按视频播放时间动态画计数、剩余时间、进度条。 */
@OptIn(UnstableApi::class)
private class CountOverlay(
    jumps: IntArray,
    private val startOffsetMs: Long,
    private val plannedMs: Long,
) : BitmapOverlay() {
    private val jumps = jumps.sortedArray()
    private var width = 2
    private var height = 2
    private var lastBitmap: Bitmap? = null
    private var lastKey = ""
    private val settings = OverlaySettings.Builder()
        .setScale(2f, 2f)
        .build()

    override fun configure(videoSize: Size) {
        width = (videoSize.width / 2).coerceAtLeast(2)
        height = (videoSize.height / 2).coerceAtLeast(2)
    }

    override fun getTextureSize(presentationTimeUs: Long): Size =
        Size(width, height)

    override fun getOverlaySettings(presentationTimeUs: Long): OverlaySettings = settings

    override fun getBitmap(presentationTimeUs: Long): Bitmap {
        val videoMs = presentationTimeUs / 1000
        val sessionMs = startOffsetMs + videoMs
        var count = 0
        for (j in jumps) {
            if (j <= sessionMs) count++ else break
        }
        val remainMs = if (plannedMs > 0) {
            (plannedMs - sessionMs).coerceAtLeast(0)
        } else {
            sessionMs
        }
        val key = "$count|$remainMs|$width|$height"
        lastBitmap?.let { if (key == lastKey) return it }
        val bmp = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        draw(bmp, count, sessionMs, remainMs)
        lastKey = key
        lastBitmap = bmp
        return bmp
    }

    override fun release() {
        lastBitmap?.recycle()
        lastBitmap = null
        super.release()
    }

    private fun draw(
        bitmap: Bitmap,
        count: Int,
        sessionMs: Long,
        remainMs: Long,
    ) {
        val canvas = Canvas(bitmap)
        val w = bitmap.width.toFloat()
        val h = bitmap.height.toFloat()

        val shadow = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = 0x66000000
        }
        val text = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            textAlign = Paint.Align.CENTER
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            setShadowLayer(6f, 0f, 2f, 0x99000000)
        }

        // 顶部倒计时/用时
        val label = if (plannedMs > 0) {
            "剩余 ${((remainMs + 999) / 1000)}s"
        } else {
            "用时 ${clock(sessionMs)}"
        }
        text.textSize = h * 0.033f
        val labelWidth = text.measureText(label)
        val rect = RectF(
            w / 2 - labelWidth / 2 - 26,
            h * 0.045f,
            w / 2 + labelWidth / 2 + 26,
            h * 0.045f + h * 0.058f,
        )
        canvas.drawRoundRect(rect, rect.height() / 2, rect.height() / 2, shadow)
        canvas.drawText(
            label,
            w / 2,
            rect.centerY() - (text.descent() + text.ascent()) / 2,
            text,
        )

        // 中央计数
        text.textSize = h * 0.13f
        canvas.drawText("$count", w / 2, h * 0.68f, text)
        text.textSize = h * 0.032f
        canvas.drawText("次", w / 2, h * 0.72f, text)

        // 底部进度条
        val barLeft = w * 0.12f
        val barRight = w * 0.88f
        val barTop = h * 0.80f
        val barHeight = h * 0.008f
        val bar = RectF(barLeft, barTop, barRight, barTop + barHeight)
        val track = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0x55FFFFFF }
        val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            shader = LinearGradient(
                barLeft,
                0f,
                barRight,
                0f,
                0xFFFF8A1F.toInt(),
                0xFFFF2D6B.toInt(),
                Shader.TileMode.CLAMP,
            )
        }
        canvas.drawRoundRect(bar, barHeight / 2, barHeight / 2, track)
        val ratio = if (plannedMs > 0) {
            ((plannedMs - remainMs).toFloat() / plannedMs).coerceIn(0f, 1f)
        } else {
            0f
        }
        if (ratio > 0) {
            val filled = RectF(barLeft, barTop, barLeft + (barRight - barLeft) * ratio, barTop + barHeight)
            canvas.drawRoundRect(filled, barHeight / 2, barHeight / 2, fill)
        }
    }

    private fun clock(ms: Long): String {
        val total = (ms / 1000).coerceAtLeast(0)
        return "%02d:%02d".format(total / 60, total % 60)
    }
}
