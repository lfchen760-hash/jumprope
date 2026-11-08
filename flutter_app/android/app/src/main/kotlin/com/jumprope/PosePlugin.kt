package com.jumprope

import android.app.Activity
import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.os.Handler
import android.os.Looper
import androidx.lifecycle.LifecycleOwner
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Flutter 与 MediaPipe 之间的唯一桥梁。
 *
 * 通道协议：
 *   MethodChannel  com.jumprope/pose
 *     init(modelAsset: String, useGpu: Boolean) -> Boolean
 *     startCamera(front: Boolean)               -> Boolean
 *     stopCamera()                              -> Unit
 *     processVideo(path: String, fps: Int)      -> Boolean   (调试用，慢)
 *     stopVideo()
 *     dispose()
 *
 *   EventChannel   com.jumprope/pose_frames
 *     Map { "t": Int(ms), "lm": List<Double>? }   // 33*4 扁平数组，无人时 lm=null
 *
 * 注意：事件只在主线程发出。
 */
class PosePlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler,
    ActivityAware {

    private lateinit var context: Context
    private var activity: Activity? = null
    private var channel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var sink: EventChannel.EventSink? = null

    private var processor: PoseProcessor? = null
    private var camera: CameraStreamHandler? = null

    private val main = Handler(Looper.getMainLooper())
    private val videoExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val videoRunning = AtomicBoolean(false)

    // ---------------- FlutterPlugin ----------------

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        processor = PoseProcessor(context)

        channel = MethodChannel(binding.binaryMessenger, "com.jumprope/pose").also {
            it.setMethodCallHandler(this)
        }
        eventChannel = EventChannel(binding.binaryMessenger, "com.jumprope/pose_frames").also {
            it.setStreamHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        eventChannel?.setStreamHandler(null)
        channel = null
        eventChannel = null
        camera?.dispose()
        camera = null
        processor?.close()
        processor = null
    }

    // ---------------- ActivityAware ----------------

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    // ---------------- EventChannel ----------------

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    private fun emit(timestampMs: Long, landmarks: FloatArray?) {
        val payload = HashMap<String, Any?>()
        payload["t"] = timestampMs
        payload["lm"] = landmarks?.map { it.toDouble() }
        main.post { sink?.success(payload) }
    }

    // ---------------- MethodChannel ----------------

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "init" -> {
                val asset = call.argument<String>("modelAsset") ?: "pose_landmarker_lite.task"
                val gpu = call.argument<Boolean>("useGpu") ?: true
                val ok = processor?.init(asset, gpu) ?: false
                result.success(ok)
            }

            "startCamera" -> {
                val front = call.argument<Boolean>("front") ?: true
                val owner = activity as? LifecycleOwner
                if (owner == null || processor == null) {
                    result.success(false)
                    return
                }
                if (camera == null) {
                    camera = CameraStreamHandler(context, owner, processor!!) { ts, lm ->
                        emit(ts, lm)
                    }
                }
                result.success(camera?.start(front) ?: false)
            }

            "stopCamera" -> {
                camera?.stop()
                result.success(null)
            }

            "processVideo" -> {
                val path = call.argument<String>("path")
                val fps = call.argument<Int>("fps") ?: 30
                if (path == null || processor == null) {
                    result.success(false)
                    return
                }
                result.success(startVideo(path, fps))
            }

            "stopVideo" -> {
                videoRunning.set(false)
                result.success(null)
            }

            "dispose" -> {
                camera?.dispose()
                camera = null
                processor?.close()
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    /**
     * 调试用：逐帧解码本地视频并检测。
     *
     * 这里用 MediaMetadataRetriever，实现简单但**很慢**（每帧一次 seek）。
     * 只用于验证「手机上的关键点和 Web 差多少」，不适合日常使用。
     * 正式版本可换成 MediaCodec 顺序解码。
     */
    private fun startVideo(path: String, fps: Int): Boolean {
        if (!videoRunning.compareAndSet(false, true)) return false
        val proc = processor ?: return false

        videoExecutor.execute {
            val retriever = MediaMetadataRetriever()
            try {
                retriever.setDataSource(path)
                val durationMs = retriever
                    .extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                    ?.toLongOrNull() ?: 0L
                val step = (1000.0 / fps).toLong().coerceAtLeast(1)

                var t = 0L
                while (videoRunning.get() && t <= durationMs) {
                    val frame: Bitmap? = retriever.getFrameAtTime(
                        t * 1000,
                        MediaMetadataRetriever.OPTION_CLOSEST,
                    )
                    if (frame != null) {
                        val scaled = if (frame.width > frame.height) {
                            if (frame.width > 640) {
                                Bitmap.createScaledBitmap(
                                    frame, 640,
                                    (frame.height * 640f / frame.width).toInt().coerceAtLeast(1), true,
                                )
                            } else frame
                        } else {
                            if (frame.height > 640) {
                                Bitmap.createScaledBitmap(
                                    frame,
                                    (frame.width * 640f / frame.height).toInt().coerceAtLeast(1), 640, true,
                                )
                            } else frame
                        }
                        emit(t, proc.detect(scaled, t))
                        if (scaled !== frame) scaled.recycle()
                    } else {
                        emit(t, null)
                    }
                    t += step
                }
            } catch (_: Exception) {
            } finally {
                try {
                    retriever.release()
                } catch (_: Exception) {
                }
                videoRunning.set(false)
                main.post { sink?.endOfStream() }
            }
        }
        return true
    }
}
