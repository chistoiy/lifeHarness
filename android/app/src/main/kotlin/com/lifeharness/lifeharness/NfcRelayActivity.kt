package com.lifeharness.lifeharness

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.util.Log
import io.flutter.plugin.common.MethodChannel

/**
 * NFC 贴卡**透明中转界面**（批3c · 2026-10-17）。
 *
 * 为什么需要它：NDEF 过滤器原先挂在 [MainActivity] 上，系统一贴卡就把**主界面**拉到
 * 前台（真机 logcat 实证 `Displayed +261ms`），用户看到「闪一下 App 页面」。对照同类
 * App（时间日志 `me.liujia95.solitude`）的做法——把过滤器挂在**专用透明界面**上，
 * 处理完立刻结束，主界面全程不启动。本类照此实现，标签内容**不需要重写**。
 *
 * 两条分支：
 * · **引擎活着**（App 进程还在后台）⇒ 把 `nfc:<cardId>` 经 `lh/nfc` 通道直接推给
 *   Dart，界面全程不出现，业务在后台完成（零闪现）；
 * · **引擎不活**（进程被杀）⇒ 把原始 NDEF intent 交给 [MainActivity] 走既有冷启动
 *   路径（冷启动首帧本来就慢，用户感知不到闪）。
 *
 * 红线：本类**不解释任何 NFC 业务**（与 [MainActivity.enqueueLaunch] 同口径）——
 * 只解析出 cardId 原样投递，总闸/去抖/查表/执行全在 Dart 侧。
 */
class NfcRelayActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        relay(intent)
    }

    override fun onNewIntent(intent: Intent?) {
        super.onNewIntent(intent)
        relay(intent)
    }

    private fun relay(intent: Intent?) {
        val data = intent?.data
        // 只接本 App 的贴卡地址（`lh://nfc/<cardId>`）；其余一律静默结束。
        // 日志只记 scheme/host（cardId 在 path 里·C11 红线不记）。
        if (data == null || data.scheme != MainActivity.LH_SCHEME) {
            Log.d("LH-NFC", "relay: 非本 App 地址，忽略")
            finishNow()
            return
        }
        val cardId = if (data.host == "nfc") {
            data.pathSegments?.firstOrNull().orEmpty()
        } else {
            ""
        }
        if (cardId.isEmpty()) {
            Log.d("LH-NFC", "relay: scheme/host 不合形态，忽略")
            finishNow()
            return
        }

        val engine = MainActivity.engineRef
        if (engine != null) {
            // 引擎活着 ⇒ 直投 Dart。界面不出现，业务在后台跑（零闪现）。
            MethodChannel(engine.dartExecutor.binaryMessenger, MainActivity.NFC_CHANNEL)
                .invokeMethod(
                    "dispatch",
                    mapOf("action" to "nfc:$cardId", "fromBackground" to true),
                )
            Log.d("LH-NFC", "relay → dart：已投递（引擎活着）")
        } else {
            // 进程刚起来：交给主界面走既有冷启动路径（handle → enqueueLaunch）。
            startActivity(
                Intent(this, MainActivity::class.java).apply {
                    action = intent?.action
                    this.data = data
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                }
            )
            Log.d("LH-NFC", "relay → main：冷启动转交")
        }
        finishNow()
    }

    /** 结束本界面且不留转场动画（用户不该看到任何窗口变化）。 */
    private fun finishNow() {
        finish()
        @Suppress("DEPRECATION")
        overridePendingTransition(0, 0)
    }
}
