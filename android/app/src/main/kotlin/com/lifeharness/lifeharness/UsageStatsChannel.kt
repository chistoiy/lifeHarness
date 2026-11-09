package com.lifeharness.lifeharness

import android.app.Activity
import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Process
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * C06 自动时间采集（2026-11-09）：`UsageStatsManager` 前台应用分段只读通道。
 *
 * 口径：
 * - 通道 `lh/usagestats`，只做**读**与**跳设置页**；不写库、不做建议块判定
 *   （聚合/跨天切分/入待确认队列全在 Dart 侧，纯函数可测）。
 * - `PACKAGE_USAGE_STATS` 是「使用情况访问」**特殊权限**，不是运行时弹窗：
 *   系统设置里授予后 `AppOps` 才放行；未授予时 `querySegments` 回
 *   `granted=false`＋空分段＋明确文案，**不抛异常、不重试**（拒权优雅降级）。
 * - 跨天不在原生切：这里只回原始 `[startMs, endMs)` 分段，按日切分在 Dart。
 * - 本 App 自己的前台段直接跳过（采集器自身不是「应用使用」建议）。
 */
object UsageStatsChannel {

    const val CHANNEL = "lh/usagestats"

    private const val TAG = "LH-USAGE"

    /** `UsageEvents.Event.ACTIVITY_RESUMED` 与旧 `MOVE_TO_FOREGROUND` 同为 1。 */
    private const val EVENT_RESUMED = 1

    /** `UsageEvents.Event.ACTIVITY_PAUSED` 与旧 `MOVE_TO_BACKGROUND` 同为 2。 */
    private const val EVENT_PAUSED = 2

    private const val NO_PERMISSION =
        "未授予「使用情况访问」权限：请到 系统设置 › 特殊应用权限 › 使用情况访问 打开本应用，再回来重试"

    fun wire(activity: Activity, engine: FlutterEngine) {
        MethodChannel(
            engine.dartExecutor.binaryMessenger, CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasPermission" -> result.success(hasPermission(activity))
                "openSettings" -> result.success(openSettings(activity))
                "querySegments" -> handleQuery(call, activity, result)
                else -> result.notImplemented()
            }
        }
    }

    /**
     * 是否已授予「使用情况访问」。
     *
     * 为什么不用 `checkSelfPermission`：该权限的常规判定走 AppOps（`MODE_DEFAULT`
     * 时才回落到权限声明判定），只查权限位在多数 ROM 上恒为 DENIED。
     */
    fun hasPermission(activity: Activity): Boolean {
        val ops = activity.getSystemService(Context.APP_OPS_SERVICE) as? AppOpsManager
            ?: return false
        @Suppress("DEPRECATION")
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ops.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                activity.packageName,
            )
        } else {
            ops.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                activity.packageName,
            )
        }
        if (mode == AppOpsManager.MODE_ALLOWED) return true
        if (mode == AppOpsManager.MODE_DEFAULT) {
            return activity.checkSelfPermission(
                android.Manifest.permission.PACKAGE_USAGE_STATS
            ) == PackageManager.PERMISSION_GRANTED
        }
        return false
    }

    /** 跳系统「使用情况访问」页；部分 ROM 需不带包名的通用页，均失败则静默 false。 */
    private fun openSettings(activity: Activity): Boolean {
        val withPackage = Intent(
            Settings.ACTION_USAGE_ACCESS_SETTINGS,
            Uri.parse("package:${activity.packageName}"),
        )
        return try {
            activity.startActivity(withPackage)
            true
        } catch (_: Exception) {
            try {
                activity.startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                true
            } catch (e2: Exception) {
                Log.w(TAG, "无使用情况访问设置页：${e2.javaClass.simpleName}")
                false
            }
        }
    }

    private fun handleQuery(
        call: MethodCall,
        activity: Activity,
        result: MethodChannel.Result,
    ) {
        val fromMs = (call.argument<Number>("fromMs"))?.toLong() ?: 0L
        val toMs = (call.argument<Number>("toMs"))?.toLong() ?: 0L
        if (fromMs <= 0L || toMs <= fromMs) {
            result.success(emptyPayload("时间范围无效：结束时刻必须晚于开始时刻"))
            return
        }
        if (!hasPermission(activity)) {
            // 拒权降级：空分段＋去授予文案，绝不抛错（Dart 侧照常收口）。
            result.success(emptyPayload(NO_PERMISSION))
            return
        }
        try {
            result.success(
                mapOf(
                    "granted" to true,
                    "message" to "",
                    "segments" to querySegments(activity, fromMs, toMs),
                )
            )
        } catch (e: Exception) {
            Log.w(TAG, "querySegments 失败：${e.javaClass.simpleName}")
            // 首参必须是非空 String（可空串/属性式写法是历史实锤坑）。
            result.error(
                "usage_query_failed",
                e.message ?: e.javaClass.simpleName,
                null,
            )
        }
    }

    /**
     * 把 `UsageEvents` 折成前台分段：RESUMED 开段、同包 PAUSED 收段，
     * 末尾未收口的段截到 [toMs]。相邻同包段**不在这里合并**（Dart 侧按阈值做）。
     */
    private fun querySegments(
        activity: Activity,
        fromMs: Long,
        toMs: Long,
    ): List<Map<String, Any?>> {
        val usm = activity.getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager
            ?: return emptyList()
        val events = usm.queryEvents(fromMs, toMs) ?: return emptyList()
        val pm = activity.packageManager
        val labels = HashMap<String, String>()
        val out = ArrayList<Map<String, Any?>>()
        val event = UsageEvents.Event()
        var currentPkg: String? = null
        var currentStart = 0L

        fun closeAt(endMs: Long) {
            val pkg = currentPkg ?: return
            val end = minOf(endMs, toMs)
            if (end > currentStart) {
                out.add(segmentOf(pkg, currentStart, end, pm, labels))
            }
            currentPkg = null
        }

        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            val ts = event.timeStamp
            when (event.eventType) {
                EVENT_RESUMED -> {
                    closeAt(ts)
                    val pkg = event.packageName
                    // 空包名/本 App 自身：不参与建议（也不开新段）。
                    if (!pkg.isNullOrEmpty() && pkg != activity.packageName) {
                        currentPkg = pkg
                        currentStart = maxOf(ts, fromMs)
                    }
                }
                EVENT_PAUSED -> {
                    if (currentPkg != null && currentPkg == event.packageName) {
                        closeAt(ts)
                    }
                }
            }
        }
        closeAt(toMs)
        return out
    }

    private fun segmentOf(
        pkg: String,
        startMs: Long,
        endMs: Long,
        pm: PackageManager,
        labels: MutableMap<String, String>,
    ): Map<String, Any?> {
        val label = labels.getOrPut(pkg) { labelOf(pm, pkg) }
        return mapOf(
            "package" to pkg,
            "label" to label,
            "startMs" to startMs,
            "endMs" to endMs,
        )
    }

    @Suppress("DEPRECATION")
    private fun labelOf(pm: PackageManager, pkg: String): String = try {
        pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
    } catch (_: Exception) {
        // 已卸载/不可见包：用包名兜底，不因单个包中断整段采集。
        pkg
    }

    private fun emptyPayload(message: String): Map<String, Any?> = mapOf(
        "granted" to false,
        "message" to message,
        "segments" to emptyList<Map<String, Any?>>(),
    )
}
