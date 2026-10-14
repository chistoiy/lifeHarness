import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/calendar/presentation/calendar_providers.dart'
    show calendarTickerProvider;
import '../../features/media/data/media_repo_session.dart';
import '../../features/media/presentation/media_actions.dart'
    show refreshTimeAfterMediaSession;
import '../../features/media/presentation/media_progress_sheet.dart'
    show showMediaProgressSheet;
import '../../features/media/presentation/media_providers.dart';
import '../../features/read/presentation/read_providers.dart';
import '../../features/read/presentation/read_sheets.dart'
    show readToast, showProgressSheet, showQuoteEditPage;

/// 悬浮条落点（相对壳内容顶）＝安全区 + 8（**贴状态栏下悬浮**）。
///
/// 真机口径修正（产品 2026-10-14）：旧值 60＝「让过页面自带顶栏」，条被顶到
/// 页面标题下方且内容垫掉 104px，观感＝「胶囊占据顶部一块地」。改贴顶悬浮：
/// 条浮在状态栏正下（叠在页面顶栏区上方），内容只让出条高（F2-5 预留保留）。
/// 与 [kTimerBarHeight] 一起构成 F2-5 的占位预留口径。
const double kTimerBarTopOffset = 8;

/// 悬浮条单条内容高（两条并存时另加 [kTimerBarGap] 间距）。
///
/// **44 ＝ 实测渲染高**（`read_f2_nav_test` 现场量）＝
/// 容器上下各 9 内边距 ＋ 行内最高件（「■ 结束」胶囊：上下各 5 内边距 ＋ 11px 文本）。
/// 曾按「11.5px 文本 + 上下各 9」记作 38——**少算 6px**，预留 < 条底时首卡仍被压。
/// 改常量而非改断言。
const double kTimerBarHeight = 44;

/// 悬浮条间距（两条并存时）。
const double kTimerBarGap = 8;

/// 贴边圆圈直径（悬浮胶囊增强批A · 2026-10-14 原型过门口径）。
const double kPillFabSize = 52;

/// 贴边吸附带宽：胶囊拖到距屏幕左/右边缘 ≤ 此值松手 → 折叠成贴边圆圈。
const double kPillEdgeSnap = 24;

/// 折叠态（圆圈⇄胶囊）＝**会话内内存态**（跨页保持，跨进程不保持——
/// 重开 app 回胶囊形态，位置仍按 kv 恢复）。两态互斥由 [pillShow] 保证。
final readPillFoldedProvider = StateProvider<bool>((_) => false);
final mediaPillFoldedProvider = StateProvider<bool>((_) => false);

/// 胶囊形态**恒为紧凑**（呼吸点＋时长＋动作钮），不显书名。
///
/// 产品口径 2026-10-14（真机反馈）：旧「点时间展宽显《书名》」形态在靠右时
/// 右半截被屏边裁掉（＋笔记/■结束看不见），且书名属冗余信息——**整条去掉**。
/// 原 `readPillLabelOnProvider`/`mediaPillLabelOnProvider` 两态开关已删除；
/// 胶囊宽度自此恒定，贴边夹取口径唯一（见 [_TimerPillState._barW]）。

/// 展开落点覆盖（点圆圈展开时「接住圆圈处」）：内存态，仅到下次拖动/折叠前生效。
final readPillBarSpotProvider = StateProvider<Offset?>((_) => null);
final mediaPillBarSpotProvider = StateProvider<Offset?>((_) => null);

String _two(int v) => v.toString().padLeft(2, '0');

/// 胶囊时长：`m:ss`，满 1 小时升 `h:mm:ss`（批A C5 · 等宽字形由样式挂
/// tabularFigures，与原型 `fmtPillSec` 同口径）；「■ 结束」结算仍按分钟。
String pillFmtHMS(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  return h > 0 ? '$h:${_two(m)}:${_two(s)}' : '${d.inMinutes}:${_two(s)}';
}

/// 圆圈时长：`m:ss`，满 1 小时降为 `h:mm`（52px 圈面只保时与分，同原型）。
String pillFabFmt(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60;
  return h > 0 ? '$h:${_two(m)}' : '${d.inMinutes}:${_two(d.inSeconds % 60)}';
}

/// ■结束（批A 胶囊钮与批B 系统悬浮窗事件共用同一结束路径·单源）：
/// 结束会话 → tick 失效 → toast → autoAsk 记进度弹层。
/// host＝提示/弹层挂载上下文（批B 走根 Navigator，与 R14 弹层护栏同源；
/// 批A 传胶囊自身 context，行为逐字节不变）。
Future<void> endReadPillTimer(
    BuildContext host, WidgetRef ref, String bookId) async {
  final repo = ref.read(readRepositoryProvider);
  final closed = await repo.endSession(bookId);
  ref.read(readTickProvider.notifier).state++;
  if (!host.mounted) return;
  final books = ref.read(booksProvider).valueOrNull ?? const [];
  final title =
      books.where((b) => b.id == bookId).firstOrNull?.title ?? '阅读';
  readToast(
    host,
    closed == null
        ? '《$title》计时已取消'
        : '《$title》已结束计时 · ${closed.minutes} 分钟',
  );
  if (closed != null &&
      await ref.read(autoAskProvider.future) &&
      host.mounted) {
    final nb = await repo.bookById(bookId);
    if (nb != null && host.mounted) {
      showProgressSheet(host, ref, nb);
    }
  }
}

/// 影音侧同构结束路径（container 现抓——跨弹层/跨页提交的既定坑口径）。
Future<void> endMediaPillTimer(
    BuildContext host, WidgetRef ref, String itemId) async {
  final c = ProviderScope.containerOf(host, listen: false);
  final repo = ref.read(mediaRepositoryProvider);
  final closed = await repo.endSession(itemId);
  refreshTimeAfterMediaSession(c, [closed?.startedAt, closed?.endedAt]);
  ref.read(mediaTickProvider.notifier).state++;
  if (!host.mounted) return;
  final item = await repo.itemById(itemId);
  if (!host.mounted) return;
  final title = item?.title ?? '影音';
  readToast(
    host,
    closed == null
        ? '《$title》计时已取消'
        : '《$title》已结束计时 · ${closed.minutes} 分钟',
  );
  if (closed != null &&
      await ref.read(mediaAutoAskProvider.future) &&
      host.mounted) {
    final ni = await repo.itemById(itemId);
    if (ni != null && host.mounted) {
      showMediaProgressSheet(host, ref, ni, sessionMinutes: closed.minutes);
    }
  }
}

Offset? _parseXY(String raw) {
  final p = raw.split(',');
  if (p.length != 2) return null;
  final x = double.tryParse(p[0]), y = double.tryParse(p[1]);
  if (x == null || y == null) return null;
  return Offset(x, y);
}

/// 悬浮计时条（需求 V1.11/V1.12 · M0 基础设施）：
/// B10（2026-10-13 裁决）起旧 events 表已退役，**进行中事项条随表退役**——
/// 「计时中」唯一源=时间块（V1.52），轴视图卡内结束；本壳只承载
/// 读书长胶囊（read.timerUI）与影音计时条（media.floatBar/media.timerUI=capsule）。
///
/// **产品改口（2026-10-14，真机回知两轮）**：胶囊是**纯悬浮**——叠在页面内容
/// 之上、内容**零让位**（不再给页面垫顶，旧 F2-5「预留等量空间」口径废弃；
/// 原型 `timerBarSpace` 同步作废）。条浮在状态栏正下（top+8），压住页面标题带
/// 上沿属设计内（悬浮件本来就在内容 Z 序之上）。
///
/// **批A（悬浮胶囊增强批 · 原型 2026-10-14 过门）**：每条计时胶囊两形态——
/// ①**紧凑胶囊（默认）**＝呼吸点＋时间＋＋笔记＋■结束（点「时间」显/隐书名）；
/// ②拖到屏幕边缘（[kPillEdgeSnap] 内）松手 → **贴边圆圈**（只显时长，点圆圈
/// 直接展开）。两态严格互斥（[pillShow] 唯一出口）；位置记忆 per 形态入 kv。
class TimerBarOverlay extends ConsumerWidget {
  const TimerBarOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readOn = ref.watch(readTimerBarVisibleProvider).valueOrNull ?? false;
    // 影音计时条（批3 · media.floatBar/media.timerUI=capsule）：与阅读胶囊并存，互不遮蔽。
    final mediaOn = ref.watch(mediaTimerBarVisibleProvider);
    final bars = (readOn ? 1 : 0) + (mediaOn ? 1 : 0);
    // 会话退场后把折叠态复位：下次起表回胶囊形态（圆圈态只跟随一个活会话）。
    if (bars == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (ref.read(readPillFoldedProvider)) {
          ref.read(readPillFoldedProvider.notifier).state = false;
        }
        if (ref.read(mediaPillFoldedProvider)) {
          ref.read(mediaPillFoldedProvider.notifier).state = false;
        }
      });
    }
    return Stack(
      children: [
        child,
        if (bars > 0)
          Positioned.fill(
            child: Stack(
              children: [
                if (readOn) const _ReadPill(baseDy: 0),
                if (mediaOn)
                  _MediaPill(baseDy: readOn ? kTimerBarHeight + kTimerBarGap : 0),
              ],
            ),
          ),
      ],
    );
  }
}

/// 中性浮层底（批A 配色改口 2026-10-14：弃纯黑底，跟随主题——
/// 亮色档白底浅描边深字，深色档深底白字；全部走 colorScheme 令牌）。
BoxDecoration _pillBox(BuildContext context, {bool circle = false}) {
  final cs = Theme.of(context).colorScheme;
  return BoxDecoration(
    color: cs.surface.withValues(alpha: .97),
    borderRadius: BorderRadius.circular(circle ? 999 : 16),
    border: Border.all(color: cs.outlineVariant),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: .14),
        blurRadius: 12,
        offset: const Offset(0, 4),
      ),
    ],
  );
}

/// 条内小按钮（＋笔记 / ■ 结束）：浅灰底深字，按压有水波（〇B 按压反馈）。
Widget _pillBtn(
  BuildContext context,
  String label, {
  required VoidCallback onTap,
  Key? key,
}) {
  final cs = Theme.of(context).colorScheme;
  return InkWell(
    key: key,
    borderRadius: BorderRadius.circular(9),
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: cs.onSurfaceVariant,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
  );
}

/// 两形态计时胶囊基座（批A）：紧凑胶囊 ⇄ 贴边圆圈，拖动 / 贴边吸附 /
/// 位置记忆（kv `prefix.pillPos`·`prefix.pillFabPos`）/ 两态互斥。
/// 胶囊内容**恒紧凑**（无展宽形态·2026-10-14 产品口径）。
///
/// 折叠态与展开落点覆盖是内存态；位置 kv 直读直写（不经 readKvProvider——
/// 位置只被手势改变，无需随 tick 重建）。圆圈点击判定统一在 onTap（拖动
/// 走 pan，位移超滑距即算拖、松手吸附最近边）。
class _TimerPill extends ConsumerStatefulWidget {
  const _TimerPill({
    required this.prefix,
    required this.tag,
    required this.foldedProvider,
    required this.barSpotProvider,
    required this.baseDy,
    required this.kvGet,
    required this.kvSet,
    required this.fabText,
    required this.bar,
    this.barKey,
    this.fabKey,
    this.onBarTap,
  });

  final String prefix;
  final String tag;
  final StateProvider<bool> foldedProvider;
  final StateProvider<Offset?> barSpotProvider;

  /// 与另一条并存时的默认纵向让位（未拖过时生效）。
  final double baseDy;
  final Future<String?> Function(String key) kvGet;
  final Future<void> Function(String key, String value) kvSet;

  /// 圆圈面时长文案（调用方随秒级 ticker 逐帧刷新）。
  final String fabText;
  final Widget bar;
  final Key? barKey;
  final Key? fabKey;
  final VoidCallback? onBarTap;

  @override
  ConsumerState<_TimerPill> createState() => _TimerPillState();
}

class _TimerPillState extends ConsumerState<_TimerPill> {
  Offset? _barPos; // 胶囊左上角（绝对屏坐标；null＝默认落点）
  Offset? _barFrac; // kv 恢复的屏占比分数（x/宽，y/高）——build 时折算成绝对
  Size? _barSize; // 拖起时量到的胶囊尺寸
  String _fabSide = 'l';
  double? _fabLeft;
  double? _fabTop; // 绝对屏坐标（交互后即绝对；kv 恢复走 _fabFrac）
  (String, double)? _fabFrac; // kv 恢复的（边，y/高）

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final rawBar = await widget.kvGet('${widget.prefix}.pillPos');
    final rawFab = await widget.kvGet('${widget.prefix}.pillFabPos');
    if (!mounted) return;
    setState(() {
      // kv 存屏占比分数（跨机型不漂），build 时折算绝对像素。
      final p = (rawBar == null || rawBar.isEmpty) ? null : _parseXY(rawBar);
      if (p != null) _barFrac = p;
      if (rawFab != null && rawFab.isNotEmpty) {
        final parts = rawFab.split(',');
        final yf = parts.length == 2 ? double.tryParse(parts[1]) : null;
        if ((parts[0] == 'l' || parts[0] == 'r') && yf != null) {
          _fabSide = parts[0];
          _fabFrac = (parts[0], yf);
        }
      }
    });
  }

  double _clampTop(double top, double h, double itemH) =>
      top.clamp(4.0, h - itemH - 4).toDouble();

  /// 胶囊实测宽（首帧 / 拖起时量得）。未量到时用保守估值——**宁大不小**：
  /// 夹取上界收得更紧，只会偏左，绝不越出屏右把「＋笔记 / ■ 结束」裁掉。
  ///
  /// 历史坑（2026-10-14 真机）：build 里曾写死 `mq.width - 60`，而实际胶囊
  /// 宽 ~215px——靠右拖动/展宽后右半截直接出屏。口径现与 [_dragBar]、
  /// [_settleBar]、[_unfold] 统一走本函数。
  static const double _kBarWGuess = 240;

  double _barW(Size mq) =>
      (_barSize?.width ?? _kBarWGuess).clamp(0.0, mq.width - 8);

  void _foldTo(String side, Offset barTopLeft, Size mq) {
    _fabSide = side;
    _fabFrac = null; // 交互后走绝对像素
    _fabTop = _clampTop(
      barTopLeft.dy,
      mq.height,
      kPillFabSize,
    ).clamp(kPillFabSize, mq.height - kPillFabSize - 4).toDouble();
    _fabLeft = side == 'l' ? 4 : mq.width - 4 - kPillFabSize;
    ref.read(widget.foldedProvider.notifier).state = true;
    // 位置记忆 per 形态：圆圈位入 kv（y 存屏高比例，跨机型不漂）。
    widget.kvSet('${widget.prefix}.pillFabPos',
        '$side,${(_fabTop! / mq.height).toStringAsFixed(5)}');
  }

  void _unfold(Size mq) {
    final top = _clampTop(
      _fabTop ?? (_fabFrac?.$2 ?? 0) * mq.height,
      mq.height,
      kTimerBarHeight,
    ).clamp(kPillFabSize, mq.height - kTimerBarHeight - 4).toDouble();
    ref.read(widget.barSpotProvider.notifier).state = Offset(
      _fabSide == 'l' ? 4 : mq.width - _barW(mq) - 4,
      top,
    );
    ref.read(widget.foldedProvider.notifier).state = false;
  }

  void _dragFab(Offset delta, Size mq) {
    setState(() {
      _fabFrac = null; // 交互后走绝对像素
      _fabLeft = ((_fabLeft ??
              (_fabSide == 'r' ? mq.width - 4 - kPillFabSize : 4)) +
          delta.dx)
          .clamp(4.0, mq.width - kPillFabSize - 4).toDouble();
      _fabTop = _clampTop(
        (_fabTop ?? 0) + delta.dy,
        mq.height,
        kPillFabSize,
      ).clamp(kPillFabSize, mq.height - kPillFabSize - 4).toDouble();
    });
  }

  void _settleFab(Size mq) {
    _fabSide = (_fabLeft ?? 4) + kPillFabSize / 2 < mq.width / 2 ? 'l' : 'r';
    _fabLeft = _fabSide == 'l' ? 4 : mq.width - 4 - kPillFabSize;
    setState(() {});
    widget.kvSet('${widget.prefix}.pillFabPos',
        '$_fabSide,${((_fabTop ?? 0) / mq.height).toStringAsFixed(5)}');
  }

  void _dragBar(Offset delta, Size mq, double baseTop) {
    final cur = _barPos ??
        (_barFrac != null
            ? Offset(_barFrac!.dx * mq.width, _barFrac!.dy * mq.height)
            : Offset(16, baseTop));
    _barFrac = null; // 交互后走绝对像素
    final h = _barSize?.height ?? kTimerBarHeight;
    setState(() {
      _barPos = Offset(
        (cur.dx + delta.dx).clamp(4.0, mq.width - _barW(mq) - 4).toDouble(),
        (cur.dy + delta.dy).clamp(4.0, mq.height - h - 4).toDouble(),
      );
    });
  }

  void _settleBar(Size mq) {
    final pos = _barPos;
    if (pos == null) return;
    final bw = _barW(mq);
    if (pos.dx <= kPillEdgeSnap) {
      _foldTo('l', pos, mq);
    } else if (mq.width - (pos.dx + bw) <= kPillEdgeSnap) {
      _foldTo('r', pos, mq);
    } else {
      widget.kvSet('${widget.prefix}.pillPos',
          '${(pos.dx / mq.width).toStringAsFixed(5)},${(pos.dy / mq.height).toStringAsFixed(5)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final folded = ref.watch(widget.foldedProvider);
    final mq = MediaQuery.sizeOf(context);
    final baseTop = MediaQuery.paddingOf(context).top + kTimerBarTopOffset;
    if (folded) {
      final fl =
          _fabLeft ?? (_fabSide == 'r' ? mq.width - 4 - kPillFabSize : 4);
      final ft = _clampTop(
        _fabTop ?? (_fabFrac?.$2 ?? 0) * mq.height,
        mq.height,
        kPillFabSize,
      ).clamp(kPillFabSize, mq.height - kPillFabSize - 4).toDouble();
      return Positioned(
        left: fl,
        top: ft,
        child: GestureDetector(
          key: widget.fabKey,
          onTap: () => _unfold(mq),
          onPanUpdate: (d) => _dragFab(d.delta, mq),
          onPanEnd: (_) => _settleFab(mq),
          child: Container(
            width: kPillFabSize,
            height: kPillFabSize,
            decoration: _pillBox(context, circle: true),
            alignment: Alignment.center,
            child: Text(
              widget.fabText,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      );
    }
    final spot = ref.watch(widget.barSpotProvider);
    Offset? pos = spot ?? _barPos;
    if (pos == null && _barFrac != null) {
      pos = Offset(
        (_barFrac!.dx * mq.width)
            .clamp(4.0, mq.width - _barW(mq) - 4)
            .toDouble(),
        (_barFrac!.dy * mq.height)
            .clamp(4.0, mq.height - kTimerBarHeight - 4)
            .toDouble(),
      );
    }
    final left =
        ((pos?.dx ?? 16)).clamp(4.0, mq.width - _barW(mq) - 4).toDouble();
    final top = pos?.dy ?? baseTop + widget.baseDy;
    if (_barSize == null) {
      // 首帧量一次实测宽，供贴边夹取用（只补一次，不循环）。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _barSize != null) return;
        final box = context.findRenderObject() as RenderBox?;
        final sz = box?.size;
        if (sz != null && sz.width > 0) setState(() => _barSize = sz);
      });
    }
    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        key: widget.barKey,
        onPanStart: (d) {
          final box = context.findRenderObject() as RenderBox?;
          _barSize = box?.size ?? const Size(200, kTimerBarHeight);
          _barPos ??= _barFrac != null
              ? Offset(_barFrac!.dx * mq.width, _barFrac!.dy * mq.height)
              : Offset(16, baseTop + widget.baseDy);
        },
        onPanUpdate: (d) => _dragBar(d.delta, mq, baseTop),
        onPanEnd: (_) => _settleBar(mq),
        onTap: widget.onBarTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: mq.width - 24),
          child: widget.bar,
        ),
      ),
    );
  }
}

/// 读书计时胶囊（批A · §3.3 跨页常驻 · 原地结束；内容恒紧凑）。
class _ReadPill extends ConsumerWidget {
  const _ReadPill({required this.baseDy});

  final double baseDy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(readTickProvider);
    ref.watch(calendarTickerProvider); // 秒级心跳（秒显 C5 与日程条共用流）
    final s = ref.watch(runningSessionProvider).valueOrNull;
    if (s == null) return const SizedBox.shrink();
    final elapsed = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(s.startedAt));
    final cs = Theme.of(context).colorScheme;
    final bar = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: _pillBox(context),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration:
                BoxDecoration(shape: BoxShape.circle, color: cs.primary),
          ),
          const SizedBox(width: 8),
          // 恒紧凑：只显时长（不显书名·2026-10-14 产品口径）。
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              pillFmtHMS(elapsed),
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 4),
          // C6 已拍板＝案A：＋笔记直开书摘新建页（预选在跑书）。
          _pillBtn(
            context,
            '＋笔记',
            key: const ValueKey('read-pill-note'),
            onTap: () => showQuoteEditPage(context, ref, bookId: s.bookId),
          ),
          const SizedBox(width: 6),
          _pillBtn(
            context,
            '■ 结束',
            key: const ValueKey('read-pill-end'),
            onTap: () => endReadPillTimer(context, ref, s.bookId),
          ),
        ],
      ),
    );
    return _TimerPill(
      prefix: 'read',
      tag: 'read',
      foldedProvider: readPillFoldedProvider,
      barSpotProvider: readPillBarSpotProvider,
      baseDy: baseDy,
      kvGet: (k) => ref.read(readRepositoryProvider).kv(k),
      kvSet: (k, v) => ref.read(readRepositoryProvider).setKv(k, v),
      fabText: pillFabFmt(elapsed),
      bar: bar,
      barKey: const ValueKey('read-bar'),
      fabKey: const ValueKey('read-fab'),
      onBarTap: () => context.push('/read/timer/${s.bookId}'),
    );
  }
}

/// 影音计时胶囊（与阅读胶囊同构继承拖动/贴边/秒显；C6 仅阅读侧）。
class _MediaPill extends ConsumerWidget {
  const _MediaPill({required this.baseDy});

  final double baseDy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(mediaTickProvider);
    ref.watch(calendarTickerProvider); // 秒级心跳（三条共用流）
    final s = ref.watch(mediaRunningSessionProvider).valueOrNull;
    if (s == null) return const SizedBox.shrink();
    final elapsed = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(s.startedAt));
    final cs = Theme.of(context).colorScheme;
    final bar = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: _pillBox(context),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration:
                BoxDecoration(shape: BoxShape.circle, color: cs.tertiary),
          ),
          const SizedBox(width: 8),
          // 恒紧凑：只显时长（不显条目标题·2026-10-14 产品口径）。
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              pillFmtHMS(elapsed),
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 4),
          _pillBtn(
            context,
            '■ 结束',
            key: const ValueKey('media-pill-end'),
            onTap: () => endMediaPillTimer(context, ref, s.itemId),
          ),
        ],
      ),
    );
    return _TimerPill(
      prefix: 'media',
      tag: 'media',
      foldedProvider: mediaPillFoldedProvider,
      barSpotProvider: mediaPillBarSpotProvider,
      baseDy: baseDy,
      kvGet: (k) => ref.read(mediaRepositoryProvider).kv(k),
      kvSet: (k, v) => ref.read(mediaRepositoryProvider).setKv(k, v),
      fabText: pillFabFmt(elapsed),
      bar: bar,
      barKey: const ValueKey('media-bar'),
      fabKey: const ValueKey('media-fab'),
      onBarTap: () => context.push('/media/timer/${s.itemId}'),
    );
  }
}
