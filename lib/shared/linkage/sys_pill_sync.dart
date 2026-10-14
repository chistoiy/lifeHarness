/// 批B 同步器（工单 悬浮胶囊增强批-20261014 §7）：把 app 内计时会话推给
/// 原生系统悬浮窗（app 外显示）。悬浮窗「■ 结束」事件的消费在组合根
/// （app.dart：resumed＋首帧两探点——事件必随意图拉起 app 前台，两处覆盖
/// 冷/热启动），结束路径与 app 内胶囊钮共用
/// [endReadPillTimer]/[endMediaPillTimer]（单源）。
///
/// 驱动＝秒级 ticker（[calendarTickerProvider]）——与 app 内胶囊同源心跳；
/// 决策＝纯函数 [sysPillTarget]（pill_overlay.dart）；动作＝`lh/pill` 通道。
///
/// 服务生命周期口径（Android 14+ 后台禁起 FGS）：
/// - **起服务只发生在 app 前台**（会话开跑/开功能/冷启动都在前台）；
/// - 退后台后只更新/收视图，服务已在跑则继续保活；
/// - 会话结束或功能关闭 → stop（stopService 不受后台启动限制）。
/// - 无权限/被撤 → 完全降级（不保活，仅 app 内胶囊）。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ai/ai_review.dart' show aiRootNavKey;
import '../../core/platform/pill_overlay.dart';
import '../../features/calendar/presentation/calendar_providers.dart'
    show calendarTickerProvider;
import '../../features/media/presentation/media_actions.dart'
    show mediaTimerWord;
import '../../features/media/presentation/media_providers.dart'
    show mediaItemDetailProvider, mediaRunningSessionProvider, mediaTickProvider;
import '../../features/read/presentation/read_providers.dart'
    show booksProvider, readKvProvider, readTickProvider, readerOpenProvider,
        runningSessionProvider;
import 'timer_bar_overlay.dart' show endMediaPillTimer, endReadPillTimer;

/// app 是否在前台（系统悬浮窗在 app 前台时隐藏——免与 app 内胶囊重复；
/// 由根 Widget 的生命周期回调维护，默认真）。
final sysPillAppActiveProvider = StateProvider<bool>((_) => true);

/// 系统悬浮窗功能开关（read.sysPill，默认关·设置页「系统悬浮窗」行）。
final sysPillOnProvider = FutureProvider<bool>((ref) async =>
    (await ref.watch(readKvProvider(('read.sysPill', 'false')).future)) ==
    'true');

/// 已推送签名（隐藏态不含秒——免去隐藏期间每秒空推）与服务在跑备忘。
/// 模块级：跨 tick 去重，仅本文件写。
String? _lastSig;
bool _serviceOn = false;

/// 悬浮窗一次性事件消费（■结束）：按在跑会话现算结束哪条（read 优先），
/// 提示/弹层挂根 Navigator（R14 护栏同源）。异常不回流 tick 循环。
Future<void> drainPillEvents(WidgetRef ref) async {
  final SysPillEvent? ev = await takePillEvent();
  if (ev == null || ev.type != 'end') return;
  final navCtx = aiRootNavKey.value?.currentState?.context;
  if (navCtx == null || !navCtx.mounted) return;
  try {
    final readS = ref.read(runningSessionProvider).valueOrNull;
    if (readS != null) {
      await endReadPillTimer(navCtx, ref, readS.bookId);
      return;
    }
    final mediaS = ref.read(mediaRunningSessionProvider).valueOrNull;
    if (mediaS != null) {
      await endMediaPillTimer(navCtx, ref, mediaS.itemId);
    }
  } catch (_) {
    // catch-ok: 会话已落库，UI 侧（toast/弹层）失败不回流。
  }
}

/// 同步器主体：被 [sysPillSyncMount]／根 Widget 以 listenManual 保活，
/// 依赖变化（含每秒 tick）即重算；UI 零重建。
final sysPillSyncProvider = FutureProvider<void>((ref) async {
  ref.watch(calendarTickerProvider); // 秒级心跳（与 app 内胶囊共用流）
  ref.watch(readTickProvider);
  ref.watch(mediaTickProvider);
  final appActive = ref.watch(sysPillAppActiveProvider);

  final sysPillOn =
      (await ref.watch(readKvProvider(('read.sysPill', 'false')).future)) ==
          'true';
  if (!sysPillOn) {
    if (_serviceOn) {
      await sysPillStop();
      _serviceOn = false;
      _lastSig = null;
    }
    return;
  }

  final readS = await ref.watch(runningSessionProvider.future);
  final mediaS = await ref.watch(mediaRunningSessionProvider.future);
  final sessionOn = readS != null || mediaS != null;
  if (!sessionOn) {
    if (_serviceOn) {
      await sysPillStop();
      _serviceOn = false;
      _lastSig = null;
    }
    return;
  }

  // 无权限（含被撤）＝完全降级：不保活，仅 app 内胶囊。
  final canDraw = await sysPillCanDraw();
  if (!canDraw) {
    if (_serviceOn) {
      await sysPillStop();
      _serviceOn = false;
      _lastSig = null;
    }
    return;
  }

  final readerOpen = ref.watch(readerOpenProvider) > 0;
  final target = sysPillTarget(
    sysPillOn: sysPillOn,
    canDraw: canDraw,
    appActive: appActive,
    readerOpen: readerOpen,
    readRunning: readS != null,
    mediaRunning: mediaS != null,
  );
  final visible = target != SysPillTarget.none;

  // 后台不冷起服务（Android 14+ FGS 限制）：不在跑且 app 不在前台 → 等回前台。
  if (!_serviceOn && !appActive) return;

  // 载荷总是取在跑会话（read 优先）——隐藏态也照推（通知文案用）。
  final SysPillState state;
  if (readS != null) {
    final books = ref.watch(booksProvider).valueOrNull ?? const [];
    final title =
        books.where((b) => b.id == readS.bookId).firstOrNull?.title ?? '阅读';
    final elapsed = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(readS.startedAt));
    state = SysPillState(
      kind: 'read',
      title: title,
      status: '阅读中',
      seconds: elapsed.inSeconds,
    );
  } else {
    final item = await ref.watch(mediaItemDetailProvider(mediaS!.itemId).future);
    final elapsed = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(mediaS.startedAt));
    state = SysPillState(
      kind: 'media',
      title: item?.title ?? '影音',
      status: mediaTimerWord(mediaS.kind),
      seconds: elapsed.inSeconds,
    );
  }

  final sig = visible
      ? 'v:${state.kind}:${state.title}:${state.status}:${state.seconds}'
      : 'h:${state.kind}:${state.title}:${state.status}';
  if (sig != _lastSig) {
    await sysPillSync(state, visible);
    _serviceOn = true;
    _lastSig = sig;
  }
  // 事件消费不在同步器内：WidgetRef 与 FutureProviderRef 是两套层级
  // （riverpod 2.6.1），消费点在组合根 app.dart（resumed＋首帧两探点）。
});
