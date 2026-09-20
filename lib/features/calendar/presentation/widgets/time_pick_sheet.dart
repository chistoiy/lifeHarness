import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/category.dart';
import '../calendar_providers.dart';

/// 当月天数（避开 DateTime(y,m+1,0)：day-0 归一化在 FakeAsync 时区解析下会挂死）。
int daysInMonthOf(int y, int m) {
  const dm = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  if (m != 2) return dm[m - 1];
  return (y % 4 == 0 && (y % 100 != 0 || y % 400 == 0)) ? 29 : 28;
}

/// 统一添加事件/时间块弹层（V1.23 · 图2 · 轴/块/日/周共用）。
/// 上尾·起始 / 当前·结束 两组三列滚轮（日/时/分）+ 时长快捷 + 两级分类 + 备注 + 继续添加。
Future<void> showTimePickSheet(BuildContext context, WidgetRef ref,
    {DateTime? day, int? startMin}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _TimePick(day: day, startMin: startMin),
  );
}

class _TimePick extends ConsumerStatefulWidget {
  const _TimePick({this.day, this.startMin});
  final DateTime? day;
  final int? startMin;

  @override
  ConsumerState<_TimePick> createState() => _TimePickState();
}

/// 单向数据流：滚轮自持滚动状态，父层经 ValueNotifier 只读汇总，
/// 不在 onSel 后回写/重建滚轮——避免同帧重建回环。
class _TimePickState extends ConsumerState<_TimePick> {
  static const _durs = [0, 15, 30, 60, 120];

  late final DateTime _date;
  late final int _daysInMonth;
  // items 跨 rebuild 保持同一 List 实例：CupertinoPicker 每次 build 拿到新
  // delegate 会重置内部索引上报，故这些列表必须缓存进 state（不能就地新建）。
  //
  // ⚠️ 一律用 List.generate 而非 `[for (...; ...; ...) ...]` 集合推导：
  // 手写三段式 for 的增量子句极易漏写（曾把 `h++` 写成 `h`），而空增量在
  // 集合推导里是**静默无限循环**——同帧同步空转、列表无界 add，实测吃满
  // 单核并膨胀到 20GB OOM，且因不让出事件循环，`--timeout` 也杀不掉。
  // List.generate 没有增量子句，从结构上让该 bug 不可表示。
  late final List<String> _dayItems;
  late final List<String> _hourItems;
  late final List<String> _minItems;
  late final ValueNotifier<int> _dayN;
  late final ValueNotifier<int> _sMinN;
  late final ValueNotifier<int> _eDayN;
  late final ValueNotifier<int> _eMinN;
  late final Listenable _all;
  int? _catId;
  String _catName = '工作';
  String? _subName;
  final _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    final d = widget.day ?? DateTime.now();
    _date = DateTime(d.year, d.month, d.day);
    _daysInMonth = daysInMonthOf(_date.year, _date.month);
    _dayItems = List.generate(_daysInMonth, (i) => '${_date.month}/${i + 1}');
    _hourItems = List.generate(24, (h) => h.toString().padLeft(2, '0'));
    _minItems = List.generate(12, (i) => (i * 5).toString().padLeft(2, '0'));
    final sm = widget.startMin ?? (DateTime.now().hour * 60 ~/ 5 * 5);
    _dayN = ValueNotifier<int>(_date.day);
    _sMinN = ValueNotifier<int>(sm);
    _eDayN = ValueNotifier<int>(_date.day);
    _eMinN = ValueNotifier<int>((sm + 60).clamp(0, 1440));
    _all = Listenable.merge([_dayN, _sMinN, _eDayN, _eMinN]);
  }

  @override
  void dispose() {
    _note.dispose();
    _dayN.dispose();
    _sMinN.dispose();
    _eDayN.dispose();
    _eMinN.dispose();
    super.dispose();
  }

  int get _durMin => _eMinN.value - _sMinN.value;

  void _setDur(int min) {
    // 时长快捷：结束=起始+时长（封顶当日 24:00），驱动结束滚轮同步跳转。
    setState(() => _eMinN.value = (_sMinN.value + min).clamp(0, 1440));
  }

  static String _fmt(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

  Future<void> _add() async {
    final cats = ref.read(categoriesProvider).valueOrNull ?? const [];
    final id = _subName != null
        ? cats
            .where((c) => c.name == _subName && c.parentId == _catId)
            .map((c) => c.id)
            .firstOrNull
        : _catId;
    final date = DateTime(_date.year, _date.month, _dayN.value);
    final eDate = DateTime(_date.year, _date.month, _eDayN.value);
    final s = _sMinN.value;
    final e = _eMinN.value;
    final dao = ref.read(timeBlockDaoProvider);
    if (eDate == date) {
      await dao.markRange(date, s, e <= s ? s + 1 : e,
          catId: id,
          catName: _subName ?? _catName,
          note: _note.text.trim().isEmpty ? null : _note.text.trim());
      ref.invalidate(dayBlocksProvider(date));
    } else {
      // 跨天：拆两段（起始日到 24:00 + 结束日 00:00 到结束时刻）
      await dao.markRange(date, s, 1440,
          catId: id,
          catName: _subName ?? _catName,
          note: _note.text.trim().isEmpty ? null : _note.text.trim());
      await dao.markRange(eDate, 0, e <= 0 ? 1 : e,
          catId: id,
          catName: _subName ?? _catName,
          note: _note.text.trim().isEmpty ? null : _note.text.trim());
      ref.invalidate(dayBlocksProvider(date));
      ref.invalidate(dayBlocksProvider(eDate));
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text('✔ 已添加 ${_fmt(s)}-${_fmt(e)} · ${_subName ?? _catName}'
              '（四视图与时间账本同步 L4）')));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final cats = ref.watch(categoriesProvider).valueOrNull ?? const <Category>[];
    final catColors = ref.watch(catColorsByNameProvider);
    final primary = cats.where((c) => c.isPrimary).toList();
    final subs = cats.where((c) => c.parentId == _catId).toList();

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
                const Expanded(
                    child: Text('添加事件 / 时间块',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
                AnimatedBuilder(
                  animation: _all,
                  builder: (context, _) => Text(
                      '${_date.month}/${_dayN.value} ${_fmt(_sMinN.value)} → '
                      '${_date.month}/${_eDayN.value} ${_fmt(_eMinN.value)} · $_durMin 分钟',
                      style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant)),
                ),
              ],
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
                          onSel: (i) => _dayN.value = i + 1),
                      _Wheel(
                          items: _hourItems,
                          initialIndex: _sMinN.value ~/ 60,
                          onSel: (i) => _sMinN.value = i * 60 + _sMinN.value % 60),
                      _Wheel(
                          items: _minItems,
                          initialIndex: (_sMinN.value % 60) ~/ 5,
                          onSel: (i) => _sMinN.value = _sMinN.value ~/ 60 * 60 + i * 5),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _WheelGroup(
                    label: '当前 · 结束',
                    children: [
                      _Wheel(
                          items: _dayItems,
                          initialIndex: _eDayN.value - 1,
                          onSel: (i) => _eDayN.value = i + 1),
                      _Wheel(
                          items: _hourItems,
                          initialIndex: _eMinN.value ~/ 60,
                          onSel: (i) => _eMinN.value = i * 60 + _eMinN.value % 60),
                      _Wheel(
                          items: _minItems,
                          initialIndex: (_eMinN.value % 60) ~/ 5,
                          onSel: (i) => _eMinN.value = _eMinN.value ~/ 60 * 60 + i * 5),
                    ],
                  ),
                ),
              ],
            ),
            // 时长快捷 + 标签 / 无分类入口（原型 tpDur chips 行）
            const SizedBox(height: 8),
            Row(
              children: [
                Text('时长',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurfaceVariant)),
                const SizedBox(width: 6),
                for (final d in _durs)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onTap: () => _setDur(d),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 5),
                        decoration: BoxDecoration(
                          color: _durMin == d
                              ? tokens.accent
                              : scheme.onSurface.withValues(alpha: .08),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          d < 60 ? '$d分' : '${d ~/ 60}时',
                          style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: _durMin == d
                                  ? Colors.white
                                  : scheme.onSurfaceVariant),
                        ),
                      ),
                    ),
                  ),
                const Spacer(),
                GestureDetector(
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('标签将取所选分类的默认标签'))),
                  child: Text('标签 ›',
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurfaceVariant)),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => context.push('/categories'),
                  child: Text('无分类 ›',
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurfaceVariant)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text('分类（点一级 · 有次级再点次级精确到子项）',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in primary)
                  ChoiceChip(
                    visualDensity: VisualDensity.compact,
                    selected: _catName == c.name && _subName == null,
                    onSelected: (_) => setState(() {
                      _catId = c.id;
                      _catName = c.name;
                      _subName = null;
                    }),
                    avatar: Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(3),
                            color: c.name == '工作' ? tokens.accent : catColors[c.name])),
                    label: Text(c.name, style: const TextStyle(fontSize: 11)),
                  ),
              ],
            ),
            if (subs.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final sc in subs)
                    ChoiceChip(
                      visualDensity: VisualDensity.compact,
                      selected: _subName == sc.name,
                      onSelected: (_) =>
                          setState(() => _subName = _subName == sc.name ? null : sc.name),
                      label: Text('${sc.name}${sc.tag == null ? '' : ' ${sc.tag}'}',
                          style: const TextStyle(fontSize: 11)),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: _note,
              maxLength: 5000,
              decoration: const InputDecoration(
                  hintText: '请输入备注',
                  isDense: true,
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      _add();
                      setState(() => _note.clear());
                    },
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(46)),
                    child: const Text('继续添加'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                          gradient: tokens.gradient,
                          borderRadius: BorderRadius.circular(8)),
                      child: TextButton(
                        onPressed: () async {
                          await _add();
                          if (context.mounted) Navigator.of(context).pop();
                        },
                        child: const Text('添加',
                            style: TextStyle(
                                color: Colors.white, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Center(
                child: Text('5 分一档',
                    style:
                        TextStyle(fontSize: 10, color: scheme.onSurfaceVariant))),
          ],
        ),
      ),
    );
  }
}

class _WheelGroup extends StatelessWidget {
  const _WheelGroup({required this.label, required this.children});
  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
          color: scheme.onSurface.withValues(alpha: .05),
          borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
                color: scheme.onSurface.withValues(alpha: .85),
                borderRadius: BorderRadius.circular(6)),
            child: Text(label,
                style: const TextStyle(
                    fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white)),
          ),
          const SizedBox(height: 4),
          Row(children: children),
        ],
      ),
    );
  }
}

/// 单列滚轮：自持 controller（仅取初值）与选中高亮，滚动只回调 onSel；
/// 父层不得据此重建本组件（单向数据流，杜绝重建回环）。
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
    // 外部取值变化（如时长快捷 chip）驱动滚轮同步跳转；同值不动，避免自激。
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
        height: 96,
        child: ListenableBuilder(
          listenable: _selN,
          builder: (context, _) {
            final sel = _selN.value.clamp(0, _base.isEmpty ? 0 : _base.length - 1);
            return CupertinoPicker(
              scrollController: _ctl,
              itemExtent: 32,
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
                                  fontSize: 17,
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
