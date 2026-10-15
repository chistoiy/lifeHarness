package com.lifeharness.lifeharness

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.os.Bundle
import android.view.View
import android.widget.Button
import android.widget.CheckBox

/**
 * 「添加到桌面」配置 Activity（F2-4）· 拖到桌面时可选「显示什么」。
 *
 * Android 对 `android:configure` 的硬要求：
 * ① 从 `EXTRA_APPWIDGET_ID` 取 widget id；② 用户完成时 `setResult(RESULT_OK, intent 带 id)`
 * 并 `finish()`；③ 用户取消时保持 `RESULT_CANCELED`（则该实例不落桌面）。
 *
 * **与设置页共用同一份偏好（F2-4：禁两套）**：直接读写 Flutter 侧 legacy
 * SharedPreferences 文件 `FlutterSharedPreferences` 的 `flutter.desktop.*` 键 ——
 * 与 `SettingsRepository.loadDesktopWidgetSummary/Quick/HideAmount` 是**同一份数据**
 * （文件与键前缀取自 [LhWidget]，两侧常量由 `test/desktop_widget_test.dart` 交叉核对）。
 *
 * **视觉（批3 重做）**：2026-10-15 装机反馈「从 App 被添加的话，弹窗太丑了」。现改成
 * App 内卡片体系——描边圆角卡片 ＋ 1dp 分隔的开关行 ＋ 文字按钮，勾选框自绘圆形
 * （禁系统 Material 方块，见 `res/drawable/lh_cfg_check.xml`）。
 *
 * ⚠ **四枚开关全列**（不按 provider 隐藏）：这些偏好是**全局**的（设置页同一份），
 * 在这里藏掉其中几行，用户会以为「这枚小组件不受这个设置影响」——实际却受。
 * 四行全列＝所见即所得，且每行都能看出「别的入口也管它」。
 */
class WidgetConfigActivity : Activity() {

    private var widgetId: Int = AppWidgetManager.INVALID_APPWIDGET_ID

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // 默认取消：中途返回/被杀 ⇒ 不落桌面（Android 约定）。
        setResult(RESULT_CANCELED)
        widgetId = intent?.getIntExtra(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID,
        ) ?: AppWidgetManager.INVALID_APPWIDGET_ID
        if (widgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }
        setContentView(R.layout.lh_widget_config)

        val prefs = getSharedPreferences(LhWidget.FLUTTER_PREFS, MODE_PRIVATE)

        val cbSummary = findViewById<CheckBox>(R.id.lh_cfg_summary)
        val cbQuick = findViewById<CheckBox>(R.id.lh_cfg_quick)
        val cbTodo = findViewById<CheckBox>(R.id.lh_cfg_todo_list)
        val cbLedger = findViewById<CheckBox>(R.id.lh_cfg_ledger)
        val cbHide = findViewById<CheckBox>(R.id.lh_cfg_hide_amount)

        cbSummary.isChecked = prefs.getBoolean(LhWidget.PREF_WIDGET_SUMMARY, true)
        cbQuick.isChecked = prefs.getBoolean(LhWidget.PREF_WIDGET_QUICK, true)
        cbTodo.isChecked = prefs.getBoolean(LhWidget.PREF_WIDGET_TODO_LIST, true)
        cbLedger.isChecked = prefs.getBoolean(LhWidget.PREF_WIDGET_LEDGER, true)
        cbHide.isChecked = prefs.getBoolean(LhWidget.PREF_HIDE_AMOUNT, false)

        // 本枚的标题换成「正在配置哪一枚」，免得用户在四行里找自己那枚。
        findViewById<android.widget.TextView>(R.id.lh_cfg_title).text =
            getString(R.string.lh_widget_cfg_title_of, providerName())

        findViewById<Button>(R.id.lh_cfg_cancel).setOnClickListener { finish() }
        findViewById<Button>(R.id.lh_cfg_ok).setOnClickListener {
            // 写回**同一份**偏好（设置页下次进入即读到；App 存活时进程内实例同源）。
            prefs.edit()
                .putBoolean(LhWidget.PREF_WIDGET_SUMMARY, cbSummary.isChecked)
                .putBoolean(LhWidget.PREF_WIDGET_QUICK, cbQuick.isChecked)
                .putBoolean(LhWidget.PREF_WIDGET_TODO_LIST, cbTodo.isChecked)
                .putBoolean(LhWidget.PREF_WIDGET_LEDGER, cbLedger.isChecked)
                .putBoolean(LhWidget.PREF_HIDE_AMOUNT, cbHide.isChecked)
                .commit()
            // ⚠ 光重绘不够：若用户顺手关掉了**本枚**，桌面实例得真消失，
            // 否则就是「弹窗里说关了、桌面上还亮着」（死开关的第三种形态）。
            LhWidget.applyEnabledFlags(this)
            LhWidget.notifyWidgets(this)
            setResult(
                RESULT_OK,
                Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId),
            )
            finish()
        }
    }

    /** 本实例的中文名（据 provider 类名判定；取不到按概览处理）。 */
    private fun providerName(): String {
        val cls = try {
            AppWidgetManager.getInstance(this).getAppWidgetInfo(widgetId)
                ?.provider?.className?.substringAfterLast('.') ?: LhWidget.PROVIDER_OVERVIEW
        } catch (_: Exception) {
            LhWidget.PROVIDER_OVERVIEW
        }
        return when (cls) {
            LhWidget.PROVIDER_TODO_LIST -> getString(R.string.lh_widget_todo_name)
            LhWidget.PROVIDER_LEDGER -> getString(R.string.lh_widget_ledger_name)
            LhWidget.PROVIDER_QUICK -> getString(R.string.lh_widget_quick_name)
            else -> getString(R.string.lh_widget_overview_name)
        }
    }
}
