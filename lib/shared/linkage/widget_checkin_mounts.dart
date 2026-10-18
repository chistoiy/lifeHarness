/// 小组件模块 批A · 打卡交互闭环挂载点（工单 §2 交互闭环层 · 评估件 §4.1/§4.2）。
///
/// **为什么在 shared/linkage**：本文件是「原生广播直达 → 后台 isolate 跑 Dart
/// → 同源仓库出口」三段链的中段，要同时碰 features/habit（写库）与 core
/// （快照桥）；R1 守护下 features/widget 不得 import 其他 feature，故编排落
/// 共享层（与 habit_mounts/nfc_mounts 同惯例）。
///
/// **三态回显口径**（评估件 §4.2·产品 2026-10-17 勾定）：
///  · 点击瞬间：原生**乐观回显**（画成已打卡，按钮意图撤掉）——isolate 冷启动
///    几百 ms~1s+ 的延迟由它盖住；
///  · 后台成功：本文件把习惯三键推回快照并重绘（**收敛**到真值）；
///  · 后台失败/超时：原生**回滚**显示态并入待排空队列（原生侧 `enqueuePendingCheck`），
///    App 下次启动由 [drainPendingWidgetChecks] 补写——**闭环最终一致**。
///
/// **后台 isolate 纪律（B8）**：本文件不 import 任何 Flutter/UI 依赖，不建
/// riverpod 容器——入口 `widgetBackgroundMain`（lib/main.dart）跑在无头引擎的
/// 独立 isolate 里，只开库、写库、推快照。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart' show Database;

import '../../core/database/app_database.dart';
import '../../core/platform/desktop_widget.dart';
import '../../core/providers.dart';
import '../../features/habit/data/habit_repository.dart';
import '../../features/habit/presentation/habit_providers.dart' show HabitData;
import 'habit_mounts.dart' show HabitCheckOutcome, habitCheckinWrite;
import 'desktop_widget_mounts.dart'
    show desktopWidgetKickProvider, habitDueCounts, widgetHabitItems;

/// 待排空队列的键（原生 `LhWidget.PREF_PENDING_CHECKS` 逐字一致·守护测试交叉核对）。
///
/// 与待办勾圈的 `desktop.widget_pending_toggles` 同族：原生广播写库失败时把
/// **习惯名**存进来，App 下次启动排空补写（打卡是幂等写，重复补无害）。
const String kWidgetPendingChecksKey = 'desktop.widget_pending_checks';

/// 队列条目分隔符（与待办行/绑定值同族控制字符）。
///
/// ⚠ 习惯名可能含逗号/顿号（「喝水, 运动」）——逗号分隔会把一条切成两条，
/// 故不用逗号；控制字符在名称编码链里本就要剔除（`encodeWidgetHabitItems` 同口径）。
const String kWidgetCheckSep = '\u001e';

/// 按**习惯名**打卡（小组件后台 isolate 出口·评估件 §4.1）。
///
/// 为什么按名而不是按 id：widget 进程只拿得到绑定里的 `sub`＝习惯名（C5：
/// 禁直读 sqlite，id 在库里）。写库口径与 NFC 贴卡/App 内手动打卡**同一实现**
/// （[habitCheckinWrite]）——禁在原生或此处复刻一份 upsert（行为分叉）。
///
/// 返回 null ＝ 未归档习惯里查不到这个名字（被删/改名/归档）⇒ 调用方按失败
/// 处理（原生回滚并入队，排空时再判一次仍是 null 就清掉死条目）。
Future<HabitCheckOutcome?> widgetCheckinByName(
  String name, {
  Database? db,
  DateTime? now,
}) async {
  final n = name.trim();
  if (n.isEmpty) return null;
  final repo = HabitRepository(db ?? AppDatabase.instance.db);
  final habits = await repo.allHabits();
  // 只认**未归档**：快照表（`habit_items`）本来就只有未归档习惯（＝`book`），
  // 绑着归档习惯的实例在桌面上显示「内容已失效」，按钮根本不渲染 ⇒ 这里也不该写。
  final hit = habits.where((h) => !h.isArchived && h.name == n).toList();
  if (hit.isEmpty) return null;
  return habitCheckinWrite(repo, hit.first, now: now);
}

/// 后台 isolate 的一条龙：写库 → 推习惯三键 → 收敛重绘。
///
/// 返回 false ＝ 这一趟没办成（原生收到 false 后回滚显示态并入队）。
/// **任何异常都吞掉返回 false**：后台 isolate 崩了没人兜，且写库本身是原子的
/// （成功一半不存在——sqflite 事务要么落要么滚）。
Future<bool> runWidgetHabitCheckin(String name) async {
  final n = name.trim();
  if (n.isEmpty) return false;
  try {
    if (!AppDatabase.instance.isInitialized) {
      await AppDatabase.instance.open();
    }
    final now = DateTime.now();
    final out = await widgetCheckinByName(n, now: now);
    if (out == null) return false;
    final repo = HabitRepository(AppDatabase.instance.db);
    final data = await _loadHabitData(repo);
    final (done, total) = habitDueCounts(data, now);
    await pushWidgetHabitSnapshot(
      items: widgetHabitItems(data, now),
      done: done,
      total: total,
    );
    return true;
  } catch (_) {
    // catch-ok: 后台静默失败——原生入队兜底，App 启动排空。
    return false;
  }
}

/// 轻量 [HabitData]（只取习惯域两读：habits＋entries）。
///
/// 后台 isolate 没有 riverpod 容器，也不该为一个桌面按键把偏好/宽限/待确认
/// 全量取齐——`dueToday/okOn/streak` 只用得到 habits＋entries，其余字段给
/// 中性默认值（**不参与本文件任何计算**，故不可能因缺字段算错）。
Future<HabitData> _loadHabitData(HabitRepository repo) async {
  return HabitData(
    habits: await repo.allHabits(),
    entries: await repo.entriesByHabit(),
    cats: const [],
    units: const [],
    view: 'list',
    seg: 'all',
    catF: '全部',
    weekStart: 0,
    spanFromStart: true,
    rateByTotalDays: false,
    grace: 1,
    graceOf: const {},
    autoMode: 0,
    pends: const [],
    bfTotal: 0,
  );
}

/// 排空「打卡没能当场写成的习惯名」（批A 交互闭环层·App 启动时调）。
///
/// 来由同 [drainPendingWidgetToggles]（待办勾圈）：原生广播直达写库可能失败
/// （App 没起过/库被占/isolate 冷启动超时），失败的名字进
/// [kWidgetPendingChecksKey]，App 起来（库已开）后补写。
///
/// 幂等：`upsertEntry` 对已打卡者是 no-op；**逐名补写、逐名移除**——中途
/// 进程死掉不丢剩下的条目（下次启动接着排）。查不到习惯（已删/归档）的死
/// 条目也移除：重试一万次也不会活过来。
Future<void> drainPendingWidgetChecks(Ref ref) async {
  if (!AppDatabase.instance.isInitialized) return;
  final repo = ref.read(settingsRepositoryProvider);
  final names = repo.loadDesktopPendingChecks();
  if (names.isEmpty) return;
  for (final name in names) {
    try {
      await widgetCheckinByName(name);
    } catch (_) {
      // catch-ok: 这条没写成 ⇒ 留在队列里，下次启动再试（闭环不丢）。
      continue;
    }
    await repo.removeDesktopPendingCheck(name);
  }
  // 补写完踢一脚：让 App 侧三源快照整包重推一次（收敛 habit_done/total 等计数）。
  ref.read(desktopWidgetKickProvider.notifier).state++;
}
