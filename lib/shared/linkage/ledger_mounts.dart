import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../features/ledger/data/ledger_repository.dart';
import '../../features/ledger/domain/ledger_calc.dart';
import '../../features/ledger/presentation/ledger_providers.dart';

/// 记账 → 日程/生成调度 联动挂载点（记账计划 §5 批2「周期生成调度」+
/// §6 L8「周期账单生成 → 续费提醒日程」· 仿 habit_mounts 惯例，R1 守护下
/// 记账/日程两侧不互相 import，统一经本文件编排）。
///
/// 原型真实语义取证（index-ledger.html · recGen/recGenDue/renderFinDue）：
/// - 到期批量生成**不是自动生成**：触发入口 = L1 横幅「去生成 ›」跳 L9 + L9
///   到期横幅内手动「生成」钮（`onclick="recGenDue()"`）；无任何启动/零点
///   自动调用的原型代码 → UI 侧一律按钮手动触发，逐字保留原型 toast 文案。
/// - 「续费提醒日程已同步（L8）」在原型中仅为 toast 文案
///   （`toast('已生成「'+r.n+'」流水 · 续费提醒日程已同步（L8）')`），
///   不真正写 events 表 → 本挂载按同口径占位（文案常量），不建真实日程行。
/// - 计划书 §5 批2 另列「周期生成调度（App 启动/每日零点触发）」：
///   App 启动扫尾 = [ledgerRecurMountProvider]（静默批量生成，等价 quiet 路径）；
///   「每日零点」不挂常驻 Timer（本地 App 跨零点通常已退出进程，下次启动即
///   覆盖；常驻 Timer 亦会破坏全 app widget 测试的 pending-timer 约束），
///   由 [maybeGenerateDue] 提供可注入 now 的纯入口供后续批次/测试接线。

/// 批量生成 toast（原型 recGenDue：``已批量生成 N 笔到期流水（L8 日程联动）``）。
String ledgerRecurBatchGenToast(int n) => '已批量生成 $n 笔到期流水（L8 日程联动）';

/// 单笔生成 + 续费提醒日程占位 toast（原型 recGen 非 quiet 路径文案）。
String ledgerRecurGenToast(String name) =>
    '已生成「$name」流水 · 续费提醒日程已同步（L8）';

/// 可注入的到期批量生成纯入口：当前账本 active 且 next≤today 行 → 统一
/// addTxn 写路径落 source='recurring' 流水并推进 next。返回生成笔数。
Future<int> maybeGenerateDue(LedgerRepository repo, {DateTime? now}) async {
  final today = dayKey(now ?? DateTime.now());
  final bk = await repo.curBookId();
  return repo.genDueRecur(bk, today);
}

/// 应用根部启动扫尾（app.dart watch，仿 habitLinkageProvider）：
/// 数据库未初始化（widget 测试全 app 场景）直接跳过，不触库不挂 Timer。
final ledgerRecurMountProvider = Provider<void>((ref) {
  if (!AppDatabase.instance.isInitialized) return;
  Future(() async {
    try {
      final n = await maybeGenerateDue(ref.read(ledgerRepositoryProvider));
      if (n > 0) ref.read(ledgerTickProvider.notifier).state++;
    } catch (_) {
      // 启动扫尾失败静默（L9 手动「生成」钮兜底，同原型唯一真实路径）。
    }
  });
});
