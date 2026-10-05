import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../../../shared/widgets/load_error_state.dart';
import '../domain/care_models.dart';
import 'care_kit.dart';
import 'care_providers.dart';

/// p-vaccine 疫苗计划（原型 C9）：hero 汇总 + 计划中/已完成/全部三态 +
/// sheetVaxAdd 新建/编辑 + 完成/重新发起/凭证。状态按日期推导（plan|late|done）。
class VaccinePage extends ConsumerStatefulWidget {
  const VaccinePage({super.key});

  @override
  ConsumerState<VaccinePage> createState() => _VaccinePageState();
}

class _VaccinePageState extends ConsumerState<VaccinePage> {
  String _view = 'plan'; // plan|done|all

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(careDataProvider);
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('疫苗计划'),
            Text('完成自动生成下次接种提醒',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.normal)),
          ],
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => LoadErrorBanner(
              title: '疫苗接种计划没加载出来',
              error: e,
              onRetry: () => ref.invalidate(careDataProvider),
            ),
        data: (d) {
          final baby = d.currentBaby;
          if (baby == null) {
            return const Center(
                child: Text('先建立宝宝档案',
                    style: TextStyle(fontSize: 11, color: Colors.grey)));
          }
          final today = DateTime.now().withoutTimeCare();
          final vax = d.vaccines;
          final pending = vax.where((x) => !x.done).toList();
          final next = (vax
                  .where((x) => x.status(today) == 'plan')
                  .toList()
                ..sort((a, b) => a.due.compareTo(b.due)))
              .firstOrNull;
          final shown = vax.where((x) => switch (_view) {
            'plan' => !x.done,
            'done' => x.done,
            _ => true,
          }).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: careGrad(const ['#34d399', '#38bdf8', '#818cf8'],
                      begin: const Alignment(-.9, -1), end: const Alignment(.9, 1)),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('👶 ${baby.name} · 疫苗计划',
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: Colors.white)),
                        GestureDetector(
                          key: const ValueKey('vx-add'),
                          onTap: () => showVaxForm(context),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                                color: Colors.white24,
                                borderRadius: BorderRadius.circular(999)),
                            child: const Text('+ 新增计划',
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '待接种 ${pending.length} 剂 · 下一剂 '
                      '${next == null ? '—' : '${next.due.substring(5)} ${next.name}'}'
                      '（提前 7 天提醒，联动重要日子倒数）',
                      style: const TextStyle(fontSize: 10.5, color: Colors.white),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _SegRow(
                labels: const ['计划中', '已完成', '全部'],
                keys: const ['vax-t-plan', 'vax-t-done', 'vax-t-all'],
                selected: ['plan', 'done', 'all'].indexOf(_view),
                onPick: (i) => setState(() => _view = ['plan', 'done', 'all'][i]),
              ),
              const SizedBox(height: 12),
              for (final x in shown) _vaxRow(context, x, today),
              if (shown.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                      child: Text('暂无该状态疫苗',
                          style: TextStyle(fontSize: 11, color: Colors.grey))),
                ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: context.cardDecoration,
                child: Text.rich(
                  const TextSpan(style: TextStyle(fontSize: 11, height: 1.7, color: Colors.grey), children: [
                    TextSpan(
                        text: '免疫规划说明\n',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF64748B))),
                    TextSpan(
                        text: '标记「免规」为国家免疫规划疫苗（免费）；「自费」为推荐非强制。'
                            '完成后自动生成下一剂提醒写入「重要日子」（联动 L10），'
                            '接种凭证照片仅存本机。'),
                  ]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _vaxRow(BuildContext context, CareVaccine x, DateTime today) {
    final tokens = context.tokens;
    final st = x.status(today);
    final dd = x.daysTo(today);
    final sub = switch (st) {
      'done' => '已完成 · 凭证已归档',
      'late' => '已过计划日期 ${-dd} 天 · 尽快补种',
      _ => '计划 ${x.due} · ${dd > 0 ? '还有 $dd 天' : '即将到期'} · 提前 ${x.lead} 天提醒',
    };
    return Opacity(
      opacity: st == 'done' ? .55 : 1,
      child: GestureDetector(
        key: ValueKey('vax-row-${x.id}'),
        onTap: () => showVaxForm(context, edit: x),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
              color: tokens.cardBorder.withValues(alpha: .55),
              borderRadius: BorderRadius.circular(14)),
          child: Row(
            children: [
              Text(st == 'done' ? '✅' : st == 'late' ? '⚠️' : '💉',
                  style: const TextStyle(fontSize: 15)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text('${x.name} ${x.dose}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w800)),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                              color: x.kind == '免规'
                                  ? const Color(0xFFE0F2FE)
                                  : const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(999)),
                          child: Text(x.kind,
                              style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.w800,
                                  color: x.kind == '免规'
                                      ? const Color(0xFF0284C7)
                                      : const Color(0xFFD97706))),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(sub,
                        style: const TextStyle(fontSize: 9, color: Colors.grey)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (st != 'done')
                _miniBtn(context, '完成', () async {
                  final messenger = ScaffoldMessenger.of(context);
                  await ref.read(careRepositoryProvider).updateVaccine(
                      CareVaccine(
                          id: x.id,
                          babyId: x.babyId,
                          name: x.name,
                          dose: x.dose,
                          due: x.due,
                          kind: x.kind,
                          lead: x.lead,
                          doneDay: careDayKey(DateTime.now())));
                  careTouch(ref);
                  messenger
                    ..hideCurrentSnackBar()
                    ..showSnackBar(const SnackBar(
                        content: Text('✔ 已记录接种 · 下一针提醒已自动写入「重要日子」（联动 L10）'),
                        duration: Duration(milliseconds: 1800)));
                }, key: ValueKey('vax-done-${x.id}'))
              else ...[
                _txtBtn('重新发起', () async {
                  final messenger = ScaffoldMessenger.of(context);
                  await ref.read(careRepositoryProvider).updateVaccine(
                      CareVaccine(
                          id: x.id,
                          babyId: x.babyId,
                          name: x.name,
                          dose: x.dose,
                          due: x.due,
                          kind: x.kind,
                          lead: x.lead));
                  careTouch(ref);
                  messenger
                    ..hideCurrentSnackBar()
                    ..showSnackBar(SnackBar(
                        content: Text('已重新发起「${x.name}」接种计划'),
                        duration: const Duration(milliseconds: 1600)));
                }, key: ValueKey('vax-undo-${x.id}')),
                _txtBtn('凭证', () {
                  AppToast.show(context, '查看接种凭证照片（本地图档）');
                }, key: ValueKey('vax-cert-${x.id}')),
              ],
              const Text(' ›', style: TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniBtn(BuildContext context, String t, VoidCallback onTap,
      {Key? key}) {
    final tokens = context.tokens;
    return GestureDetector(
      key: key,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
            border: Border.all(color: tokens.cardBorder),
            borderRadius: BorderRadius.circular(999),
            color: tokens.card),
        child: Text(t,
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700, color: tokens.accent)),
      ),
    );
  }

  Widget _txtBtn(String t, VoidCallback onTap, {Key? key}) => GestureDetector(
        key: key,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: Text(t,
              style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w700, color: context.tokens.accent)),
        ),
      );
}

/// sheetVaxAdd 新增/编辑疫苗计划。
Future<void> showVaxForm(BuildContext context, {CareVaccine? edit}) {
  return showCareSheet<void>(
      context, builder: (bc) => _VaxForm(edit: edit));
}

class _VaxForm extends ConsumerStatefulWidget {
  const _VaxForm({this.edit});
  final CareVaccine? edit;

  @override
  ConsumerState<_VaxForm> createState() => _VaxFormState();
}

class _VaxFormState extends ConsumerState<_VaxForm> {
  late final TextEditingController _name =
      TextEditingController(text: widget.edit?.name ?? '');
  late final TextEditingController _dose =
      TextEditingController(text: widget.edit?.dose ?? '');
  late DateTime _date = widget.edit != null
      ? DateTime.parse(widget.edit!.due)
      : DateTime.now().add(const Duration(days: 30));
  late String _kind = widget.edit?.kind ?? '免规';
  late int _lead = widget.edit?.lead ?? 7;

  @override
  void dispose() {
    _name.dispose();
    _dose.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final d = ref.watch(careDataProvider).valueOrNull;
    final isEdit = widget.edit != null;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(isEdit ? '编辑疫苗计划' : '新增疫苗计划',
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
              if (isEdit)
                GestureDetector(
                  key: const ValueKey('va-del'),
                  onTap: () async {
                    // T3（批六·拍板②）：点删即真删改成先确认（不可恢复，说清楚）。
                    if (!await lhConfirm(context, '删除该疫苗计划？删除后不可恢复')) return;
                    if (!context.mounted) return;
                    final messenger = ScaffoldMessenger.of(context);
                    await ref.read(careRepositoryProvider).delVaccine(widget.edit!.id!);
                    careTouch(ref);
                    if (context.mounted) Navigator.pop(context);
                    messenger
                      ..hideCurrentSnackBar()
                      ..showSnackBar(const SnackBar(
                          content: Text('计划已删除'),
                          duration: Duration(milliseconds: 1500)));
                  },
                  child: const Text('删除计划',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFF43F5E))),
                ),
            ],
          ),
          const CLabel('名称 + 剂次', top: 12),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: _inp(context, _name, '如：13价肺炎', 'va-name'),
              ),
              const SizedBox(width: 8),
              Expanded(
                  flex: 1, child: _inp(context, _dose, '第1剂', 'va-dose')),
            ],
          ),
          const CLabel('计划日期', top: 12),
          GestureDetector(
            key: const ValueKey('va-date'),
            onTap: () async {
              final r = await showCareDatePick(context, initial: _date);
              if (r != null && r.date != null && mounted) {
                setState(() => _date = r.date!);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                  border: Border.all(color: tokens.cardBorder),
                  borderRadius: BorderRadius.circular(10)),
              child: Text(careDayKey(_date),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const CLabel('类别', top: 0),
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final k in const ['免规', '自费'])
                          CChip(
                            key: ValueKey('va-kind-$k'),
                            label: k,
                            dense: true,
                            selected: _kind == k,
                            onTap: () => setState(() => _kind = k),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const CLabel('提前提醒', top: 0),
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final v in const [3, 7])
                          CChip(
                            key: ValueKey('va-lead-$v'),
                            label: '$v天',
                            dense: true,
                            selected: _lead == v,
                            onTap: () => setState(() => _lead = v),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('va-cancel'),
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13)),
                  child: const Text('取消',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  key: const ValueKey('va-save'),
                  onTap: () async {
                    final baby = d?.currentBaby;
                    if (baby == null) return;
                    final messenger = ScaffoldMessenger.of(context);
                    final nm = _name.text.trim();
                    if (nm.isEmpty) {
                      messenger
                        ..hideCurrentSnackBar()
                        ..showSnackBar(const SnackBar(
                            content: Text('先填疫苗名称'),
                            duration: Duration(milliseconds: 1500)));
                      return;
                    }
                    final repo = ref.read(careRepositoryProvider);
                    final v = CareVaccine(
                        id: widget.edit?.id,
                        babyId: baby.id,
                        name: nm,
                        dose: _dose.text.trim().isEmpty ? '第1剂' : _dose.text.trim(),
                        due: careDayKey(_date),
                        kind: _kind,
                        lead: _lead,
                        doneDay: widget.edit?.doneDay);
                    if (isEdit) {
                      await repo.updateVaccine(v);
                    } else {
                      await repo.addVaccine(v);
                    }
                    careTouch(ref);
                    if (context.mounted) Navigator.pop(context);
                    messenger
                      ..hideCurrentSnackBar()
                      ..showSnackBar(SnackBar(
                          content: Text(isEdit
                              ? '✔ 已更新接种计划'
                              : '已加入「${baby.name}」计划 · 提前 $_lead 天提醒已生成（联动 L10）'),
                          duration: const Duration(milliseconds: 1800)));
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: careGrad(kBabyHeroStops,
                          begin: const Alignment(-1, 0), end: const Alignment(1, 0)),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(isEdit ? '保存修改' : '加入计划',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _inp(BuildContext context, TextEditingController c, String hint, String key) {
    final tokens = context.tokens;
    return TextField(
      key: ValueKey(key),
      controller: c,
      style: const TextStyle(fontSize: 12),
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 11, color: Colors.grey),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: tokens.cardBorder)),
      ),
    );
  }
}

/// 三态分段钮（原型 .seg 槽；growth_page 同款内联避免跨页依赖）。
class _SegRow extends StatelessWidget {
  const _SegRow({required this.labels, required this.keys, required this.selected, required this.onPick});
  final List<String> labels;
  final List<String> keys;
  final int selected;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: tokens.cardBorder.withValues(alpha: .8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                key: ValueKey(keys[i]),
                onTap: () => onPick(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == selected ? tokens.card : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(labels[i],
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: i == selected ? tokens.accent : Colors.grey)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
