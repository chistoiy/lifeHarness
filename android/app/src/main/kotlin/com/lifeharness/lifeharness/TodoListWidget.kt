package com.lifeharness.lifeharness

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * 2×2 待办清单小组件（批3· 产品令「待办显示最近一个或多个待办，可直接点击闭环」）。
 *
 * 结构＝标题 + **最多三行**（左圈＝勾掉这条／右文本＝看详情）+ 底部「还有 N 条」。
 * 行数据由 Dart 侧 `todoItems` 快照下发并**编码**（见 `LhWidget.readTodoRows`），
 * 本Provider 只解码 + 渲染 —— **读数链路仍是 C5 的快照单向下发**。
 *
 * 两处点击语义**刻意不同**（产品定案）：
 * - 左圈 → [LhWidget.toggleIntent] 广播 → `TodoActionReceiver` 写库（**不开 App**）；
 * - 行文本 → [LhWidget.clickIntent] 走 `lh://today`（C15 唯一出口）。
 *   桌面上不该从一行标题猜「这条详情在哪一页」，统一进今天页最不容易错。
 *
 * 三行是固定的三份布局（`lh_widget_todo.xml` 里 `lh_wg_t_1..3`）而非动态列表：
 * `RemoteViews` 不支持动态 child（`addView` 在部分 ROM 上静默失效），
 * 数量变化只通过 `setViewVisibility(GONE)` 表达。
 */
class TodoListWidget : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val views = RemoteViews(context.packageName, R.layout.lh_widget_todo)

        if (!LhWidget.isTodoListEnabled(context)) {
            renderDisabled(context, appWidgetManager, appWidgetIds, views)
            return
        }

        val has = LhWidget.hasSnapshot(widgetData)
        val rows = LhWidget.readTodoRows(widgetData)

        if (!has) {
            // B6：从未写过快照 ⇒ 不显示 0，也不显示假行；三行全藏，只留标题与提示。
            for (i in 1..LhWidget.TODO_ROWS) hideRow(views, i)
            views.setTextViewText(
                R.id.lh_wg_todo_more,
                context.getString(R.string.lh_widget_no_data),
            )
            views.setContentDescription(
                R.id.lh_wg_root,
                context.getString(R.string.lh_widget_no_data),
            )
        } else if (rows.isEmpty()) {
            // 空态：说「今天没有待办」而不是留三个空圈（空圈会被读成「有三条但都崩了」）。
            for (i in 1..LhWidget.TODO_ROWS) hideRow(views, i)
            views.setTextViewText(
                R.id.lh_wg_todo_more,
                context.getString(R.string.lh_widget_todo_empty),
            )
            views.setContentDescription(
                R.id.lh_wg_root,
                context.getString(R.string.lh_widget_todo_empty),
            )
        } else {
            for (i in 1..LhWidget.TODO_ROWS) {
                val row = rows.getOrNull(i - 1)
                if (row == null) {
                    hideRow(views, i)
                    continue
                }
                showRow(views, i)
                views.setTextViewText(titleIdOf(i), row.title)
                views.setImageViewResource(
                    chkIdOf(i),
                    if (row.done) R.drawable.ic_lh_wg_circle_on else R.drawable.ic_lh_wg_circle,
                )
                // 已完成的行禁勾圈点击（再点一次会把它改回未完成——桌面不该提供撤销，
                // 撤销走 App 内，语义清楚）。
                if (row.done) {
                    views.setOnClickPendingIntent(chkIdOf(i), doneRowIntent(context, row))
                } else {
                    views.setOnClickPendingIntent(
                        chkIdOf(i),
                        LhWidget.toggleIntent(context, row.id, REQ_CHK_BASE + i),
                    )
                }
                views.setOnClickPendingIntent(
                    titleIdOf(i),
                    LhWidget.clickIntent(context, LhWidget.SEG_TODAY, REQ_ROW_BASE + i),
                )
            }
            val more = LhWidget.readTodoMore(widgetData)
            views.setTextViewText(
                R.id.lh_wg_todo_more,
                if (more > 0) context.getString(R.string.lh_widget_todo_more, more) else "",
            )
            views.setContentDescription(
                R.id.lh_wg_root,
                context.getString(R.string.lh_widget_a11y_todo, rows.size),
            )
        }

        for (id in appWidgetIds) appWidgetManager.updateAppWidget(id, views)
    }

    /** 总开关关闭后的空态（与概览同款：宁可灰着也不留旧读数）。 */
    private fun renderDisabled(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        views: RemoteViews,
    ) {
        for (i in 1..LhWidget.TODO_ROWS) hideRow(views, i)
        views.setTextViewText(
            R.id.lh_wg_todo_more,
            context.getString(R.string.lh_widget_disabled),
        )
        views.setOnClickPendingIntent(
            R.id.lh_wg_root,
            LhWidget.clickIntent(context, LhWidget.SEG_TODAY, REQ_ROOT),
        )
        views.setContentDescription(R.id.lh_wg_root, context.getString(R.string.lh_widget_disabled))
        for (id in appWidgetIds) appWidgetManager.updateAppWidget(id, views)
    }

    /** 已完成行的点击＝去今天页看（禁静默改回未完成）。 */
    private fun doneRowIntent(context: Context, row: LhWidget.TodoRow) =
        LhWidget.clickIntent(context, LhWidget.SEG_TODAY, REQ_ROW_BASE + 100 + row.id % 100)

    private fun hideRow(views: RemoteViews, i: Int) {
        views.setViewVisibility(titleIdOf(i), View.GONE)
        views.setViewVisibility(chkIdOf(i), View.GONE)
    }

    private fun showRow(views: RemoteViews, i: Int) {
        views.setViewVisibility(titleIdOf(i), View.VISIBLE)
        views.setViewVisibility(chkIdOf(i), View.VISIBLE)
    }

    private fun titleIdOf(i: Int): Int = when (i) {
        1 -> R.id.lh_wg_t_1
        2 -> R.id.lh_wg_t_2
        else -> R.id.lh_wg_t_3
    }

    private fun chkIdOf(i: Int): Int = when (i) {
        1 -> R.id.lh_wg_chk_1
        2 -> R.id.lh_wg_chk_2
        else -> R.id.lh_wg_chk_3
    }

    private companion object {
        const val REQ_ROOT = 0x4C3001
        const val REQ_CHK_BASE = 0x4C3100
        const val REQ_ROW_BASE = 0x4C3200

        // ⚠ requestCode **不按实例编号**（只按行号）。这是有意的：
        // `PendingIntent` 的相等性忽略 extras，同一 requestCode + `FLAG_UPDATE_CURRENT`
        // 会让多个桌面实例共用同一个 Intent 对象。本卡的行数据来自**同一份快照**
        // ⇒ 所有实例显示的是同三条待办 ⇒ 共用 Intent 的目标 id 恒一致，不会误闭环
        // 另一条。反过来若按实例编号分散requestCode，实例被删除重建后会留下
        // 一批永远命中不到的 PendingIntent 槽位。
    }
}