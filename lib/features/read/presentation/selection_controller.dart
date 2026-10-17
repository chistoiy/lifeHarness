import 'package:flutter_riverpod/flutter_riverpod.dart';

/// V1.53.2 性能批 1：选区控制器
/// 
/// 独立管理长按选区状态，避免触发全量 rebuild
class SelectionController extends StateNotifier<({int ci, int p0, int p1, int o0, int o1})?> {
  SelectionController() : super(null);

  /// 设置新选区
  void setSelection({required int ci, required int p0, required int p1, required int o0, required int o1}) {
    state = (ci: ci, p0: p0, p1: p1, o0: o0, o1: o1);
  }

  /// 清空选区
  void clear() {
    state = null;
  }

  /// 公开 getter（供外部只读访问，避免 protected member 警告）
  ({int ci, int p0, int p1, int o0, int o1})? get sel => state;

  /// 更新尾端点（扩选）
  void updateTail({required int pi, required int off}) {
    if (state == null) return;
    final s = state!;
    
    if (pi < s.p0 || (pi == s.p0 && off <= s.o0)) {
      // 拖过首端＝互换
      state = (ci: s.ci, p0: pi, p1: s.p0, o0: off, o1: s.o0);
    } else {
      state = (ci: s.ci, p0: s.p0, p1: pi, o0: s.o0, o1: off);
    }
  }

  /// 更新首端点（扩选）
  void updateHead({required int pi, required int off}) {
    if (state == null) return;
    final s = state!;
    
    if (pi > s.p1 || (pi == s.p1 && off >= s.o1)) {
      state = (ci: s.ci, p0: s.p1, p1: pi, o0: s.o1, o1: off);
    } else {
      state = (ci: s.ci, p0: pi, p1: s.p1, o0: off, o1: s.o1);
    }
  }

  bool get isSingleParagraph => state?.p0 == state?.p1;
  int get characterCount => state == null ? 0 : (state!.o1 - state!.o0).abs();
}
