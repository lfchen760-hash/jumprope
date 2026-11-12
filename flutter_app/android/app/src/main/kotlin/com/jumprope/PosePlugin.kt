package com.jumprope

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.media.AudioAttributes
import android.media.MediaMetadataRetriever
import android.media.SoundPool
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import androidx.camera.video.VideoRecordEvent
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import io.flutter.view.TextureRegistry
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import com.jumprope.jumprope_app.R
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.File
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
    ActivityAware,
    PluginRegistry.RequestPermissionsResultListener {

    private lateinit var context: Context
    private var activity: Activity? = null
    private var channel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var sink: EventChannel.EventSink? = null
    private var previewChannel: EventChannel? = null
    private var previewSink: EventChannel.EventSink? = null

    // 每跳一下的「嘀」：SoundPool 低延迟，资源是 res/raw/tick_*.wav
    private var soundChannel: MethodChannel? = null
    private var soundPool: SoundPool? = null
    private var tickLowId = 0
    private var tickHighId = 0

    private var processor: PoseProcessor? = null
    private var camera: CameraStreamHandler? = null
    private var surfaceProducer: TextureRegistry.SurfaceProducer? = null

    // 录像通道：com.jumprope/video
    private var videoChannel: MethodChannel? = null
    private var videoEventChannel: EventChannel? = null
    private var videoSink: EventChannel.EventSink? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingStartResult: MethodChannel.Result? = null
    private var pendingStopResult: MethodChannel.Result? = null
    private val audioRequestCode = 1002

    private val main = Handler(Looper.getMainLooper())
    private val videoExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val videoRunning = AtomicBoolean(false)

    // ---------------- FlutterPlugin ----------------

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        processor = PoseProcessor(context)

        surfaceProducer = binding.textureRegistry.createSurfaceProducer()


        channel = MethodChannel(binding.binaryMessenger, "com.jumprope/pose").also {
            it.setMethodCallHandler(this)
        }
        eventChannel = EventChannel(binding.binaryMessenger, "com.jumprope/pose_frames").also {
            it.setStreamHandler(this)
        }
        previewChannel = EventChannel(binding.binaryMessenger, "com.jumprope/preview").also {
            it.setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    previewSink = events
                }

                override fun onCancel(arguments: Any?) {
                    previewSink = null
                }
            })
        }

        // 音效通道：playTick(high: Boolean)
        soundPool = SoundPool.Builder()
            .setMaxStreams(4)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
            .build()
        // 直接引用 R：静态引用能避免 release 资源压缩把 wav 删掉
        tickLowId = soundPool?.load(context, R.raw.tick_low, 1) ?: 0
        tickHighId = soundPool?.load(context, R.raw.tick_high, 1) ?: 0
        soundChannel = MethodChannel(binding.binaryMessenger, "com.jumprope/sound").also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "playTick" -> {
                        val high = call.argument<Boolean>("high") ?: false
                        soundPool?.play(
                            if (high) tickHighId else tickLowId,
                            1f, 1f, 1, 0, 1f
                        )
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }

        videoChannel = MethodChannel(binding.binaryMessenger, "com.jumprope/video").also {
            it.setMethodCallHandler { call, result -> onVideoCall(call, result) }
        }
        videoEventChannel = EventChannel(binding.binaryMessenger, "com.jumprope/video_events").also {
            it.setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    videoSink = events
                }

                override fun onCancel(arguments: Any?) {
                    videoSink = null
                }
            })
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        eventChannel?.setStreamHandler(null)
        previewChannel?.setStreamHandler(null)
        previewChannel = null
        previewSink = null
        soundChannel?.setMethodCallHandler(null)
        soundChannel = null
        soundPool?.release()
        soundPool = null
        videoChannel?.setMethodCallHandler(null)
        videoChannel = null
        videoEventChannel?.setStreamHandler(null)
        videoEventChannel = null
        videoSink = null
        channel = null
        eventChannel = null
        camera?.dispose()
        camera = null
        processor?.close()
        processor = null
        surfaceProducer?.release()
        surfaceProducer = null
    }

    // ---------------- ActivityAware ----------------

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        PreviewHolder.detach()
        activity = null
    }

    // ---------------- 录像权限 / 通道 ----------------

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != audioRequestCode) return false
        val pending = pendingStartResult
        pendingStartResult = null
        if (pending == null) return true
        if (grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        ) {
            startRecordingNow(pending)
        } else {
            pending.error(
                "audio_permission_denied",
                "需要麦克风权限才能录制声音",
                null,
            )
        }
        return true
    }

    private fun onVideoCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startRecording" -> {
                if (pendingStartResult != null) {
                    result.error("busy", "上一次录像还在启动", null)
                    return
                }
                val act = activity
                if (act == null || camera == null) {
                    result.error("camera_not_ready", "相机还没准备好", null)
                    return
                }
                if (ContextCompat.checkSelfPermission(
                        context,
                        Manifest.permission.RECORD_AUDIO,
                    ) != PackageManager.PERMISSION_GRANTED
                ) {
                    pendingStartResult = result
                    ActivityCompat.requestPermissions(
                        act,
                        arrayOf(Manifest.permission.RECORD_AUDIO),
                        audioRequestCode,
                    )
                    return
                }
                startRecordingNow(result)
            }

            "stopRecording" -> {
                if (pendingStopResult != null) {
                    result.error("busy", "正在保存上一段录像", null)
                    return
                }
                val cam = camera
                if (cam == null || !cam.isRecording) {
                    result.success(null)
                    return
                }
                pendingStopResult = result
                cam.stopRecording()
                // 兜底：某些机型 Finalize 不回调，别让 Dart 永远等
                main.postDelayed({
                    val pending = pendingStopResult
                    if (pending != null) {
                        pendingStopResult = null
                        pending.error("finalize_timeout", "录像保存超时", null)
                    }
                }, 15000)
            }

            "pauseRecording" -> {
                camera?.pauseRecording()
                result.success(null)
            }

            "resumeRecording" -> {
                camera?.resumeRecording()
                result.success(null)
            }

            "isRecording" -> result.success(camera?.isRecording == true)
            "getVideoSupport" -> result.success(camera?.videoBound == true)
            else -> result.notImplemented()
        }
    }

    private fun startRecordingNow(result: MethodChannel.Result) {
        val cam = camera
        if (cam == null) {
            result.error("camera_not_ready", "相机还没准备好", null)
            return
        }
        val base = context.getExternalFilesDir(Environment.DIRECTORY_MOVIES)
            ?: context.filesDir
        val dir = File(base, "jumprope")
        if (!dir.exists() && !dir.mkdirs()) {
            result.error("storage", "无法创建录像目录", null)
            return
        }
        val file = File(dir, "vid-${System.currentTimeMillis()}.mp4")
        val startedAt = SystemClock.elapsedRealtime()
        val ok = cam.startRecording(file, true) { event ->
            handleVideoEvent(event, file)
        }
        if (!ok) {
            result.error("start_failed", "相机不支持同时录像，或启动失败", null)
            return
        }
        result.success(
            mapOf(
                "path" to file.absolutePath,
                "startedAtMs" to startedAt,
            ),
        )
    }

    private fun handleVideoEvent(event: VideoRecordEvent, file: File) {
        when (event) {
            is VideoRecordEvent.Start -> {
                main.post {
                    videoSink?.success(
                        mapOf("event" to "started", "path" to file.absolutePath),
                    )
                }
            }

            is VideoRecordEvent.Finalize -> {
                val map = HashMap<String, Any?>()
                map["event"] = "finalized"
                map["path"] = file.absolutePath
                map["error"] = if (event.hasError()) event.error else 0
                map.putAll(readVideoInfo(file))
                main.post {
                    val pending = pendingStopResult
                    pendingStopResult = null
                    if (pending != null) {
                        if (event.hasError()) {
                            pending.error(
                                "finalize_failed",
                                "录像保存失败 (${event.error})",
                                null,
                            )
                        } else {
                            pending.success(map)
                        }
                    } else {
                        videoSink?.success(map)
                    }
                }
            }
        }
    }

    private fun readVideoInfo(file: File): Map<String, Any> {
        val out = HashMap<String, Any>()
        if (!file.exists()) return out
        val r = MediaMetadataRetriever()
        try {
            r.setDataSource(file.absolutePath)
            out["durationMs"] =
                r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                    ?.toLongOrNull() ?: 0L
            out["width"] =
                r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
                    ?.toIntOrNull() ?: 0
            out["height"] =
                r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
                    ?.toIntOrNull() ?: 0
            out["rotation"] =
                r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                    ?.toIntOrNull() ?: 0
            out["hasAudio"] =
                r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO) == "yes"
            out["sizeBytes"] = file.length()
        } catch (_: Exception) {
        } finally {
            try {
                r.release()
            } catch (_: Exception) {
            }
        }
        return out
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
                val p = processor
                if (p == null) {
                    result.success(false)
                    return
                }
                val ok = p.init(asset, gpu)
                if (!ok) {
                    android.util.Log.e("PosePlugin", "init failed: ${p.lastError}")
                }
                result.success(ok)
            }

            "getDiagnostics" -> {
                val sb = StringBuilder()
                val b = android.os.Build::class.java
                sb.append("device=").append(android.os.Build.MANUFACTURER)
                    .append(' ').append(android.os.Build.MODEL).append('\n')
                sb.append("android=").append(android.os.Build.VERSION.RELEASE)
                    .append(" API ").append(android.os.Build.VERSION.SDK_INT).append('\n')
                sb.append("abis=").append(android.os.Build.SUPPORTED_ABIS.joinToString(",")).append('\n')

                val modelNames = listOf("pose_landmarker_lite.task")
                for (m in modelNames) {
                    val info = try {
                        context.assets.open(m).use { "OK ${it.available()}B" }
                    } catch (e: Throwable) {
                        "FAIL ${e.javaClass.simpleName}: ${e.message}"
                    }
                    sb.append("model:assets/").append(m).append("=").append(info).append('\n')
                }

                val perm = try {
                    androidx.core.content.ContextCompat.checkSelfPermission(
                        context, android.Manifest.permission.CAMERA,
                    ) == android.content.pm.PackageManager.PERMISSION_GRANTED
                } catch (e: Throwable) {
                    false
                }
                sb.append("cameraPermission=").append(perm).append('\n')
                sb.append("activity=").append(activity != null).append('\n')
                sb.append("mpInit=")
                    .append(processor?.lastError?.ifBlank { "ok" } ?: "未调用 init")
                    .append('\n')
                sb.append("camera=").append(camera?.diagnostics() ?: "未启动").append('\n')
                result.success(sb.toString())
            }

            "getInitError" -> {
                result.success(processor?.lastError ?: "")
            }

            "getPreviewDebug" -> {
                val c = camera
                result.success(
                    "pv=${if (PreviewHolder.view != null) 1 else 0}" +
                        " b=${if (c?.previewBound == true) 1 else 0}" +
                        " a=${if (c?.previewAttached == true) 1 else 0}" +
                        " t=${c?.previewAttempts ?: -1}",
                )
            }

            "getPreviewRequests" -> {
                result.success(camera?.previewRequests ?: -1)
            }

            "getPreviewTextureId" -> {
                result.success(surfaceProducer?.id() ?: -1)
            }

            "startCamera" -> {
                val front = call.argument<Boolean>("front") ?: true
                val act = activity
                val owner = act as? LifecycleOwner
                if (act == null || owner == null || processor == null) {
                    result.success(false)
                    return
                }
                // 此时 Activity 已 setContentView，挂上去才不会被替换掉
                runCatching { PreviewHolder.ensureAttached(act) }
                    .onFailure { android.util.Log.e("PosePlugin", "attach preview failed", it) }
                if (camera == null) {
                    camera = CameraStreamHandler(
                        context,
                        owner,
                        processor!!,
                        surfaceProducer,
                        { PreviewHolder.view },
                        { ts, lm -> emit(ts, lm) },
                        { jpeg -> main.post { previewSink?.success(jpeg) } },
                    )
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
