import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../domain/goal_calc.dart';
import '../domain/goal_models.dart';
import 'goals_kit.dart';
import 'goals_providers.dart';

/// P10b 目标编辑（新建/修改共用；原型 renderGe/goalSave 4150-4180 对译）。
///
/// 口径：标题输入 + 周期 chips（年度目标 + 当年四季，stateLabel 提示，
/// 归档/未来均可选但保存时归档拦截）+ KR 行卡族（≥2 才可删、上限 4、
/// 目标值数字输入、单位/数据源底部弹层选项）+ 校验链逐字 + 删除二次确认。
class GoalEditPage extends ConsumerStatefulWidget {
  const GoalEditPage({this.goalId, super.key});

  final int? goalId;

  /// 路由表里不许塞闭包（深链不可用·兜底查不到），故本参数已摘。

  @override
  ConsumerState<GoalEditPage> createState() => _GoalEditPageState();
}

class _KrDraft {
  _KrDraft({
    this.id,
    required this.label,
    required this.target,
    required this.unit,
    required this.source,
    this.cur = 0,
  });

  final int? id;
  final TextEditingController label;
  final TextEditingController target;
  String unit;
  KrSource source;
  double cur;

  void dispose() {
    label.dispose();
    target.dispose();
  }
}

class _GoalEditPageState extends ConsumerState<GoalEditPage> {
  final _title = TextEditingController();
  final _rows = <_KrDraft>[];
  String _period = '';
  bool _inited = false;
  int _sort = 0;

  bool get _isEdit => widget.goalId != null;

  @override
  void initState() {
    super.initState();
    _period = ref.read(goalsPeriodProvider);
    // 原型 goalNew 默认两行：目标值 10 % / 1 项，数据源手动
    _rows.add(_KrDraft(
        label: TextEditingController(),
        target: TextEditingController(text: '10'),
        unit: '%',
        source: KrSource.manual));
    _rows.add(_KrDraft(
        label: TextEditingController(),
        target: TextEditingController(text: '1'),
        unit: '项',
        source: KrSource.manual));
  }

  @override
  void dispose() {
    _title.dispose();
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  void _toast(String msg) => AppToast.show(context, msg);

  void _loadFrom(Goal g) {
    if (_inited) return;
    _inited = true;
    _period = g.period;
    _sort = g.sort;
    _title.text = g.title;
    for (final r in _rows) {
      r.dispose();
    }
    _rows
      ..clear()
      ..addAll([
        for (final k in g.krs)
          _KrDraft(
              id: k.id,
              label: TextEditingController(text: k.label),
              target: TextEditingController(text: k.tgtText),
              unit: k.unit,
              source: k.source,
              cur: k.cur)
      ]);
  }

  /// KR 上限 4（原型 geKrAdd）。
  void _addKr() {
    if (_rows.length >= 4) {
      _toast('KR 上限 4 个 · 建议合并同类项');
      return;
    }
    setState(() => _rows.add(_KrDraft(
        label: TextEditingController(),
        target: TextEditingController(text: '1'),
        unit: '项',
        source: KrSource.manual)));
  }

  void _delKr(int i) => setState(() => _rows.removeAt(i).dispose());

  Future<void> _pickUnit(int i) async {
    final r = await showGoalsChoiceSheet(context,
        title: '单位', options: [...kKrUnits], selected: _rows[i].unit);
    if (r != null) setState(() => _rows[i].unit = r);
  }

  Future<void> _pickSource(int i) async {
    final labels = [for (final s in KrSource.values) s.label];
    final r = await showGoalsChoiceSheet(context,
        title: '数据源',
        options: labels,
        selected: _rows[i].source.label);
    if (r != null) {
      setState(() =>
          _rows[i].source = KrSource.values[labels.indexOf(r)]);
    }
  }

  Future<void> _save(GoalsData d) async {
    final t = _title.text.trim();
    if (t.isEmpty) {
      _toast('先写目标 O 标题');
      return;
    }
    if (_rows.length < 2) {
      _toast('至少 2 个 KR');
      return;
    }
    if (_rows.any((k) => k.label.text.trim().isEmpty)) {
      _toast('KR 描述不能为空');
      return;
    }
    if (d.isArchived(_period)) {
      _toast('归档周期不可写入 · 请选择进行中的周期');
      return;
    }
    final repo = ref.read(goalsRepositoryProvider);
    final krs = [
      for (final r in _rows)
        GoalKr(
          id: r.id,
          goalId: widget.goalId ?? 0,
          label: r.label.text.trim(),
          target: double.tryParse(r.target.text) ?? 0,
          unit: r.unit,
          source: r.source,
          cur: r.id != null ? r.cur : 0,
        )
    ];
    if (_isEdit) {
      await repo.updateGoal(
          Goal(id: widget.goalId, title: t, period: _period, sort: _sort, krs: krs));
      if (!mounted) return;
      goalsTouch(ref);
      _toast('目标已更新');
      Navigator.pop(context);
    } else {
      final id = await repo.addGoal(
          Goal(title: t, period: _period, sort: d.inPeriod(_period).length, krs: krs));
      if (!mounted) return;
      if (id == null) {
        _toast('目标数量上限提醒：$_period 已有 $kMaxOkrPerPeriod 个 O，建议先归档/收敛一个');
        return;
      }
      goalsTouch(ref);
      _toast('目标已创建到 $_period · KR 数据源已挂自动汇聚');
      Navigator.pop(context);
    }
  }

  Future<void> _delete() async {
    final ok = await goalsConfirm(context, '确认删除此目标？KR 与复盘记录一并移除',
        okKey: const ValueKey('g-edit-del-confirm'));
    if (!ok || !mounted) return;
    await ref.read(goalsRepositoryProvider).removeGoal(widget.goalId!);
    if (!mounted) return;
    goalsTouch(ref);
    _toast('目标已删除');
    // T10：带结果出栈，发起页（目标详情）收到 'purged' 后连退。
    Navigator.pop(context, 'purged');
  }

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(goalsClockProvider)();
    final async = ref.watch(goalsDataProvider);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_isEdit ? '编辑目标' : '新建目标'),
            Text('O ＋ 2~4 个 KR',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.normal,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (d) {
          if (_isEdit && !_inited) {
            final g = d.goals.where((x) => x.id == widget.goalId).firstOrNull;
            if (g != null) _loadFrom(g);
          }
          return _body(d, now);
        },
      ),
    );
  }

  Widget _body(GoalsData d, DateTime now) {
    final tokens = context.tokens;
    final qs = GoalPeriod.quartersOfYear(now.year);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      children: [
        TextField(
          key: const ValueKey('g-edit-title'),
          controller: _title,
          decoration:
              const InputDecoration(hintText: '目标 O 标题，如：O4 把身体养回来'),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 16, bottom: 6),
          child: Text('周期',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            PillChip(
              key: const ValueKey('g-edit-period-year'),
              label: GoalPeriod.yearBucket,
              selected: _period == GoalPeriod.yearBucket,
              onTap: () => setState(() => _period = GoalPeriod.yearBucket),
            ),
            for (var i = 0; i < qs.length; i++)
              PillChip(
                key: ValueKey('g-edit-period-q${i + 1}'),
                label: qs[i],
                selected: _period == qs[i],
                onTap: () => setState(() => _period = qs[i]),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6, left: 2),
          child: Text(
              key: const ValueKey('g-edit-period-state'),
              '$_period · ${GoalPeriod.stateLabel(_period, d.archivedPeriods, now)}',
              style: const TextStyle(fontSize: 10, color: kGoalsMuted)),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Row(
            children: [
              const Expanded(
                child: Text('关键结果 KR（2~4 个）',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
              ),
              MiniBtn(
                key: const ValueKey('g-edit-kr-add'),
                icon: Icons.add,
                label: '添加 KR',
                onTap: _addKr,
              ),
            ],
          ),
        ),
        for (var i = 0; i < _rows.length; i++)
          Container(
            key: ValueKey('g-edit-kr-$i'),
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: tokens.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: tokens.cardBorder),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Text('KR${i + 1}',
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: kGoalsMuted)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        key: ValueKey('g-edit-kr-$i-label'),
                        controller: _rows[i].label,
                        style: const TextStyle(fontSize: 12),
                        decoration: const InputDecoration(
                            hintText: '关键结果描述，如：每周运动 ≥3 次',
                            isDense: true),
                      ),
                    ),
                    if (_rows.length > 2)
                      IconButton(
                        key: ValueKey('g-edit-kr-$i-del'),
                        icon: const Icon(Icons.close,
                            size: 18, color: kGoalsMuted),
                        onPressed: () => _delKr(i),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('目标值',
                        style: TextStyle(fontSize: 11, color: kGoalsMuted)),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 64,
                      child: TextField(
                        key: ValueKey('g-edit-kr-$i-target'),
                        controller: _rows[i].target,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true, signed: false),
                        style: const TextStyle(fontSize: 12),
                        decoration: const InputDecoration(isDense: true),
                      ),
                    ),
                    const SizedBox(width: 6),
                    MiniBtn(
                      key: ValueKey('g-edit-kr-$i-unit'),
                      label: _rows[i].unit,
                      icon: Icons.expand_more,
                      onTap: () => _pickUnit(i),
                    ),
                    const Spacer(),
                    const Text('数据源',
                        style: TextStyle(fontSize: 11, color: kGoalsMuted)),
                    const SizedBox(width: 6),
                    MiniBtn(
                      key: ValueKey('g-edit-kr-$i-src'),
                      label: _rows[i].source.label,
                      icon: Icons.expand_more,
                      onTap: () => _pickSource(i),
                    ),
                  ],
                ),
              ],
            ),
          ),
        // 进度汇聚口径说明（原型 L1264 逐字，联动元信息保留）
        const GoalsNoteCard(
          '进度汇聚口径：KR 绑定数据源后自动按周期计算'
          '（待办完成数 / 阅读本数 / 日记篇数 / 习惯打卡 / 记账结余），也可随时手动回填。'
          '单周期目标数量建议 ≤ 5 个 O，超出时创建入口将提醒收敛。',
        ),
        const SizedBox(height: 16),
        GradButton(
          key: const ValueKey('g-edit-save'),
          label: _isEdit ? '保存修改' : '保存目标',
          onTap: () => _save(d),
        ),
        if (_isEdit)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: RoseOutlineButton(
              key: const ValueKey('g-edit-del'),
              label: '删除此目标',
              onTap: _delete,
            ),
          ),
      ],
    );
  }
}
