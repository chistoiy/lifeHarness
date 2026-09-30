import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/ai/ai_review.dart';
import '../../../../core/providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/wheel_date.dart';
import '../todo_providers.dart';
import '../../../../core/widgets/wheel_time.dart';
import '../../../../shared/linkage/stats_providers.dart';

/// 打开新建弹层（原型 sheetAddTask）。
/// [type] norm/pomo（FAB 前置选择决定，弹层内不再显示类型切换）；
/// [preset] 预置两问答案（失衡提醒「去规划」= Quadrant.q2）；
/// [editing] 非空=编辑态（V1.27 T3 详情复用本表单，保存覆盖原条目）。
Future<void> showTodoAddSheet(BuildContext context, WidgetRef ref,
    {String type = 'norm', Quadrant? preset, Todo? editing}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _TodoAddSheet(type: type, preset: preset, editing: editing),
  );
}

/// 打开任务详情/编辑弹层（原型 sheetTask）。
Future<void> showTodoDetailSheet(BuildContext context, WidgetRef ref, Todo todo) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _TodoDetailSheet(todo: todo),
  );
}

/// 到期文本（原型 due 展示：今天/明天/本周/已逾期 N 天/MM-dd）。
String dueLabel(Todo t) {
  if (t.dueAt == null) return '—';
  final now = DateTime.now();
  final due = t.dueAt!;
  final today = DateTime(now.year, now.month, now.day);
  final dueDay = DateTime(due.year, due.month, due.day);
  final diff = dueDay.difference(today).inDays;
  if (t.overdue) return diff <= -1 ? '已逾期 ${-diff} 天' : '已逾期';
  if (diff == 0) return '今天';
  if (diff == 1) return '明天';
  if (diff < 7) return '本周';
  return '${due.month.toString().padLeft(2, '0')}-${due.day.toString().padLeft(2, '0')}';
}

void _toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(milliseconds: 1600)));
}

/// 原型 CAT_COLORS（设置·分类管理共用色板的 9 个命名色）。
const catColorNames = <(String, String)>[
  ('亚麻色', '#A16207'),
  ('品牌蓝', '#6366F1'),
  ('天青', '#38BDF8'),
  ('橙', '#FB923C'),
  ('玫瑰', '#FB7185'),
  ('薄荷', '#2DD4BF'),
  ('紫罗兰', '#8B5CF6'),
  ('石墨', '#64748B'),
  ('靛夜', '#3730A3'),
];

Color catColorOf(int idx, Color accent) => idx == 1
    ? accent // 品牌蓝随主题令牌
    : Color(0xFF000000 |
        (int.tryParse(catColorNames[idx].$2.substring(1), radix: 16) ?? 0));

class _TodoAddSheet extends ConsumerStatefulWidget {
  const _TodoAddSheet({required this.type, this.preset, this.editing});

  /// norm | pomo（FAB 前置选择传入；编辑态按条目是否番茄取）。
  final String type;

  /// 预置判象限两问（null=不预置，走原型未答态）。
  final Quadrant? preset;

  /// 非空=编辑已有条目（V1.27 T3）。
  final Todo? editing;

  @override
  ConsumerState<_TodoAddSheet> createState() => _TodoAddSheetState();
}

class _TodoAddSheetState extends ConsumerState<_TodoAddSheet> {
  late final TextEditingController _title =
      TextEditingController(text: widget.editing?.title ?? '');
  late bool? _imp = widget.editing != null
      ? widget.editing!.quadrant.value <= 2
      : widget.preset == null
          ? null
          : widget.preset!.value <= 2; // q1/q2=重要
  late bool? _urg = widget.editing != null
      ? (widget.editing!.quadrant == Quadrant.q1 ||
          widget.editing!.quadrant == Quadrant.q3)
      : widget.preset == null
          ? null
          : (widget.preset == Quadrant.q1 || widget.preset == Quadrant.q3);
  DateTime? _due;
  int _remind = 1; // 0 不提醒 1 当天HH:MM(默认09:00) 2 提前1小时 3 自定义时刻
  TimeOfDay _remindAt = const TimeOfDay(hour: 9, minute: 0); // 自定义提醒时刻

  // ===== 原型 sheetAddTask 扩展字段 =====
  late final String _type = widget.editing != null
      ? (widget.editing!.isPomo ? 'pomo' : 'norm')
      : widget.type; // norm | pomo
  String _pomoMode = 'up'; // up 正计时 | down 倒计时
  int _pomoMin = 25;
  String _status = 'open'; // open | done | drop
  String _timeMode = 'none'; // none | point | range | all
  late TimeOfDay _tStart;
  late TimeOfDay _tEnd;
  int? _colorIdx;
  bool _linkOn = false; // 关联计时分类
  String? _linkCatName; // 选中的计时分类名（保存时解析为 id）
  String _bindHabit = '不绑定';

  bool get _isEdit => widget.editing != null;

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    // 原型截止日期默认明天；时间点/段默认当前时间（5 分一档）。
    _due = DateTime(n.year, n.month, n.day + 1, 18);
    final t = TimeOfDay(hour: n.hour, minute: ((n.minute / 5).round() * 5) % 60);
    _tStart = t;
    _tEnd = t;
    final e = widget.editing;
    if (e != null) {
      // 编辑态回填（V1.27 T3 复用新建表单）
      _due = e.dueAt;
      _status = e.dropped ? 'drop' : (e.done ? 'done' : 'open');
      _pomoMode = e.pomoMode ?? 'up';
      _pomoMin = (e.pomoMin ?? 25).clamp(1, 60);
      _timeMode = e.timeMode ?? 'none';
      if (e.startMin != null) {
        _tStart = TimeOfDay(hour: e.startMin! ~/ 60, minute: e.startMin! % 60);
      }
      if (e.endMin != null) {
        _tEnd = TimeOfDay(hour: e.endMin! ~/ 60, minute: e.endMin! % 60);
      }
      _colorIdx = e.colorIdx;
      _linkOn = e.linkCat != null;
      if (e.remindAt != null) {
        _remindAt = TimeOfDay(hour: e.remindAt!.hour, minute: e.remindAt!.minute);
        _remind = 3;
      }
    }
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  int get _sMin => _tStart.hour * 60 + _tStart.minute;
  int get _eMin => _tEnd.hour * 60 + _tEnd.minute;

  Quadrant get _derived => (_imp == true && _urg == true)
      ? Quadrant.q1
      : _imp == true
          ? Quadrant.q2
          : _urg == true
              ? Quadrant.q3
              : Quadrant.q4;

  Future<void> _pickDue() async {
    // V1.27 T5：截止日期复用时间模块三列滚轮弹层（年/月/日）。
    final now = DateTime.now();
    final d = await showWheelDatePick(context, _due ?? now.add(const Duration(days: 1)));
    if (d != null) {
      setState(() => _due = DateTime(d.year, d.month, d.day, 18));
    }
  }

  /// 自定义提醒时刻（时/分双列滚轮，原型「自定义时间…」）。
  Future<void> _pickRemindTime() async {
    var h = _remindAt.hour, m = _remindAt.minute;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      builder: (bc) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('提醒时刻',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              SizedBox(
                height: 120,
                child: InlineWheelTime(
                    initial: _remindAt, onChanged: (hh, mm) { h = hh; m = mm; }),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(bc).pop(false),
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(42)),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 42,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                            gradient: bc.tokens.gradient,
                            borderRadius: BorderRadius.circular(12)),
                        child: TextButton(
                          onPressed: () => Navigator.of(bc).pop(true),
                          child: const Text('确定',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (ok == true) setState(() => _remindAt = TimeOfDay(hour: h, minute: m));
  }

  DateTime get _remindDateTime {
    final base = _due ?? DateTime.now();
    return DateTime(base.year, base.month, base.day, _remindAt.hour, _remindAt.minute);
  }

  /// AI批4-A：AI 判象限（能力点 todo.quadrant）。走 core/ai 通用通道：
  /// 三重门控 → 发送前审阅弹层 → 请求 + 结构校验；取消/失败由通道 toast 归因。
  /// 结果只写入表单两问状态（[_imp]/[_urg]），保存后才落库。
  Future<void> _aiQuadrant() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      _toast(context, 'AI 判象限：请先输入任务标题');
      return;
    }
    final result = await aiRunWithReview(context, ref,
        taskId: 'todo.quadrant', vars: {'title': title});
    if (result == null || !mounted) return;
    final q = (result.requireJson()['quadrant'] as int).clamp(1, 4);
    final reason = '${result.requireJson()['reason']}';
    setState(() {
      _imp = q <= 2; // 1/2=重要
      _urg = q.isOdd; // 1/3=紧急
    });
    _toast(context, 'AI 判定：Q$q · $reason（保存后生效）');
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      _toast(context, '请先输入任务标题');
      return;
    }
    DateTime? remindAt;
    if (_remind == 1) {
      remindAt = DateTime(
          (_due ?? DateTime.now()).year,
          (_due ?? DateTime.now()).month,
          (_due ?? DateTime.now()).day,
          9);
    } else if (_remind == 2) {
      remindAt = _due?.subtract(const Duration(hours: 1));
    } else if (_remind == 3) {
      remindAt = _remindDateTime;
    }
    // 关联计时分类：按名称解析为全局分类表 id（V1.19.1 同源）。
    int? linkCat;
    if (_timeMode != 'none' || _type == 'pomo') {
      final cats = ref.read(categoriesProvider).valueOrNull ?? const <Category>[];
      final want = _linkCatName ?? cats.where((c) => c.isPrimary).firstOrNull?.name;
      linkCat = cats.where((c) => _linkOn && c.name == want).map((c) => c.id).firstOrNull;
    }
    final q = _derived;
    final repo = ref.read(todoRepositoryProvider);
    if (_isEdit) {
      // V1.27 T3：编辑态覆盖原条目（保留 id/sort_order/时间字段回填）。
      final e = widget.editing!;
      await repo.edit(e.copyWith(
        title: title,
        quadrant: q,
        dueAt: _due,
        remindAt: remindAt,
        done: _status == 'done' || _status == 'drop',
        dropped: _status == 'drop',
        tag: _status == 'drop' ? '放弃' : (e.tag == '收集箱' || e.tag == '日记' ? e.tag : null),
        pomoMode: _type == 'pomo' ? _pomoMode : null,
        pomoMin: _type == 'pomo' && _pomoMode == 'down' ? _pomoMin : null,
        timeMode: _timeMode == 'none' ? null : _timeMode,
        startMin: _timeMode == 'point' || _timeMode == 'range'
            ? _sMin
            : (_timeMode == 'all' ? 0 : null),
        endMin: _timeMode == 'range'
            ? (_eMin <= _sMin ? 0 : _eMin)
            : (_timeMode == 'all' ? 1440 : null),
        colorIdx: _colorIdx,
        linkCat: linkCat,
      ));
    } else {
      await repo.add(Todo(
        title: title,
        quadrant: q,
        dueAt: _due,
        remindAt: remindAt,
        done: _status == 'done' || _status == 'drop',
        dropped: _status == 'drop',
        tag: _status == 'drop' ? '放弃' : null,
        pomoMode: _type == 'pomo' ? _pomoMode : null,
        pomoMin: _type == 'pomo' && _pomoMode == 'down' ? _pomoMin : null,
        timeMode: _timeMode == 'none' ? null : _timeMode,
        startMin: _timeMode == 'point' || _timeMode == 'range'
            ? _sMin
            : (_timeMode == 'all' ? 0 : null),
        endMin: _timeMode == 'range'
            ? (_eMin <= _sMin ? 0 : _eMin)
            : (_timeMode == 'all' ? 1440 : null),
        colorIdx: _colorIdx,
        linkCat: linkCat,
      ));
    }
    ref.invalidate(todosProvider);
    ref.invalidate(overdueCountProvider);
    if (!mounted) return;
    Navigator.of(context).pop();
    _toast(context, _isEdit ? '修改已保存 ✓' : '已保存到「${q.label}」象限 ✓');
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final cats = ref.watch(categoriesProvider).valueOrNull ?? const <Category>[];
    final primary = cats.where((c) => c.isPrimary).toList();

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 14, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_isEdit ? '编辑待办' : '新建待办',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            // V1.27 T4：类型由 FAB 前置二选一决定，弹层内不再放类型段；名称置顶。
            TextField(
              controller: _title,
              autofocus: !_isEdit,
              decoration: const InputDecoration(
                  hintText: '任务标题，如：给绿植浇水', isDense: true),
              textInputAction: TextInputAction.next,
            ),
            // ===== V1.27 T5：番茄配置卡（倒计时=横向进度条 1~60 分 + 5/15/30/45 快捷点） =====
            if (_type == 'pomo') ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF43F5E).withValues(alpha: .06),
                  borderRadius: BorderRadius.circular(14),
                  border:
                      Border.all(color: const Color(0xFFF43F5E).withValues(alpha: .25)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('🍅 番茄计时',
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFE11D48))),
                        const Spacer(),
                        _MiniSeg(
                          options: const [('up', '正计时'), ('down', '倒计时')],
                          value: _pomoMode,
                          onChanged: (v) => setState(() => _pomoMode = v),
                        ),
                      ],
                    ),
                    if (_pomoMode == 'down') ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Text('$_pomoMin 分钟',
                              key: const ValueKey('pomo-min-label'),
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFFE11D48))),
                        ],
                      ),
                      Slider(
                        key: const ValueKey('pomo-min'),
                        value: _pomoMin.toDouble().clamp(1, 60),
                        min: 1,
                        max: 60,
                        activeColor: const Color(0xFFF43F5E),
                        onChanged: (v) => setState(() => _pomoMin = v.round()),
                      ),
                      Row(
                        children: [
                          for (final m in const [5, 15, 30, 45])
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: InkWell(
                                key: ValueKey('pomo-quick-$m'),
                                borderRadius: BorderRadius.circular(20),
                                onTap: () => setState(() => _pomoMin = m),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: _pomoMin == m
                                        ? const Color(0xFFF43F5E)
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                        color: const Color(0xFFF43F5E)
                                            .withValues(alpha: .5)),
                                  ),
                                  child: Text('$m′',
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          color: _pomoMin == m
                                              ? Colors.white
                                              : const Color(0xFFE11D48))),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text('完成后自动写入时间模块（L4）· 上限 60 分钟',
                        style: TextStyle(
                            fontSize: 10.5, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text('引导式判象限（推荐）',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _AskCard(
                    question: '这件事重要吗？',
                    sub: '对目标/价值有贡献',
                    answer: _imp,
                    accent: tokens.accent,
                    onTap: () => setState(() => _imp = _imp == true ? false : true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _AskCard(
                    question: '这件事紧急吗？',
                    sub: '有明确近期期限',
                    answer: _urg,
                    accent: tokens.accent,
                    onTap: () => setState(() => _urg = _urg == true ? false : true),
                  ),
                ),
              ],
            ),
            // V1.27 追加：预置两问答案的直观落点预览（保存后进入对应象限，可随时改点）
            if (_imp != null && _urg != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _derived.colorOf(tokens.accent)),
                  ),
                  const SizedBox(width: 6),
                  Text('保存后进入「${_derived.label}」象限',
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: _derived.colorOf(tokens.accent))),
                ],
              ),
            ],
            const SizedBox(height: 10),
            // ===== 状态三态（原型 tsOpenB/tsDoneB/tsDropB） =====
            Row(
              children: [
                const Text('状态', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                const Spacer(),
                _MiniSeg(
                  options: const [('open', '未完成'), ('done', '完成'), ('drop', '放弃')],
                  value: _status,
                  colorFor: {'done': const Color(0xFF10B981), 'drop': const Color(0xFFF43F5E)},
                  onChanged: (v) => setState(() => _status = v),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // ===== 颜色 / 分组（原型 tsColor + 未分组›） =====
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Text('颜色', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                      Text('（体现在时间模块）',
                          style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                      const SizedBox(width: 6),
                      if (_colorIdx != null)
                        Container(
                            width: 12,
                            height: 12,
                            margin: const EdgeInsets.only(right: 4),
                            decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: catColorOf(_colorIdx!, tokens.accent))),
                      DropdownButton<int>(
                        value: _colorIdx,
                        hint: Text('默认', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                        isDense: true,
                        isExpanded: false,
                        underline: const SizedBox.shrink(),
                        items: [
                          for (var i = 0; i < catColorNames.length; i++)
                            DropdownMenuItem(
                                value: i,
                                child: Text(catColorNames[i].$1,
                                    style: const TextStyle(fontSize: 11))),
                        ],
                        onChanged: (v) => setState(() => _colorIdx = v),
                      ),
                    ],
                  ),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _toast(context, '分组管理 · 敬请期待（默认未分组）'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                    child: Row(
                        children: const [
                          Text('分组 · 未分组 ›',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF6366F1))),
                        ]),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // ===== 截止日期 / 提醒 =====
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _pickDue,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.event, size: 15, color: scheme.onSurfaceVariant),
                          const SizedBox(width: 6),
                          Text(
                            _due == null
                                ? '选择截止日期'
                                : '${_due!.year}-${_due!.month.toString().padLeft(2, '0')}-${_due!.day.toString().padLeft(2, '0')}',
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: _remind,
                        isDense: true,
                        isExpanded: true,
                        borderRadius: BorderRadius.circular(12),
                        items: [
                          const DropdownMenuItem(value: 1, child: Text('提醒 · 当天 09:00', style: TextStyle(fontSize: 12))),
                          DropdownMenuItem(
                              value: 3,
                              child: Text(
                                  // 菜单里必须写「自定义时间…」（原型 ntRemind 第二项同字面）；
                                  // 之前跟着当前时刻显示成「提醒 · 当天 09:00」，与第一项同字面，
                                  // 真机反馈看着像重复项、点下去才知道是自定义。选中后才显具体时刻。
                                  _remind == 3
                                      ? '提醒 · 当天 ${_remindAt.hour.toString().padLeft(2, '0')}:${_remindAt.minute.toString().padLeft(2, '0')}'
                                      : '提醒 · 自定义时间…',
                                  style: const TextStyle(fontSize: 12))),
                          const DropdownMenuItem(value: 2, child: Text('提醒 · 提前1小时', style: TextStyle(fontSize: 12))),
                          const DropdownMenuItem(value: 0, child: Text('提醒 · 不提醒', style: TextStyle(fontSize: 12))),
                        ],
                        onChanged: (v) async {
                          if (v == 3) {
                            // 选中「自定义」即开滚轮改时刻（V1.27 T5 提醒默认9点可改）
                            setState(() => _remind = 3);
                            await _pickRemindTime();
                          } else {
                            setState(() => _remind = v ?? 0);
                          }
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                InkWell(
                  onTap: () => _toast(context, '重复规则 · 敬请期待'),
                  child: Text('重复：不重复 ›',
                      style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
                ),
                const Spacer(),
                InkWell(
                  onTap: () => _toast(context, '两级子任务 · 敬请期待'),
                  child: Text('子任务：＋ 添加',
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: tokens.accent)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // ===== 设置时间卡（原型 tk* 灰底容器） =====
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.onSurface.withValues(alpha: .05),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('设置时间',
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
                      const Spacer(),
                      _MiniSeg(
                        options: const [
                          ('none', '无'),
                          ('point', '时间点'),
                          ('range', '时间段'),
                          ('all', '全天'),
                        ],
                        value: _timeMode,
                        compact: true,
                        onChanged: (m) => setState(() {
                          _timeMode = m;
                          // 每次进入模式重置默认=当前时间（5 分一档）
                          final n = DateTime.now();
                          final t = TimeOfDay(
                              hour: n.hour, minute: ((n.minute / 5).round() * 5) % 60);
                          if (m == 'point' || m == 'range') _tStart = t;
                          if (m == 'range') _tEnd = t;
                        }),
                      ),
                    ],
                  ),
                  if (_timeMode == 'point') ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        SizedBox(
                            width: 40,
                            child: Text('时间点',
                                style: TextStyle(
                                    fontSize: 12, color: scheme.onSurfaceVariant))),
                        Expanded(
                          child: InlineWheelTime(
                            key: const ValueKey('tk-point'),
                            initial: _tStart,
                            onChanged: (h, m) => _tStart = TimeOfDay(hour: h, minute: m),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (_timeMode == 'range') ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        SizedBox(
                            width: 40,
                            child: Text('起',
                                style: TextStyle(
                                    fontSize: 12, color: scheme.onSurfaceVariant))),
                        Expanded(
                          child: InlineWheelTime(
                            key: const ValueKey('tk-start'),
                            initial: _tStart,
                            onChanged: (h, m) => _tStart = TimeOfDay(hour: h, minute: m),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        SizedBox(
                            width: 40,
                            child: Text('止',
                                style: TextStyle(
                                    fontSize: 12, color: scheme.onSurfaceVariant))),
                        Expanded(
                          child: InlineWheelTime(
                            key: const ValueKey('tk-end'),
                            initial: _tEnd,
                            onChanged: (h, m) => _tEnd = TimeOfDay(hour: h, minute: m),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (_timeMode == 'all')
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('全天 · 在日程视图顶部以横幅展示；时间段起止相同将自动转为全天',
                          style: TextStyle(
                              fontSize: 10.5, color: scheme.onSurfaceVariant)),
                    ),
                  if (_timeMode != 'none') ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        SizedBox(
                          width: 22,
                          height: 22,
                          child: Checkbox(
                            value: _linkOn,
                            activeColor: tokens.accent,
                            onChanged: (v) => setState(() => _linkOn = v ?? false),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text('关联计时分类（完成后按实际耗时入 L4 账本）',
                            style: TextStyle(fontSize: 11)),
                      ],
                    ),
                    if (_linkOn && primary.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: DropdownButton<String>(
                          value: _linkCatName ?? primary.first.name,
                          isDense: true,
                          isExpanded: true,
                          underline: const SizedBox.shrink(),
                          items: [
                            for (final c in primary)
                              DropdownMenuItem(
                                  value: c.name,
                                  child: Text('计时分类 · ${c.name}',
                                      style: const TextStyle(fontSize: 12))),
                          ],
                          onChanged: (v) => setState(() => _linkCatName = v),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text('绑定习惯打卡（完成即回写）', style: TextStyle(fontSize: 11)),
                        const Spacer(),
                        DropdownButton<String>(
                          value: _bindHabit,
                          isDense: true,
                          underline: const SizedBox.shrink(),
                          items: const [
                            DropdownMenuItem(value: '不绑定', child: Text('不绑定', style: TextStyle(fontSize: 12))),
                          ],
                          onChanged: (v) => setState(() => _bindHabit = v ?? '不绑定'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            // ===== AI 自动判象限（原型虚线品牌色钮） =====
            InkWell(
              key: const ValueKey('ai-quadrant-btn'),
              borderRadius: BorderRadius.circular(12),
              onTap: _aiQuadrant,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: tokens.accent.withValues(alpha: .6)),
                ),
                alignment: Alignment.center,
                child: Text('AI 自动判象限（依据标题）',
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700, color: tokens.accent)),
              ),
            ),
            const SizedBox(height: 12),
            // ===== 取消 / 存入四象限 =====
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(46)),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                          gradient: tokens.gradient,
                          borderRadius: BorderRadius.circular(12)),
                      child: TextButton(
                        onPressed: _save,
                        child: Text(_isEdit ? '保存修改' : '保存',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 14)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 小型分段选择器（原型 p-1 深灰底 + seg-on 白底）。
class _MiniSeg extends StatelessWidget {
  const _MiniSeg({
    required this.options,
    required this.value,
    required this.onChanged,
    this.colorFor,
    this.compact = false,
  });

  final List<(String, String)> options;
  final String value;
  final ValueChanged<String> onChanged;
  final Map<String, Color>? colorFor;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (v, label) in options)
            GestureDetector(
              onTap: () => onChanged(v),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                padding: EdgeInsets.symmetric(
                    horizontal: compact ? 8 : 10, vertical: compact ? 4 : 5),
                decoration: BoxDecoration(
                  color: v == value ? scheme.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(7),
                  boxShadow: v == value
                      ? const [BoxShadow(color: Color(0x1A0F172A), blurRadius: 4)]
                      : null,
                ),
                child: Text(
                  label,
                  style: TextStyle(
                      fontSize: compact ? 10.5 : 11,
                      fontWeight: FontWeight.w700,
                      color: v == value
                          ? (colorFor?[v] ?? scheme.onSurface)
                          : scheme.onSurfaceVariant),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 引导两问卡（原型 .q-ask）：未答显示副文案，答后显示 是 ✓ / 否。
class _AskCard extends StatelessWidget {
  const _AskCard({
    required this.question,
    required this.sub,
    required this.answer,
    required this.accent,
    required this.onTap,
  });

  final String question;
  final String sub;
  final bool? answer;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final answered = answer != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: answered ? accent : Colors.grey.withValues(alpha: .4),
            width: answered ? 1.6 : 1,
          ),
          color: answered ? accent.withValues(alpha: .08) : Colors.transparent,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(question, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text(
              answer == null ? sub : (answer == true ? '是 ✓' : '否'),
              style: TextStyle(
                fontSize: 11,
                color: answer == null
                    ? Colors.grey
                    : (answer == true ? accent : Colors.grey),
                fontWeight: answer == null ? FontWeight.normal : FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 任务详情（原型 sheetTask：圆形勾选 + 右上删除 + q-move 四钮 + 关联信息行 + 关闭）。
class _TodoDetailSheet extends ConsumerStatefulWidget {
  const _TodoDetailSheet({required this.todo});

  final Todo todo;

  @override
  ConsumerState<_TodoDetailSheet> createState() => _TodoDetailSheetState();
}

class _TodoDetailSheetState extends ConsumerState<_TodoDetailSheet> {
  late Todo _t = widget.todo;

  static const _qMoveLabels = ['立即做', '计划做', '委托', '淘汰'];

  static String _hm2(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

  Future<void> _toggleDone() async {
    await ref.read(todoRepositoryProvider).toggleDone(_t);
    ref.invalidate(todosProvider);
    ref.invalidate(overdueCountProvider);
    setState(() => _t = _t.copyWith(done: !_t.done));
  }

  Future<void> _move(Quadrant q) async {
    if (q == _t.quadrant) return;
    await ref.read(todoRepositoryProvider).moveQuadrant(_t, q);
    ref.invalidate(todosProvider);
    ref.invalidate(overdueCountProvider);
    setState(() => _t = _t.copyWith(quadrant: q));
    if (mounted) _toast(context, '已改判为「${q.label}」（拖拽同样可用）');
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final t = _t;
    final qc = t.quadrant.colorOf(tokens.accent);

    final planBlock = t.timeMode == null
        ? null
        : t.timeMode == 'all'
            ? '今日 全天（联动 L1）'
            : (t.timeMode == 'point'
                ? '今日 ${_hm2(t.startMin ?? 0)}（联动 L1）'
                : '今日 ${_hm2(t.startMin ?? 0)}-${_hm2(t.endMin ?? 0)}（联动 L1）');

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 14, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 圆形勾选（原型 sheetTask 顶部 chk）
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: _toggleDone,
                  child: Container(
                    width: 24,
                    height: 24,
                    margin: const EdgeInsets.only(top: 2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: t.done ? qc : Colors.transparent,
                      border: Border.all(color: qc, width: 2),
                    ),
                    child: t.done
                        ? const Icon(Icons.check, size: 15, color: Colors.white)
                        : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.title,
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              decoration:
                                  t.done ? TextDecoration.lineThrough : null,
                              color: t.done ? Colors.grey : scheme.onSurface)),
                      const SizedBox(height: 2),
                      Text(
                          '⏰ ${dueLabel(t)}'
                          '${t.remindAt != null ? ' · 提醒 ${t.remindAt!.month.toString().padLeft(2, '0')}-${t.remindAt!.day.toString().padLeft(2, '0')} ${t.remindAt!.hour.toString().padLeft(2, '0')}:${t.remindAt!.minute.toString().padLeft(2, '0')}' : ''}'
                          '${t.tag != null ? ' · #${t.tag}' : ''}',
                          style: TextStyle(
                              fontSize: 11.5, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // ✏️ 编辑（T3：复用新建弹层编辑态回填）
                OutlinedButton(
                  onPressed: () {
                    final navigator = Navigator.of(context);
                    final bc = context;
                    navigator.pop();
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (bc.mounted) {
                        showTodoAddSheet(bc, ref,
                            type: t.pomoMode == null ? 'norm' : 'pomo',
                            editing: t);
                      }
                    });
                  },
                  style: OutlinedButton.styleFrom(
                      foregroundColor: tokens.accent,
                      side: BorderSide(color: tokens.accent.withValues(alpha: .4)),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                  child: const Text('✏️ 编辑', style: TextStyle(fontSize: 11)),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    final messenger = ScaffoldMessenger.of(context);
                    // V1.57 E 批：删除＝软删进垃圾箱；keep 须在 pop 前取（弹层销毁后 ref 失效）
                    final keep = ref.read(settingsControllerProvider).trashKeepTxt;
                    await ref.read(todoRepositoryProvider).softRemove(t);
                    ref.invalidate(todosProvider);
                    ref.invalidate(overdueCountProvider);
                    navigator.pop();
                    messenger.showSnackBar(SnackBar(content: Text('已移入垃圾箱 · $keep'), duration: const Duration(milliseconds: 1600)));
                  },
                  style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFF43F5E),
                      side: const BorderSide(color: Color(0xFFFDA4AF)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                  child: const Text('🗑 删除', style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // q-move 四钮（原型 grid-cols-4）
            Row(
              children: [
                for (var i = 0; i < 4; i++)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: i == 3 ? 0 : 8),
                      child: GestureDetector(
                        onTap: () => _move(Quadrant.of(i + 1)),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: t.quadrant.value == i + 1
                                ? tokens.accent
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: t.quadrant.value == i + 1
                                    ? tokens.accent
                                    : scheme.outlineVariant),
                          ),
                          child: Text(
                            _qMoveLabels[i],
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: t.quadrant.value == i + 1
                                    ? Colors.white
                                    : scheme.onSurfaceVariant),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            // 关联信息行（原型 text-xs space-y-2）
            _InfoRow(label: '子任务', value: '—'),
            _InfoRow(
                label: '计划时间块',
                value: planBlock ?? '未设置',
                valueColor: planBlock != null ? tokens.accent : null,
                bold: planBlock != null),
            _InfoRow(
                label: '实际耗时',
                value: t.isPomo ? '番茄结束后自动入账' : '手动回填（番茄钟自动 · V1.x）'),
            _InfoRow(label: '关联目标', value: '—'),
            if (t.note != null && t.note!.isNotEmpty)
              _InfoRow(label: '备注', value: t.note!),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                    foregroundColor: scheme.onSurface),
                child: const Text('关闭'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.valueColor, this.bold = false});

  final String label;
  final String value;
  final Color? valueColor;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          Text(value,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
                  color: valueColor ?? scheme.onSurface)),
        ],
      ),
    );
  }
}
