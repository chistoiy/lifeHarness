import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/care_models.dart';
import 'care_kit.dart';
import 'care_providers.dart';

/// p-milestones 发育里程碑（原型 C11）：汇总条 + 已达成/观察中双区 +
/// sheetMilestone 记录/编辑（领域 5 档 · 品牌日期选择）。
class MilestonesPage extends ConsumerWidget {
  const MilestonesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(careDataProvider);
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('发育里程碑'),
            Text('四域打点 · 成长时间线',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.normal)),
          ],
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (d) {
          final baby = d.currentBaby;
          if (baby == null) {
            return const Center(
                child: Text('先建立宝宝档案',
                    style: TextStyle(fontSize: 11, color: Colors.grey)));
          }
          final miles = d.milestones;
          final dn = miles.where((m) => m.done).toList();
          final wa = miles.where((m) => !m.done).toList();
          final cats = miles.map((m) => m.cat).toSet().length;
          final doneRows = dn.reversed.toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
            children: [
              Container(
                padding: const EdgeInsets.all(13),
                decoration: context.cardDecoration,
                child: Text.rich(TextSpan(
                    style: const TextStyle(fontSize: 11.5),
                    children: [
                      const TextSpan(text: '已达成 '),
                      TextSpan(
                          text: '${dn.length}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFF59E0B))),
                      const TextSpan(text: ' 项 · 观察中 '),
                      TextSpan(
                          text: '${wa.length}',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, color: context.tokens.accent)),
                      TextSpan(text: ' 项 · 覆盖 $cats 个领域'),
                    ])),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('已达成',
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
                  GestureDetector(
                    key: const ValueKey('ms-add'),
                    onTap: () => showMilestoneForm(context),
                    child: Text('＋ 记录里程碑',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: context.tokens.accent)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              for (final m in doneRows)
                GestureDetector(
                  key: ValueKey('ms-row-${m.id}'),
                  onTap: () => showMilestoneForm(context, edit: m),
                  child: _card(context,
                      icon: '🏆',
                      iconBg: const Color(0xFFFEF3C7),
                      title: m.name,
                      sub: '${m.cat} · ${m.day ?? ''}',
                      trailing: const Text('›',
                          style: TextStyle(color: Colors.grey, fontSize: 12))),
                ),
              if (doneRows.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Text('还没有达成的里程碑',
                      style: TextStyle(fontSize: 11, color: Colors.grey)),
                ),
              const SizedBox(height: 18),
              const Text('观察中',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              for (final m in wa)
                _card(context,
                    icon: '👀',
                    iconBg: context.tokens.cardBorder,
                    title: m.name,
                    sub: '${m.cat} · 等待打点',
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          key: ValueKey('ms-done-${m.id}'),
                          onTap: () async {
                            final messenger = ScaffoldMessenger.of(context);
                            await ref.read(careRepositoryProvider).updateMilestone(
                                CareMilestone(
                                    id: m.id,
                                    babyId: m.babyId,
                                    name: m.name,
                                    cat: m.cat,
                                    day: careDayKey(DateTime.now()),
                                    done: true));
                            careTouch(ref);
                            messenger
                              ..hideCurrentSnackBar()
                              ..showSnackBar(SnackBar(
                                  content: Text('已记录「${m.name}」达成 · 同步到成长档案'),
                                  duration: const Duration(milliseconds: 1600)));
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(
                                border: Border.all(color: context.tokens.cardBorder),
                                borderRadius: BorderRadius.circular(999),
                                color: context.tokens.card),
                            child: Text('达成',
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: context.tokens.accent)),
                          ),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          key: ValueKey('ms-edit-${m.id}'),
                          onTap: () => showMilestoneForm(context, edit: m),
                          child: const Text('编辑',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.grey)),
                        ),
                      ],
                    )),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: context.cardDecoration,
                child: const Text(
                    '里程碑为发育观察记录，不构成医疗评估；明显落后参考窗口时建议儿保时咨询。',
                    style: TextStyle(fontSize: 10, height: 1.6, color: Colors.grey)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _card(BuildContext context,
      {required String icon,
      required Color iconBg,
      required String title,
      required String sub,
      required Widget trailing}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: context.cardDecoration,
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(12)),
            alignment: Alignment.center,
            child: Text(icon, style: const TextStyle(fontSize: 15)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                const SizedBox(height: 1),
                Text(sub, style: const TextStyle(fontSize: 9, color: Colors.grey)),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}

/// sheetMilestone 记录/编辑里程碑（保存即达成 · 决策同原型）。
Future<void> showMilestoneForm(BuildContext context, {CareMilestone? edit}) {
  return showCareSheet<void>(
      context, builder: (bc) => _MilestoneForm(edit: edit));
}

class _MilestoneForm extends ConsumerStatefulWidget {
  const _MilestoneForm({this.edit});
  final CareMilestone? edit;

  @override
  ConsumerState<_MilestoneForm> createState() => _MilestoneFormState();
}

class _MilestoneFormState extends ConsumerState<_MilestoneForm> {
  static const cats = ['大运动', '精细动作', '语言', '社交', '认知'];
  late final TextEditingController _name =
      TextEditingController(text: widget.edit?.name ?? '');
  late String _cat = widget.edit?.cat ?? '大运动';
  late DateTime _date = widget.edit?.day != null
      ? DateTime.parse(widget.edit!.day!)
      : DateTime.now();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
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
              Text(isEdit ? '编辑里程碑' : '记录里程碑',
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
              if (isEdit)
                GestureDetector(
                  key: const ValueKey('ms-del'),
                  onTap: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    await ref.read(careRepositoryProvider).delMilestone(widget.edit!.id!);
                    careTouch(ref);
                    if (context.mounted) Navigator.pop(context);
                    messenger
                      ..hideCurrentSnackBar()
                      ..showSnackBar(const SnackBar(
                          content: Text('里程碑已删除'),
                          duration: Duration(milliseconds: 1500)));
                  },
                  child: const Text('删除',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFF43F5E))),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('ms-name'),
            controller: _name,
            style: const TextStyle(fontSize: 12),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              hintText: '里程碑名称，如：第一次独立站立',
              hintStyle: const TextStyle(fontSize: 11, color: Colors.grey),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: tokens.cardBorder)),
            ),
          ),
          const CLabel('领域', top: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in cats)
                CChip(
                  key: ValueKey('ms-cat-$c'),
                  label: c,
                  dense: true,
                  selected: _cat == c,
                  onTap: () => setState(() => _cat = c),
                ),
            ],
          ),
          const CLabel('达成日期', top: 12),
          GestureDetector(
            key: const ValueKey('ms-date'),
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
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('ms-cancel'),
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
                  key: const ValueKey('ms-save'),
                  onTap: () async {
                    final d = ref.read(careDataProvider).valueOrNull;
                    final baby = d?.currentBaby;
                    if (baby == null) return;
                    final messenger = ScaffoldMessenger.of(context);
                    final nm = _name.text.trim();
                    if (nm.isEmpty) {
                      messenger
                        ..hideCurrentSnackBar()
                        ..showSnackBar(const SnackBar(
                            content: Text('先填里程碑名称'),
                            duration: Duration(milliseconds: 1500)));
                      return;
                    }
                    final repo = ref.read(careRepositoryProvider);
                    final m = CareMilestone(
                        id: widget.edit?.id,
                        babyId: baby.id,
                        name: nm,
                        cat: _cat,
                        day: careDayKey(_date),
                        done: true);
                    if (isEdit) {
                      await repo.updateMilestone(m);
                    } else {
                      await repo.addMilestone(m);
                    }
                    careTouch(ref);
                    if (context.mounted) Navigator.pop(context);
                    messenger
                      ..hideCurrentSnackBar()
                      ..showSnackBar(const SnackBar(
                          content: Text('✔ 里程碑已保存'),
                          duration: Duration(milliseconds: 1500)));
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: careGrad(const ['#6366f1', '#8b5cf6', '#c084fc'],
                          begin: const Alignment(-1, 0), end: const Alignment(1, 0)),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Text('保存',
                        style: TextStyle(
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
}
