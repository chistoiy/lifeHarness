import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';

/// V1.28⑥ 主页卡片自由编排状态（壳层返回键拦截的单一点）：
/// null=未编排；非 null=编排中的顺序工作副本（「✓ 完成」或返回键才落 settings）。
class DashEditor extends Notifier<List<String>?> {
  @override
  List<String>? build() => null;

  void enter(List<String> order) => state = order;

  void set(List<String> order) => state = order;

  /// 退出编排 = 工作副本落 settings 并清空（✓ 按钮与系统返回键共用）。
  /// 返回是否实际发生了保存。
  bool commit() {
    final draft = state;
    if (draft == null) return false;
    ref.read(settingsControllerProvider.notifier).setHomeOrder(draft);
    state = null;
    return true;
  }
}

final dashDraftProvider =
    NotifierProvider<DashEditor, List<String>?>(DashEditor.new);

/// UIUX批（2026-10-12）：FAB 快捷记录菜单开态。提升为 provider 的唯一原因＝
/// 壳层返回键要读（shellBackAction 优先级最高：菜单开着按返回＝收菜单，不退栈）。
/// 单一状态源在本 provider，页面不再持有同名 setState 字段（旧实现无遮罩、
/// 返回键直接退 app＝收不掉）。
class DashFabOpen extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;

  void close() => state = false;
}

final dashFabOpenProvider = NotifierProvider<DashFabOpen, bool>(DashFabOpen.new);
