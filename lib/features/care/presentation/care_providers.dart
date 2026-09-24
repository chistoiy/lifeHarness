import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../data/care_repository.dart';
import '../domain/care_models.dart';

/// 呵护模块 providers（仿 ledger/habit 范式：写库后 careTick++ 全量重取快照）。

final careRepositoryProvider = Provider<CareRepository>(
  (ref) => CareRepository(AppDatabase.instance.db),
);

final careTickProvider = StateProvider<int>((ref) => 0);

/// 一帧呵护域数据（两顶层视图与全部弹层共用；watch tick 失效重取）。
final careDataProvider = FutureProvider<CareData>((ref) {
  ref.watch(careTickProvider);
  return ref.watch(careRepositoryProvider).loadAll();
});

/// 顶层视图互切：'cycle'（她·周期）| 'baby'（宝宝）。
/// 红线 2：同一路由 /care 内切换，不走路由堆栈；退出走底部导航。
final careViewProvider = StateProvider<String>((ref) => 'cycle');

/// 写库后的统一失效触发（同 ledgerTouch 先例）。
void careTouch(WidgetRef ref) =>
    ref.read(careTickProvider.notifier).state++;

/// Notifier 内使用的同名助手。
void careTouchRef(Ref ref) => ref.read(careTickProvider.notifier).state++;

/// 全天记录页事件类型多选筛选（bdKinds 同构；页面级共享，跨导航保留）。
final careDayFilterProvider = StateProvider<Set<String>>((ref) => const {});

/// 悬浮/卡内计时状态（startTimer/endFeed 同构；结束自动入账）。
class FeedTimerState {
  const FeedTimerState({
    required this.kind,
    required this.t0,
    required this.startHHMM,
    this.side,
    this.swapMin,
  });

  final String kind;
  final DateTime t0;
  final String startHHMM;

  /// 亲喂换边侧（'左'|'右'|null=未换过）。
  final String? side;
  final int? swapMin;

  FeedTimerState copyWith({String? side, int? swapMin}) =>
      FeedTimerState(
          kind: kind, t0: t0, startHHMM: startHHMM, side: side ?? this.side, swapMin: swapMin ?? this.swapMin);
}

class FeedTimerNotifier extends Notifier<FeedTimerState?> {
  @override
  FeedTimerState? build() => null;

  void start(String kind) {
    final n = DateTime.now();
    state = FeedTimerState(
      kind: kind,
      t0: n,
      startHHMM:
          '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}',
    );
  }

  /// 换边：记录当前累计分钟并翻转侧。
  void swap() {
    final s = state;
    if (s == null) return;
    final mins = DateTime.now().difference(s.t0).inMinutes;
    final next = s.side == '左' ? '右' : '左';
    state = s.copyWith(side: next, swapMin: mins);
  }

  /// 结束并入账（返回入账记录；亲喂按换边点拆 seg）。
  Future<CareRecord?> stop() async {
    final s = state;
    if (s == null) return null;
    final now = DateTime.now();
    final mins =
        now.difference(s.t0).inSeconds ~/ 60 == 0 ? 1 : now.difference(s.t0).inSeconds ~/ 60;
    final d = await ref.read(careDataProvider.future);
    final e =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    String? seg;
    if (s.kind == 'nurse' && s.swapMin != null) {
      final l = s.side == '左' ? s.swapMin! : mins - s.swapMin!;
      seg = '左${l.clamp(0, mins)}′/右${(mins - l).clamp(0, mins)}′';
    }
    final r = CareRecord(
      babyId: d.currentBaby?.id ?? 0,
      day: careDayKey(now),
      k: s.kind,
      s: s.startHHMM,
      e: e,
      dur: mins,
      seg: seg,
      rec: d.curCarer,
    );
    state = null;
    if (r.babyId == 0) return r; // 无档案时不入账（UI 层守卫）
    await ref.read(careRepositoryProvider).addLog(r);
    careTouchRef(ref);
    return r;
  }
}

final feedTimerProvider =
    NotifierProvider<FeedTimerNotifier, FeedTimerState?>(FeedTimerNotifier.new);

