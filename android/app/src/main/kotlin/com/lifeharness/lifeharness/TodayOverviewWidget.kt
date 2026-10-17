package com.lifeharness.lifeharness

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * 2×2 今日概览小组件（F2-1）。
 *
 * 展示今日待办数 / 习惯打卡进度（原型 prototype/index-desktop.html 屏 `dt-widget`）；
 * 点击进 `/` 今天页（动作表 `nav.today` → `lh://today`）；无快照显示占位（B6）。
 *
 * 读数**只读快照**（C5），由 Dart 侧 `pushDesktopWidgetSnapshot` 下发；
 * 系统调频导致的延迟不视为缺陷（C4）。
 */
class TodayOverviewWidget : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val views = RemoteViews(context.packageName, R.layout.lh_widget_overview)
        val has = LhWidget.hasSnapshot(widgetData)

        // 2026-10-15 8148 装机实锤修的「死开关」：设置页拨「今日概览读数（2×2）」原本
        // 桌面毫无反应——因为本 Provider 压根没读那个偏好。现读它，关闭时渲染「已停用」
        // 空态（正常路径由 `LhWidget.applyEnabledFlags` 直接把实例从桌面删掉；
        // 这里是**双保险**：万一实例还在（如宿主未回调删除），也不继续显示旧读数）。
        if (!LhWidget.isOverviewEnabled(context)) {
            renderDisabled(context, appWidgetManager, appWidgetIds, views)
            return
        }

        if (!has) {
            // B6：从未写过快照（首装/清数据）⇒ 读数位占位，提示打开应用同步。
            views.setTextViewText(R.id.lh_wg_todo, LhWidget.PLACEHOLDER)
            views.setTextViewText(R.id.lh_wg_habit, LhWidget.PLACEHOLDER)
            views.setTextViewText(R.id.lh_wg_habit_total, "")
            views.setTextViewText(R.id.lh_wg_hint, context.getString(R.string.lh_widget_no_data))
            views.setProgressBar(R.id.lh_wg_bar, 1, 0, false)
            views.setContentDescription(
                R.id.lh_wg_root,
                context.getString(R.string.lh_widget_no_data),
            )
        } else {
            val todo = LhWidget.readCell(widgetData, LhWidget.KEY_TODO)
            val total = LhWidget.readCell(widgetData, LhWidget.KEY_HABIT_TOTAL).toIntOrNull() ?: 0
            val done = LhWidget.readCell(widgetData, LhWidget.KEY_HABIT_DONE).toIntOrNull() ?: 0

            views.setTextViewText(R.id.lh_wg_todo, todo)
            views.setTextViewText(R.id.lh_wg_habit, "$done")
            views.setTextViewText(R.id.lh_wg_habit_total, "/$total")
            views.setTextViewText(R.id.lh_wg_hint, hintOf(context, total, done))
            views.setProgressBar(
                R.id.lh_wg_bar,
                if (total <= 0) 1 else total,
                done.coerceIn(0, if (total <= 0) 0 else total),
                false,
            )
            views.setContentDescription(
                R.id.lh_wg_root,
                context.getString(
                    R.string.lh_widget_a11y_overview,
                    todo.toIntOrNull() ?: 0,
                    done,
                    total,
                ),
            )
        }

        val click = LhWidget.clickIntent(context, LhWidget.SEG_TODAY, REQ_OVERVIEW_ROOT)
        views.setOnClickPendingIntent(R.id.lh_wg_root, click)

        for (id in appWidgetIds) appWidgetManager.updateAppWidget(id, views)
    }

    /** 底部一行提示（与原型同口径：还差 N 项就全勤）。 */
    private fun hintOf(context: Context, total: Int, done: Int): String = when {
        total <= 0 -> context.getString(R.string.lh_widget_hint_none)
        done >= total -> context.getString(R.string.lh_widget_hint_all)
        else -> context.getString(R.string.lh_widget_hint_left, total - done)
    }

    /** 总开关关闭后的空态（不显示旧读数，避免「关了却还显示」的另一种死开关形态）。 */
    private fun renderDisabled(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        views: RemoteViews,
    ) {
        views.setTextViewText(R.id.lh_wg_todo, LhWidget.PLACEHOLDER)
        views.setTextViewText(R.id.lh_wg_habit, LhWidget.PLACEHOLDER)
        views.setTextViewText(R.id.lh_wg_habit_total, "")
        views.setTextViewText(R.id.lh_wg_hint, context.getString(R.string.lh_widget_disabled))
        views.setProgressBar(R.id.lh_wg_bar, 1, 0, false)
        views.setOnClickPendingIntent(
            R.id.lh_wg_root,
            LhWidget.clickIntent(context, LhWidget.SEG_TODAY, REQ_OVERVIEW_ROOT),
        )
        views.setContentDescription(R.id.lh_wg_root, context.getString(R.string.lh_widget_disabled))
        for (id in appWidgetIds) appWidgetManager.updateAppWidget(id, views)
    }

    private companion object {
        const val REQ_OVERVIEW_ROOT = 0x4C1001
    }
}
