package com.lifeharness.lifeharness

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * 4×1 快捷记录小组件（F2-2）。
 *
 * 左半「记一笔」；右半名称＋今日支出金额位（原型 `dt-widget`）。
 * **整个 widget 是单一点击区**（§4.4）→ 走动作表 `quick.ledger` → `lh://ledger/add`
 * → App 内 `/ledger/add`（**只预填，提交须 App 内确认** · C18）。
 *
 * ⚠ 本 widget 不做输入控件（C3/§2.5 明确不做：RemoteViews 禁输入）。
 * 读数**只读快照**（C5）。
 */
class QuickRecordWidget : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val views = RemoteViews(context.packageName, R.layout.lh_widget_quick)

        // 2026-10-15 8148 装机实锤修的「死开关」：设置页拨「快捷记录入口（4×1）」原本
        // 桌面毫无反应——本 Provider 压根没读那个偏好（同 TodayOverviewWidget）。
        if (!LhWidget.isQuickEnabled(context)) {
            renderDisabled(context, appWidgetManager, appWidgetIds, views)
            return
        }

        views.setTextViewText(R.id.lh_wg_amount, LhWidget.readAmount(widgetData, context))
        // B7：金额位已经在 Dart 侧按「隐藏金额」遮蔽，原生不再判一次（单一口径）。
        views.setContentDescription(
            R.id.lh_wg_root,
            context.getString(R.string.lh_widget_quick_name) + " · " +
                context.getString(R.string.lh_widget_label_today_cost) + " " +
                LhWidget.readAmount(widgetData, context),
        )

        val click = LhWidget.clickIntent(context, LhWidget.SEG_LEDGER_ADD, REQ_QUICK_ROOT)
        // 整块与左半按钮同一目标（§4.4：单一点击区）。
        views.setOnClickPendingIntent(R.id.lh_wg_root, click)
        views.setOnClickPendingIntent(R.id.lh_wg_btn, click)

        for (id in appWidgetIds) appWidgetManager.updateAppWidget(id, views)
    }

    /** 总开关关闭后的空态（与 2×2 同口径：不显示旧金额）。 */
    private fun renderDisabled(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        views: RemoteViews,
    ) {
        views.setTextViewText(R.id.lh_wg_amount, LhWidget.PLACEHOLDER)
        views.setContentDescription(
            R.id.lh_wg_root,
            context.getString(R.string.lh_widget_disabled),
        )
        val click = LhWidget.clickIntent(context, LhWidget.SEG_LEDGER_ADD, REQ_QUICK_ROOT)
        views.setOnClickPendingIntent(R.id.lh_wg_root, click)
        views.setOnClickPendingIntent(R.id.lh_wg_btn, click)
        for (id in appWidgetIds) appWidgetManager.updateAppWidget(id, views)
    }

    private companion object {
        const val REQ_QUICK_ROOT = 0x4C1002
    }
}
