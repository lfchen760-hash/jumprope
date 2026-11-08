package com.jumprope

import android.app.Activity
import android.view.ViewGroup
import androidx.camera.view.PreviewView

/**
 * 相机预览视图的持有者。
 *
 * 不再走 PlatformView：预览直接挂在 Activity 窗口最底层，
 * Flutter 用透明渲染把 UI 叠在上面（RenderMode.texture）。
 * 这样预览完全不经过 Flutter 的渲染管线。
 */
object PreviewHolder {
    @Volatile
    var view: PreviewView? = null
        private set

    /** 把预览视图插到窗口最底层（index 0），铺满全屏 */
    fun attach(activity: Activity): PreviewView {
        view?.let { existing ->
            (existing.parent as? ViewGroup)?.removeView(existing)
        }
        val pv = PreviewView(activity).apply {
            scaleType = PreviewView.ScaleType.FILL_CENTER
        }
        val content = activity.findViewById<ViewGroup>(android.R.id.content)
        content.addView(
            pv,
            0,
            ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            ),
        )
        view = pv
        return pv
    }

    /**
     * 确保预览视图真的挂在窗口上。
     *
     * 不能在 onAttachedToActivity 里挂：那时 FlutterActivity 还没 setContentView，
     * 随后会被整体替换掉，视图就变成"存在但不在窗口里"的孤儿（isAttachedToWindow=false）。
     */
    fun ensureAttached(activity: Activity): PreviewView {
        val existing = view
        if (existing != null && existing.isAttachedToWindow) return existing
        return attach(activity)
    }

    fun detach() {
        val v = view ?: return
        (v.parent as? ViewGroup)?.removeView(v)
        view = null
    }
}
