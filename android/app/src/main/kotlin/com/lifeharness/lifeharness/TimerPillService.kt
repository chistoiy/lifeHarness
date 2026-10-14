package com.lifeharness.lifeharness

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import android.text.TextUtils
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView
import java.util.Locale

/// 批B（工单 悬浮胶囊增强批-20261014 §7）：app 外系统悬浮窗载体。
///
/// 形态（照 §5 ⓕ mock）：固定顶部、不拖动、深色中性浮层——呼吸点＋
/// 「书名 · 状态」＋等宽秒显＋「■ 结束」；点胶囊体＝普通拉起 app，
/// 点「■ 结束」＝带 [MainActivity.ACTION_PILL_END] 拉起 app（Dart 侧
/// takePillEvent 消费后结束会话·与 lh/intents 同模式）。
///
/// 生命周期由 Dart 侧 `lh/pill` 通道驱动（起服务只发生在 app 前台，规避
/// Android 14+ 后台起 FGS 限制）：
/// - sync（visible=true）＝起/更新服务＋加/刷新悬浮视图；
/// - sync（visible=false）＝服务保活、视图收起（app 前台/进阅读器）；
/// - stop＝停服务（会话结束/功能关闭/权限被撤）。
/// 保活兜底：视图在场且 120s 无 sync＝dart 侧已死（activity 销毁但进程还在），
/// 自停防「僵尸悬浮窗」。
class TimerPillService : Service() {

    private var wm: WindowManager? = null
    private var overlayView: View? = null
    private var payload = PillPayload()
    private var lastSyncAt = 0L

    private val staleHandler = Handler(Looper.getMainLooper())
    private val staleCheck = object : Runnable {
        override fun run() {
            if (overlayView != null &&
                SystemClock.elapsedRealtime() - lastSyncAt > STALE_MS
            ) {
                stopSelf()
            } else {
                staleHandler.postDelayed(this, STALE_CHECK_MS)
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_SYNC -> {
                payload = readPayload(intent)
                if (!Settings.canDrawOverlays(this)) {
                    stopSelf()
                    return START_NOT_STICKY
                }
                startForeground(NOTI_ID, buildNotification(payload))
                lastSyncAt = SystemClock.elapsedRealtime()
                applyOverlay()
                staleHandler.removeCallbacks(staleCheck)
                staleHandler.postDelayed(staleCheck, STALE_CHECK_MS)
            }
            else -> stopSelf()
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        staleHandler.removeCallbacks(staleCheck)
        removeOverlay()
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // ---- 悬浮视图 ----

    private fun applyOverlay() {
        if (!payload.visible) {
            removeOverlay()
            return
        }
        val cur = overlayView
        if (cur != null) {
            updateTexts(cur)
            return
        }
        if (!Settings.canDrawOverlays(this)) return
        val v = buildOverlay()
        try {
            wm?.addView(v, overlayParams())
            overlayView = v
        } catch (_: Exception) {
            // 个别 ROM 拒绝加窗：服务与通知仍在，视图缺失降级（不停主流程）。
        }
    }

    private fun removeOverlay() {
        val v = overlayView ?: return
        overlayView = null
        try {
            wm?.removeView(v)
        } catch (_: Exception) {
            // 已随窗口 detach：重复移除按无害处理。
        }
    }

    private fun overlayParams(): WindowManager.LayoutParams {
        val dm = resources.displayMetrics
        fun dp(v: Int) = (v * dm.density + 0.5f).toInt()
        val statusBar = try {
            val id = resources.getIdentifier("status_bar_height", "dimen", "android")
            if (id > 0) resources.getDimensionPixelSize(id) else dp(25)
        } catch (_: Exception) {
            dp(25)
        }
        return WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = dp(12)
            y = statusBar + dp(8)
        }
    }

    private fun buildOverlay(): View {
        val dm = resources.displayMetrics
        fun dp(v: Int) = (v * dm.density + 0.5f).toInt()
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(12), dp(9), dp(12), dp(9))
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dp(16).toFloat()
                setColor(Color.parseColor("#E60F172A"))
                setStroke(dp(1), Color.parseColor("#2EFFFFFF"))
            }
            isClickable = true
            setOnClickListener { launchApp(null) }
        }
        val dot = View(this).apply {
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#FB7185"))
            }
        }
        root.addView(dot, LinearLayout.LayoutParams(dp(7), dp(7)))
        val label = TextView(this).apply {
            textSize = 11f
            setTextColor(Color.WHITE)
            maxLines = 1
            ellipsize = TextUtils.TruncateAt.END
            setPadding(dp(8), 0, dp(8), 0)
            layoutParams = LinearLayout.LayoutParams(dp(140), LinearLayout.LayoutParams.WRAP_CONTENT)
            tag = TAG_LABEL
        }
        root.addView(label)
        val time = TextView(this).apply {
            textSize = 13f
            setTextColor(Color.WHITE)
            typeface = Typeface.MONOSPACE
            paint.isFakeBoldText = true
            tag = TAG_TIME
        }
        root.addView(
            time,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ),
        )
        val end = TextView(this).apply {
            text = "■ 结束"
            textSize = 11f
            setTextColor(Color.WHITE)
            paint.isFakeBoldText = true
            setPadding(dp(10), dp(5), dp(10), dp(5))
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dp(9).toFloat()
                setColor(Color.parseColor("#26FFFFFF"))
            }
            isClickable = true
            setOnClickListener { launchApp(payload.kind) }
        }
        root.addView(
            end,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply { leftMargin = dp(6) },
        )
        updateTexts(root)
        return root
    }

    private fun updateTexts(root: View) {
        root.findViewWithTag<TextView>(TAG_LABEL)?.text =
            if (payload.status.isEmpty()) payload.title else "${payload.title} · ${payload.status}"
        root.findViewWithTag<TextView>(TAG_TIME)?.text = fmt(payload.seconds)
    }

    // ---- 通知（前台 Service 载体）----

    private fun createChannel() {
        val nm = getSystemService(NotificationManager::class.java) ?: return
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return
        nm.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "计时悬浮窗",
                NotificationManager.IMPORTANCE_LOW,
            ).apply { description = "计时进行中的常驻通知 · app 外悬浮窗载体" },
        )
    }

    private fun buildNotification(p: PillPayload): Notification {
        val open = PendingIntent.getActivity(
            this,
            REQ_OPEN,
            Intent(this, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val end = PendingIntent.getActivity(
            this,
            REQ_END,
            Intent(this, MainActivity::class.java).apply {
                action = MainActivity.ACTION_PILL_END
                putExtra(MainActivity.EXTRA_PILL_KIND, p.kind)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val title = if (p.title.isEmpty()) "计时悬浮窗运行中" else "计时中 · ${p.title}"
        return Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(p.status)
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setContentIntent(open)
            .addAction(0, "■ 结束", end)
            .build()
    }

    // ---- 拉起 app ----

    private fun launchApp(endKind: String?) {
        val intent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (endKind != null) {
                action = MainActivity.ACTION_PILL_END
                putExtra(MainActivity.EXTRA_PILL_KIND, endKind)
            }
        }
        try {
            startActivity(intent)
        } catch (_: Exception) {
            // 极端态（app 被禁用中）拉不起：不崩，悬浮窗仍在。
        }
    }

    /// 悬浮窗载荷（Dart 侧 SysPillState 同构）——类体直接嵌套（勿放
    /// companion：外部 `TimerPillService.PillPayload` 限定访问不可解析）。
    data class PillPayload(
        val kind: String = "read",
        val title: String = "",
        val status: String = "",
        val seconds: Int = 0,
        val visible: Boolean = true,
    )

    companion object {
        const val CHANNEL_ID = "lh_timer_pill"
        const val ACTION_SYNC = "com.lifeharness.pill.SYNC"
        const val ACTION_STOP = "com.lifeharness.pill.STOP"
        const val EXTRA_KIND = "kind"
        const val EXTRA_TITLE = "title"
        const val EXTRA_STATUS = "status"
        const val EXTRA_SECONDS = "seconds"
        const val EXTRA_VISIBLE = "visible"
        const val TAG_LABEL = "pill-label"
        const val TAG_TIME = "pill-time"
        const val NOTI_ID = 0x9107
        const val REQ_OPEN = 0x9108
        const val REQ_END = 0x9109
        const val STALE_MS = 120_000L
        const val STALE_CHECK_MS = 15_000L

        private fun readPayload(intent: Intent): PillPayload = PillPayload(
            kind = intent.getStringExtra(EXTRA_KIND) ?: "read",
            title = intent.getStringExtra(EXTRA_TITLE) ?: "",
            status = intent.getStringExtra(EXTRA_STATUS) ?: "",
            seconds = intent.getIntExtra(EXTRA_SECONDS, 0),
            visible = intent.getBooleanExtra(EXTRA_VISIBLE, true),
        )

        fun syncIntent(context: Context, p: PillPayload): Intent =
            Intent(context, TimerPillService::class.java).apply {
                action = ACTION_SYNC
                putExtra(EXTRA_KIND, p.kind)
                putExtra(EXTRA_TITLE, p.title)
                putExtra(EXTRA_STATUS, p.status)
                putExtra(EXTRA_SECONDS, p.seconds)
                putExtra(EXTRA_VISIBLE, p.visible)
            }

        fun stopIntent(context: Context): Intent =
            Intent(context, TimerPillService::class.java).apply { action = ACTION_STOP }

        /// m:ss→h:mm:ss（与 Dart 侧 pillFmtHMS 同口径）。
        fun fmt(sec: Int): String {
            val h = sec / 3600
            val m = (sec % 3600) / 60
            val s = sec % 60
            return if (h > 0) String.format(Locale.US, "%d:%02d:%02d", h, m, s)
            else String.format(Locale.US, "%d:%02d", m, s)
        }
    }
}
