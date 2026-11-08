package com.jumprope

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Matrix
import android.graphics.SurfaceTexture
import android.view.Surface
import android.util.Size
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * 相机帧源：CameraX ImageAnalysis -> 位图 -> PoseProcessor -> 回调。
 *
 * 只在原生侧完成，不把每帧送回 Dart（那会多一次跨语言拷贝）。
 */
class CameraStreamHandler(
    private val context: Context,
    private val lifecycleOwner: LifecycleOwner,
    private val processor: PoseProcessor,
    private val previewTexture: SurfaceTexture?,
    private val onFrame: (timestampMs: Long, landmarks: FloatArray?) -> Unit,
) {
    companion object {
        /** 检测时长边上限，与 Web 版保持一致 */
        private const val LONG_SIDE = 640
    }

    private var cameraProvider: ProcessCameraProvider? = null
    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
    private val busy = AtomicBoolean(false)
    private var running = false

    fun start(frontCamera: Boolean = true): Boolean {
        if (running) return true
        val provider = ProcessCameraProvider.getInstance(context).get()
        cameraProvider = provider

        val preview = Preview.Builder().build()
        if (previewTexture != null) {
            preview.setSurfaceProvider { request ->
                previewTexture.setDefaultBufferSize(
                    request.resolution.width,
                    request.resolution.height,
                )
                val surf = Surface(previewTexture)
                request.provideSurface(surf, executor) { _ -> surf.release() }
            }
        }

        val analysis = ImageAnalysis.Builder()
            .setTargetResolution(Size(640, 480))
            .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
            .build()

        analysis.setAnalyzer(executor) { proxy -> handle(proxy) }

        val selector = if (frontCamera) {
            CameraSelector.DEFAULT_FRONT_CAMERA
        } else {
            CameraSelector.DEFAULT_BACK_CAMERA
        }

        return try {
            provider.unbindAll()
            if (previewTexture != null) {
                provider.bindToLifecycle(lifecycleOwner, selector, preview, analysis)
            } else {
                provider.bindToLifecycle(lifecycleOwner, selector, analysis)
            }
            running = true
            true
        } catch (e: Exception) {
            false
        }
    }

    fun stop() {
        running = false
        try {
            cameraProvider?.unbindAll()
        } catch (_: Exception) {
        }
    }

    private fun handle(proxy: ImageProxy) {
        // 丢帧保护：上一帧还没算完就跳过，避免排队
        if (!busy.compareAndSet(false, true)) {
            proxy.close()
            return
        }
        try {
            val ts = proxy.imageInfo.timestamp / 1_000_000

            @Suppress("UnsafeOptInUsageError")
            var bitmap: Bitmap = proxy.toBitmap()

            val rotation = proxy.imageInfo.rotationDegrees
            if (rotation != 0) {
                val m = Matrix().apply { postRotate(rotation.toFloat()) }
                bitmap = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, m, true)
            }

            val scaled = scaleToLongSide(bitmap, LONG_SIDE)
            val landmarks = if (scaled.width > 0) processor.detect(scaled, ts) else null
            if (scaled !== bitmap) scaled.recycle()

            onFrame(ts, landmarks)
        } catch (e: Exception) {
            onFrame(0L, null)
        } finally {
            busy.set(false)
            proxy.close()
        }
    }

    private fun scaleToLongSide(src: Bitmap, longSide: Int): Bitmap {
        val w = src.width
        val h = src.height
        val long = if (w > h) w else h
        if (long <= longSide) return src
        val ratio = longSide.toFloat() / long
        return Bitmap.createScaledBitmap(
            src,
            (w * ratio).toInt().coerceAtLeast(1),
            (h * ratio).toInt().coerceAtLeast(1),
            true,
        )
    }

    fun dispose() {
        stop()
        executor.shutdown()
    }
}
