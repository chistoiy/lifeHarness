package com.lifeharness.lifeharness

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import java.io.File

/**
 * 待办 2×2 · 行内勾圈的**闭环执行器**（批3 · 产品令「点勾圈直接闭环」）。
 *
 * ## 为什么允许它碰 sqlite（C5 的窄例外，务必知悉）
 *
 *冻结档 C5 原文是「**读数**只读 SharedPreferences 快照，禁 widget 进程直读 sqlite」。
 *本 Receiver **不产生任何读数**——它只执行一次写入（`UPDATE todos SET done=1`），
 *写完立刻触发重绘、读数仍由 Dart 侧快照下发。所以这条不违反 C5 的**意图**
 *（读数单一真源不受影响），属于「写入类」而非「读数类」。
 *
 * ⚠ 若将来有人想在这里**读**待办、或做聚合统计 ⇒ 立刻越了C5，必须改回广播给 App。
 * 守护`test/desktop_widget_test.dart` 会钉住这条：禁出现 `SELECT`。
 *
 * ## 写库失败怎么办
 *
 * 桌面点击**不能弹 Toast**（Receiver 无 UI 上下文，且崩溃会拖垮宿主）。所以失败时
 * 把 id 追加进 `desktop.widget_pending_toggles` 队列，App 下次启动排空补写
 * （见 `lib/app.dart` 的 `drainPendingWidgetToggles`）——**闭环最终一致**。
 */
class TodoActionReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_TOGGLE) return
        val id = intent.getIntExtra(EXTRA_TODO_ID, -1)
        if (id <= 0) return
        // goAsync：写库是同步 IO，广播线程 10s 超时；不 hold 住会被系统判 ANR。
        val pending = goAsync()
        val app = context.applicationContext
        Thread {
            try {
                markDone(app, id)
            } catch (_: Exception) {
                enqueuePending(app, id)
            } catch (_: LinkageError) {
                enqueuePending(app, id)
            } finally {
                // 重绘与入队都做完再交还广播（顺序不能反：入队失败也不能丢闭环意图）。
                try {
                    LhWidget.notifyWidgets(app)
                } catch (_: Exception) {
                    // catch-ok: 重绘失败不致命，下一次快照下发会纠正。
                }
                pending.finish()
            }
        }.start()
    }

    /**
     * 把一条待办标记为完成。
     *
     * 库文件路径＝`context.getDatabasePath(DB_NAME)`（Android app 私有目录，Dart 侧
     * `getDatabasesPath()` 指向同一处，见 `DbSchema.fileName`）。
     *
     * ⚠ 只写 `done`/`updated_at` 两列、**不碰 `deleted_at`/`dropped`**——闭环是
     * 「做完」，不是「删除」；`sort_order` 等列一律不碰，免得与 App 侧排序冲突。
     */
    private fun markDone(context: Context, id: Int) {
        val db = openDb(context)
        try {
            db.execSQL(
                "UPDATE todos SET done = 1, updated_at = ? WHERE id = ? AND done = 0",
                arrayOf<Any>(System.currentTimeMillis(), id),
            )
        } finally {
            db.close()
        }
    }

    /**
     * 打开库文件（**只读写这一个文件**，不做任何查询）。
     *
     * ⚠ 用 `SQLiteDatabase.openDatabase` 而非 sqflite：Dart 侧的连接可能未开
     * （App 没起过），这里要能独立写。`OPEN_READWRITE` 不带 `CREATE` ⇒ 库不存在时
     * 直接抛，由上层入队兜底（**绝不凭空建库**——那会造出一个空壳把真库盖掉风险）。
     */
    private fun openDb(context: Context): SQLiteDatabase {
        val f = File(context.getDatabasePath(DB_NAME).absolutePath)
        if (!f.exists()) throw IllegalStateException("库不存在：${f.absolutePath}")
        return SQLiteDatabase.openDatabase(
            f.absolutePath,
            null,
            SQLiteDatabase.OPEN_READWRITE,
        )
    }

    /** 写库失败 ⇒ 记住这个 id，等 App 起来补写（闭环不能丢）。 */
    private fun enqueuePending(context: Context, id: Int) {
        try {
            val p = LhWidget.prefs(context)
            val cur = p.getString(LhWidget.PREF_PENDING_TOGGLES, "") ?: ""
            val ids = cur.split(',').mapNotNull { it.trim().toIntOrNull() }.toMutableSet()
            if (ids.add(id)) {
                p.edit().putString(LhWidget.PREF_PENDING_TOGGLES, ids.joinToString(",")).apply()
            }
        } catch (_: Exception) {
            // catch-ok: 连偏好都写不了（极端情况）只能放弃本次闭环，不崩宿主。
        }
    }

    companion object {
        const val ACTION_TOGGLE = "com.lifeharness.lifeharness.WIDGET_TODO_TOGGLE"
        const val EXTRA_TODO_ID = "todo_id"

        /** 库文件名，与 Dart `DbSchema.fileName` 逐字一致（守护测试交叉核对）。 */
        const val DB_NAME = "lifeharness.db"
    }
}