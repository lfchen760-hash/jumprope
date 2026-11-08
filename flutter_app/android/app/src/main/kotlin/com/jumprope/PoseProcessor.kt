package com.jumprope

import android.content.Context
import android.graphics.Bitmap
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker

/**
 * MediaPipe PoseLandmarker 的薄封装。
 *
 * 职责边界：**只负责「位图 -> 33 个关键点」**。
 * 不做角度计算、不做计数、不做取景判断 —— 那些都在 Dart 的 domain 层。
 */
class PoseProcessor(private val context: Context) {

    private var landmarker: PoseLandmarker? = null
    private var lastTimestamp = 0L

    /** 返回 33*4 的扁平数组 [x, y, z, visibility] × 33；无人时返回 null */
    fun detect(bitmap: Bitmap, timestampMs: Long): FloatArray? {
        val lm = landmarker ?: return null

        // MediaPipe VIDEO 模式要求时间戳严格递增
        var ts = timestampMs
        if (ts <= lastTimestamp) ts = lastTimestamp + 1
        lastTimestamp = ts

        val image = BitmapImageBuilder(bitmap).build()
        val result = try {
            lm.detectForVideo(image, ts)
        } catch (e: Exception) {
            return null
        }

        val poses = result.landmarks()
        if (poses.isEmpty()) return null
        val points = poses[0]
        if (points.size < 33) return null

        val out = FloatArray(33 * 4)
        for (i in 0 until 33) {
            val p = points[i]
            out[i * 4 + 0] = p.x()
            out[i * 4 + 1] = p.y()
            out[i * 4 + 2] = p.z()
            // visibility 在不同版本里可能是 float 或 Optional<Float>
            out[i * 4 + 3] = runCatching { p.visibility().orElse(1f) }.getOrElse { 1f }
        }
        return out
    }

    fun init(modelAsset: String, useGpu: Boolean = true): Boolean {
        close()
        lastTimestamp = 0L

        fun build(delegate: Delegate): PoseLandmarker {
            val base = BaseOptions.builder()
                .setModelAssetPath(modelAsset)
                .setDelegate(delegate)
                .build()
            val opts = PoseLandmarker.PoseLandmarkerOptions.builder()
                .setBaseOptions(base)
                .setRunningMode(RunningMode.VIDEO)
                .setNumPoses(1)
                .setMinPoseDetectionConfidence(0.5f)
                .setMinPosePresenceConfidence(0.5f)
                .setMinTrackingConfidence(0.5f)
                .build()
            return PoseLandmarker.createFromOptions(context, opts)
        }

        landmarker = try {
            if (useGpu) build(Delegate.GPU) else build(Delegate.CPU)
        } catch (e: Exception) {
            try {
                build(Delegate.CPU)
            } catch (e2: Exception) {
                null
            }
        }
        return landmarker != null
    }

    fun close() {
        try {
            landmarker?.close()
        } catch (_: Exception) {
        }
        landmarker = null
    }
}
