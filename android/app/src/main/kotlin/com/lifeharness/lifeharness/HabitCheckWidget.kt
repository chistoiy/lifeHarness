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
        // 步进行同理收掉（批D）：占位态整卡只剩一行文案。
        views.setViewVisibility(R.id.lh_wg_cnt, View.GONE)
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
        // 步进行默认收起：只有计数型（数值型）的**未提交态**才展开（见 [renderNumeric]）。
        views.setViewVisibility(R.id.lh_wg_cnt, View.GONE)

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

        // 已打卡态：按钮置灰，但**不是死区**——点它回 App 的该习惯（批E）。
        // ⚠ 「改数/撤销回 App 内」原本只是一句文案：桌面撤了意图后，已打卡态
        //   整块按钮点下去毫无反应，而 App 里当时也**没有**改记录/改打卡时间的
        //   入口（产品原话「缺少修改打卡记录，删除或修改」）。现在两件事一起补：
        //   App 侧记录可改可删（`showHabitLogSheet(day:)`），桌面这枚按钮把用户
        //   送到那里——是**导航**意图，仍然不写库。
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
        if (row.done) {
            views.setOnClickPendingIntent(
                R.id.lh_wg_btn,
                LhWidget.clickIntent(context, LhWidget.SEG_HABIT_CHECK, REQ_BTN),
            )
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
     * 数值型（记量）习惯的正常态：状态行给进度，**步进行 `[−5] [30] [+5]` ＋「打卡」**。
     *
     * 2026-10-18 真机报障原话：「带数值打卡，只显示了＋10，没有减数值，跟原型里的
     * 不一样」——原型（`index-desktop.html` 计数型）是**三格步进 ＋ 一次提交**：
     * `±` 只改本实例显示态里的中间计数（快照键，不动业务库），「打卡」把中间值
     * 一次提交（仍走 isolate 出口），提交后只显示「已打卡 · 30」，撤销/改数回 App 内。
     *
     * 两态（同一份布局，只切 visibility）：
     *  · **未提交**（今日 `value == 0`）⇒ 步进行展开：左 `−步长`／中 `中间值`／右 `+步长`，
     *    主按钮「打卡」，点它把**中间值**作为本次量提交（不是再加一档）；
     *  · **已提交**（今日 `value > 0`）⇒ 步进行收起、按钮灰底不可点、文案 `已打卡 · N`。
     *
     * ⚠ 与布尔型**故意不同**的三点：状态行让位给进度（`3/8 杯`，连击只在 `streak > 0`
     *   时追加）；中间值初值是**今日目标量**（原型「计数型习惯（默认 30）」）；
     *   已提交态才撤意图（布尔型是「打卡即终态」，数值型要等这一次提交落库）。
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

        if (row.value > 0) {
            // ── 已提交态（原型：提交后只显示「已打卡 · 30」，撤销/改数回 App 内）──
            views.setViewVisibility(R.id.lh_wg_cnt, View.GONE)
            views.setTextViewText(
                R.id.lh_wg_btn,
                context.getString(R.string.lh_widget_habit_done_val, v),
            )
            views.setInt(R.id.lh_wg_btn, "setBackgroundResource", R.drawable.lh_wg_habit_btn_off)
            views.setTextColor(
                R.id.lh_wg_btn,
                ContextCompat.getColor(context, R.color.lh_wg_sub),
            )
            // 「不可点」改成「点了回 App 改」：批E 起 App 内有该日记录编辑
            // （改数值/改打卡时间/删除），桌面这枚灰按钮就是去那里的入口。
            views.setOnClickPendingIntent(
                R.id.lh_wg_btn,
                LhWidget.clickIntent(context, LhWidget.SEG_HABIT_CHECK, REQ_BTN),
            )
            bindRoot(context, views, row, status)
            return
        }

        // ── 未提交态：步进行 ＋「打卡」一次提交 ──
        val step = if (row.step > 0) row.step else 1.0
        val mid = LhWidget.draftValue(context, appWidgetId, row.name, LhWidget.todayKey())
            ?: LhWidget.initialDraftValue(row)
        views.setViewVisibility(R.id.lh_wg_cnt, View.VISIBLE)
        views.setTextViewText(
            R.id.lh_wg_cnt_minus,
            context.getString(R.string.lh_widget_habit_minus, LhWidget.numText(step)),
        )
        views.setTextViewText(R.id.lh_wg_cnt_val, LhWidget.numText(mid))
        views.setTextViewText(
            R.id.lh_wg_cnt_plus,
            context.getString(R.string.lh_widget_habit_add, LhWidget.numText(step)),
        )
        // ± 两条意图：每实例每钮一个 requestCode（见 [LhWidget.habitAdjustIntent]）。
        views.setOnClickPendingIntent(
            R.id.lh_wg_cnt_minus,
            LhWidget.habitAdjustIntent(context, appWidgetId, row.name, -step),
        )
        views.setOnClickPendingIntent(
            R.id.lh_wg_cnt_plus,
            LhWidget.habitAdjustIntent(context, appWidgetId, row.name, step),
        )
        // 中间格是「数」不是「钮」：点它不提交（提交只走主按钮，避免误记）。
        views.setOnClickPendingIntent(R.id.lh_wg_cnt_val, null)

        views.setInt(R.id.lh_wg_btn, "setBackgroundResource", R.drawable.lh_wg_habit_btn)
        views.setTextColor(
            R.id.lh_wg_btn,
            ContextCompat.getColor(context, R.color.lh_wg_btn_fg),
        )
        if (mid > 0) {
            views.setTextViewText(R.id.lh_wg_btn, context.getString(R.string.lh_widget_habit_btn))
            // 广播直达：Dart 侧按「带不带 value」分流到**绝对量写**（禁原生复刻写库）。
            views.setOnClickPendingIntent(
                R.id.lh_wg_btn,
                LhWidget.habitCheckIntent(context, appWidgetId, row.name, amount = mid),
            )
        } else {
            // 中间值被减到 0：记 0 是空记录（写进去只会污染「今日已记」），撤意图。
            views.setTextViewText(R.id.lh_wg_btn, context.getString(R.string.lh_widget_habit_btn))
            views.setInt(
                R.id.lh_wg_btn,
                "setBackgroundResource",
                R.drawable.lh_wg_habit_btn_off,
            )
            views.setTextColor(
                R.id.lh_wg_btn,
                ContextCompat.getColor(context, R.color.lh_wg_sub),
            )
            views.setOnClickPendingIntent(R.id.lh_wg_btn, null)
        }
        bindRoot(context, views, row, status)
    }

    /** 整卡点击（去习惯页）＋无障碍描述（两种形态共用·批D 抽出避免两处漂移）。 */
    private fun bindRoot(
        context: Context,
        views: RemoteViews,
        row: LhWidget.HabitRow,
        status: String,
    ) {
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
     * 只重画**这一枚**实例（± 调节后即时反馈 · 批D）。
     *
     * 为什么不用广播整类重绘：`±` 是高频连点操作，广播会让同类的每一枚都跟着
     * 重建 RemoteViews（桌面肉眼可见的集体闪一下），而这次变化只属于本实例。
     */
    fun redraw(context: Context, appWidgetId: Int) {
        val mgr = AppWidgetManager.getInstance(context) ?: return
        val views = RemoteViews(context.packageName, R.layout.lh_widget_habit)
        renderOne(context, views, LhWidget.snapshot(context), appWidgetId)
        mgr.updateAppWidget(appWidgetId, views)
    }

    /**
     * 乐观回显：把该实例**当场画成**点完之后的样子（批A 交互闭环层·评估件 §4.2）。
     *
     * 为什么需要：后台 isolate 冷启动要几百 ms~1s+，这段时间用户看到的还是
     * 旧态——「点了没反应」是桌面交互最劣的反馈。回显借用 [renderHabit] 的
     * 两条分支，与真写库后的观感逐像素一致；数值与连击暂用「推算值」，等 Dart
     * 推回真快照时自然收敛。
     *
     * **两种形态各回显什么**（2026-10-18 报障补数值型 · 批D 改「一次提交」）：
     *  · 布尔型 ⇒ `done=true`（淡底＋「已打卡」＋**按钮意图撤掉**防连点）；
     *  · 数值型 ⇒ 值直接置为**本次提交量**（步进行里那一刻的中间值），当场画成
     *    `已打卡 · N`（步进行收起、按钮置灰）——与提交成功后的观感逐像素一致。
     *
     * 三条纪律：
     *  · **只画自己这一枚**（appWidgetId 直改，不走广播重绘——回显要的是即时）；
     *  · 快照表里查不到这个名字 ⇒ **不猜一个状态画上去**（源失效让它走占位）；
     *  · 本函数不碰任何业务库——回显只改「显示态」，写库归 isolate（C5 精神）。
     */
    fun echoChecked(
        context: Context,
        appWidgetId: Int,
        habitName: String,
        amount: Double? = null,
    ) {
        val mgr = AppWidgetManager.getInstance(context) ?: return
        val row = LhWidget.readHabitRows(LhWidget.snapshot(context))
            .firstOrNull { it.name == habitName } ?: return
        val views = RemoteViews(context.packageName, R.layout.lh_widget_habit)
        // 借实例方法即可（provider 无状态，渲染不吃字段）。
        val echo = if (row.isNumeric) {
            // 提交量以意图里带的为准（原生侧刚从草稿读出），缺省才回落到草稿/初值。
            val next = amount
                ?: LhWidget.draftValue(context, appWidgetId, habitName, LhWidget.todayKey())
                ?: LhWidget.initialDraftValue(row)
            row.copy(value = next, done = row.done || next >= row.goal)
        } else {
            row.copy(done = true)
        }
        HabitCheckWidget().renderHabit(context, views, echo, appWidgetId)
        mgr.updateAppWidget(appWidgetId, views)
    }

    private companion object {
        const val REQ_ROOT = 0x4C4001

        /** 主按钮「回 App 改」请求码（与 root 分开：两个目标同一个段，码不同互不覆写）。 */
        const val REQ_BTN = 0x4C4002
    }
}
