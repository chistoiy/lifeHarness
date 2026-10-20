import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../domain/block_ops.dart';
import '../../domain/category.dart';
import '../../domain/time_block.dart';
import '../calendar_providers.dart';

/// 当月天数（避开 DateTime(y,m+1,0)：day-0 归一化在 FakeAsync 时区解析下会挂死）。
int daysInMonthOf(int y, int m) {
  const dm = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  if (m != 2) return dm[m - 1];
  return (y % 4 == 0 && (y % 100 != 0 || y % 400 == 0)) ? 29 : 28;
}

/// V1.52 统一添加 / 编辑弹层（原型 sheetTimePick）。
///
/// 四视图（轴/块/日/周）点已有时间块、计时块 **都打开本弹层**并预填，
/// 底部按钮随形态切换：添加=继续添加+添加；编辑=删除+保存修改；
/// 计时中额外给「■ 结束计时」，已结束额外给「对半拆分 / 与上一个合并 / 与下一个合并」。
/// 今天：起止默认当前分钟，确认即为「计时中」块；非今天：纯补录，无计时。
/// B10（2026-10-13 产品裁决）：旧 events 表已并入块表并退役，本弹层不再有事件形态。
Future<void> showTimePickSheet(BuildContext context, WidgetRef ref,
    {DateTime? day, int? startMin, TimeBlock? block}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _TimePick(day: day, startMin: startMin, block: block),
  );
}

class _TimePick extends ConsumerStatefulWidget {
  const _TimePick({this.day, this.startMin, this.block});
  final DateTime? day;
  final int? startMin;
  final TimeBlock? block;

  @override
  ConsumerState<_TimePick> createState() => _TimePickState();
}

/// 单向数据流：滚轮自持滚动状态，父层经 ValueNotifier 只读汇总，
/// 不在 onSel 后回写/重建滚轮——避免同帧重建回环。
class _TimePickState extends ConsumerState<_TimePick> {
  static const _rowH = 26.0; // 3 行 × 26 = 78（V1.52 弹层瘦身）
  static const _catCols = 6; // 一级分类每行 6 个

  late final DateTime _date;
  late final int _daysInMonth;
  late final TimeBlock? _blk;
  late final int _nowMin; // 打开弹层时的当前分钟（isNow 判定基准，避免跨分钟失效）

  // items 跨 rebuild 保持同一 List 实例：CupertinoPicker 每次 build 拿到新
  // delegate 会重置内部索引上报，故这些列表必须缓存进 state（不能就地新建）。
  //
  // ⚠️ 一律用 List.generate 而非集合推导手写三段式 for：增量子句漏写是
  // **静默无限循环**（曾吃满单核膨胀到 20GB OOM，--timeout 也杀不掉）。
  late final List<String> _dayItems;
  late final List<String> _hourItems;
  late final List<String> _minItems;
  late final ValueNotifier<int> _dayN;
  late final ValueNotifier<int> _sMinN;

  /// B1（冻结）：结束日=起始日 +0..7 天的**动态窗口**（可跨月，如 9/30→10/1），
  /// 滚轮只存偏移；起始日变化时重建标签实例（_Wheel 靠 items 实例感知，位置=偏移不变）。
  late ValueNotifier<int> _eOffN;
  late List<String> _eOffItems;
  late final ValueNotifier<int> _eMinN;
  late final Listenable _all;
  int? _catId;
  String _catName = '工作';
  String? _subName;

  /// 弹层内即时反馈（校验拒绝一类）。**不走** 页面 ScaffoldMessenger：
  /// 条子由页面 Scaffold 渲染，弹层浮着时既被压在弹层与遮罩后头看不见，
  /// 又因带 action 的 SnackBar 默认 `persist` 而不退场（真机反馈②）。
  String? _hint;
  final _note = TextEditingController();

  /// 根容器。撤销闭包在弹层 pop（State dispose）之后才执行，用 `ref` 会静默失效
  /// ——真机反馈「点了撤销要再添加一次事件才看到恢复」即此。
  /// 只在 mounted 期间取（initState 里取会撞 dependOnInheritedWidget 限制），
  /// 取到的是随 App 存活的根容器，pop 后照样能 invalidate。
  ProviderContainer get _container =>
      ProviderScope.containerOf(context, listen: false);

  bool get _editing => _blk != null;
  bool get _timing => _blk?.isTiming ?? false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _nowMin = now.hour * 60 + now.minute;
    _blk = widget.block;
    final b = _blk;
    final d = b?.day ?? widget.day ?? now;
    _date = DateTime(d.year, d.month, d.day);
    _daysInMonth = daysInMonthOf(_date.year, _date.month);
    _dayItems = List.generate(_daysInMonth, (i) => '${_date.month}/${i + 1}');
    _hourItems = List.generate(24, (h) => h.toString().padLeft(2, '0'));
    _minItems = List.generate(60, (i) => i.toString().padLeft(2, '0')); // 1 分一档

    int s0, e0, off0 = 0;
    if (b != null) {
      s0 = b.startMin;
      e0 = b.effEnd(now);
    } else if (widget.startMin != null) {
      s0 = widget.startMin!;
      e0 = s0 + 60; // 允许 >1440：统一走下方 off/e 折算（B1/C8），勿先 clamp 丢跨天
    } else if (_isTodaySel) {
      s0 = _nowMin;
      e0 = _nowMin; // 今天默认起止=当前
    } else {
      s0 = 9 * 60;
      e0 = 10 * 60;
    }
    // 段尾 1440（=次日 00:00）折算为「跨一天 + 0 分」（C8/B2 口径），滚轮不出现 24:00。
    off0 += e0 ~/ 1440;
    e0 = e0 % 1440;
    off0 = off0.clamp(0, 7);
    _dayN = ValueNotifier<int>(_date.day);
    _sMinN = ValueNotifier<int>(s0.clamp(0, 1439));
    _eOffN = ValueNotifier<int>(off0);
    _eOffItems = _buildEndItems();
    _eMinN = ValueNotifier<int>(e0.clamp(0, 1439));
    _all = Listenable.merge([_dayN, _sMinN, _eOffN, _eMinN]);

    // 分类回填：categoriesProvider 是异步的，initState 时通常还没值——
    // 先记下待回填的 catId/catName，等 build 里拿到 cats 再解析（否则编辑弹层预填不到分类）。
    _pendingCatId = b?.catId;
    _pendingCatName = b?.catName;
    _pendingCat = b != null;
    _note.text = b?.note ?? '';
  }

  int? _pendingCatId;
  String? _pendingCatName;
  bool _pendingCat = false;

  /// 用已加载的分类表解析待回填项：次级→选中父级并勾中次级；一级→直接选中。
  /// catId 缺失（历史行 cat_id 为 null）时按分类名回退匹配。
  void _applyPendingCat(List<Category> cats) {
    if (cats.isEmpty || !_pendingCat) return;
    final cid = _pendingCatId;
    _pendingCat = false;
    Category? hit;
    if (cid != null) hit = cats.where((c) => c.id == cid).firstOrNull;
    final name = _pendingCatName;
    hit ??= name == null ? null : cats.where((c) => c.name == name).firstOrNull;
    if (hit == null) return;
    if (hit.isPrimary) {
      _catId = hit.id;
      _catName = hit.name;
      _subName = null;
    } else {
      final p = cats.where((c) => c.id == hit!.parentId).firstOrNull;
      _catId = p?.id;
      _catName = p?.name ?? _catName;
      _subName = hit.name;
    }
  }

  bool get _isTodaySel {
    final n = DateTime.now();
    final d = widget.block?.day ?? widget.day ?? n;
    return d.year == n.year && d.month == n.month && d.day == n.day;
  }

  @override
  void dispose() {
    _note.dispose();
    _dayN.dispose();
    _sMinN.dispose();
    _eOffN.dispose();
    _eMinN.dispose();
    super.dispose();
  }

  /// 结束日轮 8 档标签：起始日 +0..7（B1 动态窗口 · 跨月直接表达）。
  List<String> _buildEndItems() {
    final s = _sDate;
    return List.generate(8, (i) {
      final d = s.add(Duration(days: i));
      return '${d.month}/${d.day}';
    });
  }

  /// 起始日变化后重建结束日标签（items 实例变化驱动 _Wheel 重建，选中位=偏移不变）。
  void _refreshEndItems() => setState(() => _eOffItems = _buildEndItems());

  int get _s => _sMinN.value;
  int get _eOff => _eOffN.value;
  int get _e => _eMinN.value;
  int get _durMin => _eOff * 1440 + _e - _s;
  DateTime get _sDate => DateTime(_date.year, _date.month, _dayN.value);
  DateTime get _eDate => _sDate.add(Duration(days: _eOff));
  bool get _crossDay => _eOff > 0;
  String get _pickedCat => _subName ?? _catName;

  int? _catIdForName(String name) {
    final cats = ref.read(categoriesProvider).valueOrNull ?? const <Category>[];
    if (_subName != null) {
      return cats
          .where((c) => c.name == _subName && c.parentId == _catId)
          .map((c) => c.id)
          .firstOrNull;
    }
    return cats.where((c) => c.name == name).map((c) => c.id).firstOrNull ?? _catId;
  }

  /// 弹层保持打开时的反馈（校验拒绝/继续添加）：写在弹层内的提示行上。
  void _hintAt(String msg) {
    if (!mounted) return;
    setState(() => _hint = msg);
  }

  /// 落库成功后的收口提示：**先关弹层，再在下一帧挂条**。
  /// 两条理由：① 弹层浮着时挂的条由页面 Scaffold 渲染，会被模态弹层与遮罩压住看不见；
  /// ② 撤销闭包要在弹层关闭后仍能刷新四视图，所以趁 mounted 把 messenger 与根容器取好。
  /// T4（交互整改批一）：带撤销的条改走 AppToast.showUndoWith 统一原语
  /// （排他存续＋显式 persist:false，不被普通提示顶掉、也不永挂）。
  void _closeAndToast(String msg, {DateTime? alsoDay, Future<void> Function()? undo}) {
    if (!mounted) return;
    final ms = ScaffoldMessenger.of(context);
    final day = _sDate, c = _container;
    Navigator.of(context).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reloadOn(c, day, alsoDay);
      if (undo == null) {
        ms
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text(msg),
            duration: const Duration(milliseconds: 1600),
          ));
      } else {
        AppToast.showUndoWith(
          ms,
          msg,
          ms: 5000,
          onUndo: () => undo().then((_) => _reloadOn(c, day, alsoDay)),
        );
      }
    });
  }

  /// 四视图 / 账本 / 月历圆点的数据源刷新（只依赖根容器与日期，弹层关掉后仍可用）。
  void _reloadOn(ProviderContainer c, DateTime day, [DateTime? other]) {
    c.invalidate(dayBlocksProvider(day));
    c.invalidate(timingBlockProvider);
    c.invalidate(monthTimingDaysProvider((day.year, day.month)));
    if (other != null) c.invalidate(dayBlocksProvider(other));
  }

  void _reload([DateTime? other]) => _reloadOn(_container, _sDate, other);

  /// 添加（含继续添加）：今天起止=当前 → 计时块；否则普通块（跨天自动拆两段）。
  Future<void> _add({bool keepOpen = false}) async {
    final dao = ref.read(timeBlockDaoProvider);
    final s = _s, e = _e;
    final note = _note.text.trim().isEmpty ? null : _note.text.trim();
    final cat = _pickedCat, catId = _catIdForName(cat);

    final t = await dao.activeTiming();
    if (t != null &&
        DateTime(t.day.year, t.day.month, t.day.day) ==
            DateTime(_sDate.year, _sDate.month, _sDate.day)) {
      if (addRejected(
          timing: t,
          bStart: s,
          // 跨天补录的首段是 [s,1440)，按整段判定是否吞掉计时中区间。
          bEnd: _eOff == 0 ? (e <= s ? s + 1 : e) : 1440)) {
        _hintAt('✕ 补录事件的结束不能晚于计时中事件的开始（${fmtMin(t.startMin)}）· 请调整');
        return;
      }
    }
    final isNow = _isTodaySel && s == _nowMin;
    if (isNow && e <= s) {
      await dao.startTiming(_sDate, s, catId: catId, catName: cat, note: note);
      _closeAndToast('▶ 已按当前时间开始计时 · 下次点击该事件可「■ 结束计时」');
      return;
    }
    // B3（冻结）：同日 e ≤ s ⇒ 拦截 + 就地红字，不落库（原「静默兜底 s+1」作废）。
    if (_eOff == 0 && e <= s) {
      _hintAt('✕ 结束不能早于开始');
      return;
    }
    // B1（冻结）：跨天段按两段行落库（首日 [s,1440) ＋ 次日 [0,e)），结束日一并刷新；
    // 结束恰为次日 00:00（e==0）时次日尾巴零长，只落首日到 24:00。
    final other = _crossDay ? _eDate : null;
    if (other == null) {
      await dao.markRange(_sDate, s, e,
          catId: catId, catName: cat, note: note);
    } else {
      await dao.markRange(_sDate, s, 1440, catId: catId, catName: cat, note: note);
      if (e > 0) {
        await dao.markRange(other, 0, e, catId: catId, catName: cat, note: note);
      }
    }
    if (keepOpen) {
      _reload(other);
      setState(() {
        _note.clear();
        _hint = '✔ 已添加 ${fmtMin(s)}-${fmtMin(e)} · $cat（${_sDate.month}/${_sDate.day}）';
      });
      return;
    }
    _closeAndToast(
        '✔ 已添加 · 轴/块/日/周四视图与时间账本同步（L4）'
        '${_crossDay ? ' · 跨天' : ''}${other != null ? ' · 已补录到 ${other.month}/${other.day}' : ''}',
        alsoDay: other);
  }

  /// 编辑保存：块改起止/分类/备注；事件改起止/分类/标题。
  /// B3（冻结）：非计时中且同日 e ≤ s ⇒ 拦截 + 就地红字，不落库。
  /// B1（冻结）：跨天保存拆两段行——首日 [s,1440) 落原行，次日 [0,e) 新行（可撤销）。
  Future<void> _save() async {
    final s = _s, e = _e;
    if (_eOff == 0 && e <= s && !_timing) {
      _hintAt('✕ 结束不能早于开始');
      return;
    }
    if (_blk != null) {
      final dao = ref.read(timeBlockDaoProvider);
      final b = _blk;
      final wasTiming = b.isTiming;
      final cat = _pickedCat;
      final catId = _catIdForName(cat);
      final note = _note.text.trim().isEmpty ? cat : _note.text.trim();
      final src = wasTiming && (e != _nowMin || s != b.startMin) ? kSrcMark : b.source;
      var endMin = e;
      if (endMin <= s) endMin = s + 1; // 计时中同分兜底 1 分（B3 只拦非计时）
      if (_eOff == 0) {
        await dao.save(b.copyWith(
            day: _sDate,
            startMin: s,
            endMin: endMin.clamp(0, 1440),
            catId: catId,
            catName: cat,
            note: note,
            source: src));
        _closeAndToast('✔ 已保存 · 轴/块/日/周四视图与时间账本同步（L4）');
        return;
      }
      final snapA = await dao.snapshotDay(_sDate);
      final snapB = await dao.snapshotDay(_eDate);
      await dao.save(b.copyWith(
          day: _sDate,
          startMin: s,
          endMin: 1440,
          catId: catId,
          catName: cat,
          note: note,
          source: src));
      if (e > 0) {
        await dao.insert(TimeBlock(
            day: _eDate,
            startMin: 0,
            endMin: e,
            catId: catId,
            catName: cat,
            note: note,
            source: kSrcMark));
      }
      _closeAndToast(
          '✔ 已保存 · 跨天拆两段行（首日到 24:00 ＋ 次日尾巴）· 四视图与账本同步',
          alsoDay: _eDate,
          undo: () async {
            await dao.restoreDay(_sDate, snapA);
            await dao.restoreDay(_eDate, snapB);
          });
    }
  }

  Future<void> _delete() async {
    final dao = ref.read(timeBlockDaoProvider);
    if (_blk != null) {
      final day = _blk.day;
      final snap = await dao.snapshotDay(day);
      await dao.remove(_blk.id!);
      _closeAndToast('🗑 已删除 · 四视图与时间账本同步移除',
          undo: () => dao.restoreDay(day, snap));
    }
  }

  Future<void> _endTiming() async {
    final b = _blk;
    if (b == null || !b.isTiming) return;
    final now = DateTime.now();
    final dao = ref.read(timeBlockDaoProvider);
    await dao.endTiming(b.id, now.hour * 60 + now.minute);
    _closeAndToast(
        '■ 结束计时 · 结束 ${fmtMin(now.hour * 60 + now.minute)} · 已落账（L4）');
  }

  Future<void> _split() async {
    final b = _blk;
    if (b == null || b.isTiming) return;
    final dao = ref.read(timeBlockDaoProvider);
    final day = b.day;
    final snap = await dao.snapshotDay(day);
    final parts = splitHalf(b);
    if (parts == null) {
      _hintAt('✕ 时长不足 2 分钟 · 无法对半拆分');
      return;
    }
    await dao.save(parts[0]);
    await dao.insert(parts[1]);
    _closeAndToast(
        '✂ 已对半拆分为两段 · ${fmtMin(parts[0].startMin)}-${fmtMin(parts[0].endMin)} / '
        '${fmtMin(parts[1].startMin)}-${fmtMin(parts[1].endMin)}',
        undo: () => dao.restoreDay(day, snap));
  }

  Future<void> _merge(int dir) async {
    final b = _blk;
    if (b == null || b.isTiming) return;
    final dao = ref.read(timeBlockDaoProvider);
    final day = await dao.listByDay(b.day);
    final o = neighborOf(day, b, dir);
    if (o == null) {
      _hintAt(dir < 0
          ? '✕ 上方没有 30 分钟内可合并的已结束事件'
          : '✕ 下方没有 30 分钟内可合并的已结束事件');
      return;
    }
    final snap = await dao.snapshotDay(b.day);
    final m = mergePair(b, o);
    // mergePair 的身份归「较早那段」（原型 tpMerge 同口径：保留早者的分类/备注），
    // 所以必须删的是**另一段**。真机缺陷：原先无条件删 o，「与上一个合并」时 o 就是
    // 早者 → 先删掉 m 所依附的行，随后 save 的 update 命中 0 行，两段一起消失。
    await dao.remove(m.id == b.id ? o.id! : b.id!);
    await dao.save(m);
    _closeAndToast(
        '⇄ 已合并为 ${fmtMin(m.startMin)}-${fmtMin(m.endMin)} · ${m.catName}',
        undo: () => dao.restoreDay(b.day, snap));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    // F5-3：编辑计时中块时接秒级心跳，「已 X 分钟」每秒刷新（关弹层即停）。
    if (ref.watch(timingBlockProvider).valueOrNull != null) {
      ref.watch(calendarTickerProvider);
    }
    final cats = ref.watch(categoriesProvider).valueOrNull ?? const <Category>[];
    _applyPendingCat(cats); // 分类异步到位后补一次编辑态预填
    final catColors = ref.watch(catColorsByNameProvider);
    final primary = cats.where((c) => c.isPrimary).toList();
    final subs = cats.where((c) => c.parentId == _catId).toList();
    final b = _blk;
    final canMerge = b != null && !b.isTiming;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            20, 14, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                    child: Text(_editing ? '编辑时间块' : '添加时间块',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
                // 非弹性子项：加「· 跨天」后缀后文本变长会撑爆 Row（4.8px 溢出），须 Flexible。
                Flexible(
                  child: AnimatedBuilder(
                    animation: _all,
                    builder: (context, _) => Text(
                        '${_dayItems[_dayN.value - 1]} ${fmtMin(_s)} → '
                        '${_eOffItems[_eOff]} ${fmtMin(_e)} · $_durMin 分钟'
                        '${_crossDay ? ' · 跨天' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 10.5, color: scheme.onSurfaceVariant)),
                  ),
                ),
              ],
            ),
            if (_editing || _isTodaySel)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                    b != null
                        ? (b.isTiming
                            ? '● 计时中 · 已 ${DateTime.now().difference(DateTime(b.day.year, b.day.month, b.day.day, b.startMin ~/ 60, b.startMin % 60)).inMinutes} 分钟 · 点「■ 结束计时」落当前时刻'
                            : '✎ 编辑中 · 修改即保存')
                        : (_isTodaySel ? '▶ 起止默认当前 · 确认后即为计时中' : ''),
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: b?.isTiming ?? false ? const Color(0xFFF43F5E) : tokens.accent)),
              ),
            // 弹层内即时反馈（校验拒绝/继续添加成功）——不走页面 ScaffoldMessenger，
            // 否则条子既被弹层遮住、又不会自动退场（真机反馈②）。
            if (_hint != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(_hint!,
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: _hint!.startsWith('✕')
                            ? const Color(0xFFF43F5E)
                            : tokens.accent)),
              ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _WheelGroup(
                    label: '上尾 · 起始',
                    children: [
                      _Wheel(
                          items: _dayItems,
                          initialIndex: _dayN.value - 1,
                          onSel: (i) {
                            _dayN.value = i + 1;
                            // B1：结束日窗口随起始日走（标签重建，选中偏移不变）。
                            _refreshEndItems();
                          }),
                      _Wheel(
                          items: _hourItems,
                          initialIndex: _s ~/ 60,
                          onSel: (i) => _sMinN.value = i * 60 + _s % 60),
                      _Wheel(
                          items: _minItems,
                          initialIndex: _s % 60,
                          onSel: (i) => _sMinN.value = _s ~/ 60 * 60 + i),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _WheelGroup(
                    label: '当前 · 结束',
                    children: [
                      _Wheel(
                          items: _eOffItems,
                          initialIndex: _eOff,
                          onSel: (i) => _eOffN.value = i),
                      _Wheel(
                          items: _hourItems,
                          initialIndex: _e ~/ 60,
                          onSel: (i) => _eMinN.value = i * 60 + _e % 60),
                      _Wheel(
                          items: _minItems,
                          initialIndex: _e % 60,
                          onSel: (i) => _eMinN.value = _e ~/ 60 * 60 + i),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text('一级分组',
                    style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
                const Spacer(),
                // C9（冻结）：「标签 ›」假入口已摘除——标签维护下沉到分类管理的默认标签。
                Semantics(button: true, label: '关闭', child: GestureDetector(
                  onTap: () {
                    Navigator.of(context).pop();
                    if (context.mounted) context.push('/categories');
                  },
                  child: Text('管理 ›',
                      style: TextStyle(
                          fontSize: 10.5, fontWeight: FontWeight.w700, color: tokens.accent)),
                )),
              ],
            ),
            const SizedBox(height: 6),
            LayoutBuilder(builder: (context, c) {
              const sp = 6.0;
              final w = (c.maxWidth - sp * (_catCols - 1)) / _catCols;
              // 原型 .tp-catgrid：max-height 82px + 纵向滚动 → 最多 3 行，再多可滚。
              return ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 26 * 3 + 4 * 2),
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: sp,
                    runSpacing: 4,
                    children: [
                      for (final cat in primary)
                        CatPill(
                          width: w,
                          name: cat.name,
                          dot: cat.name == '工作'
                              ? tokens.accent
                              : catColors[cat.name],
                          selected: _catName == cat.name && _subName == null,
                          onTap: () => setState(() {
                            _catId = cat.id;
                            _catName = cat.name;
                            _subName = null;
                            _hint = null;
                          }),
                        ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 10),
            const DashedDivider(),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('子分组',
                    style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text('属于上方选中的一级分组 · 再点可取消',
                      style: TextStyle(fontSize: 9.5, color: scheme.onSurfaceVariant)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 34, maxHeight: 96),
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: scheme.onSurface.withValues(alpha: .05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SingleChildScrollView(
                child: subs.isEmpty
                    ? Text('该分组暂无子分组',
                        style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant))
                    : Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          for (final sc in subs)
                            CatPill(
                              name:
                                  '${sc.name}${sc.tag == null ? '' : ' · ${sc.tag}'}',
                              dot: catColors[sc.name] ?? catColors[_catName],
                              dotOpacity: .6,
                              selected: _subName == sc.name,
                              onTap: () => setState(() {
                                _subName =
                                    _subName == sc.name ? null : sc.name;
                                _hint = null;
                              }),
                            ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _note,
              maxLength: 5000,
              maxLines: 2,
              decoration: InputDecoration(
                  hintText: '请输入备注',
                  isDense: true,
                  counterText: '',
                  border: const OutlineInputBorder()),
            ),
            if (canMerge)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Expanded(child: _miniBtn('✂ 对半拆分', _split)),
                    const SizedBox(width: 6),
                    Expanded(child: _miniBtn('⇧ 与上一个合并', () => _merge(-1))),
                    const SizedBox(width: 6),
                    Expanded(child: _miniBtn('⇩ 与下一个合并', () => _merge(1))),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                if (_editing)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _delete,
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(44),
                          foregroundColor: const Color(0xFFF43F5E)),
                      child: const Text('删除'),
                    ),
                  )
                else
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _add(keepOpen: true),
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                      child: const Text('继续添加'),
                    ),
                  ),
                if (_timing) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: _endTiming,
                      style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(44),
                          backgroundColor: const Color(0xFFF43F5E)),
                      child: const Text('■ 结束计时'),
                    ),
                  ),
                ],
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                          gradient: tokens.gradient, borderRadius: BorderRadius.circular(8)),
                      child: TextButton(
                        onPressed: _editing ? _save : () => _add(),
                        child: Text(_editing ? '保存修改' : '添加',
                            style: const TextStyle(
                                color: Colors.white, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Center(
                child: Text('1 分一档 · 滚轮循环',
                    style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant))),
          ],
        ),
      ),
    );
  }

  Widget _miniBtn(String label, VoidCallback onTap) => OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(34),
            padding: EdgeInsets.zero,
            textStyle: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700)),
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      );
}

class _WheelGroup extends StatelessWidget {
  const _WheelGroup({required this.label, required this.children});
  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
          color: scheme.onSurface.withValues(alpha: .05),
          borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
                color: scheme.onSurface.withValues(alpha: .85),
                borderRadius: BorderRadius.circular(6)),
            child: Text(label,
                style: const TextStyle(
                    fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white)),
          ),
          const SizedBox(height: 2),
          Row(children: children),
        ],
      ),
    );
  }
}

/// 单列滚轮：自持 controller（仅取初值）与选中高亮，滚动只回调 onSel；
/// 父层不得据此重建本组件（单向数据流，杜绝重建回环）。looping=真循环滚动。
class _Wheel extends StatefulWidget {
  const _Wheel(
      {required this.items, required this.initialIndex, required this.onSel});
  final List<String> items;
  final int initialIndex;
  final ValueChanged<int> onSel;

  @override
  State<_Wheel> createState() => _WheelState();
}

class _WheelState extends State<_Wheel> {
  late final FixedExtentScrollController _ctl =
      FixedExtentScrollController(initialItem: widget.initialIndex);
  final ValueNotifier<int> _selN = ValueNotifier<int>(0);
  late List<Widget> _base;

  @override
  void initState() {
    super.initState();
    _selN.value = widget.initialIndex;
    _rebuildBase();
  }

  /// 非选中子项恒定实例，仅选中位换样式 Widget（减少重建开销）。
  void _rebuildBase() {
    _base = List<Widget>.generate(
        widget.items.length,
        (i) => Center(
            key: ValueKey('w$i'),
            child: Text(widget.items[i],
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))));
  }

  @override
  void didUpdateWidget(_Wheel old) {
    super.didUpdateWidget(old);
    if (!identical(old.items, widget.items)) _rebuildBase();
    if (widget.initialIndex != old.initialIndex &&
        _ctl.hasClients &&
        _ctl.selectedItem != widget.initialIndex) {
      _ctl.jumpToItem(widget.initialIndex);
      if (_selN.value != widget.initialIndex) _selN.value = widget.initialIndex;
    }
  }

  @override
  void dispose() {
    _selN.dispose();
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Expanded(
      child: SizedBox(
        height: _TimePickState._rowH * 3,
        child: ListenableBuilder(
          listenable: _selN,
          builder: (context, _) {
            final sel = _selN.value.clamp(0, _base.isEmpty ? 0 : _base.length - 1);
            return CupertinoPicker(
              scrollController: _ctl,
              itemExtent: _TimePickState._rowH,
              // CupertinoPicker 默认 squeeze=1.45（"visually mimic iOS"）会把可见行数
              // 放大到 高度/itemExtent×1.45 —— 真机反馈④：78px 高显示成 5 行。
              // 原型的滚轮就是等距 3 行，故显式锁 1.0。
              squeeze: 1.0,
              looping: true,
              diameterRatio: 1.4,
              backgroundColor: Colors.transparent,
              onSelectedItemChanged: (i) {
                if (_selN.value != i) _selN.value = i;
                widget.onSel(i);
              },
              children: [
                for (var i = 0; i < _base.length; i++)
                  i == sel
                      ? Center(
                          key: ValueKey('w$i'),
                          child: Text(widget.items[i],
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: tokens.accent)))
                      : _base[i],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 弹层分类胶囊（原型 `.tag-chip`：色点 + 名称 · 选中=accent 实底白字）。
///
/// 不用 ChoiceChip 的两条硬理由（真机反馈⑤）：
/// ① 6 列窄格（约 48dp）下 ChoiceChip 的 label 会被 avatar+内边距挤到 0 宽，
///    屏幕上只剩一个色点，分类名整个看不见；
/// ② ChoiceChip 选中时把 avatar 换成 ✓，把分类色点顶掉，与原型口径不符。
/// 本组件自排：点 7×7 + 3dp 间距 + `Flexible(Text)`，窄格下退化为「点 + 省略号名」，
/// 名称始终占位可见。
class CatPill extends StatelessWidget {
  const CatPill({
    super.key,
    required this.name,
    required this.selected,
    this.dot,
    this.dotOpacity = 1,
    this.width,
    this.onTap,
  });

  final String name;
  final Color? dot;

  /// 色点透明度（子分组沿用父级色 · 原型 `opacity-60`）。
  final double dotOpacity;
  final bool selected;

  /// 定宽（一级分类 6 列等分）；null=按内容自适应（子分组）。
  final double? width;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final fg = selected ? Colors.white : scheme.onSurfaceVariant;
    return SizedBox(
      width: width,
      height: 26,
      child: Material(
        color: selected
            ? tokens.accent
            : scheme.onSurface.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(999),
        child: Semantics(button: true, label: '选择分类', child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Row(
              mainAxisSize: width == null ? MainAxisSize.min : MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (dot != null) ...[
                  Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(3),
                          color: dot!.withValues(alpha: dotOpacity))),
                  const SizedBox(width: 3),
                ],
                Flexible(
                  child: Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 10,
                          height: 1.2,
                          fontWeight: FontWeight.w600,
                          color: fg)),
                ),
              ],
            ),
          ),
        )),
      ),
    );
  }
}

/// 虚线分隔（原型 border-t-2 border-dashed · V1.27 C5 分组区隔）。
class DashedDivider extends StatelessWidget {
  const DashedDivider({super.key, this.color});
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ??
        Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .8);
    return LayoutBuilder(
      builder: (context, constraints) {
        const dash = 5.0, gap = 4.0;
        final count = (constraints.maxWidth / (dash + gap)).floor();
        return SizedBox(
          height: 2,
          child: Row(
            children: [
              for (var i = 0; i < count; i++)
                Container(
                    width: dash,
                    height: 2,
                    margin: const EdgeInsets.only(right: gap),
                    color: c),
            ],
          ),
        );
      },
    );
  }
}
