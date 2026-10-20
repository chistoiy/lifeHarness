package com.lifeharness.lifeharness

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * 2×2 记账概览小组件（批3 · 产品令「记账还行，但可以再搞个 2×2 的」）。
 *
 * 三行读数＝今日支出 / 本月支出 / 本月结余（产品定案的口径与顺序，逐字实现）。
 *
 * **隐私**：金额位全部由 Dart 侧算好（`widgetAmountCell` / `widgetBalanceCell`，
 * 开启「隐藏金额」时就是 `••••`），本Provider **不再判一次**——B7 的口径只有一处，
 * 免得 Dart 遮了、原生又「聪明地」把 `¥` 加回去。
 * 唯一例外是 [LhWidget.readAmount] 里的总开关兜底（快照是隐藏开关打开**之前**
 * 写下的情形）。
 */
class LedgerOverviewWidget : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val views = RemoteViews(context.packageName, R.layout.lh_widget_ledger)

        if (!LhWidget.isLedgerEnabled(context)) {
            renderDisabled(context, appWidgetManager, appWidgetIds, views)
            return
        }

        val has = LhWidget.hasSnapshot(widgetData)
        if (!has) {
            views.setTextViewText(R.id.lh_wg_today, LhWidget.PLACEHOLDER)
            views.setTextViewText(R.id.lh_wg_month, LhWidget.PLACEHOLDER)
            views.setTextViewText(R.id.lh_wg_balance, LhWidget.PLACEHOLDER)
            views.setTextViewText(
                R.id.lh_wg_hint,
                context.getString(R.string.lh_widget_no_data),
            )
            views.setContentDescription(
                R.id.lh_wg_root,
                context.getString(R.string.lh_widget_no_data),
            )
        } else {
            views.setTextViewText(R.id.lh_wg_today, LhWidget.readAmount(widgetData, context))
            views.setTextViewText(
                R.id.lh_wg_month,
                LhWidget.readMonthAmount(widgetData, context),
            )
            views.setTextViewText(
                R.id.lh_wg_balance,
                LhWidget.readBalance(widgetData, context),
            )
            views.setTextViewText(
                R.id.lh_wg_hint,
                context.getString(R.string.lh_widget_ledger_hint),
            )
            views.setContentDescription(
                R.id.lh_wg_root,
                context.getString(
                    R.string.lh_widget_a11y_ledger,
                    LhWidget.readAmount(widgetData, context),
                    LhWidget.readMonthAmount(widgetData, context),
                    LhWidget.readBalance(widgetData, context),
                ),
            )
        }

        // 整卡点击＝去记账（动作表 `writePrefill.ledger` → lh://ledger/add）。
        // 三行读数**逐行可点吗**：不做——记账只有「记一笔」一个动作，逐行点没有
        // 对应语义，给了反而是坏 affordance（点了却不知道会发生什么）。
        views.setOnClickPendingIntent(
            R.id.lh_wg_root,
            LhWidget.clickIntent(context, LhWidget.SEG_LEDGER_ADD, REQ_ROOT),
        )

        for (id in appWidgetIds) appWidgetManager.updateAppWidget(id, views)
    }

    /** 总开关关闭后的空态。 */
    private fun renderDisabled(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        views: RemoteViews,
    ) {
        views.setTextViewText(R.id.lh_wg_today, LhWidget.PLACEHOLDER)
        views.setTextViewText(R.id.lh_wg_month, LhWidget.PLACEHOLDER)
        views.setTextViewText(R.id.lh_wg_balance, LhWidget.PLACEHOLDER)
        views.setTextViewText(
            R.id.lh_wg_hint,
            context.getString(R.string.lh_widget_disabled),
        )
        views.setOnClickPendingIntent(
            R.id.lh_wg_root,
            LhWidget.clickIntent(context, LhWidget.SEG_LEDGER_ADD, REQ_ROOT),
        )
        views.setContentDescription(R.id.lh_wg_root, context.getString(R.string.lh_widget_disabled))
        for (id in appWidgetIds) appWidgetManager.updateAppWidget(id, views)
    }

    private companion object {
        const val REQ_ROOT = 0x4C4001
    }
}