package com.lifeharness.lifeharness

import android.app.Activity
import android.app.Application
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
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import android.text.TextUtils
import android.util.Log
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView
import java.util.Locale

/// app 可见性（进程级真值）：由 [MainActivity] 注册 ActivityLifecycleCallbacks
/// 维护，[TimerPillService] 读取它以自决悬浮窗显隐。
///
/// 为什么不让 Dart 决定（6133 热修 · 真机 BACK 退 app 不复现）：
/// BACK 结束 MainActivity 时 FlutterActivity 会连 FlutterEngine 一并销毁
/// （Dart 隔离区随之消失，此后一帧都不会再跑）。退后台那一次 `lh/pill` push
/// 与 engine teardown 是竞态——赶不上就永远不出现，且此后 Dart 无从再推。
/// 「本进程有没有已 start 的 Activity」是原生就能测的真值，与 Dart 死活无关。
internal object AppVisibility {

    /// 已 start 的 Activity 数（0＝app 不在前台）。默认 0：注册发生在
    /// MainActivity.onCreate，早于本次 onStart，首个计数不会漏。
    @Volatile
    var started: Int = 0
        private set

    /// 显隐变化回调（服务挂；只可能在主线程触发）。
    @Volatile
    private var listener: (() -> Unit)? = null

    private var registered = false

    val foreground: Boolean get() = started > 0

    fun setListener(l: (() -> Unit)?) {
        listener = l
    }

    /// 进程内只注册一次（Activity 重建会再进 onCreate，重复注册＝重复计数）。
    fun registerOnce(app: Application) {
        if (registered) return
        registered = true
        app.registerActivityLifecycleCallbacks(
            object : Application.ActivityLifecycleCallbacks {
                override fun onActivityStarted(activity: Activity) {
                    started++
                    listener?.invoke()
                }

                override fun onActivityStopped(activity: Activity) {
                    if (started > 0) started--
                    listener?.invoke()
                }

                override fun onActivityCreated(
                    activity: Activity,
                    savedInstanceState: Bundle?,
                ) = Unit

                override fun onActivityResumed(activity: Activity) = Unit

                override fun onActivityPaused(activity: Activity) = Unit

                override fun onActivitySaveInstanceState(
                    activity: Activity,
                    outState: Bundle,
                ) = Unit

                override fun onActivityDestroyed(activity: Activity) = Unit
            },
        )
    }
}

/// 批B（工单 悬浮胶囊增强批-20261014 §7）：app 外系统悬浮窗载体。
///
/// 形态（照 §5 ⓕ mock）：固定顶部、不拖动、深色中性浮层——呼吸点＋
/// 「书名 · 状态」＋等宽秒显＋「■ 结束」；点胶囊体＝普通拉起 app，
/// 点「■ 结束」＝带 [MainActivity.ACTION_PILL_END] 拉起 app（Dart 侧
/// takePillEvent 消费后结束会话·与 lh/intents 同模式）。
///
/// 生命周期由 Dart 侧 `lh/pill` 通道驱动（起服务只发生在 app 前台，规避
/// Android 14+ 后台起 FGS 限制）：
/// - sync＝起/更新服务＋按 [AppVisibility] 加/收悬浮视图；
/// - stop＝停服务（会话结束/功能关闭/权限被撤）。
/// **视图显隐＝原生自决**（6133 热修）：app 在不在前台由 [AppVisibility] 自测，
/// 不看 Dart 推来的 visible——BACK 退 app 会把 Dart 一起带走，靠 Dart 推的窗口
/// 会永久缺席。Dart 只在「功能开关/有无会话/权限」三条上把关（该推 stop 才停）。
/// 保活兜底：app 仍在前台却 30 分钟无 sync＝Dart 侧确实卡死，自停防僵尸；
/// app 已不在前台时**不设窗口**——会话仍在跑，窗口就该一直在。
class TimerPillService : Service() {

    private var wm: WindowManager? = null
    private var overlayView: View? = null
    private var payload = PillPayload()
    private var lastSyncAt = 0L

    /// 原生自走秒（6132 热修）：秒显由本进程按 session 起点自算，不依赖 Dart
    /// 每秒推送——HyperOS 退后台会挂起整进程（Dart tick 与 FGS 同冻结），
    /// 靠 Dart 推秒在真机上会停表。顺带自决视图显隐（6133 热修，每秒兜一次，
    /// 防生命周期回调漏触发）与僵尸兜底（见下）。
    private val tickHandler = Handler(Looper.getMainLooper())
    private val tick = object : Runnable {
        override fun run() {
            refreshOverlay()
            val v = overlayView
            if (v != null) {
                val sec = if (payload.startedAtMs > 0) {
                    ((System.currentTimeMillis() - payload.startedAtMs) / 1000L)
                        .toInt()
                } else {
                    payload.seconds
                }
                v.findViewWithTag<TextView>(TAG_TIME)?.text = fmt(sec)
            }
            // 僵尸兜底：**app 仍在前台**却 STALE_MS 无 Dart sync ＝ dart 侧确实
            // 卡死（engine 还在但回调停摆），自停防僵尸窗口。app 已不在前台时
            // 不设窗口：会话仍在跑，窗口就该一直在——Dart 死活与它无关（终局由
            // Dart 的 stop／用户点「■ 结束」收）。
            if (AppVisibility.foreground &&
                SystemClock.elapsedRealtime() - lastSyncAt > STALE_MS
            ) {
                stopSelf()
                return
            }
            tickHandler.postDelayed(this, TICK_MS)
        }
    }

    override fun onCreate() {
        super.onCreate()
        wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        createChannel()
        // 显隐随 Activity 生死即时应答（秒级 tick 只是兜底）。
        AppVisibility.setListener { refreshOverlay() }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_SYNC) payload = readPayload(intent)
        Log.i(
            TAG,
            "onStartCommand action=${intent?.action} visible=${payload.visible} " +
                "sec=${payload.seconds} startAt=${payload.startedAtMs} " +
                "appFg=${AppVisibility.foreground}(${AppVisibility.started})",
        )
        // startForeground 必须先行：startForegroundService 起的服务 5s 内不进前台
        // ＝RemoteServiceException 崩溃；无权限/ROM 拒授也先吃下回调再自停，且包
        // try/catch——失败按无悬浮窗降级，绝不崩 app（6128 实伤：缺 FOREGROUND_SERVICE
        // 基础权限，sync 即 SecurityException 主进程崩）。
        val fgOk = try {
            startForeground(NOTI_ID, buildNotification(payload))
            true
        } catch (_: Exception) {
            false
        }
        when (intent?.action) {
            ACTION_SYNC -> {
                if (!fgOk || !Settings.canDrawOverlays(this)) {
                    stopSelf()
                    return START_NOT_STICKY
                }
                lastSyncAt = SystemClock.elapsedRealtime()
                refreshOverlay()
                tickHandler.removeCallbacks(tick)
                tickHandler.postDelayed(tick, TICK_MS)
            }
            else -> stopSelf()
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        tickHandler.removeCallbacks(tick)
        AppVisibility.setListener(null)
        removeOverlay()
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // ---- 悬浮视图 ----

    /// 视图该不该在＝**app 在不在前台**（原生真值）。服务只在有会话且功能开
    /// 且已授权时才被 Dart 拉起，故「不在前台＝该显示」成立；Dart 推来的
    /// visible 不再参与判断（6133 热修，见类注释）。
    private fun overlayWanted(): Boolean = !AppVisibility.foreground

    /// 按当前前台状态加/收视图（幂等；生命周期回调与秒级 tick 两处调用）。
    private fun refreshOverlay() {
        if (overlayWanted()) applyOverlay() else removeOverlay()
    }

    private fun applyOverlay() {
        if (!overlayWanted()) {
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
            Log.i(TAG, "overlay added")
        } catch (e: Exception) {
            // 个别 ROM 拒绝加窗：服务与通知仍在，视图缺失降级（不停主流程）。
            Log.w(TAG, "overlay add failed: ${e.javaClass.simpleName} ${e.message}")
        }
    }

    private fun removeOverlay() {
        val v = overlayView ?: return
        overlayView = null
        try {
            wm?.removeView(v)
            Log.i(TAG, "overlay removed")
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
        val startedAtMs: Long = 0L,
        val visible: Boolean = true,
    )

    companion object {
        const val TAG = "lh_pill"
        const val CHANNEL_ID = "lh_timer_pill"
        const val ACTION_SYNC = "com.lifeharness.pill.SYNC"
        const val ACTION_STOP = "com.lifeharness.pill.STOP"
        const val EXTRA_KIND = "kind"
        const val EXTRA_TITLE = "title"
        const val EXTRA_STATUS = "status"
        const val EXTRA_SECONDS = "seconds"
        const val EXTRA_STARTED_AT = "startedAt"
        const val EXTRA_VISIBLE = "visible"
        const val TAG_LABEL = "pill-label"
        const val TAG_TIME = "pill-time"
        const val NOTI_ID = 0x9107
        const val REQ_OPEN = 0x9108
        const val REQ_END = 0x9109
        const val TICK_MS = 1_000L
        /// 僵尸兜底窗口（放宽：正常退后台 Dart 可能被系统挂起，短窗口会误杀）。
        const val STALE_MS = 30 * 60 * 1000L

        private fun readPayload(intent: Intent): PillPayload = PillPayload(
            kind = intent.getStringExtra(EXTRA_KIND) ?: "read",
            title = intent.getStringExtra(EXTRA_TITLE) ?: "",
            status = intent.getStringExtra(EXTRA_STATUS) ?: "",
            seconds = intent.getIntExtra(EXTRA_SECONDS, 0),
            startedAtMs = intent.getLongExtra(EXTRA_STARTED_AT, 0L),
            visible = intent.getBooleanExtra(EXTRA_VISIBLE, true),
        )

        fun syncIntent(context: Context, p: PillPayload): Intent =
            Intent(context, TimerPillService::class.java).apply {
                action = ACTION_SYNC
                putExtra(EXTRA_KIND, p.kind)
                putExtra(EXTRA_TITLE, p.title)
                putExtra(EXTRA_STATUS, p.status)
                putExtra(EXTRA_SECONDS, p.seconds)
                putExtra(EXTRA_STARTED_AT, p.startedAtMs)
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
