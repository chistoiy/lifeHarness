package com.lifeharness.lifeharness

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/**
 * 打卡-单习惯 2×2 主按钮的**闭环执行器**（批A 交互闭环层·评估件 §4.1/§4.2）。
 *
 * ## 为什么不像待办勾圈那样原生直写（C5 窄例外不复刻）
 *
 * `TodoActionReceiver` 能直写 sqlite，是因为「勾一下待办」是单列 UPDATE。
 * 习惯打卡**不是**：写一日流水（未来日时钟防护、同日改值不新增、唯一键冲突
 * 先清再插、组习惯子项行先删后插）＋**全量重算连击/最佳并回写缓存列**＋流水
 * 留痕。在原生里复刻＝行为分叉（评估件 §4.1 硬事实）⇒ 本 Receiver 自己
 * **一行 sqlite 都不碰**，只负责起一个**无头 Flutter 引擎**，让 Dart 侧走
 * 与 App 内/NFC 贴卡同一个仓库出口（`habitCheckinWrite`·isolate 内跑）。
 *
 * ## 三态回显口径（评估件 §4.2）
 *
 *  · 点击瞬间：[HabitCheckWidget.echoChecked] 先画「已打卡」（乐观回显，
 *    盖住 isolate 冷启动的几百 ms~1s+ 延迟；连击数暂用旧值）；
 *  · Dart 回执 ok：Dart 已把习惯三键推回快照并重绘 ⇒ **收敛**到真值；
 *  · Dart 回执 error／整链炸／超时：**回滚**显示态（按快照重绘）并把习惯名
 *    入待排空队列（[LhWidget.enqueuePendingCheck]），App 启动排空补写——
 *    闭环最终一致。⚠ 超时只入队**不回滚**：那一刻 Dart 可能还在写（写了会
 *    自推快照自我纠正），而打卡是幂等写，重复入队无副作用。
 *
 * ## 线程模型（⚠ 2026-10-18 实证：引擎初始化只能在主线程）
 *
 * `FlutterLoader.ensureInitializationComplete` 带 Looper 检查（非主线程直接
 * 抛 IllegalStateException）。故拆两段：
 *  · **onReceive（主线程）**：乐观回显 → 建引擎 → 投 `habitCheckin` 调用 →
 *    执行 Dart 入口点（isolate 异步起，不卡广播）；
 *  · **worker 单线程**：等回执（[CHECKIN_TIMEOUT_MS] 上限）→ 按结果收摊 →
 *    销毁引擎 → `pending.finish()`。
 * 多次点击在 worker 上**串行**（一枚一枚办，避免并发双引擎）；回显各自即时。
 */
class HabitCheckReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_CHECK) return
        val app = context.applicationContext
        val widgetId = intent.getIntExtra(EXTRA_WIDGET_ID, 0)
        val name = intent.getStringExtra(EXTRA_HABIT_NAME)?.trim()
        if (widgetId <= 0 || name.isNullOrEmpty()) return
        // ① 乐观回显（主线程毫秒级；写库结果未定也先给确定感）。
        // provider 无状态，渲染不吃字段 ⇒ 借个实例调即可。
        HabitCheckWidget().echoChecked(app, widgetId, name)
        // ② 主线程建引擎＋发调用＋起 Dart（goAsync：后面还有异步等待）。
        val pending = goAsync()
        val call = try {
            startCall(app, name)
        } catch (e: Exception) {
            // 引擎都起不来（极端：资源占满/ROM 限制）：回滚＋入队，App 启动补写。
            LhWidget.enqueuePendingCheck(app, name)
            rollback(app, widgetId)
            try {
                pending.finish()
            } catch (_: Exception) {
            }
            return
        }
        // ③ worker 等回执收摊（不占广播主线程）。
        worker {
            try {
                awaitOutcome(app, call, widgetId, name)
            } finally {
                try {
                    pending.finish()
                } catch (_: Exception) {
                }
            }
        }
    }

    /** 一次待等的后台调用（引擎＋回执闸门）。 */
    private class PendingCall(
        val engine: FlutterEngine,
        val latch: CountDownLatch,
        val outcome: AtomicReference<String>,
    )

    companion object {
        const val ACTION_CHECK = "com.lifeharness.lifeharness.WIDGET_HABIT_CHECK"
        const val EXTRA_WIDGET_ID = "widget_id"
        const val EXTRA_HABIT_NAME = "habit_name"

        /** 后台 isolate 通道名（Dart `kWidgetBgChannel` 逐字一致·守护测试交叉核对）。 */
        private const val CHANNEL = "lh/widget_bg"

        /** 后台 isolate 方法名（Dart `kWidgetBgCheckin` 逐字一致）。 */
        private const val CHECKIN = "habitCheckin"

        /**
         * Dart 入口点函数名（Dart `widgetBackgroundMain` 逐字一致）。
         *
         * ⚠ 名字写错＝引擎起不来但**不报错**（原生只见到回执超时），是
         * 「点了有回显、但永远不收敛」的静默故障——守护测试钉两侧同值。
         */
        private const val ENTRYPOINT = "widgetBackgroundMain"

        /** 等回执的上限（release 冷启动经验值 1~3s；留足余量又不拖爆广播 10s 窗）。 */
        private const val CHECKIN_TIMEOUT_MS = 8000L

        /** 回执结果内部态（不是 Dart 的返回值原样，只表达成败）。 */
        private const val RESULT_OK = "ok"

        /** 单线程串行执行器（多次点击排队办；回显各自已在主线程画过）。 */
        private val EXEC = Executors.newSingleThreadExecutor()

        private fun worker(block: () -> Unit) {
            EXEC.execute(block)
        }

        /**
         * 建无头引擎并投打卡调用（**必须在主线程调用**——loader 初始化带 Looper 检查）。
         *
         * `invokeMethod` 先于 `executeDartEntrypoint` 无妨：消息在原生侧排队，
         * isolate 起来、handler 挂上后照样送达（与冷启动插件通道同机制）。
         */
        private fun startCall(app: Context, name: String): PendingCall {
            val engine = FlutterEngine(app)
            val latch = CountDownLatch(1)
            val outcome = AtomicReference("pending")
            val result = object : MethodChannel.Result {
                override fun success(result: Any?) {
                    outcome.set(RESULT_OK)
                    latch.countDown()
                }

                override fun error(
                    errorCode: String,
                    errorMessage: String?,
                    errorDetails: Any?,
                ) {
                    outcome.set("error")
                    latch.countDown()
                }

                override fun notImplemented() {
                    outcome.set("noimpl")
                    latch.countDown()
                }
            }
            MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
                .invokeMethod(CHECKIN, mapOf("habit" to name), result)
            engine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint(
                    FlutterInjector.instance().flutterLoader().findAppBundlePath(),
                    ENTRYPOINT,
                ),
            )
            return PendingCall(engine, latch, outcome)
        }

        /**
         * 等 Dart 回执并按结果收摊（worker 线程）。
         *
         * ok ⇒ Dart 已自推快照收敛，什么都不做；
         * error/noimpl/超时 ⇒ 入队（＋ 明确失败类回滚显示态）；
         * 引擎无论成败都销毁（后台 isolate 办事完即退·B8 功耗口径）。
         */
        private fun awaitOutcome(
            app: Context,
            call: PendingCall,
            widgetId: Int,
            name: String,
        ) {
            try {
                val replied = call.latch.await(CHECKIN_TIMEOUT_MS, TimeUnit.MILLISECONDS)
                if (!replied) {
                    // 超时：Dart 可能还在写（幂等；写了会自推快照）。并入队兜底，
                    // 不回滚——写成功的那一半让快照自己纠正显示。
                    LhWidget.enqueuePendingCheck(app, name)
                    return
                }
                if (call.outcome.get() != RESULT_OK) {
                    // 明确失败：回滚显示态（按快照重绘）＋入队，App 启动补写。
                    LhWidget.enqueuePendingCheck(app, name)
                    rollback(app, widgetId)
                }
                // RESULT_OK：Dart 已推习惯三键＋重绘 ⇒ 已收敛，无需动作。
            } catch (_: Exception) {
                LhWidget.enqueuePendingCheck(app, name)
                rollback(app, widgetId)
            } finally {
                try {
                    call.engine.destroy()
                } catch (_: Exception) {
                    // catch-ok: 销毁失败不致命（进程级兜底由系统回收）。
                }
            }
        }

        private fun rollback(app: Context, widgetId: Int) {
            try {
                LhWidget.notifyWidget(app, HabitCheckWidget::class.java, intArrayOf(widgetId))
            } catch (_: Exception) {
                // catch-ok: 重绘失败不致命，下次快照下发会纠正。
            }
        }
    }
}
