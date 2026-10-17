package com.lifeharness.lifeharness

import android.content.Context
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView

/**
 * 贴卡结果**悬浮横幅**（批3e · 2026-10-17 真机报障）。
 *
 * 为什么不用系统 Heads-Up：真机（HyperOS）实测——同一台机器上 `Importance.high`
 * 渠道的通知**只进通知栏、不上浮**（`dumpsys notification` 里 importance=4 确认无
 * 误判），即 ROM 层把后台 App 的 Heads-Up 静默掉了。系统层没有强制手段
 *（`fullScreenIntent` 在 Android 14+ 只给闹钟/通话类应用），所以改由**本 App 自己
 * 画一条**：`TYPE_APPLICATION_OVERLAY` 悬浮窗，和悬浮胶囊同一套权限与机制（该权限
 * 真机已授予、胶囊可证机制可用）。
 *
 * 红线：
 * · 加窗失败（无悬浮窗权限／ROM 拒绝）**一律返回 false**，由 Dart 侧退回系统通知，
 *   绝不因为回执失败影响已经落库的业务动作；
 * · `FLAG_NOT_TOUCHABLE`——横幅只报信不接收点击，绝不挡住状态栏下拉与首屏点击；
 * · 只显示一句话，2.6 秒自动消失，连贴两张时后一条顶掉前一条（不排队堆积）。
 */
object NfcBanner {
    private const val TAG = "LH-NFC"

    /** 停留时长（含淡出）：够读完一句话，又不至于在桌面赖着。 */
    private const val SHOW_MS = 2600L
    private const val FADE_IN_MS = 140L
    private const val FADE_OUT_MS = 180L

    private val main = Handler(Looper.getMainLooper())
    private var host: WindowManager? = null
    private var view: View? = null
    private var hideTask: Runnable? = null

    /**
     * 弹一条横幅。返回 false ＝ 没能弹（无权限/加窗被拒），调用方据此退回系统通知。
     *
     * 必须在主线程调用（`lh/nfc` 通道回调本身就在主线程）。
     */
    fun show(context: Context, text: String): Boolean {
        if (text.isBlank()) return false
        val app = context.applicationContext
        val wm = app.getSystemService(Context.WINDOW_SERVICE) as? WindowManager ?: return false
        return try {
            dismissNow() // 连贴两张：后一条顶掉前一条
            val v = build(app, text)
            wm.addView(v, params(app))
            host = wm
            view = v
            v.alpha = 0f
            v.animate().alpha(1f).setDuration(FADE_IN_MS).start()
            val task = Runnable { dismiss() }
            hideTask = task
            main.postDelayed(task, SHOW_MS)
            true
        } catch (e: Exception) {
            // 常见：未授予「显示在其他应用上层」/ ROM 拒绝后台加窗。
            Log.w(TAG, "贴卡横幅不可用：${e.javaClass.simpleName}")
            host = null
            view = null
            false
        }
    }

    private fun dismiss() {
        val v = view ?: return
        val wm = host
        view = null
        v.animate()
            .alpha(0f)
            .setDuration(FADE_OUT_MS)
            .withEndAction { if (wm != null) removeQuietly(wm, v) }
            .start()
    }

    /** 立刻撤下（新横幅进场前调用，避免两条叠在一起）。 */
    private fun dismissNow() {
        hideTask?.let { main.removeCallbacks(it) }
        hideTask = null
        val v = view ?: return
        val wm = host
        view = null
        if (wm != null) removeQuietly(wm, v)
    }

    /** 摘窗；**不动 [host]/[view] 字段**——淡出动画收尾时可能已经有新横幅进场。 */
    private fun removeQuietly(wm: WindowManager, v: View) {
        try {
            wm.removeView(v)
        } catch (_: Exception) {
            // 已被系统摘掉（权限撤销/窗口被回收）——忽略即可，无回执可发。
        }
    }

    private fun build(app: Context, text: String): View {
        val night = (app.resources.configuration.uiMode and
                Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
        val surface = if (night) Color.parseColor("#2B2B2B") else Color.WHITE
        val onSurface = if (night) Color.parseColor("#F2F2F2") else Color.parseColor("#1C1B1F")
        val outline = if (night) Color.parseColor("#4A4A4A") else Color.parseColor("#E4E1E6")
        val accent = Color.parseColor("#3F8F91")

        val row = LinearLayout(app).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(app, 14), dp(app, 12), dp(app, 14), dp(app, 12))
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dp(app, 16).toFloat()
                setColor(surface)
                setStroke(dp(app, 1), outline)
            }
            elevation = dp(app, 8).toFloat()
        }
        // 左侧小圆点：与悬浮胶囊的「呼吸点」同一视觉语言。
        row.addView(View(app).apply {
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(accent)
            }
            layoutParams = LinearLayout.LayoutParams(dp(app, 8), dp(app, 8)).apply {
                marginEnd = dp(app, 10)
            }
        })
        row.addView(TextView(app).apply {
            this.text = text
            setTextColor(onSurface)
            textSize = 14f
            maxLines = 3
            typeface = Typeface.DEFAULT
        })
        return row
    }

    private fun params(app: Context): WindowManager.LayoutParams {
        val width = app.resources.displayMetrics.widthPixels - dp(app, 32)
        return WindowManager.LayoutParams(
            width,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            // NOT_FOCUSABLE：不抢焦点（不打断输入）；NOT_TOUCHABLE：不接收点击
            //（横幅只报信，绝不能挡住状态栏下拉或桌面图标）。
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            y = statusBarHeight(app) + dp(app, 10)
        }
    }

    private fun dp(app: Context, v: Int): Int =
        (v * app.resources.displayMetrics.density + 0.5f).toInt()

    private fun statusBarHeight(app: Context): Int {
        val id = app.resources.getIdentifier("status_bar_height", "dimen", "android")
        return if (id > 0) app.resources.getDimensionPixelSize(id) else dp(app, 25)
    }
}
