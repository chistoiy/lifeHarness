/// 小组件模块 批A · 设置页入口挂载点（工单 §2 配置页层 · 评估件 §2.3 层4）。
///
/// 规格＝`docs/handoff/小组件模块-批A按实例绑定与打卡试点.md` §2／§6「先选后落」四步：
/// ① 设置页「添加小组件」→ ② 开共享五段选择（打卡段预开）→ ③ `requestPinAppWidget`
/// 系统确认（取消则不落桌面）→ ④ 配置页读预选绑定无感回写 → 落桌面。
///
/// **为什么在这里而不是设置页里**：R1 守护下 `features/settings` 不得 import
/// `features/widget`（跨模块只经 `shared/linkage`）。本文件是设置页能看见小组件能力的
/// **唯一出口**——设置页只拿到「选了哪一项」的人话标签，不接触目标模型、不碰绑定键。
///
/// 第④步（无感回写）在原生侧：`WidgetConfigActivity.onCreate` 读到预选绑定即写本实例键、
/// 清预选、直接 `RESULT_OK` 收摊（用户看不到配置页）。Dart 侧不参与。
library;

import 'package:flutter/widgets.dart';
import 'package:home_widget/home_widget.dart' show HomeWidget;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' show Database;

import '../../core/platform/desktop_shortcuts.dart' show pinDesktopWidget;
import '../../core/platform/desktop_widget.dart' show LhWidgetNames;
import '../../features/widget/data/widget_binding_store.dart';
import '../../features/widget/domain/widget_binding.dart'
    show kWidgetKindHabit, WidgetTarget;
import '../../features/widget/presentation/widget_target_picker.dart'
    show showWidgetTargetPicker, widgetTargetLabel, WidgetPickerMode;

/// 设置页「添加小组件」（批A 试点＝打卡-单习惯 2×2）：开选择器 → 落预选 → 请系统 pin。
///
/// 返回 null＝**用户在选择器里取消**：不落预选、不调 pin（原型步③「取消则不落桌面」）。
/// 否则返回所选目标的人话标签（如 `打卡 · 早起`），调用点直接拿去提示。
///
/// ⚠ 系统那个「是否添加到主屏幕」弹窗由桌面进程画，App 拿不到它的结果；
/// 用户在那里取消时预选会留在交接位，靠 [kWidgetBindPendingTtlMs] 过期作废
/// （见域层注释：不设期限就会被下一次随手拖出的别的枚误吃）。
///
/// [db]＝测试注入缝（不传走 `AppDatabase.instance.db`·与 `showWidgetTargetPicker` 同口径）。
Future<String?> addHabitWidgetFromSettings(
  BuildContext context,
  SharedPreferences prefs, {
  Database? db,
}) async {
  final picked = await showWidgetTargetPicker(
    context,
    mode: WidgetPickerMode.widget,
    // 打卡段预开：批A 试点就这一枚，别让用户先找区（原型步2「开五段选择（打卡段）」）。
    initialTab: 'habit',
    db: db,
  );
  if (picked == null) return null;
  final store = WidgetBindingStore(prefs);
  await store.setPendingTarget(kWidgetKindHabit, picked);
  // 2026-10-18 真机报障修（「到桌面后打卡里面没有打卡内容」）：先选后落的第④步
  // 「配置页无感回写」依赖系统在 pin 成功后拉起 `android:configure` —— **MIUI 桌面
  // 实测不拉**，于是选完等于没选，新实例一落地就是「未选择内容」。
  //
  // 故落点补一道**默认绑定回落**（R2 那个键，语义从「只给老实例」扩成
  // 「最近一次选择的回落」）：实例有自己的绑定键就用它；没有就显示这次选的。
  // 与原生侧 `HabitCheckWidget.resolveBinding` 的「实例自认领交接位」是**两条独立
  // 兜底**——谁先到谁生效，都幂等。
  await store.setGlobalDefault(picked);
  await pinDesktopWidget(kWidgetKindHabit);
  // 已经在桌面上的未绑定枚不会自己重绘（等下一次快照推送）——选完当场推一把，
  // 用户「选了 → 桌面立刻显示该习惯」闭环。桌面上没有这一枚时是空操作。
  //
  // 重绘是**锦上添花**：通道不可用（非 Android／测试环境／宿主拒绝广播）不该
  // 让「已经选好并落盘」这件事报错回滚——绑定与 pin 都已完成，失败只影响
  // 「什么时候看见」，下一次快照推送自会收敛。
  try {
    await HomeWidget.updateWidget(androidName: LhWidgetNames.habitCheck);
  } catch (_) {
    // catch-ok: 见上——重绘失败不影响已完成的绑定与 pin。
  }
  return widgetTargetLabel(picked);
}

/// 预选绑定的目标（未过期才算；种类不匹配／已过期／脏值 ⇒ null）。
///
/// 设置页回显「上次选的目标」与排障用；**不写**任何东西。
WidgetTarget? stagedHabitWidgetTarget(
  SharedPreferences prefs, {
  int? nowMs,
}) =>
    WidgetBindingStore(prefs).pendingBindFor(kWidgetKindHabit, nowMs: nowMs)?.target;

/// 预选绑定的人话标签（无预选 ⇒ null）。
String? stagedHabitWidgetLabel(SharedPreferences prefs, {int? nowMs}) {
  final t = stagedHabitWidgetTarget(prefs, nowMs: nowMs);
  return t == null ? null : widgetTargetLabel(t);
}
