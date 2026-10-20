package com.lifeharness.lifeharness

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * 4×1 快捷记录小组件（F2-2）。
 *
 * 2026-10-18 三区改版（产品令·原型 `52d79315` 已过门）：记一笔｜今日支出｜
 * 本月结余 三区并列——原「左按钮＋右金额」两区占整行、信息密度低。
 *
 * **整块是单一点击区**（§4.4）→ 起 `QuickAddActivity`（对话框主题·不开 App·
 * 不进最近任务·工单 §7.1）。意图仍走 [LhWidget.quickAddIntent] 唯一出口（C15），
 * 禁在本类里自己拼 Intent。
 *
 * ⚠ 本 widget 不做输入控件（C3/§2.5 不变：RemoteViews 禁输入）——输入发生在
 * 那个对话框 Activity 里的 Flutter 表单，不在 widget 自身。
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
        // 三区改版：本月结余（符号口径由 readBalance 处理：负数显示 `-¥1,286`）。
        views.setTextViewText(R.id.lh_wg_balance, LhWidget.readBalance(widgetData, context))
        // B7：金额位已经在 Dart 侧按「隐藏金额」遮蔽，原生不再判一次（单一口径）。
        views.setContentDescription(
            R.id.lh_wg_root,
            context.getString(R.string.lh_widget_quick_name) + " · " +
                context.getString(R.string.lh_widget_label_today_cost) + " " +
                LhWidget.readAmount(widgetData, context),
        )

        // 2026-10-18 拍板 A 路：点击＝弹窗记账，**不再**走 `lh://ledger/add`
        // 起 App（那正是产品要去掉的「打开 App」）。
        val click = LhWidget.quickAddIntent(context, REQ_QUICK_ROOT)
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
        views.setTextViewText(R.id.lh_wg_balance, LhWidget.PLACEHOLDER)
        views.setContentDescription(
            R.id.lh_wg_root,
            context.getString(R.string.lh_widget_disabled),
        )
        val click = LhWidget.quickAddIntent(context, REQ_QUICK_ROOT)
        views.setOnClickPendingIntent(R.id.lh_wg_root, click)
        views.setOnClickPendingIntent(R.id.lh_wg_btn, click)
        for (id in appWidgetIds) appWidgetManager.updateAppWidget(id, views)
    }

    private companion object {
        const val REQ_QUICK_ROOT = 0x4C1002
    }
}
