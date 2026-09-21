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
