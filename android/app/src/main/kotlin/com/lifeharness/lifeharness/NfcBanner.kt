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
import android.view.animation.AccelerateInterpolator
import android.view.animation.DecelerateInterpolator
import android.widget.FrameLayout
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
 * 动效（批3f · 照「时间日志」的横条效果）：整条卡片**从屏幕一侧横向滑进来**，
 * 停 2.6 秒后再**往反方向滑出去**，且**进场方向逐次交替**（第一次左→右，第二次
 * 右→左，第三次又左→右），连贴两张时视觉上有「来回穿梭」的节奏感，而不是每回都
 * 从同一边弹出来。
 *
 * 实现要点：悬浮窗会把超出窗口矩形的内容裁掉，所以**窗口必须铺满整屏宽**（卡片靠
 * 左右 margin 内缩 16dp）；只有这样，卡片的横向位移才表现为「从屏幕边缘滑入／滑出」，
 * 而不是从窗口边缘凭空出现。
 *
 * 红线：
 * · 加窗失败（无悬浮窗权限／ROM 拒绝）**一律返回 false**，由 Dart 侧退回系统通知，
 *   绝不因为回执失败影响已经落库的业务动作；
 * · `FLAG_NOT_TOUCHABLE`——横幅只报信不接收点击，绝不挡住状态栏下拉与首屏点击
 *   （窗口虽是整屏宽，但该标志下系统完全不把触摸派给它）；
 * · 只显示一句话，2.6 秒自动消失，连贴两张时后一条顶掉前一条（不排队堆积）。
 */
object NfcBanner {
    private const val TAG = "LH-NFC"

    /** 停留时长（含滑出）：够读完一句话，又不至于在桌面赖着。 */
    private const val SHOW_MS = 2600L

    /** 滑入／滑出时长：参考应用观感偏利落，250ms 上下。 */
    private const val SLIDE_IN_MS = 250L
    private const val SLIDE_OUT_MS = 200L

    private val main = Handler(Looper.getMainLooper())
    private var host: WindowManager? = null
    private var root: View? = null
    private var card: View? = null
    private var hideTask: Runnable? = null

    /** 下一次进场是否从左往右；每次 show 后取反 ⇒ 左右交替。 */
    private var enterFromLeft = true

    /** 当前这条横幅的进场方向（退场一律往反方向滑出）。 */
    private var currentFromLeft = true

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
            val fromLeft = enterFromLeft
            enterFromLeft = !fromLeft
            val screenW = app.resources.displayMetrics.widthPixels.toFloat()
            val built = build(app, text)
            val lp = params(app)
            wm.addView(built.root, lp)
            // 真机（HyperOS）实测：挂上去后窗口带 alpha=0.8（`dumpsys window windows`
            // 里 mAttrs 与 mShownAlpha 都是 0.8），整条卡片半透明、桌面图标透出来。
            // 这里挂完再回写一次 alpha，并打一行回读日志——若日志是 1.0 而 dumpsys
            // 仍是 0.8，即 ROM 在系统侧强制调暗，App 侧无法解除。
            lp.alpha = 1f
            wm.updateViewLayout(built.root, lp)
            Log.i(TAG, "横幅已挂：alpha=${lp.alpha} w=${lp.width} fromLeft=$fromLeft")
            host = wm
            root = built.root
            card = built.card
            currentFromLeft = fromLeft
            // 起点放在屏幕外（整条都在视野外），再滑到位。
            // 只做横向位移、**不碰 alpha**：实测「位移＋淡入」同时跑时淡入会停在
            // 半路（真机截图反推不透明度 0.78 后不再上升，卡片半透明透出桌面图标）；
            // 参考应用本身也是纯滑动无淡入，去掉更贴原效果。
            built.card.translationX = if (fromLeft) -screenW else screenW
            built.card.alpha = 1f
            built.card.animate()
                .translationX(0f)
                .setDuration(SLIDE_IN_MS)
                .setInterpolator(DecelerateInterpolator())
                .start()
            val task = Runnable { dismiss() }
            hideTask = task
            main.postDelayed(task, SHOW_MS)
            true
        } catch (e: Exception) {
            // 常见：未授予「显示在其他应用上层」/ ROM 拒绝后台加窗。
            Log.w(TAG, "贴卡横幅不可用：${e.javaClass.simpleName}")
            host = null
            root = null
            card = null
            false
        }
    }

    /** 滑出去（往进场方向的**反方向**），滑完摘窗。 */
    private fun dismiss() {
        val c = card ?: return
        val r = root
        val wm = host
        card = null
        hideTask = null
        val screenW = c.resources.displayMetrics.widthPixels.toFloat()
        val out = if (currentFromLeft) screenW else -screenW
        c.animate()
            .translationX(out)
            .setDuration(SLIDE_OUT_MS)
            .setInterpolator(AccelerateInterpolator())
            .withEndAction { if (wm != null && r != null) removeQuietly(wm, r) }
            .start()
    }

    /** 立刻撤下（新横幅进场前调用，避免两条叠在一起）。 */
    private fun dismissNow() {
        hideTask?.let { main.removeCallbacks(it) }
        hideTask = null
        val r = root ?: return
        val wm = host
        root = null
        card = null
        if (wm != null) removeQuietly(wm, r)
    }

    /** 摘窗；**不动 [host]/[root] 字段**——滑出收尾时可能已经有新横幅进场。 */
    private fun removeQuietly(wm: WindowManager, v: View) {
        try {
            wm.removeView(v)
        } catch (_: Exception) {
            // 已被系统摘掉（权限撤销/窗口被回收）——忽略即可，无回执可发。
        }
    }

    /** 窗口根（整屏宽透明容器）＋ 真正做位移动画的卡片。 */
    private class Built(val root: View, val card: View)

    private fun build(app: Context, text: String): Built {
        val night = (app.resources.configuration.uiMode and
                Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
        val surface = if (night) Color.parseColor("#2B2B2B") else Color.WHITE
        val onSurface = if (night) Color.parseColor("#F2F2F2") else Color.parseColor("#1C1B1F")
        val outline = if (night) Color.parseColor("#4A4A4A") else Color.parseColor("#E4E1E6")
        val accent = Color.parseColor("#3F8F91")

        val row = LinearLayout(app).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(app, 16), dp(app, 14), dp(app, 16), dp(app, 14))
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dp(app, 18).toFloat()
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
                marginEnd = dp(app, 12)
            }
        })
        row.addView(TextView(app).apply {
            this.text = text
            setTextColor(onSurface)
            textSize = 15f
            maxLines = 3
            typeface = Typeface.DEFAULT_BOLD
        })

        // 整屏宽的透明容器：卡片在里面横移，越界部分正好被屏幕边缘裁掉。
        val container = FrameLayout(app).apply { setBackgroundColor(Color.TRANSPARENT) }
        container.addView(
            row,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
            ).apply {
                marginStart = dp(app, 16)
                marginEnd = dp(app, 16)
            },
        )
        return Built(container, row)
    }

    private fun params(app: Context): WindowManager.LayoutParams =
        WindowManager.LayoutParams(
            // 必须 MATCH_PARENT：见类注释「实现要点」。
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            // NOT_FOCUSABLE：不抢焦点（不打断输入）；NOT_TOUCHABLE：不接收点击
            //（横幅只报信，绝不能挡住状态栏下拉或桌面图标）。
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            y = statusBarHeight(app) + dp(app, 8)
            // 显式钉死窗口不透明度。真机实测（`dumpsys window windows` 读 mAttrs）：
            // 不写这一行时窗口带着 alpha=0.8 上来，整条卡片半透明、桌面图标透过来
            //（截图反推不透明度 0.78，与 View 层 alpha 无关）。
            alpha = 1f
        }

    private fun dp(app: Context, v: Int): Int =
        (v * app.resources.displayMetrics.density + 0.5f).toInt()

    private fun statusBarHeight(app: Context): Int {
        val id = app.resources.getIdentifier("status_bar_height", "dimen", "android")
        return if (id > 0) app.resources.getDimensionPixelSize(id) else dp(app, 25)
    }
}
