import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// T2-B（交互整改批一）·主屏滚动垫。
///
/// 为什么不用 PageStorageKey：PageStorageBucket 挂在每条 ModalRoute 上
/// （framework routes.dart `_storageBucket`），切栏即销毁旧子路由＝连桶一起丢，
/// PageStorageKey 跨不了路由。改用 app 常驻 provider 记滚动位，
/// 下次进屏以 initialScrollOffset 复原——判据等价（切回保留滚动），逐页可退。
///
/// 用法：把长列表（或其所在容器）包进 [ScrollPad]，子树内**未显式挂 controller**
/// 的纵向滚动视图经 PrimaryScrollController 自动吃到垫位控制器；
/// 横向/自带 controller 的嵌套列表不受影响。
final scrollPadProvider = StateProvider.family<double, String>((ref, id) => 0);

class ScrollPad extends ConsumerStatefulWidget {
  const ScrollPad({super.key, required this.id, required this.child});

  final String id;
  final Widget child;

  @override
  ConsumerState<ScrollPad> createState() => _ScrollPadState();
}

class _ScrollPadState extends ConsumerState<ScrollPad> {
  late final ScrollController _c =
      ScrollController(initialScrollOffset: ref.read(scrollPadProvider(widget.id)));

  @override
  void initState() {
    super.initState();
    _c.addListener(_save);
  }

  void _save() {
    if (!_c.hasClients) return;
    // 只写常驻槽位，不 watch——滚动不触发任何重建。
    ref.read(scrollPadProvider(widget.id).notifier).state = _c.offset;
  }

  @override
  Widget build(BuildContext context) =>
      PrimaryScrollController(controller: _c, child: widget.child);

  @override
  void dispose() {
    _c.removeListener(_save);
    _c.dispose();
    super.dispose();
  }
}
