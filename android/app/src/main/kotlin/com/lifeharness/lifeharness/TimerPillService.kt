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
import android.content.SharedPreferences
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import android.util.Log
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
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
/// 形态（照 §5ⓕmock＋批A 交互口径）：**可拖动**的深色中性浮层——呼吸点＋
/// 「书名 · 状态」＋等宽秒显＋「■ 结束」；点胶囊体＝普通拉起 app，点「■ 结束」
/// ＝带 [MainActivity.ACTION_PILL_END] 拉起 app（Dart 侧 takePillEvent 消费后
/// 结束会话·与 lh/intents 同模式）。
///
/// **拖动与折叠（6135·对齐 app 内胶囊手感）**：整条可拖；拖到屏幕左右边缘
/// [EDGE_SNAP_DP] 内松手 → 折叠成 [FAB_SIZE_DP] 贴边圆圈（只显时长），点圆圈
/// 直接展开；两态互斥。位置按形态入 SharedPreferences（y 存屏高比例，跨机型
/// 不漂）——与 app 内 `*.pillPos`/`*.pillFabPos` kv 同口径。
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

    // ---- 拖动 / 折叠态（6135）----
    /** 当前是否折叠成贴边圆圈。 */
    private var folded = false

    /** 胶囊/圆圈左上角绝对坐标（相对屏幕，gravity=TOP|START 下的 x/y）。 */
    private var posX = 0
    private var posY = 0

    /** 折叠时吸附到哪一侧：'l' 或 'r'。 */
    private var fabSide = "l"

    /** 拖动手势状态。 */
    private var downRawX = 0f
    private var downRawY = 0f
    private var downPosX = 0
    private var downPosY = 0

    /** 越过 slop 那一帧回退出的基准点（吃掉阈值＝起步不粘滞）。 */
    private var slopBaseX = 0
    private var slopBaseY = 0
    private var dragging = false
    private var touchSlop = 0

    /**
     * 窗口上一次**真正应用**的 x/y（6135 热修·拖动跟手）。
     *
     * `moveOverlay` 的去重守卫必须比对这对字段而非新建的 `overlayParams()`
     * （后者构造时已带 `posX/posY`，恒等于目标值 → 每帧 MOVE 都提前 return，
     * 窗口从头到尾没动过＝拖动不跟手）。`addView` 后同步播种。
     */
    private var appliedX = Int.MIN_VALUE
    private var appliedY = Int.MIN_VALUE

    /**
     * 胶囊实测宽度（6135·对齐 app 内 `_barW`）。
     * 首次布局完成后取一次；期间回落 [BAR_W_GUESS_DP] 估算。
     */
    private var measuredBarW = 0

    private val prefs: SharedPreferences
        get() = getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /**
     * 配色令牌（6135·与 app 内胶囊同源）。
     *
     * app 内 `_pillBox` 用 `colorScheme.surface/onSurface/outlineVariant`，
     * 而该 scheme 由 `ColorScheme.fromSeed(seedColor: #6366F1)` 生成（见
     * `app_theme.dart`）——原生拿不到 Flutter 的 scheme，故按 **M3 标准算法**
     * 在此复刻同一组值，亮/暗跟随系统。色值与 app 内逐档一致（非新增色相，
     * 是同一 seed 的派生值），符合 UI 组件规范〇B「走主题令牌」。
     */
    private val palette: Pal get() = if (isNight) Pal.DARK else Pal.LIGHT

    private val isNight: Boolean
        get() = (resources.configuration.uiMode and
            android.content.res.Configuration.UI_MODE_NIGHT_MASK) ==
            android.content.res.Configuration.UI_MODE_NIGHT_YES

    /** M3 surface/onSurface/outlineVariant（seed #6366F1 派生·同 app 内 scheme）。 */
    private enum class Pal(
        val surface: Int,
        val onSurface: Int,
        val outlineVariant: Int,
        val surfaceContainerHighest: Int,
        val onSurfaceVariant: Int,
        val primary: Int,
        val tertiary: Int,
    ) {
        LIGHT(
            surface = 0xFFFFFFFF.toInt(),
            onSurface = 0xFF1B1B1F.toInt(),
            outlineVariant = 0xFFE2E1EC.toInt(),
            surfaceContainerHighest = 0xFFE9E7EF.toInt(),
            onSurfaceVariant = 0xFF47464F.toInt(),
            primary = 0xFF6366F1.toInt(),
            tertiary = 0xFFB84C9B.toInt(),
        ),
        DARK(
            surface = 0xFF141318.toInt(),
            onSurface = 0xFFE5E1E9.toInt(),
            outlineVariant = 0xFF47464F.toInt(),
            surfaceContainerHighest = 0xFF47464F.toInt(),
            onSurfaceVariant = 0xFFCAC4D0.toInt(),
            primary = 0xFFA8A2FF.toInt(),
            tertiary = 0xFFFFB0DA.toInt(),
        ),
    }

    /// 原生自走秒（6132 热修）：秒显由本进程按 session 起点自算，不依赖 Dart
    /// 每秒推送——HyperOS 退后台会挂起整进程（Dart tick 与 FGS 同冻结），
    /// 靠 Dart 推秒在真机上会停表。顺带自决视图显隐（6133 热修，每秒兜一次，
    /// 防生命周期回调漏触发）与僵尸兜底（见下）。
    private val tickHandler = Handler(Looper.getMainLooper())
    private val tick = object : Runnable {
        override fun run() {
            // 用户拖动中不打断（会与手势抢窗口更新）。
            if (!dragging) refreshOverlay()
            val v = overlayView
            if (v != null) {
                v.findViewWithTag<TextView>(TAG_TIME)?.text = fmtNow()
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
        touchSlop = ViewConfiguration.get(this).scaledTouchSlop
        // 位置/形态恢复：只在服务创建时做一次，此后由拖动与折叠自行维护。
        restorePos()
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
        // 形态与实际挂载的一致 → 只刷文案；不一致（用户拖到边缘折叠/点圆圈展开）
        // → 重建视图，否则圆圈与胶囊的视图树对不上。
        val cur = overlayView
        if (cur != null) {
            if (cur.getTag(R_TAG_FORM) == folded) {
                updateTexts(cur)
                moveOverlay(cur)
                return
            }
            removeOverlay()
        }
        if (!Settings.canDrawOverlays(this)) return
        // 位置恢复只在服务创建时做一次（onCreate）：这里若每次重建都恢复，
        // 会把 foldTo/unfold 刚算好的落点覆盖成存档值（折叠后 y 跳位）。
        val v = if (folded) buildFab() else buildOverlay()
        try {
            wm?.addView(v, overlayParams())
            overlayView = v
            // 播种「已应用位置」，否则首个 MOVE 会被去重守卫吃掉。
            appliedX = posX
            appliedY = posY
            Log.i(TAG, "overlay added folded=$folded x=$posX y=$posY")
            // 首次布局后量一次胶囊实宽（app 内 `_barW` 同口径），供贴边判定/展开定位。
            if (!folded) {
                v.post {
                    val w = v.width
                    if (w > 0 && w != measuredBarW) {
                        measuredBarW = w
                        Log.i(TAG, "bar measured w=$w")
                    }
                }
            }
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

    /**
     * 位置变化时更新窗口（拖动/吸附/展开都走这里，避免反复重建视图）。
     *
     * 6135 热修：**守卫必须比对「窗口上一次真正应用的位置」，不能拿新建的
     * `overlayParams()` 比**——后者在构造时已写入 `posX/posY`，恒等于目标值，
     * 会让每个 `ACTION_MOVE` 都在第一行 return，窗口一动不动（拖动「不跟手」）。
     */
    private fun moveOverlay(v: View) {
        if (appliedX == posX && appliedY == posY) return
        appliedX = posX
        appliedY = posY
        val p = overlayParams()
        p.x = posX
        p.y = posY
        try {
            wm?.updateViewLayout(v, p)
        } catch (_: Exception) {
            // 视图已 detach（竞态）：下个 tick 会重建。
        }
    }

    /// 拖动 + 点击判定（6135·与 app 内胶囊同手感）。
    ///
    /// app 内是 `GestureDetector(onPanUpdate/onPanEnd/onTap)`：位移一超 slop
    /// 就**从落点起连续跟手**（`_dragBar` 累加 delta），松手才判点击/吸附。
    /// 原生须复刻两点，否则用户感知就是「不跟手」：
    /// ① 位移超 [touchSlop] 的**那一帧**就把超出部分计入（吃掉阈值本身，
    ///   消除起步那段「粘滞」——先滑一点才突然追上手指）；
    /// ② 每个 MOVE 都 `updateViewLayout`（守卫比对 `appliedX/appliedY`），
    ///   而非等松手才落位。
    /// 松手：拖过 → [settle]（胶囊贴边折叠／圆圈吸附最近边）；没拖过 →
    /// 胶囊拉起 app、圆圈展开（同 app 内 `onTap` 语义）。
    private fun attachTouch(v: View) {
        v.setOnTouchListener { view, ev ->
            when (ev.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downRawX = ev.rawX
                    downRawY = ev.rawY
                    downPosX = posX
                    downPosY = posY
                    dragging = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = (ev.rawX - downRawX).toInt()
                    val dy = (ev.rawY - downRawY).toInt()
                    if (!dragging &&
                        (kotlin.math.abs(dx) > touchSlop ||
                            kotlin.math.abs(dy) > touchSlop)
                    ) {
                        // 判定与「吃掉阈值」同一帧完成：越过阈值的首帧即贴手。
                        dragging = true
                        slopBaseX = downPosX - sign(dx) * touchSlop
                        slopBaseY = downPosY - sign(dy) * touchSlop
                    }
                    if (dragging) {
                        posX = slopBaseX + dx
                        posY = slopBaseY + dy
                        moveOverlay(view)
                    }
                    true
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    val wasDragging = dragging
                    dragging = false
                    if (wasDragging) {
                        settle()
                    } else if (ev.actionMasked == MotionEvent.ACTION_UP) {
                        if (folded) unfold() else launchApp(null)
                    }
                    true
                }
                else -> false
            }
        }
    }

    private fun sign(v: Int): Int = if (v > 0) 1 else if (v < 0) -1 else 0

    /**
     * 松手落定（与 app 内 `_settleBar`/`_settleFab` 同口径）：
     * 横向夹取入 `EDGE_MARGIN_DP` 边距内；折叠态纵向再夹到「圆圈不压状态栏」
     * （app 内 `_dragFab` 的 `.clamp(kPillFabSize, …)`）；胶囊距左右边 ≤
     * [EDGE_SNAP_DP] 即折叠。
     */
    private fun settle() {
        val dm = resources.displayMetrics
        val w = dm.widthPixels
        val h = dm.heightPixels
        val size = currentSize()
        val m = dp(EDGE_MARGIN_DP)
        posX = posX.coerceIn(m, (w - size - m).coerceAtLeast(m))
        // 折叠态：顶边不得高于圆圈直径（＝不得压状态栏），与 app 内一致。
        val minY = if (folded) dp(FAB_SIZE_DP) else dp(8)
        posY = posY.coerceIn(minY, (h - size - dp(8)).coerceAtLeast(minY))
        if (folded) {
            // 圆圈松手＝吸附最近边（app 内 `_settleFab`）。
            fabSide = if (posX + size / 2 < w / 2) "l" else "r"
            posX = if (fabSide == "l") m else (w - dp(FAB_SIZE_DP) - m)
            persistFabPos()
            return
        }
        val nearLeft = posX <= dp(EDGE_SNAP_DP)
        val nearRight = (w - (posX + size)) <= dp(EDGE_SNAP_DP)
        if (nearLeft || nearRight) {
            foldTo(if (nearLeft) "l" else "r")
        } else {
            persistBarPos()
        }
    }

    /** 折叠成贴边圆圈：换视图树 ＋ 吸附到该侧边缘 ＋ 记位置（同 app 内 `_foldTo`）。 */
    private fun foldTo(side: String) {
        folded = true
        fabSide = side
        val dm = resources.displayMetrics
        val w = dm.widthPixels
        val h = dm.heightPixels
        val m = dp(EDGE_MARGIN_DP)
        // 纵向沿用松手位置，但按 app 内口径夹到「不压状态栏」以上。
        posY = posY.coerceIn(dp(FAB_SIZE_DP), (h - dp(FAB_SIZE_DP) - dp(8)).coerceAtLeast(dp(FAB_SIZE_DP)))
        posX = if (side == "l") m else (w - dp(FAB_SIZE_DP) - m)
        persistFabPos()
        rebuildOverlay()
    }

    /** 点圆圈展开：在圆圈同侧展开成胶囊（同 app 内 `_unfold`）。 */
    private fun unfold() {
        folded = false
        val w = resources.displayMetrics.widthPixels
        val h = resources.displayMetrics.heightPixels
        val m = dp(EDGE_MARGIN_DP)
        // 6135：用实测胶囊宽（回落 240dp 估算），右边缘展开不再错位。
        val bw = currentSize()
        posX = if (fabSide == "l") m else (w - bw - m)
        posY = posY.coerceIn(dp(8), (h - dp(BAR_H_DP) - dp(8)).coerceAtLeast(dp(8)))
        rebuildOverlay()
    }

    /** 形态切换＝视图树变了，重建（先收后加，保证顺序确定）。 */
    private fun rebuildOverlay() {
        removeOverlay()
        applyOverlay()
    }

    /**
     * 当前形态的估算尺寸（拖动夹取用）。
     *
     * 6135：胶囊宽改用**实测值**（app 内 `_dragBar` 用 `_barW(mq)` 实测宽，
     * 只在首帧量一次）；实测不可得时退回保守估算。原先一直用 240dp 猜宽，
     * 会让「贴边折叠判定」与「展开位置」都偏——右边缘展开时明显错位。
     */
    private fun currentSize(): Int =
        if (folded) dp(FAB_SIZE_DP)
        else measuredBarW.takeIf { it > 0 } ?: dp(BAR_W_GUESS_DP)

    private fun persistBarPos() {
        val dm = resources.displayMetrics
        prefs.edit()
            .putFloat(K_BAR_X, posX.toFloat() / dm.widthPixels)
            .putFloat(K_BAR_Y, posY.toFloat() / dm.heightPixels)
            .putBoolean(K_FOLDED, false)
            .apply()
    }

    private fun persistFabPos() {
        val dm = resources.displayMetrics
        prefs.edit()
            .putFloat(K_FAB_Y, posY.toFloat() / dm.heightPixels)
            .putString(K_FAB_SIDE, fabSide)
            .putBoolean(K_FOLDED, true)
            .apply()
    }

    /// 恢复上次位置（首次无记录＝默认落点：状态栏下、留 4px 边距，同 app 内）。
    private fun restorePos() {
        val dm = resources.displayMetrics
        val m = dp(EDGE_MARGIN_DP)
        folded = prefs.getBoolean(K_FOLDED, false)
        if (folded) {
            fabSide = prefs.getString(K_FAB_SIDE, "l") ?: "l"
            val yf = prefs.getFloat(K_FAB_Y, 0.06f)
            posY = (yf * dm.heightPixels).toInt()
            posX = if (fabSide == "l") m else dm.widthPixels - dp(FAB_SIZE_DP) - m
        } else {
            val xf = prefs.getFloat(K_BAR_X, Float.NaN)
            val yf = prefs.getFloat(K_BAR_Y, Float.NaN)
            posX = if (xf.isNaN()) m else (xf * dm.widthPixels).toInt()
            posY = if (yf.isNaN()) defaultTop() else (yf * dm.heightPixels).toInt()
        }
    }

    private fun defaultTop(): Int = statusBarHeight() + dp(8)

    private fun dp(v: Int): Int {
        val d = resources.displayMetrics.density
        return (v * d + 0.5f).toInt()
    }

    private fun statusBarHeight(): Int {
        val id = resources.getIdentifier("status_bar_height", "dimen", "android")
        return if (id > 0) resources.getDimensionPixelSize(id) else dp(25)
    }

    private fun overlayParams(): WindowManager.LayoutParams {
        return WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            // FLAG_NOT_FOCUSABLE 保留（不抢输入焦点）；拖动手势靠 TouchListener。
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = posX
            y = posY
        }
    }

    /**
     * 胶囊本体（6135·结构与 app 内 `_ReadPill` 的 `bar` 逐项对齐）：
     * 内边距 12/9・圆角 16・`surface` 底 .97 透明＋`outlineVariant` 描边＋阴影；
     * 内容＝**呼吸点 7＋间距 8＋时长 13 等宽＋间距 4＋按钮**（无书名——与 app 内
     * 恒紧凑口径一致，6135 前这里多一个书名标签，是不一致的一处）。
     * 按钮＝`surfaceContainerHighest` 底・圆角 9・11px 粗体 `onSurfaceVariant`。
     */
    private fun buildOverlay(): View {
        val p = palette
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(12), dp(9), dp(12), dp(9))
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dp(16).toFloat()
                setColor(withAlpha(p.surface, 248))
                setStroke(dp(1), p.outlineVariant)
            }
            elevation = dp(4).toFloat()
        }
        // 呼吸点：阅读＝primary、影音＝tertiary（同 app 内两态取值）。
        val dot = View(this).apply {
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(if (payload.kind == "media") p.tertiary else p.primary)
            }
        }
        root.addView(dot, LinearLayout.LayoutParams(dp(7), dp(7)))
        root.addView(View(this), LinearLayout.LayoutParams(dp(8), 1))
        val time = TextView(this).apply {
            textSize = 13f
            setTextColor(p.onSurface)
            typeface = MONO_BOLD
            includeFontPadding = false
            tag = TAG_TIME
        }
        root.addView(
            time,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply { leftMargin = dp(4); rightMargin = dp(4) },
        )
        // 6135：与 app 内 `_ReadPill` 的**双按钮**逐项对齐——`＋笔记`（阅读侧
        // 才有，影音侧无）＋间距 6＋`■ 结束`。此前原生只有「■结束」一个，
        // 是与 app 内不一致的一处。
        if (payload.kind != "media") {
            root.addView(pillBtn("＋笔记") { launchNote() })
            root.addView(View(this), LinearLayout.LayoutParams(dp(6), 1))
        }
        root.addView(pillBtn("■ 结束") { launchApp(payload.kind) })
        root.setTag(R_TAG_FORM, false)
        attachTouch(root)
        updateTexts(root)
        return root
    }

    /** 胶囊按钮（app 内 `_pillBtn` 同款：`surfaceContainerHighest` 底・圆角 9・
     * 11px 粗体 `onSurfaceVariant`）。clickable 自消费触摸，不与根拖动手势冲突。 */
    private fun pillBtn(label: String, onClick: () -> Unit): TextView {
        val p = palette
        return TextView(this).apply {
            text = label
            textSize = 11f
            setTextColor(p.onSurfaceVariant)
            typeface = Typeface.DEFAULT_BOLD
            includeFontPadding = false
            gravity = Gravity.CENTER
            setPadding(dp(10), dp(5), dp(10), dp(5))
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dp(9).toFloat()
                setColor(p.surfaceContainerHighest)
            }
            isClickable = true
            setOnClickListener { onClick() }
        }
    }

    /** 贴边圆圈（折叠态）：52dp 圆、同 `surface` 底与描边，只显时长（同 app 内 fab）。 */
    private fun buildFab(): View {
        val p = palette
        val root = TextView(this).apply {
            gravity = Gravity.CENTER
            textSize = 11f
            setTextColor(p.onSurface)
            typeface = MONO_BOLD
            includeFontPadding = false
            tag = TAG_TIME
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(withAlpha(p.surface, 248))
                setStroke(dp(1), p.outlineVariant)
            }
            elevation = dp(4).toFloat()
        }
        root.layoutParams = LinearLayout.LayoutParams(dp(FAB_SIZE_DP), dp(FAB_SIZE_DP))
        root.setTag(R_TAG_FORM, true)
        attachTouch(root)
        root.text = fmtNow()
        return root
    }

    /** 给色值加透明度（app 内 `surface.withValues(alpha: .97)`＝248/255）。 */
    private fun withAlpha(color: Int, alpha: Int): Int =
        (alpha shl 24) or (color and 0x00FFFFFF)

    private fun updateTexts(root: View) {
        // 6135：与 app 内恒紧凑口径一致——**不显书名**，只走时长。
        root.findViewWithTag<TextView>(TAG_TIME)?.let {
            it.text = fmtNow()
        }
    }

    /// 会话已走秒数（原生自算·不依赖 Dart 每秒推——HyperOS 退后台会挂起整进程）。
    private fun elapsedSec(): Int = if (payload.startedAtMs > 0) {
        ((System.currentTimeMillis() - payload.startedAtMs) / 1000L).toInt()
    } else {
        payload.seconds
    }

    /// 当前形态应显示的时长文案（胶囊 h:mm:ss／圆圈 h:mm）。
    private fun fmtNow(): String =
        if (folded) fmtFab(elapsedSec()) else fmt(elapsedSec())

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

    /// 悬浮窗「＋笔记」：拉起 app 带 [MainActivity.ACTION_PILL_NOTE]，
    /// Dart 侧 `drainPillEvents` 消费后直开书摘新建页（预选在跑书·同 app 内）。
    private fun launchNote() {
        try {
            startActivity(
                Intent(this, MainActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    action = MainActivity.ACTION_PILL_NOTE
                    putExtra(MainActivity.EXTRA_PILL_KIND, payload.kind)
                },
            )
        } catch (_: Exception) {
            // 拉不起不崩：胶囊仍在，计时不中断。
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
        const val TAG_TIME = "pill-time"

        /**
         * 等宽加粗（`tabularFigures` + `w700` 的原生等价）：app 内时长用
         * `FontWeight.w700` + `FontFeature.tabularFigures()`，原生取
         * `Typeface.MONOSPACE` 的粗体档最接近——数字等宽＝秒显不抖动，
         * 且字宽与 app 内一致（此前用 `MONOSPACE` 常规档偏细偏宽）。
         */
        val MONO_BOLD = Typeface.create(Typeface.MONOSPACE, Typeface.BOLD)
        const val NOTI_ID = 0x9107
        const val REQ_OPEN = 0x9108
        const val REQ_END = 0x9109
        const val TICK_MS = 1_000L
        /// 僵尸兜底窗口（放宽：正常退后台 Dart 可能被系统挂起，短窗口会误杀）。
        const val STALE_MS = 30 * 60 * 1000L

        // ---- 拖动/折叠常量（6135·与 app 内胶囊同口径：kPillFabSize/kPillEdgeSnap）----
        /** 贴边圆圈直径 dp（＝app 内 `kPillFabSize` 52）。 */
        const val FAB_SIZE_DP = 52

        /** 吸附带宽 dp：拖到距左右边 ≤24 松手即折叠（＝app 内 `kPillEdgeSnap`）。 */
        const val EDGE_SNAP_DP = 24

        /** 距屏边留白 dp（＝app 内 `_fabLeft = 4`／`_barPos` 夹取下界 4）。 */
        const val EDGE_MARGIN_DP = 4

        /** 胶囊实测高 dp（＝app 内 `kTimerBarHeight` 44）。 */
        const val BAR_H_DP = 44

        /**
         * 胶囊保守估值宽 dp（拖动夹取用）。app 内同名 `_kBarWGuess=240` 同思路：
         * **宁大不小**——夹取更紧只会偏左，绝不越出屏右把「■ 结束」裁掉。
         */
        const val BAR_W_GUESS_DP = 240

        const val PREFS = "lh_pill_pos"
        const val K_BAR_X = "bar_x"
        const val K_BAR_Y = "bar_y"
        const val K_FAB_Y = "fab_y"
        const val K_FAB_SIDE = "fab_side"
        const val K_FOLDED = "folded"

        /// 视图形态标记的 tag key（false=胶囊／true=圆圈），供 applyOverlay
        /// 判「形态是否与挂载视图一致」决定刷新还是重建。
        val R_TAG_FORM = "pill-form".hashCode()

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

        /// 圆圈面 m:ss→h:mm（52dp 圈面只保时与分，与 app 内 `pillFabFmt` 同口径）。
        fun fmtFab(sec: Int): String {
            val h = sec / 3600
            val m = (sec % 3600) / 60
            val s = sec % 60
            return if (h > 0) String.format(Locale.US, "%d:%02d", h, m)
            else String.format(Locale.US, "%d:%02d", m, s)
        }
    }
}
