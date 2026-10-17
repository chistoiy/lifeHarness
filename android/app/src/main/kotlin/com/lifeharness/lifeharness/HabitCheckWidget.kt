package com.lifeharness.lifeharness

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import androidx.core.content.ContextCompat
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * 2×2 打卡-单习惯小组件（批A · 渲染层）。
 *
 * 规格＝`docs/handoff/小组件模块-批A按实例绑定与打卡试点.md` §2 渲染层＋
 * `docs/handoff/评估结论-20261017-…评估.md` §2.2/§5.3；形态＝原型 `#dt-widget`
 * 「打卡-单习惯 双态」四件套（标题／习惯名／状态行／主按钮）。
 *
 * **按实例绑定**（与四枚读数型最大的不同）：每枚实例自己绑一个习惯——绑定值存在
 * `FlutterSharedPreferences` 的 `flutter.desktop.widget_bind.<appWidgetId>`
 * （无则回落 `…widget_bind.default`·R2），`sub` 段就是**习惯名**。
 *
 * **读数仍是快照单向下发（C5）**：习惯状态表由 Dart 侧 `encodeWidgetHabitItems`
 * 编码成 `habit_items`，本 Provider 只 `split` 查自己那一行——**禁直读 sqlite**
 * （widget 进程越轻越好·C4）。
 *
 * **失效三态**（产品 2026-10-17 勾定文案）：无快照「等待数据」／无绑定
 * 「未选择内容，点此设置」／源失效「内容已失效，点此重新选择」。三态共用同一个
 * `lh_wg_ph` 占位控件，只换文案——**不另画三套布局**（一维结构最不容易错位）。
 *
 * ⚠ 点击去向（本刀＝过渡态）：
 *  · 未打卡 → `lh://habit/check`（起 App 习惯页）；
 *  · 三态占位 → 同段（起 App 让用户去选/去核对）。
 * 交互闭环刀会把「未打卡」换成**广播直达**（乐观回显 → 后台提交 → 快照收敛，
 * 不开 App）；占位态届时改指「设置 › 桌面与快捷方式」（需新增 `lh://settings/desktop`
 * 段，跨 C19 白名单与路由解析，单独一刀做）。
 */
class HabitCheckWidget : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.lh_widget_habit)
            renderOne(context, views, widgetData, id)
            appWidgetManager.updateAppWidget(id, views)
        }
    }

    /** 一枚实例的渲染（状态判定顺序＝失效三态优先级）。 */
    private fun renderOne(
        context: Context,
        views: RemoteViews,
        data: SharedPreferences,
        appWidgetId: Int,
    ) {
        // ① 无快照压过无绑定（B6 既有口径：首装/清数据后先显示「等待数据」，
        //    等快照到了才暴露绑定态——否则用户会以为「是我没选」）。
        if (!LhWidget.hasSnapshot(data)) {
            renderPlaceholder(context, views, R.string.lh_widget_wait_data)
            return
        }
        val name = LhWidget.boundHabitName(context, appWidgetId)
        if (name == null) {
            renderPlaceholder(context, views, R.string.lh_widget_no_binding)
            return
        }
        // ② 绑定着但快照表里查不到这个名字 ⇒ 习惯被删/改名/归档。
        val row = LhWidget.readHabitRows(data).firstOrNull { it.name == name }
        if (row == null) {
            renderPlaceholder(context, views, R.string.lh_widget_source_invalid)
            return
        }
        renderHabit(context, views, row)
    }

    /** 失效三态：只留标题＋居中占位文案，整卡可点（起 App 去处理）。 */
    private fun renderPlaceholder(context: Context, views: RemoteViews, textRes: Int) {
        val text = context.getString(textRes)
        views.setViewVisibility(R.id.lh_wg_habit, View.GONE)
        views.setViewVisibility(R.id.lh_wg_status_row, View.GONE)
        views.setViewVisibility(R.id.lh_wg_gap, View.GONE)
        views.setViewVisibility(R.id.lh_wg_btn, View.GONE)
        views.setViewVisibility(R.id.lh_wg_ph, View.VISIBLE)
        views.setTextViewText(R.id.lh_wg_ph, text)
        views.setContentDescription(R.id.lh_wg_root, text)
        views.setOnClickPendingIntent(
            R.id.lh_wg_root,
            LhWidget.clickIntent(context, LhWidget.SEG_HABIT_CHECK, REQ_ROOT),
        )
    }

    /** 正常态：习惯名＋（状态点·连击/今日）＋主按钮。 */
    private fun renderHabit(context: Context, views: RemoteViews, row: LhWidget.HabitRow) {
        views.setViewVisibility(R.id.lh_wg_habit, View.VISIBLE)
        views.setViewVisibility(R.id.lh_wg_status_row, View.VISIBLE)
        views.setViewVisibility(R.id.lh_wg_gap, View.VISIBLE)
        views.setViewVisibility(R.id.lh_wg_btn, View.VISIBLE)
        views.setViewVisibility(R.id.lh_wg_ph, View.GONE)

        views.setTextViewText(R.id.lh_wg_habit, row.name)
        views.setInt(
            R.id.lh_wg_dot,
            "setBackgroundResource",
            if (row.done) R.drawable.lh_wg_dot_on else R.drawable.lh_wg_dot_off,
        )

        // 连击为 0 时不显示「连击 0 天」（0 天不是成绩，是噪音）。
        val status = when {
            row.streak > 0 && row.done ->
                context.getString(R.string.lh_widget_habit_streak_done, row.streak)
            row.streak > 0 -> context.getString(R.string.lh_widget_habit_streak, row.streak)
            row.done -> context.getString(R.string.lh_widget_habit_streak0_done)
            else -> context.getString(R.string.lh_widget_habit_streak0)
        }
        views.setTextViewText(R.id.lh_wg_status, status)

        // 已打卡态：按钮置灰不可点（只收敛、不回滚——撤销/改数回 App 内）。
        views.setTextViewText(
            R.id.lh_wg_btn,
            context.getString(
                if (row.done) R.string.lh_widget_habit_done else R.string.lh_widget_habit_btn,
            ),
        )
        views.setInt(
            R.id.lh_wg_btn,
            "setBackgroundResource",
            if (row.done) R.drawable.lh_wg_habit_btn_off else R.drawable.lh_wg_habit_btn,
        )
        views.setTextColor(
            R.id.lh_wg_btn,
            ContextCompat.getColor(
                context,
                if (row.done) R.color.lh_wg_sub else R.color.lh_wg_btn_fg,
            ),
        )
        // 已打卡态：按钮置灰**真不可点**（只收敛、不回滚——撤销/改数回 App 内）。
        // ⚠ 「不可点」不能靠「换了淡底色」就算：必须**不给**它挂点击意图，
        //   否则仍有点按反馈却毫无反应，是最糟的一种（比灰着更让人困惑）。
        //   想看详情点整卡（root 点击始终指向习惯页）。
        if (row.done) {
            views.setOnClickPendingIntent(R.id.lh_wg_btn, null)
        } else {
            // ⚠ 过渡态：本刀先起 App 习惯页；交互闭环刀换成广播直达（不开 App）。
            views.setOnClickPendingIntent(
                R.id.lh_wg_btn,
                LhWidget.clickIntent(context, LhWidget.SEG_HABIT_CHECK, REQ_BTN),
            )
        }
        views.setOnClickPendingIntent(
            R.id.lh_wg_root,
            LhWidget.clickIntent(context, LhWidget.SEG_HABIT_CHECK, REQ_ROOT),
        )
        views.setContentDescription(
            R.id.lh_wg_root,
            context.getString(R.string.lh_widget_a11y_habit, row.name, row.streak, status),
        )
    }

    private companion object {
        const val REQ_ROOT = 0x4C4001
        const val REQ_BTN = 0x4C4100
    }
}
