package com.lifeharness.lifeharness

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * 1×1 **模块瓦片**（批C · 2026-10-18）的公共基类。
 *
 * 产品口径（规格件 §1）：把各功能模块各做成一枚 1×1 瓦片，桌面上看起来就是一个
 * App 图标；点它**直接落到该模块首页**（不是先开首页再找）。**零数据、零刷新、
 * 零绑定、零配置**——与读数型四枚（概览/快捷/待办/记账/打卡）是两条链路，
 * 本类**不碰**快照、绑定、偏好开关，也不起任何引擎。
 *
 * ⚠ **为什么必须一模块一个子类**（规格 §4.1）：系统小部件选择器里「每一项＝
 * 一条 `<receiver>` ＋ 一份 appwidget-provider XML」，而**同一个 Kotlin class
 * 写两条 `<receiver>` 会被 manifest 合并成一条**（组件名相同）⇒ 17 枚只剩一枚。
 * 所以每枚模块一个 3 行子类。
 *
 * ⚠ **禁写 `android:configure`**：MIUI 桌面实测不跑它（6176 轮实锤），而「一枚
 * 瓦片＋配置页选模块」正好依赖它 ⇒ 在目标机型上必然坏。本批瓦片无参数、无需配置，
 * 天然规避。
 *
 * 点击：目标**全写进 URI**（`lh://modules/<id>`），**不往 extras 塞模块名**——
 * `PendingIntent` 相等性不比 extras，同码＋`FLAG_UPDATE_CURRENT` 会互相覆写
 * （6180 轮实锤）。意图经 [LhWidget.clickIntent] 唯一出口构造（C15/C9）。
 */
abstract class ModuleTileProvider : HomeWidgetProvider() {

    /** 模块段（`modules/<id>`）；同时是 `MainActivity.LH_WHITELIST` 的键。 */
    protected abstract val seg: String

    /** 瓦片图标（vector drawable；禁多密度 PNG）。 */
    protected abstract val iconRes: Int

    /** 瓦片标签文案（≤4 字·与模块名一致）。 */
    protected abstract val labelRes: Int

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val label = context.getString(labelRes)
        for (id in appWidgetIds) {
            val rv = RemoteViews(context.packageName, R.layout.lh_tile)
            rv.setImageViewResource(R.id.lh_tile_icon, iconRes)
            rv.setTextViewText(R.id.lh_tile_label, label)
            rv.setContentDescription(R.id.lh_tile_root, label)
            // requestCode 每实例一个（基址 + appWidgetId）：同一枚模块拖两枚到桌面
            // 时两枚都能点（共用固定码 + FLAG_UPDATE_CURRENT 会互相覆写——6180 轮
            // 打卡枚的实伤，同一个坑不踩第二次）。
            rv.setOnClickPendingIntent(
                R.id.lh_tile_root,
                LhWidget.clickIntent(context, seg, REQ_TILE_BASE + id),
            )
            appWidgetManager.updateAppWidget(id, rv)
        }
    }

    private companion object {
        /** 瓦片点击请求码基址（与既有 0x4C4xxx/0x4C5xxx 各段不撞）。 */
        const val REQ_TILE_BASE = 0x4C6000
    }
}

/**
 * 模块瓦片 · 待办（批C-1 首枚·端到端试点）。
 *
 * 壳内 tab（`/todo`）⇒ 深链消费端用 `go`，底栏留在屏幕上、栈顶唯一。
 */
class TileTodo : ModuleTileProvider() {
    override val seg: String = "modules/todo"
    override val iconRes: Int = R.drawable.ic_lh_todo
    override val labelRes: Int = R.string.lh_tile_label_todo
}
