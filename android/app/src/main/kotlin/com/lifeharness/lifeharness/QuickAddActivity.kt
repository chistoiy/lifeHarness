package com.lifeharness.lifeharness

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.TransparencyMode

/**
 * 4×1「记一笔」弹窗（工单 §7.1 · 2026-10-18 产品拍板 A 路 · 拍板件 §五 首选路②）。
 *
 * ## 它是什么
 *
 * 点桌面上 4×1 小组件的「记一笔」，浮起一个**对话框主题的 Activity**，里面嵌一棵
 * Flutter 视图渲染记账页「记一笔」的**同一份表单**（四类型 tab／分类行／子类 chips／
 * 四则键盘）。保存交 Dart 写库（与 App 内同一出口），关掉即走。
 *
 * ## 为什么不是 App 内的一个页面
 *
 * 产品的原话是「不要打开 app」——用户感知是：不起全屏、不进最近任务。所以这里
 * ① 独立 affinity（不归并主任务，不会把 App 的栈一并拉到前台）；
 * ② `excludeFromRecents`＋`noHistory`（最近任务里不留痕、离开即销毁）；
 * ③ `singleTask`（连点两下不会叠两个对话框）。
 *
 * ## 为什么要 override 入口点
 *
 * 默认入口是 `main()`——那会把整棵 App（路由、通知重排、备份服务）全初始化一遍，
 * 而这里只需要「prefs → 开库 → 主题令牌」三件事。Dart 侧对应
 * `main.dart` 的 `widgetQuickAddMain`（带 `@pragma('vm:entry-point')`，否则
 * release 树摇后全仓无静态引用，真机表现是「点了没反应」）。
 *
 * ## 软键盘
 *
 * `adjustResize` 在**浮动窗口**上不生效（系统限制），所以主题里显式
 * `windowIsFloating=false` 全屏铺开、由 Flutter 侧自己居中收边；这里再设一次
 * `setSoftInputMode` 兜底。真机门四项之一就是「软键盘不遮挡保存键」。
 */
class QuickAddActivity : FlutterActivity() {

    override fun getDartEntrypointFunctionName(): String = ENTRYPOINT

    /**
     * **必须透明**（2026-10-18 真机报障「背景全黑、不是桌面」根因）。
     *
     * `FlutterActivity` 默认 `TransparencyMode.opaque`：引擎的渲染面**不透明**，
     * Flutter 侧哪怕把 `Scaffold` 刷成 `Colors.transparent` 也没用——那只是「不画」，
     * 露出来的是不透明渲染面的底色（黑）。主题里的 `windowBackground=transparent`
     * ＋`windowIsTranslucent` 只解决**窗口**层，管不到**渲染面**这一层。
     *
     * 改成 `transparent` 后，窗口与渲染面都让位，背后就是桌面本身；压暗由主题的
     * `backgroundDimAmount=0.45` 负责——观感与原型 `.qp-mask` 一致：桌面透出来、
     * 卡片浮在上面。
     */
    override fun getTransparencyMode(): TransparencyMode = TransparencyMode.transparent

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // 软键盘顶起内容而不是盖住键盘下方那一排键（真机门第 1 项）。
        window.setSoftInputMode(
            WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE,
        )
    }

    companion object {
        /**
         * Dart 入口点名（`main.dart` 顶层 `widgetQuickAddMain`）。
         * ⚠ 两侧字面量由 `test/widget_quick_add_test.dart` 交叉核对，改名必须同改。
         */
        const val ENTRYPOINT = "widgetQuickAddMain"
    }
}
