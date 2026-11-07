import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../domain/care_events.dart';
import '../domain/care_models.dart';
import 'care_kit.dart';
import 'care_providers.dart';

/// 宝宝档案弹层组：sheetBabySwitch / sheetAddBaby（增改双用）/ sheetCarer /
/// sheetAllergy（z-60 二级，档案与辅食录入共用）。

/// 切换宝宝 / 记录人（openSheet('sheetBabySwitch')）。
Future<void> showBabySwitchSheet(BuildContext context) {
  return showCareSheet<void>(context, builder: (bc) => const _BabySwitchSheet());
}

class _BabySwitchSheet extends ConsumerWidget {
  const _BabySwitchSheet();

  Future<void> _switch(WidgetRef ref, int id) async {
    await ref.read(careRepositoryProvider).setCurBaby(id);
    careTouch(ref);
    if (ref.context.mounted) Navigator.pop(ref.context);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(careDataProvider).valueOrNull;
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    if (d == null) return const SizedBox.shrink();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('切换宝宝 / 记录人',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          const CLabel('宝宝档案', top: 14),
          for (final b in d.babies)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                key: ValueKey('bsw-${b.id}'),
                onTap: () => _switch(ref, b.id),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: tokens.cardBorder.withValues(alpha: .6),
                    borderRadius: BorderRadius.circular(14),
                    border: b.id == d.currentBaby?.id
                        ? Border.all(color: tokens.accent)
                        : null,
                  ),
                  child: Row(
                    children: [
                      CareAvatar(baby: b, size: 32),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(b.name,
                                style: const TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w700)),
                            Text(careAgeText(b.birth, DateTime.now()),
                                style: const TextStyle(fontSize: 9, color: Colors.grey)),
                          ],
                        ),
                      ),
                      if (b.id == d.currentBaby?.id)
                        Icon(Icons.check, size: 16, color: tokens.accent),
                    ],
                  ),
                ),
              ),
            ),
          const CLabel('记录人身份'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in d.carers)
                CChip(
                  key: ValueKey('bsw-carer-${c.name}'),
                  label: c.name,
                  selected: c.name == d.curCarer,
                  onTap: () async {
                    await ref.read(careRepositoryProvider).setCurCarer(c.name);
                    careTouch(ref);
                  },
                ),
              CChip(
                label: '＋ 添加',
                onTap: () => showCarerSheet(context),
              ),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () {
              Navigator.pop(context);
              context.push('/care/babies');
            },
            style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 11)),
            child: const Text('管理档案与记录人 ›',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
          ),
          SizedBox(height: 4, child: DecoratedBox(decoration: BoxDecoration(color: scheme.surface))),
        ],
      ),
    );
  }
}

class CareAvatar extends StatelessWidget {
  const CareAvatar({super.key, required this.baby, this.size = 44, this.fontSize});
  final CareBaby baby;
  final double size;
  final double? fontSize;

  @override
  Widget build(BuildContext context) {
    final g = kBabyGradients[baby.color] ?? kBabyGradients['sky']!;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: careGrad([g.$1, g.$2],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      alignment: Alignment.center,
      child: Text(baby.avatar,
          style: TextStyle(fontSize: fontSize ?? size * .5)),
    );
  }
}

/// 新增/编辑宝宝档案（sheetAddBaby 增改双用；删除二次确认·决策 11）。
Future<void> showAddBabySheet(BuildContext context, {CareBaby? edit}) {
  return showCareSheet<void>(
      context, builder: (bc) => _AddBabySheet(edit: edit));
}

class _AddBabySheet extends ConsumerStatefulWidget {
  const _AddBabySheet({this.edit});
  final CareBaby? edit;

  @override
  ConsumerState<_AddBabySheet> createState() => _AddBabySheetState();
}

class _AddBabySheetState extends ConsumerState<_AddBabySheet> {
  late final _nameCtl = TextEditingController(text: widget.edit?.name ?? '');
  late DateTime _birth = widget.edit?.birth ?? DateTime.now().withoutTimeCare();
  late String _sex = widget.edit?.sex ?? '女';
  late String _color = widget.edit?.color ?? 'sky';
  bool _delArmed = false;

  static const _colorKeys = ['sky', 'amber', 'rose', 'emerald'];

  @override
  void dispose() {
    _nameCtl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtl.text.trim();
    if (name.isEmpty) {
      AppToast.show(context, '先填宝宝昵称');
      return;
    }
    final repo = ref.read(careRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    final e = widget.edit;
    if (e == null) {
      await repo.addBaby(
          name: name, sex: _sex, birth: careDayKey(_birth), color: _color);
      careTouch(ref);
      if (mounted) Navigator.pop(context);
      messenger.showSnackBar(const SnackBar(
          content: Text('档案已创建 · 记录/曲线/疫苗独立管理'),
          duration: Duration(milliseconds: 1800)));
    } else {
      await repo.updateBaby(e.copyWith(name: name, sex: _sex, birth: _birth, color: _color));
      careTouch(ref);
      if (mounted) Navigator.pop(context);
      messenger.showSnackBar(const SnackBar(
          content: Text('✔ 档案已更新'), duration: Duration(milliseconds: 1500)));
    }
  }

  Future<void> _delete() async {
    if (widget.edit == null) return;
    final d = ref.read(careDataProvider).valueOrNull;
    if (d != null && d.babies.length <= 1) {
      AppToast.show(context, '至少保留一个宝宝档案');
      return;
    }
    if (!_delArmed) {
      setState(() => _delArmed = true);
      AppToast.show(context, '再次点击确认删除该宝宝全部档案数据');
      return;
    }
    final repo = ref.read(careRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    await repo.deleteBaby(widget.edit!.id);
    careTouch(ref);
    if (mounted) Navigator.pop(context);
    messenger.showSnackBar(const SnackBar(
        content: Text('档案已删除'), duration: Duration(milliseconds: 1500)));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final editing = widget.edit != null;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(editing ? '编辑宝宝档案' : '新增宝宝档案',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
              if (editing)
                GestureDetector(
                  key: const ValueKey('ab-del'),
                  onTap: _delete,
                  child: Text(_delArmed ? '确认删除？' : '删除档案',
                      style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFF43F5E))),
                ),
            ],
          ),
          const CLabel('昵称', top: 14),
          TextField(
            key: const ValueKey('ab-name'),
            controller: _nameCtl,
            style: const TextStyle(fontSize: 12),
            decoration: _inp(context, '如：糯米'),
          ),
          const CLabel('出生日期'),
          GestureDetector(
            key: const ValueKey('ab-birth'),
            onTap: () async {
              final r = await showCareDatePick(context, initial: _birth);
              if (r != null && r.date != null) setState(() => _birth = r.date!);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
              decoration: _inputBox(tokens),
              child: Text(careDayKey(_birth),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ),
          const CLabel('性别'),
          CSingleRow(
            options: const ['女', '男'],
            selected: _sex,
            onPick: (v) => setState(() => _sex = v),
          ),
          const CLabel('头像色'),
          Row(
            children: [
              for (final k in _colorKeys)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    key: ValueKey('ab-color-$k'),
                    onTap: () => setState(() => _color = k),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: careGrad(
                            [kBabyGradients[k]!.$1, kBabyGradients[k]!.$2],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight),
                        border: _color == k
                            ? Border.all(color: tokens.accent, width: 2)
                            : null,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12)),
                  child: const Text('取消'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  key: const ValueKey('ab-save'),
                  onPressed: _save,
                  style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12)),
                  child: Text(editing ? '保存修改' : '创建档案'),
                ),
              ),
            ],
          ),
          SizedBox(height: 4, child: DecoratedBox(decoration: BoxDecoration(color: scheme.surface))),
        ],
      ),
    );
  }
}

BoxDecoration _inputBox(ThemeTokens tokens) => BoxDecoration(
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: tokens.cardBorder),
    );

InputDecoration _inp(BuildContext ctx, String hint) {
  final tokens = ctx.tokens;
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
    border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: tokens.cardBorder)),
    enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: tokens.cardBorder)),
  );
}

Widget _field(BuildContext context, TextEditingController ctl, String hint) =>
    TextField(
      controller: ctl,
      style: const TextStyle(fontSize: 12),
      decoration: _inp(context, hint),
    );

/// 添加/编辑记录人身份（sheetCarer）。
Future<void> showCarerSheet(BuildContext context, {CareCarer? edit}) {
  return showCareSheet<void>(context, builder: (bc) => _CarerSheet(edit: edit));
}

class _CarerSheet extends ConsumerStatefulWidget {
  const _CarerSheet({this.edit});
  final CareCarer? edit;

  @override
  ConsumerState<_CarerSheet> createState() => _CarerSheetState();
}

class _CarerSheetState extends ConsumerState<_CarerSheet> {
  late final _ctl =
      TextEditingController(text: widget.edit?.name ?? '');

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _ctl.text.trim();
    final repo = ref.read(careRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    if (name.isEmpty) {
      AppToast.show(context, '先填身份名称');
      return;
    }
    final e = widget.edit;
    final ok = e == null
        ? await repo.addCarer(name)
        : await repo.renameCarer(e.id, name);
    if (!ok) {
      if (mounted) AppToast.show(context, '该身份已存在');
      return;
    }
    careTouch(ref);
    if (mounted) Navigator.pop(context);
    messenger.showSnackBar(SnackBar(
        content: Text(e == null ? '已添加并设为默认记录人：$name' : '✔ 身份已更新，历史记录署名保留'),
        duration: const Duration(milliseconds: 1800)));
  }

  Future<void> _delete() async {
    final repo = ref.read(careRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    final removed = await repo.delCarer(widget.edit!.id);
    careTouch(ref);
    if (mounted) Navigator.pop(context);
    messenger.showSnackBar(SnackBar(
        content: Text(removed == null ? '至少保留一个记录人身份' : '已删除身份「$removed」· 历史记录中的署名保留'),
        duration: const Duration(milliseconds: 1800)));
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.edit != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(editing ? '编辑记录人身份' : '添加记录人身份',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
              if (editing)
                GestureDetector(
                  key: const ValueKey('cr-del'),
                  onTap: _delete,
                  child: const Text('删除身份',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFF43F5E))),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _field(context, _ctl, '身份名称，如：外婆 / 保姆'),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12)),
                  child: const Text('取消'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  key: const ValueKey('cr-save'),
                  onPressed: _save,
                  style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12)),
                  child: const Text('保存'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// sheetAllergy 添加过敏食物（二级弹层 z-60）。
/// forProfile＝档案侧直接落库；否则返回命中的 {f,r} 供辅食录入合并展示。
Future<AlaHit?> showAllergySheet(BuildContext context, {required bool forProfile}) {
  return showCareSheet<AlaHit>(
    context,
    secondary: true,
    builder: (bc) => _AllergySheet(forProfile: forProfile),
  );
}

class _AllergySheet extends ConsumerStatefulWidget {
  const _AllergySheet({required this.forProfile});
  final bool forProfile;

  @override
  ConsumerState<_AllergySheet> createState() => _AllergySheetState();
}

class _AllergySheetState extends ConsumerState<_AllergySheet> {
  String _q = '';
  String? _sel;
  final _reactCtl = TextEditingController();

  @override
  void dispose() {
    _reactCtl.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final f = _sel;
    if (f == null) {
      AppToast.show(context, '请选择过敏食物');
      return;
    }
    final r = _reactCtl.text.trim();
    final d = ref.read(careDataProvider).valueOrNull;
    final hit = AlaHit(f: f, r: r.isEmpty ? null : r);
    if (widget.forProfile) {
      final ok = await ref
          .read(careRepositoryProvider)
          .addAllergy(d?.currentBaby?.id ?? 0, f, r.isEmpty ? null : r);
      careTouch(ref);
      if (!mounted) return;
      Navigator.pop(context);
      AppToast.show(
          context,
          ok
              ? '已加入「${d?.currentBaby?.name ?? '该宝宝'}」过敏史'
              : '该食物已在过敏史中');
    } else {
      // 反应非空同时写入宝宝过敏史（原型 confirmAla 行为）
      if (r.isNotEmpty &&
          !(d?.allergies.any((a) => a.food == f) ?? false)) {
        await ref.read(careRepositoryProvider).addAllergy(d?.currentBaby?.id ?? 0, f, r);
        careTouch(ref);
      }
      if (mounted) Navigator.pop(context, hit);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = ref.watch(careDataProvider).valueOrNull;
    final known = {
      ...?d?.allergies.map((a) => a.food),
    };
    final foods = kAllergyFoodsFiltered(_q);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Text('取消',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey))),
              const Text('添加过敏食物',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
              GestureDetector(
                key: const ValueKey('ala-confirm'),
                onTap: _confirm,
                child: Text('确定',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: context.tokens.accent)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            key: const ValueKey('ala-search'),
            style: const TextStyle(fontSize: 12),
            onChanged: (v) => setState(() => _q = v.trim()),
            decoration: _inp(context, '搜索食物名称'),
          ),
          const CLabel('过敏食物'),
          if (foods.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                  child: Text('无匹配食物',
                      style: TextStyle(fontSize: 11, color: Colors.grey))),
            ),
          for (final f in foods)
            GestureDetector(
              key: ValueKey('ala-food-$f'),
              onTap: () => setState(() => _sel = f),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
                decoration: const BoxDecoration(
                    border: Border(
                        bottom: BorderSide(color: Color(0x0F000000)))),
                child: Row(
                  children: [
                    Expanded(
                      child: Text.rich(TextSpan(children: [
                        TextSpan(
                            text: f,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: _sel == f ? FontWeight.w800 : FontWeight.w500,
                                color: _sel == f ? context.tokens.accent : null)),
                        if (known.contains(f)) ...[
                          const TextSpan(text: ' '),
                          TextSpan(
                              text: '已录',
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: careHex('#f59e0b'))),
                        ],
                      ])),
                    ),
                    if (_sel == f)
                      Icon(Icons.check, size: 14, color: context.tokens.accent),
                  ],
                ),
              ),
            ),
          const CLabel('宝宝反应'),
          TextField(
            key: const ValueKey('ala-react'),
            controller: _reactCtl,
            maxLines: 3,
            style: const TextStyle(fontSize: 12),
            decoration: _inp(context, '输入宝宝的过敏反应…'),
          ),
          const CLabel('常见症状'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in kAllergySyms)
                CChip(
                  key: ValueKey('ala-sym-$s'),
                  label: s,
                  dense: true,
                  onTap: () {
                    final t = _reactCtl.text;
                    if (!t.contains(s)) {
                      _reactCtl.text =
                          t.isEmpty ? s : '$t、$s';
                    }
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 过敏食物检索（子串匹配）。
List<String> kAllergyFoodsFiltered(String q) =>
    q.isEmpty ? kAllergyFoods : kAllergyFoods.where((f) => f.contains(q)).toList();
