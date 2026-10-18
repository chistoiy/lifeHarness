package com.lifeharness.lifeharness

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import es.antonborri.home_widget.HomeWidgetPlugin

/**
 * 桌面模块批2 · 小组件支持件（快照键 / 读数格式化 / 点击意图 / 重绘广播的唯一出口）。
 *
 * 规格＝docs/handoff/桌面模块-冻结版开发方案-20261013.md §2.2 / §4.4 / §5.6。
 *
 * **红线**：小组件**只读 SharedPreferences 快照**（C5），**禁**直读 sqlite；
 * 点击意图一律走 [lhLaunchIntent]（C15 唯一出口，禁第二套构造）。
 */
internal object LhWidget {

    // ── 快照键：与 Dart `lib/core/platform/desktop_widget.dart` 的 `LhWidgetKeys` 逐字一致 ──
    const val KEY_TODO = "todo_count"
    const val KEY_HABIT_DONE = "habit_done"
    const val KEY_HABIT_TOTAL = "habit_total"
    const val KEY_AMOUNT = "amount_cell"
    /** 本月支出金额位（记账 2×2 三行读数之二；已遮蔽）。 */
    const val KEY_MONTH_AMOUNT = "month_amount_cell"

    /** 本月结余金额位（记账 2×2 三行读数之三；已遮蔽，可能带负号）。 */
    const val KEY_BALANCE = "balance_cell"

    /** 今日待办清单（待办 2×2 的行数据；紧凑编码，见下方分隔符）。 */
    const val KEY_TODO_ITEMS = "todo_items"

    /** 待办被裁掉的剩余条数（待办 2×2 显示「还有 N 条」）。 */
    const val KEY_TODO_MORE = "todo_more"

    /** 习惯今日状态表（打卡-单习惯 2×2；编码与待办行同族，字段序 `name/streak/done`）。 */
    const val KEY_HABIT_ITEMS = "habit_items"

    const val KEY_HAS_SNAPSHOT = "has_snapshot"

    /** 无快照 / 无数据占位（B6）。 */
    const val PLACEHOLDER = "--"

    /** 隐私遮蔽结果（C8/B7）。Dart 侧 `widgetAmountCell` 已算好，原生只显示。 */
    const val MASKED = "••••"

    // ── 小组件类名：与 Dart `LhWidgetNames` 逐字一致（home_widget 按「包名.类名」解析）──
    const val PROVIDER_OVERVIEW = "TodayOverviewWidget"
    const val PROVIDER_QUICK = "QuickRecordWidget"
    const val PROVIDER_TODO_LIST = "TodoListWidget"
    const val PROVIDER_LEDGER = "LedgerOverviewWidget"

    /** 2×2 打卡-单习惯（批A）。与 Dart `LhWidgetNames.habitCheck` 逐字一致。 */
    const val PROVIDER_HABIT = "HabitCheckWidget"

    // ── 待办清单编码（与 Dart `kTodoItemSep` / `kTodoFieldSep` 逐字一致）──
    const val TODO_ITEM_SEP = '\u001e'
    const val TODO_FIELD_SEP = '\u001f'

    /** 待办 2×2 最多显示几条（与 Dart `kWidgetTodoRows` 同值·禁两处各写一个数字）。 */
    const val TODO_ROWS = 3

    /** 一条待办的行数据（[TodoListWidget] 内部用）。 */
    data class TodoRow(val id: Int, val done: Boolean, val title: String)

    /**
     * 解码 [KEY_TODO_ITEMS]。
     *
     * ⚠ 格式真源在 Dart侧 `encodeWidgetTodoItems`（见 `desktop_widget.dart`）：条目间
     * `\u001e`、字段间 `\u001f`、字段序 `id / done / title`。这里**只做 split**，
     * 禁引 JSON/三方解析器（widget 进程越轻越好 · C4 功耗口径）。
     *
     * 容错：字段不足 3 段的行**整行丢弃**（宁可少一行，也不要在桌面上显示半个
     * 标题）——桌面内容错位比少一行刺眼得多。
     */
    fun readTodoRows(p: SharedPreferences): List<TodoRow> {
        if (!hasSnapshot(p)) return emptyList()
        val raw = try {
            p.getString(KEY_TODO_ITEMS, "") ?: ""
        } catch (_: Exception) {
            ""
        }
        if (raw.isEmpty()) return emptyList()
        return raw.split(TODO_ITEM_SEP).mapNotNull { chunk ->
            val f = chunk.split(TODO_FIELD_SEP)
            if (f.size < 3) return@mapNotNull null
            val id = f[0].trim().toIntOrNull() ?: return@mapNotNull null
            val title = f[2].trim()
            if (title.isEmpty()) return@mapNotNull null
            TodoRow(id, f[1].trim() == "1", title)
        }
    }

    /** 「还有 N 条」里的 N（0 ⇒ 原生侧隐藏该行，不占位）。 */
    fun readTodoMore(p: SharedPreferences): Int =
        readCell(p, KEY_TODO_MORE).toIntOrNull()?.coerceAtLeast(0) ?: 0

    /** 一个习惯的今日状态行（[HabitCheckWidget] 用）。 */
    data class HabitRow(val name: String, val streak: Int, val done: Boolean)

    /**
     * 解码 [KEY_HABIT_ITEMS]（打卡-单习惯 2×2）。
     *
     * 格式真源＝Dart `encodeWidgetHabitItems`：条目间 `\u001e`、字段间 `\u001f`、
     * 字段序 `name / streak / done`。字段不足 3 段的行**整行丢弃**（同待办行口径：
     * 桌面内容错位比少一行刺眼得多）。
     */
    fun readHabitRows(p: SharedPreferences): List<HabitRow> {
        if (!hasSnapshot(p)) return emptyList()
        val raw = try {
            p.getString(KEY_HABIT_ITEMS, "") ?: ""
        } catch (_: Exception) {
            ""
        }
        if (raw.isEmpty()) return emptyList()
        return raw.split(TODO_ITEM_SEP).mapNotNull { chunk ->
            val f = chunk.split(TODO_FIELD_SEP)
            if (f.size < 3) return@mapNotNull null
            val name = f[0].trim()
            if (name.isEmpty()) return@mapNotNull null
            HabitRow(name, f[1].trim().toIntOrNull() ?: 0, f[2].trim() == "1")
        }
    }

    /**
     * 某实例绑定的**习惯名**（实例键优先，回落全局默认·R2；无/脏 ⇒ null）。
     *
     * 绑定值＝`kind␟ref␟sub`；打卡目标形态是 `nav␟habit␟<习惯名>`——三段落
     * 任一不符即按未绑定处理（宁可在桌面写「未选择内容」，也不猜一个习惯出来）。
     */
    fun boundHabitName(context: Context, appWidgetId: Int): String? {
        val p = prefs(context)
        habitNameOf(readString(p, "$PREF_WIDGET_BIND_PREFIX$appWidgetId"))?.let { return it }
        return habitNameOf(readString(p, PREF_WIDGET_BIND_DEFAULT))
    }

    /** 绑定值 → 习惯名（非打卡形态一律 null）。 */
    private fun habitNameOf(raw: String?): String? {
        val s = (raw ?: "").trim()
        if (s.isEmpty()) return null
        val f = s.split(WIDGET_BIND_FIELD_SEP)
        if (f.size != 3) return null
        if (f[0].trim() != WIDGET_TARGET_KIND_NAV) return null
        if (f[1].trim() != WIDGET_REF_HABIT) return null
        return f[2].trim().takeIf { it.isNotEmpty() }
    }

    /** 偏好读串（任何类型异常都不抛——小组件崩＝整个桌面入口废掉）。 */
    private fun readString(p: SharedPreferences, key: String): String? = try {
        p.getString(key, null)
    } catch (_: Exception) {
        null
    }

    /**
     * 认领「先选后落」的预选绑定（批A 第④步 · 配置页无感回写）。
     *
     * 流程：App 内选好目标 → 写 `…widget_bind.pending` → 系统 pin → **本 Activity**
     * 拿到新实例 id → 此处把目标写成本实例键并清掉交接位 → 直接 `RESULT_OK` 收摊
     * （用户看不到配置页，桌面直接出现「打卡-单习惯」）。
     *
     * 三条安全线：
     * ① **种类不符不动它**（不是给这类小组件的预选，留给真正那枚来认领）；
     * ② **过期作废**（用户在系统弹窗里取消时没人消费，不设期限就会被下一次
     *    随手拖出的别的枚误吃——Dart 侧 `kWidgetBindPendingTtlMs` 同值）；
     * ③ **脏值清掉**（段数不对的残留只会一直挡住后面的正常配置）。
     *
     * @return true＝认领成功（本实例已写好绑定）。
     */
    fun consumePendingBind(context: Context, appWidgetId: Int): Boolean {
        val p = prefs(context)
        val raw = readString(p, PREF_WIDGET_BIND_PENDING) ?: return false
        val f = raw.split(WIDGET_BIND_FIELD_SEP)
        if (f.size != 5) {
            p.edit().remove(PREF_WIDGET_BIND_PENDING).commit()
            return false
        }
        if (f[0].trim() != WIDGET_KIND_HABIT) return false
        val targetKind = f[1].trim()
        val ref = f[2].trim()
        val sub = f[3].trim()
        val at = f[4].trim().toLongOrNull()
        val now = System.currentTimeMillis()
        val fresh = at != null &&
            now - at <= WIDGET_BIND_PENDING_TTL_MS &&
            now - at >= -WIDGET_BIND_PENDING_SKEW_MS
        if (!fresh || targetKind.isEmpty() || ref.isEmpty()) {
            p.edit().remove(PREF_WIDGET_BIND_PENDING).commit()
            return false
        }
        p.edit()
            .putString(
                "$PREF_WIDGET_BIND_PREFIX$appWidgetId",
                "$targetKind$WIDGET_BIND_FIELD_SEP$ref$WIDGET_BIND_FIELD_SEP$sub",
            )
            .remove(PREF_WIDGET_BIND_PENDING)
            .commit()
        return true
    }

    /** 让指定类的实例立刻重绘（[notifyWidgets] 的单类版本）。 */
    fun notifyWidget(context: Context, cls: Class<*>, ids: IntArray) {
        if (ids.isEmpty()) return
        val i = Intent(context, cls).apply {
            action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
        }
        context.sendBroadcast(i)
    }

    /**
     * 行内勾圈的**闭环动作**意图（待办 2×2）。
     *
     *⚠ 走**广播**而非 `PendingIntent.getActivity`：闭环是写入动作，而 C18 明确
     * 「写入类只预填、提交须 App 内确认」——广播给 [TodoActionReceiver] 后由它
     * 直接改库并重绘，**不开App**（这正是「点勾圈就闭环」的意义）。
     *
     * ⚠ 与读数链路同一条纪律：勾圈**禁**自己拼 `lh://`（C15唯一出口），它带的是
     * 纯数据 id，不带任何 scheme 字面量。
     */
    fun toggleIntent(context: Context, todoId: Int, requestCode: Int): PendingIntent {
        val i = Intent(context, TodoActionReceiver::class.java).apply {
            action = TodoActionReceiver.ACTION_TOGGLE
            putExtra(TodoActionReceiver.EXTRA_TODO_ID, todoId)
        }
        return PendingIntent.getBroadcast(
            context,
            requestCode,
            i,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    /**
     * 打卡-单习惯主按钮的**闭环动作**意图（批A 交互闭环层）。
     *
     * ⚠ 走**广播**而非 `PendingIntent.getActivity`：闭环是写入动作，而打卡不是
     * 单列写（流水 upsert＋连击重算＋子项）——禁原生复刻，广播给
     * [HabitCheckReceiver] 起**无头 Flutter 引擎**跑 Dart 仓库出口（评估件
     * §4.1·B8）。用户全程看不到 App。
     *
     * ⚠ **requestCode 必须带 appWidgetId**：`PendingIntent` 的相等性**不比
     * extras**（只比 action/data/type/component）。多枚实例共用一个固定码时，
     * 第二枚的创建会以 `FLAG_UPDATE_CURRENT` **覆写**第一枚里的习惯名——两枚
     * 都打到同一个习惯上（实例 A 点了写实例 B 的习惯）。故这里每人一个码。
     *
     * ⚠ 与读数链路同纪律：意图里只带**纯数据**（实例 id＋习惯名），不带任何
     * scheme 字面量（C15 只管起 App 的那条；闭环广播不经 `lh://` 派发）。
     */
    fun habitCheckIntent(
        context: Context,
        appWidgetId: Int,
        habitName: String,
    ): PendingIntent {
        val i = Intent(context, HabitCheckReceiver::class.java).apply {
            action = HabitCheckReceiver.ACTION_CHECK
            putExtra(HabitCheckReceiver.EXTRA_WIDGET_ID, appWidgetId)
            putExtra(HabitCheckReceiver.EXTRA_HABIT_NAME, habitName)
        }
        return PendingIntent.getBroadcast(
            context,
            REQ_HABIT_CHECK_BASE + appWidgetId,
            i,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    /** 打卡闭环请求码基址（每枚实例 = 基址 + appWidgetId；与 root 0x4C4001 不撞）。 */
    const val REQ_HABIT_CHECK_BASE = 0x4C5000

    /**
     * 打卡没能当场写成 ⇒ 记住这个习惯名，等 App 起来补写（闭环不能丢）。
     *
     * 去重后 `\u001e` 拼接（Dart 侧 loadDesktopPendingChecks 同口径）；
     * 连续失败也只写一条——App 启动排空是幂等补写，重复条目没有意义。
     */
    fun enqueuePendingCheck(context: Context, name: String) {
        val n = name.trim()
        if (n.isEmpty()) return
        try {
            val p = prefs(context)
            val cur = p.getString(PREF_PENDING_CHECKS, "") ?: ""
            val names = cur.split(CHECK_SEP).map { it.trim() }
                .filter { it.isNotEmpty() }.toMutableSet()
            if (names.add(n)) {
                p.edit().putString(PREF_PENDING_CHECKS, names.joinToString(CHECK_SEP.toString()))
                    .apply()
            }
        } catch (_: Exception) {
            // catch-ok: 连偏好都写不了（极端情况）只能放弃本次闭环，不崩宿主。
        }
    }

    // ── 点击目标：段取自 `MainActivity.LH_WHITELIST`（禁散落 scheme 字面量 · C19）──
    const val SEG_TODAY = "today"
    const val SEG_LEDGER_ADD = "ledger/add"

    /** 习惯页（打卡-单习惯 2×2 的点击去向·白名单既有段）。 */
    const val SEG_HABIT_CHECK = "habit/check"

    // ── 设置页 / 配置 Activity 共用的偏好（F2-4「禁两套」）──
    //
    // 文件＝`LegacySharedPreferencesPlugin.SHARED_PREFERENCES_NAME`；键前缀＝Dart
    // `SharedPreferences._prefix`（`flutter.`）。与 `SettingsRepository` 的
    // `loadDesktopWidgetSummary/Quick/HideAmount` 读写同一份数据。
    const val FLUTTER_PREFS = "FlutterSharedPreferences"
    const val FLUTTER_KEY_PREFIX = "flutter."
    const val PREF_WIDGET_SUMMARY = FLUTTER_KEY_PREFIX + "desktop.widget_summary"
    const val PREF_WIDGET_QUICK = FLUTTER_KEY_PREFIX + "desktop.widget_quick"
    const val PREF_WIDGET_TODO_LIST = FLUTTER_KEY_PREFIX + "desktop.widget_todo_list"
    const val PREF_WIDGET_LEDGER = FLUTTER_KEY_PREFIX + "desktop.widget_ledger"
    const val PREF_HIDE_AMOUNT = FLUTTER_KEY_PREFIX + "desktop.hide_amount"

    /** 待勾圈闭环但**没能当场写库**的 id 队列（逗号分隔；App 下次启动时排空）。 */
    const val PREF_PENDING_TOGGLES = FLUTTER_KEY_PREFIX + "desktop.widget_pending_toggles"

    /**
     * 打卡闭环但**没能当场写库**的习惯名队列（`\u001e` 分隔；App 下次启动排空）。
     *
     * 与 [PREF_PENDING_TOGGLES] 的分野：待办存 **id**（原生直写库只认 id），
     * 打卡存**名字**——打卡走后台 isolate 跑 Dart 出口，widget 进程拿得到的
     * 只有绑定里的习惯名（C5：禁直读库取 id）。名字可能含逗号 ⇒ 禁逗号分隔
     * （一条会被切成两条），用与待办行同族的控制字符。
     */
    const val PREF_PENDING_CHECKS = FLUTTER_KEY_PREFIX + "desktop.widget_pending_checks"

    /** 打卡补写队列的分隔符（与 Dart `kWidgetCheckSep` 同值）。 */
    const val CHECK_SEP = '\u001e'

    // ── 按实例绑定（批A · 与 Dart `features/widget/domain/widget_binding.dart` 同口径）──
    //
    // ⚠ 本块**必须**排在 `FLUTTER_KEY_PREFIX` 之后：`const val` 的初始化按**声明次序**
    //   解析，写在前面编译器直接报 `Variable 'FLUTTER_KEY_PREFIX' must be initialized`
    //   （批A 首编译即踩）。搬动本块时别顺手挪回文件上半部分。
    // 存储＝`FlutterSharedPreferences` 的 `flutter.desktop.widget_bind.*`：
    //   一实例一键 `…widget_bind.<appWidgetId>`＝`kind␟ref␟sub`；
    //   全局默认 `…widget_bind.default`（老实例回落）；
    //   预选交接位 `…widget_bind.pending`＝`widgetKind␟kind␟ref␟sub␟atMs`（一次性·有期限）。
    const val PREF_WIDGET_BIND_PREFIX = FLUTTER_KEY_PREFIX + "desktop.widget_bind."
    const val PREF_WIDGET_BIND_DEFAULT = PREF_WIDGET_BIND_PREFIX + "default"
    const val PREF_WIDGET_BIND_PENDING = PREF_WIDGET_BIND_PREFIX + "pending"

    /** 绑定值字段分隔符（与 Dart `kWidgetBindFieldSep` 同值）。 */
    const val WIDGET_BIND_FIELD_SEP = '\u001f'

    /** 绑定目标的 `kind`：打卡走 `nav` 前缀形态（`ref`＝habit，`sub`＝习惯名）。 */
    const val WIDGET_TARGET_KIND_NAV = "nav"
    const val WIDGET_REF_HABIT = "habit"

    /** 目标小组件种类（与 Dart `kWidgetKindHabit` 同值·预选认领用）。 */
    const val WIDGET_KIND_HABIT = "habit"

    /** 预选绑定有效期／回拨容忍（与 Dart `kWidgetBindPendingTtlMs` / `…SkewMs` 同值）。 */
    const val WIDGET_BIND_PENDING_TTL_MS = 2 * 60 * 1000L
    const val WIDGET_BIND_PENDING_SKEW_MS = 60 * 1000L

    /** 快照（home_widget 自有文件 `HomeWidgetPreferences`）· C5 唯一读数源。 */
    fun snapshot(context: Context): SharedPreferences = HomeWidgetPlugin.getData(context)

    /**
     * 布尔位读取：**兼容两种落盘类型**。
     *
     * ⚠ 踩坑实锤（真机 6145 首次绑定即崩，两枚 Provider 全挂）：
     * Dart 侧 `DesktopWidgetSnapshot.toData()` 按冻结档 §6.4 的**扁平字符串口径**
     * 下发（`saveWidgetData<String>`），所以 `has_snapshot` 在 `HomeWidgetPreferences`
     * 里落的是 **String** `"true"`／`"false"`，**不是** Boolean。
     * 直读 `getBoolean` 会抛 `ClassCastException: String cannot be cast to Boolean`
     * ⇒ Provider 抛异常 ⇒ 桌面点按毫无反应（配置页还没起来 Provider 就炸了）。
     *
     * 所以这里一律按 String 读再解析；顺带容忍 Boolean（兼容历史/手工写法），
     * **任何类型都不抛**——小组件崩＝整个桌面入口废掉，不能冒这个险。
     */
    fun flag(p: SharedPreferences, key: String): Boolean = try {
        when (val v = p.all[key]) {
            is Boolean -> v
            is String -> v.equals("true", ignoreCase = true) || v == "1"
            is Int -> v != 0
            is Long -> v != 0L
            else -> false
        }
    } catch (_: Exception) {
        false
    }

    fun hasSnapshot(p: SharedPreferences): Boolean = flag(p, KEY_HAS_SNAPSHOT)

    /** 读数位取值：无快照一律占位（B6）——**不显示 0**（0 会被读成真读数）。 */
    fun readCell(p: SharedPreferences, key: String): String {
        if (!hasSnapshot(p)) return PLACEHOLDER
        return p.getString(key, PLACEHOLDER)?.takeIf { it.isNotEmpty() } ?: PLACEHOLDER
    }

    /**
     * 金额位：Dart 侧已做隐私遮蔽（`••••` / `--`，见 `widgetAmountCell`），
     * 这里只补货币符号（原型 `¥1,286`；遮蔽/占位态**不带符号**）。
     *
     * [context] 传了就**再兜一层**「隐藏金额」总开关（B7 双保险）：快照可能是隐藏开关
     * 打开**之前**写下的（没重跑 App），此时不该继续显示真金额。不传则只信快照
     * （2×2 概览不显示金额位，无需此兜底）。
     */
    fun readAmount(p: SharedPreferences, context: Context? = null): String {
        if (context != null && isHideAmount(context)) return MASKED
        val v = readCell(p, KEY_AMOUNT)
        return if (v == MASKED || v == PLACEHOLDER) v else "¥$v"
    }

    /** 本月支出位（记账 2×2 第二行）；遮蔽口径与 [readAmount] 同。 */
    fun readMonthAmount(p: SharedPreferences, context: Context? = null): String {
        if (context != null && isHideAmount(context)) return MASKED
        val v = readCell(p, KEY_MONTH_AMOUNT)
        return if (v == MASKED || v == PLACEHOLDER) v else "¥$v"
    }

    /**
     * 本月结余位（记账 2×2 第三行；**可能带负号**）。
     *
     * ⚠ 别把负号当金额位那样吞掉：Dart 侧 `widgetBalanceCell` 对负数输出 `-1,286`
     *（不带符号的 `¥`），这里必须拼成 `-¥1,286` ⇒ 靠 `startsWith("-")` 判定，
     * **禁**简单地 `"¥$v"`（那会显示成 `¥-1,286`，且中文语境下 `-¥` 才对）。
     */
    fun readBalance(p: SharedPreferences, context: Context? = null): String {
        if (context != null && isHideAmount(context)) return MASKED
        val v = readCell(p, KEY_BALANCE)
        if (v == MASKED || v == PLACEHOLDER) return v
        return if (v.startsWith("-")) "-¥${v.substring(1)}" else "¥$v"
    }

    /** 小组件点击意图（C15 唯一出口；段必须在白名单内，表外直接抛）。 */
    fun clickIntent(context: Context, seg: String, requestCode: Int): PendingIntent {
        // ⚠ 真机 8146 实锤的重复任务 bug：点小组件 → 退出后，MIUI 最近任务出现**两张
        // LifeHarness 卡片**（＝另起了一个任务）。
        //
        // 机理：`Manifest` 的 `android:taskAffinity=""`（M0 骨架时代设的，让 App 不与桌面
        // 共享任务）使本 App 任务不归属任何已有 affinity；`lhLaunchIntent` 带的
        // `FLAG_ACTIVITY_NEW_TASK` 在桌面点按时找不到同 affinity 的已有任务 ⇒ **另起新任务**。
        // `launchMode="singleTop"` 只在**同一任务内**复用，跨任务无效。
        //
        // 修法（不动 `launchMode`／`taskAffinity`——批1 工单明确依赖 singleTop 热启动语义）：
        // 桌面入口补 `CLEAR_TOP`，语义等价于 `singleTask` 的「复用已有实例并清栈顶之上的陈旧页」，
        // 这样点小组件只会**唤起既有任务**而不是新建一个。
        //
        // ⚠ 后续**每枚**桌面入口（待办闭环广播、记账 2×2、未来的任何小组件）都须走此处，
        //   禁自己拼 Intent——重复任务是整类 bug，不是个别组件的问题。
        val intent = lhLaunchIntent(context, MainActivity.lhScheme(seg))
            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
        return PendingIntent.getActivity(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    /**
     * 偏好读口（设置页／配置页与原生渲染侧共用一份 · F2-4「禁两套」）。
     *
     * ⚠ 取自 `FlutterSharedPreferences` 的 `flutter.desktop.*` 键，走 legacy 通道
     * （`LegacySharedPreferencesPlugin.setBool` ＝ 真 `putBoolean`）⇒ 这里可直读
     * `getBoolean`。**与快照 [snapshot] 那条链不同**（`HomeWidgetPreferences` 是
     * String 落盘，须用 [flag]）——两条链别混。
     */
    fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)

    /** 该枚是否「已启用」（设置页勾选框＝总开关，默认开）。 */
    fun isEnabled(context: Context, prefKey: String): Boolean =
        try {
            prefs(context).getBoolean(prefKey, true)
        } catch (_: Exception) {
            true
        }

    fun isOverviewEnabled(context: Context): Boolean =
        isEnabled(context, PREF_WIDGET_SUMMARY)

    fun isQuickEnabled(context: Context): Boolean = isEnabled(context, PREF_WIDGET_QUICK)

    fun isTodoListEnabled(context: Context): Boolean =
        isEnabled(context, PREF_WIDGET_TODO_LIST)

    fun isLedgerEnabled(context: Context): Boolean = isEnabled(context, PREF_WIDGET_LEDGER)

    fun isHideAmount(context: Context): Boolean = isEnabled(context, PREF_HIDE_AMOUNT)

    /**
     * 设置页拨动总开关后调用：**关掉的枚即刻从桌面移除**，开着的重绘。
     *
     * ⚠ 2026-10-15 8148 装机实锤修的「死开关」：原来 `PREF_WIDGET_SUMMARY`/`_QUICK`
     * 只有配置页读写，**两枚 Provider 一次都没读** ⇒ 设置页拨它桌面毫无反应。
     * 现钉死语义＝**「是否添加这枚」的总开关**（产品定案），且**关掉要真从桌面消失**
     * （否则「关」只是不更新、内容还留在桌面上，仍然是死开关的另一种形态）。
     * `deleteAppWidgetId` 会通知宿主删除实例；该枚偏好默认开 ⇒ 首次调用不会误删。
     */
    fun applyEnabledFlags(context: Context) {
        val mgr = AppWidgetManager.getInstance(context)
        for (spec in listOf(
            TodayOverviewWidget::class.java to ::isOverviewEnabled,
            QuickRecordWidget::class.java to ::isQuickEnabled,
            TodoListWidget::class.java to ::isTodoListEnabled,
            LedgerOverviewWidget::class.java to ::isLedgerEnabled,
        )) {
            val cls = spec.first
            val on = spec.second.invoke(context)
            val ids = mgr.getAppWidgetIds(ComponentName(context, cls))
            if (ids.isEmpty()) continue
            if (!on) {
                deleteIds(mgr, ids)
            } else {
                val i = Intent(context, cls).apply {
                    action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
                }
                context.sendBroadcast(i)
            }
        }
    }

    /**
     * 删掉宿主上的实例，让这枚小组件**真从桌面消失**。
     *
     * ⚠ 坑（2026-10-15 编译门实锤）：`AppWidgetManager` **没有公开**的删除方法——
     * `deleteAppWidgetId` 只存在于 `AppWidgetHost`，第三方应用拿不到宿主句柄。
     * 可行路径是反射系统内部 `AppWidgetService.mgr`（同包内 `deleteAppWidgetId`）。
     * 反射失败（厂商 ROM 改名/隐藏）时**静默返回 false** ⇒ 调用方仍会走 Provider 的
     * 「已停用」空态渲染，最坏结果是内容变灰而不是崩溃。
     */
    private fun deleteIds(mgr: AppWidgetManager, ids: IntArray): Boolean {
        return try {
            val service = Class.forName("android.appwidget.AppWidgetService")
            val smgr = service.getDeclaredMethod("getInstance").invoke(null) ?: return false
            val m = smgr.javaClass.getMethod("deleteAppWidgetId", IntArray::class.java)
            m.invoke(smgr, ids)
            true
        } catch (_: Exception) {
            false
        } catch (_: LinkageError) {
            false
        }
    }

    /** 让两枚小组件立刻重绘（偏好改动后调用；`getAppWidgetIds` 必传，否则 provider 收不到）。 */
    fun notifyWidgets(context: Context) {
        val mgr = AppWidgetManager.getInstance(context)
        for (cls in listOf(
            TodayOverviewWidget::class.java,
            QuickRecordWidget::class.java,
            TodoListWidget::class.java,
            LedgerOverviewWidget::class.java,
        )) {
            val ids = mgr.getAppWidgetIds(ComponentName(context, cls))
            if (ids.isEmpty()) continue
            val i = Intent(context, cls).apply {
                action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
            }
            context.sendBroadcast(i)
        }
    }
}
