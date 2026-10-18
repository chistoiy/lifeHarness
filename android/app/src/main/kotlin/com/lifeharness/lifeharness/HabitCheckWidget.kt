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
 * ⚠ 点击去向（批A 交互闭环层·评估件 §4.1/§4.2）：
 *  · 未打卡 → **广播直达** [LhWidget.habitCheckIntent]（起无头 Flutter 引擎跑
 *    Dart 仓库出口，**不开 App**；点击瞬间先乐观回显成已打卡，写库结果由
 *    快照收敛/回滚入队兜底）；
 *  · 三态占位 → [LhWidget.SEG_SETTINGS_DESKTOP]（设置 › 桌面与快捷方式·重选入口）。
 *    2026-10-18 真机报障前这里指向 `habit/check`（习惯页），文案却写「点此设置」
 *    ⇒ 点了到习惯页找不到设置，已改。
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
            LhWidget.trace("habit#$appWidgetId → 等待数据（无快照）")
            renderPlaceholder(context, views, R.string.lh_widget_wait_data)
            return
        }
        val name = resolveBinding(context, appWidgetId)
        if (name == null) {
            LhWidget.trace(
                "habit#$appWidgetId → 未选择（实例键=${LhWidget.hasInstanceBind(context, appWidgetId)}" +
                    " 默认键=${LhWidget.hasDefaultBind(context)}）",
            )
            // 键在却解不出名字 ⇒ 打印两份绑定值的**形状**（段数/f0/f1/sub 长度）。
            // 这是 2026-10-18 真机「打卡不显示内容」唯一能读到的取证面：release 包
            // `run-as` 不可用、无 `su`，prefs 文件读不到。
            LhWidget.traceBindShape(context, appWidgetId)
            renderPlaceholder(context, views, R.string.lh_widget_no_binding)
            return
        }
        // ② 绑定着但快照表里查不到这个名字 ⇒ 习惯被删/改名/归档。
        val rows = LhWidget.readHabitRows(data)
        val row = rows.firstOrNull { it.name == name }
        if (row == null) {
            LhWidget.trace(
                "habit#$appWidgetId → 源失效（绑定名与快照表不匹配·表内 ${rows.size} 条）",
            )
            renderPlaceholder(context, views, R.string.lh_widget_source_invalid)
            return
        }
        LhWidget.trace("habit#$appWidgetId → 正常（${row.name}·done=${row.done}）")
        renderHabit(context, views, row, appWidgetId)
    }

    /**
     * 本实例该显示哪个习惯：实例键 → （预选绑定兜底）→ 全局默认。
     *
     * **为什么要在这里认领预选绑定**（2026-10-18 真机报障「到桌面后打卡里面没有
     * 打卡内容」根因）：先选后落的第④步「配置页无感回写」依赖系统在 pin 成功后
     * 拉起 `android:configure` 那个 Activity。**MIUI 桌面实测不拉**——App 内选好
     * 习惯、系统弹窗确认、桌面上出现小组件，但交接位里的目标没人认领 ⇒ 新实例
     * 没有自己的绑定键 ⇒ 直接落「未选择内容，点此设置」，用户视角就是
     * 「选了等于没选」。
     *
     * 实例自己认领是**幂等**的（交接位认一次就清，见
     * [LhWidget.consumePendingBind]）：配置页跑了就是它先认、这里读到的已经是
     * 本实例键；配置页没跑则由本函数补上。两条路都不会二次改写已有绑定。
     *
     * ⚠ 认领发生在**任何**该类型实例的 onUpdate 上（这是它能兜住 MIUI 的原因），
     * 代价是「用户选了目标却在系统弹窗里取消」时，2 分钟内若另一枚**未绑定**的
     * 打卡枚恰好刷新，会被认领走。交接位本身有 2 分钟 TTL 兜（
     * `kWidgetBindPendingTtlMs`），且只有「一枚都没绑」的实例会走到这条路上，
     * 故接受——比「选了永远不生效」好。
     */
    private fun resolveBinding(context: Context, appWidgetId: Int): String? {
        // ① 本实例自己的键（配置页回写过，或上一次 onUpdate 已认领）。
        LhWidget.instanceHabitName(context, appWidgetId)?.let { return it }
        // ② 认领交接位（**必须排在默认键之前**，2026-10-18 真机二次实锤）：
        //    原来顺序是「实例键 → 默认键 → 认领」，于是只要默认键有值，新实例就
        //    直接吃默认、交接位永远没人认领 ⇒ 加第二枚打卡枚时，两枚都显示
        //    **最后选的那个习惯**（用户原话「添加多个不同打卡后，会全部变成最后
        //    添加的打卡内容」）。现在新实例先把自己的选择认领成本实例键，默认键
        //    只留给「从桌面小部件库直接拖出来、没有交接位」的老路。
        if (LhWidget.consumePendingBind(context, appWidgetId)) {
            LhWidget.instanceHabitName(context, appWidgetId)?.let { return it }
        }
        // ③ 全局默认（R2 老实例回落 / 手动拖出且无交接位时的兜底）。
        return LhWidget.defaultHabitName(context)
    }

    /** 失效三态：只留标题＋居中占位文案，整卡可点（去设置页重选·不再去习惯页）。 */
    private fun renderPlaceholder(context: Context, views: RemoteViews, textRes: Int) {
        val text = context.getString(textRes)
        views.setViewVisibility(R.id.lh_wg_habit, View.GONE)
        views.setViewVisibility(R.id.lh_wg_status_row, View.GONE)
        views.setViewVisibility(R.id.lh_wg_gap, View.GONE)
        // 占位态两枚撑开器都收掉，否则占位文本被顶到半空（正常态才需要它们居中）。
        views.setViewVisibility(R.id.lh_wg_gap_top, View.GONE)
        views.setViewVisibility(R.id.lh_wg_btn, View.GONE)
        views.setViewVisibility(R.id.lh_wg_ph, View.VISIBLE)
        views.setTextViewText(R.id.lh_wg_ph, text)
        views.setContentDescription(R.id.lh_wg_root, text)
        // 2026-10-18 真机报障修：三态文案写着「点此设置」，点击却落到习惯页
        // （`habit/check`）——用户原话「点击后直接打开习惯页面，没有设置的内容」。
        // 重选入口在设置 › 桌面与快捷方式，故改走系统寻址段 `settings/desktop`。
        views.setOnClickPendingIntent(
            R.id.lh_wg_root,
            LhWidget.clickIntent(context, LhWidget.SEG_SETTINGS_DESKTOP, REQ_ROOT),
        )
    }

    /** 正常态：习惯名＋（状态点·连击/今日）＋主按钮。 */
    private fun renderHabit(
        context: Context,
        views: RemoteViews,
        row: LhWidget.HabitRow,
        appWidgetId: Int,
    ) {
        views.setViewVisibility(R.id.lh_wg_habit, View.VISIBLE)
        views.setViewVisibility(R.id.lh_wg_status_row, View.VISIBLE)
        views.setViewVisibility(R.id.lh_wg_gap, View.VISIBLE)
        views.setViewVisibility(R.id.lh_wg_gap_top, View.VISIBLE)
        views.setViewVisibility(R.id.lh_wg_btn, View.VISIBLE)
        views.setViewVisibility(R.id.lh_wg_ph, View.GONE)

        views.setTextViewText(R.id.lh_wg_habit, row.name)
        views.setInt(
            R.id.lh_wg_dot,
            "setBackgroundResource",
            if (row.done) R.drawable.lh_wg_dot_on else R.drawable.lh_wg_dot_off,
        )

        if (row.isNumeric) {
            renderNumeric(context, views, row, appWidgetId)
            return
        }

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
            // 批A 交互闭环层：**广播直达**（起无头引擎跑 Dart 仓库出口，不开 App）。
            // ⚠ requestCode 每实例一个（PendingIntent 相等性不比 extras）——
            //   见 [LhWidget.habitCheckIntent]。
            views.setOnClickPendingIntent(
                R.id.lh_wg_btn,
                LhWidget.habitCheckIntent(context, appWidgetId, row.name),
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

    /**
     * 数值型（记量）习惯的正常态：状态行显示进度 `3/8 杯`，主按钮显示 `+2`。
     *
     * 2026-10-18 真机报障原话：「带数值的打卡也只显示一个打卡，不显示数值修改
     * 能力」——数值型习惯原来与布尔型走同一条渲染，桌面上只有一枚「打卡」，
     * 用户看不到今天记了多少、也不知道点下去是加量还是完成。
     *
     * 三条与布尔型**故意不同**的口径：
     *  · **按钮恒可点**（不因达标撤意图）：达标只是「今天够了」，第 9 杯水、
     *    第 31 分钟阅读照样要记上——卡在目标上等于把真数据抹掉；
     *  · 按钮文案是 `+N` 而不是「打卡」：让「点下去会加多少」在按之前就可见，
     *    否则用户点三下才发现一下加 10；
     *  · 状态行让位给进度，连击只在 `streak > 0` 时追加（2×2 一行放不下两句）。
     */
    private fun renderNumeric(
        context: Context,
        views: RemoteViews,
        row: LhWidget.HabitRow,
        appWidgetId: Int,
    ) {
        val v = LhWidget.numText(row.value)
        val g = LhWidget.numText(row.goal)
        val status = if (row.streak > 0) {
            context.getString(R.string.lh_widget_habit_val_streak, v, g, row.unit, row.streak)
        } else {
            context.getString(R.string.lh_widget_habit_val, v, g, row.unit)
        }
        views.setTextViewText(R.id.lh_wg_status, status)

        views.setTextViewText(
            R.id.lh_wg_btn,
            context.getString(
                R.string.lh_widget_habit_add,
                LhWidget.numText(if (row.step > 0) row.step else 1.0),
            ),
        )
        views.setInt(R.id.lh_wg_btn, "setBackgroundResource", R.drawable.lh_wg_habit_btn)
        views.setTextColor(
            R.id.lh_wg_btn,
            ContextCompat.getColor(context, R.color.lh_wg_btn_fg),
        )
        // 广播直达（与布尔型同一个入口）：Dart 侧按「goal > 0」分流成加量写，
        // 原生不判类型、不传量——写库口径只许有一处（C5）。
        views.setOnClickPendingIntent(
            R.id.lh_wg_btn,
            LhWidget.habitCheckIntent(context, appWidgetId, row.name),
        )
        views.setOnClickPendingIntent(
            R.id.lh_wg_root,
            LhWidget.clickIntent(context, LhWidget.SEG_HABIT_CHECK, REQ_ROOT),
        )
        views.setContentDescription(
            R.id.lh_wg_root,
            context.getString(R.string.lh_widget_a11y_habit, row.name, row.streak, status),
        )
    }

    /**
     * 乐观回显：把该实例**当场画成**点完之后的样子（批A 交互闭环层·评估件 §4.2）。
     *
     * 为什么需要：后台 isolate 冷启动要几百 ms~1s+，这段时间用户看到的还是
     * 旧态——「点了没反应」是桌面交互最劣的反馈。回显借用 [renderHabit] 的
     * 两条分支，与真写库后的观感逐像素一致；数值与连击暂用「推算值」，等 Dart
     * 推回真快照时自然收敛。
     *
     * **两种形态各回显什么**（2026-10-18 报障补数值型）：
     *  · 布尔型 ⇒ `done=true`（淡底＋「已打卡」＋**按钮意图撤掉**防连点）；
     *  · 数值型 ⇒ `value + step`（进度条当场往前走一格），跨过目标才同时点亮
     *    状态点；按钮**保持可点**（与 [renderNumeric] 口径一致——连点加量是
     *    正常操作，不是误触）。
     *
     * 三条纪律：
     *  · **只画自己这一枚**（appWidgetId 直改，不走广播重绘——回显要的是即时）；
     *  · 快照表里查不到这个名字 ⇒ **不猜一个状态画上去**（源失效让它走占位）；
     *  · 本函数不碰任何业务库——回显只改「显示态」，写库归 isolate（C5 精神）。
     */
    fun echoChecked(context: Context, appWidgetId: Int, habitName: String) {
        val mgr = AppWidgetManager.getInstance(context) ?: return
        val row = LhWidget.readHabitRows(LhWidget.snapshot(context))
            .firstOrNull { it.name == habitName } ?: return
        val views = RemoteViews(context.packageName, R.layout.lh_widget_habit)
        // 借实例方法即可（provider 无状态，渲染不吃字段）。
        val echo = if (row.isNumeric) {
            val next = row.value + (if (row.step > 0) row.step else 1.0)
            row.copy(value = next, done = row.done || next >= row.goal)
        } else {
            row.copy(done = true)
        }
        HabitCheckWidget().renderHabit(context, views, echo, appWidgetId)
        mgr.updateAppWidget(appWidgetId, views)
    }

    private companion object {
        const val REQ_ROOT = 0x4C4001
    }
}
