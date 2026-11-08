package com.jumprope

import android.content.Context
import android.view.View
import androidx.camera.view.PreviewView
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/**
 * 把原生的 CameraX PreviewView 嵌进 Flutter 界面。
 *
 * 为什么用 PlatformView 而不是 Texture：
 *   外部纹理在当前 Flutter/设备组合下拿不到画面（tex 有 id、req 有回调，但黑屏）。
 *   PlatformView 是原生 View，渲染路径独立，稳得多。
 */
class JumpropePreviewView(context: Context) : PlatformView {
    // 参考 flutter_mp_pose_landmarker 的实现：用默认的 PERFORMANCE(SurfaceView) 模式。
    // TextureView(COMPATIBLE) 在 PlatformView 里渲染不出画面。
    val previewView: PreviewView = PreviewView(context).apply {
        scaleType = PreviewView.ScaleType.FILL_CENTER
        layoutParams = android.view.ViewGroup.LayoutParams(
            android.view.ViewGroup.LayoutParams.MATCH_PARENT,
            android.view.ViewGroup.LayoutParams.MATCH_PARENT,
        )
    }

    override fun getView(): View = previewView
    override fun dispose() {}
}

class PreviewViewFactory : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    companion object {
        /** 当前活动的预览 View，CameraStreamHandler 用它拿 SurfaceProvider */
        @Volatile
        var current: JumpropePreviewView? = null

        /** 平台视图被创建过几次（诊断用） */
        @Volatile
        var createdCount: Int = 0
            private set
    }

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val v = JumpropePreviewView(context)
        current = v
        createdCount++
        return v
    }
}
