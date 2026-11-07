package com.lifeharness.lifeharness

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * 计数型（记量）打卡 `±` 的**显示态调节器**（批D · 原型 `[−5] [30] [+5]` 三格）。
 *
 * ## 为什么可以原生处理，而「打卡」不行
 *
 * 「打卡」要写一日流水＋重算连击＋组子项（见 [HabitCheckReceiver] 的说明），
 * 原生复刻＝行为分叉，所以那条必须起无头引擎跑 Dart。
 * `±` 恰恰相反：它**什么都不写**——只改「这次准备记多少」这个显示态数字
 * （存在偏好里的实例级草稿，见 [LhWidget.putDraft]）。这既不是业务数据，
 * 也就不存在「第二套写库实现」的问题；换来的是**毫秒级响应**（起引擎要
 * 1~3s 冷启动，连点几下不可用）。
 *
 * ## 三条口径（照原型）
 *
 *  · **下限 0**：连点减号停在 0，绝不出现负数（负数量没有业务含义）；
 *  · **跨日/换绑即作废**：读草稿时判日期与习惯名（[LhWidget.draftValue]），
 *    昨天的量不会带到今天，换绑后旧草稿不属于新习惯；
 *  · **已提交态不再调节**：今日已有记录（`value > 0`）时步进行本就收起来了，
 *    这里再兜一层——万一有残留意图触发，一律忽略（撤销/改数回 App 内）。
 */
class HabitAdjustReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_ADJUST) return
        val app = context.applicationContext
        val widgetId = intent.getIntExtra(EXTRA_WIDGET_ID, 0)
        val name = intent.getStringExtra(EXTRA_HABIT_NAME)?.trim()
        val delta = intent.getDoubleExtra(EXTRA_DELTA, 0.0)
        if (widgetId <= 0 || name.isNullOrEmpty() || delta == 0.0) return
        // 快照里查不到这个名字 ⇒ 源失效（桌面已是占位态），不猜、不写。
        val row = LhWidget.readHabitRows(LhWidget.snapshot(app))
            .firstOrNull { it.name == name } ?: return
        // 已提交态：步进行不可见，不接受调节。
        if (row.value > 0) return
        val day = LhWidget.todayKey()
        val base = LhWidget.draftValue(app, widgetId, name, day)
            ?: LhWidget.initialDraftValue(row)
        val next = (base + delta).coerceAtLeast(0.0)
        LhWidget.putDraft(app, widgetId, name, day, next)
        // 只重画自己这一枚（毫秒级；不广播整类，免得别的实例跟着闪）。
        HabitCheckWidget().redraw(app, widgetId)
        LhWidget.trace("habit#$widgetId ± ${LhWidget.numText(delta)} → ${LhWidget.numText(next)}")
    }

    companion object {
        const val ACTION_ADJUST = "com.lifeharness.lifeharness.WIDGET_HABIT_ADJUST"
        const val EXTRA_WIDGET_ID = "widget_id"
        const val EXTRA_HABIT_NAME = "habit_name"

        /** 本步增减量（正＝加，负＝减；步长由 Dart 下发，原生不重算）。 */
        const val EXTRA_DELTA = "delta"
    }
}
