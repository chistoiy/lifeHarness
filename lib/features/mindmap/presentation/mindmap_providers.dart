import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 导图域写信号（回收站第九类 `signals` 挂这里；列表页动作后也 invalidate 它）。
/// int tick：增删改图/恢复/到期清理各 +1。
final mindmapTickProvider = StateProvider<int>((ref) => 0);
