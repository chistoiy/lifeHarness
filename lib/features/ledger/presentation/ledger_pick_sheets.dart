import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../data/ledger_repository.dart';
import '../domain/ledger_calc.dart';
import '../domain/ledger_models.dart';
import 'ledger_providers.dart';
import 'ledger_sheets.dart' show ledgerNav;
import 'widgets/ledger_kit.dart';

/// 记账选择类弹层全家（S3/S3b/S4-lite/S6/S8/S9/S10；原型对应 sheet*）。
/// 一律「返回选中值」；管理态（升序/改名/删/设默认）在弹层内直接落库+tick。

/// 单行输入对话框（原型 prompt 等价；弹层/页面通用）。
Future<String?> lPrompt(
  BuildContext context, {
  required String title,
  String? initial,
  int maxLen = 12,
}) async {
  final ctl = TextEditingController(text: initial ?? '');
  final ok = await showDialog<bool>(
    context: context,
    builder: (bc) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctl,
        autofocus: true,
        maxLength: maxLen,
        decoration: const InputDecoration(counterText: ''),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(bc, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(bc, true),
          child: const Text('确定'),
        ),
      ],
    ),
  );
  final v = ctl.text.trim();
  ctl.dispose();
  return (ok == true && v.isNotEmpty) ? v : null;
}

// ============ S4-lite 账户选择 ============

/// 返回选中账户 id；底部「管理账户 ›」批2 前提示即将开放。
Future<int?> showLAcctPick(
  BuildContext context, {
  String title = '选择账户',
}) => showLSheet<int>(
  context,
  Consumer(
    builder: (sheetCtx, ref, _) {
      final d = ref.watch(ledgerDataProvider).valueOrNull;
      if (d == null) return const SizedBox.shrink();
      final scheme = Theme.of(sheetCtx).colorScheme;
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LSheetHead(title: title),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final a in d.accounts.where((x) => !x.archived))
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => Navigator.pop(sheetCtx, a.id),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 9,
                        ),
                        child: Row(
                          children: [
                            LTile(
                              iconKey: a.icon,
                              color: a.color,
                              size: 32,
                              radius: 11,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    a.name,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  Text(
                                    a.isCredit
                                        ? '可用额度 ${money(a.available)}'
                                        : '余额',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              amtText(a.balanceCache, hide: d.hideAmounts),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            EmptyDashRow(
              text: '管理账户 ›',
              onTap: () {
                Navigator.pop(sheetCtx);
                ledgerNav(sheetCtx, 'assets');
              },
            ),
          ],
        ),
      );
    },
  ),
  heightFactor: .62,
);

// ============ S10 角色选择/管理（原型 openWhoPick） ============

Future<String?> showLWhoPick(BuildContext context, {required String value}) =>
    showLSheet<String>(
      context,
      _WhoPick(value: value),
      heightFactor: .56,
    );

class _WhoPick extends ConsumerStatefulWidget {
  const _WhoPick({required this.value});

  final String value;

  @override
  ConsumerState<_WhoPick> createState() => _WhoPickState();
}

class _WhoPickState extends ConsumerState<_WhoPick> {
  late String _sel = widget.value;
  bool _mg = false;

  LedgerRepository get _repo => ref.read(ledgerRepositoryProvider);

  void _tick() => ref.read(ledgerTickProvider.notifier).state++;

  Future<void> _add() async {
    final n = await lPrompt(context, title: '角色名称');
    if (n == null) return;
    if (!await _repo.addWho(n)) {
      if (mounted) AppToast.show(context, '该角色已存在');
      return;
    }
    _tick();
  }

  Future<void> _rename(LedgerWho w) async {
    final n = await lPrompt(context, title: '角色名称', initial: w.name);
    if (n == null) return;
    await _repo.renameWho(w.id, n);
    if (_sel == w.name) _sel = n;
    _tick();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final d = ref.watch(ledgerDataProvider).valueOrNull;
    if (d == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LSheetHead(
            title: '角色',
            trailing: LChip(
              label: '管理',
              small: true,
              on: _mg,
              onTap: () => setState(() => _mg = !_mg),
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final w in d.whos)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: scheme.outlineVariant),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => Navigator.pop(context, w.name),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 6,
                              ),
                              child: Text(
                                w.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: w.name == _sel ? tokens.accent : null,
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (w.name == d.whoDef)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: tokens.accent.withValues(alpha: .1),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '默认',
                              style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.w700,
                                color: tokens.accent,
                              ),
                            ),
                          ),
                        if (_mg) ...[
                          _MgBtn(label: '↑', onTap: () { _repo.moveWho(w.id, -1); _tick(); }),
                          _MgBtn(label: '↓', onTap: () { _repo.moveWho(w.id, 1); _tick(); }),
                          _MgBtn(label: '改名', onTap: () => _rename(w)),
                          if (w.name != d.whoDef) ...[
                            _MgBtn(
                              label: '设默认',
                              onTap: () { _repo.setDefaultWho(w.id); _tick(); },
                            ),
                            _MgBtn(
                              label: '删',
                              danger: true,
                              onTap: () async {
                                final ok = await _repo.delWho(w.id);
                                if (!ok && mounted) {
                                  AppToast.show(
                                    this.context,
                                    '默认角色或最后一个不可删除',
                                  );
                                  return;
                                }
                                _tick();
                              },
                            ),
                          ],
                        ] else if (w.name == _sel)
                          Icon(
                            LIcons.resolve('check'),
                            size: 16,
                            color: tokens.accent,
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          EmptyDashRow(text: '＋ 添加角色', onTap: _add),
        ],
      ),
    );
  }
}

class _MgBtn extends StatelessWidget {
  const _MgBtn({required this.label, required this.onTap, this.danger = false});

  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
          decoration: BoxDecoration(
            color: danger
                ? const Color(0xFFFB7185).withValues(alpha: .1)
                : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: danger ? const Color(0xFFFB7185) : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

// ============ S9 标签两级多选（原型 openTagPick） ============

Future<List<String>?> showLTagPick(
  BuildContext context, {
  required List<String> selected,
}) => showLSheet<List<String>>(
  context,
  _TagPick(selected: selected),
  heightFactor: .62,
);

class _TagPick extends ConsumerStatefulWidget {
  const _TagPick({required this.selected});

  final List<String> selected;

  @override
  ConsumerState<_TagPick> createState() => _TagPickState();
}

class _TagPickState extends ConsumerState<_TagPick> {
  late final Set<String> _sel = {...widget.selected};
  bool _mg = false;
  int _gi = 0;

  LedgerRepository get _repo => ref.read(ledgerRepositoryProvider);

  void _tick() => ref.read(ledgerTickProvider.notifier).state++;

  Future<void> _addGroup() async {
    final n = await lPrompt(context, title: '分组名称');
    if (n == null) return;
    final ok = await _repo.addTagGroup(n);
    if (!ok) {
      if (!mounted) return;
      AppToast.show(context, '该分组已存在');
      return;
    }
    final gs = await _repo.tagGroups();
    _gi = gs.length - 1;
    _tick();
  }

  Future<void> _addTag(String groupName) async {
    final g = _group;
    if (g == null) return;
    final n = await lPrompt(context, title: '标签名称（加入「$groupName」）');
    if (n == null) return;
    final ok = await _repo.addTag(g.id, n);
    if (!ok) {
      if (!mounted) return;
      AppToast.show(context, '该标签已存在');
      return;
    }
    _tick();
  }

  LedgerTagGroup? get _group {
    final d = ref.read(ledgerDataProvider).valueOrNull;
    final gs = d?.tagGroups ?? const [];
    if (gs.isEmpty) return null;
    return gs[_gi.clamp(0, gs.length - 1)];
  }

  @override
  Widget build(BuildContext context) {
    final d = ref.watch(ledgerDataProvider).valueOrNull;
    if (d == null || d.tagGroups.isEmpty) return const SizedBox.shrink();
    final gs = d.tagGroups;
    final g = gs[_gi.clamp(0, gs.length - 1)];
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LSheetHead(
            title: '标签',
            trailing: LChip(
              label: '管理',
              small: true,
              on: _mg,
              onTap: () => setState(() => _mg = !_mg),
            ),
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 96,
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (var i = 0; i < gs.length; i++)
                        InkWell(
                          onTap: () => setState(() => _gi = i),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 11,
                            ),
                            decoration: BoxDecoration(
                              color: i == _gi
                                  ? tokens.accent.withValues(alpha: .08)
                                  : null,
                              border: Border(
                                right: BorderSide(
                                  width: 2,
                                  color: i == _gi
                                      ? tokens.accent
                                      : Colors.transparent,
                                ),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  gs[i].name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: i == _gi
                                        ? tokens.accent
                                        : scheme.onSurfaceVariant,
                                  ),
                                ),
                                Text(
                                  '${gs[i].tags.length} 个标签',
                                  style: const TextStyle(
                                    fontSize: 8,
                                    color: Color(0xFF94A3B8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (_mg)
                        InkWell(
                          onTap: _addGroup,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 10,
                            ),
                            child: Text(
                              '＋ 新分组',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(left: 10),
                    children: [
                      if (_mg)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '分组「${g.name}」',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              _MgBtn(
                                label: '改名',
                                onTap: () async {
                                  final n = await lPrompt(
                                    context,
                                    title: '分组名称',
                                    initial: g.name,
                                  );
                                  if (n == null) return;
                                  await _repo.renameTagGroup(g.id, n);
                                  _tick();
                                },
                              ),
                              _MgBtn(label: '↑', onTap: () { _repo.moveTagGroup(g.id, -1); _tick(); }),
                              _MgBtn(label: '↓', onTap: () { _repo.moveTagGroup(g.id, 1); _tick(); }),
                              _MgBtn(
                                label: '删组',
                                danger: true,
                                onTap: () async {
                                  final ok = await _repo.delTagGroup(g.id);
                                  if (!ok && mounted) {
                                    AppToast.show(
                                      this.context,
                                      '至少保留一个分组',
                                    );
                                  }
                                  _gi = 0;
                                  _tick();
                                },
                              ),
                            ],
                          ),
                        ),
                      for (var i = 0; i < g.tags.length; i++)
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: scheme.outlineVariant),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  onTap: () => setState(() {
                                    _sel.contains(g.tags[i])
                                        ? _sel.remove(g.tags[i])
                                        : _sel.add(g.tags[i]);
                                  }),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 6,
                                      horizontal: 2,
                                    ),
                                    child: Text(
                                      '#${g.tags[i]}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: _sel.contains(g.tags[i])
                                            ? tokens.accent
                                            : null,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              if (_mg) ...[
                                _MgBtn(
                                  label: '↑',
                                  onTap: () { _repo.moveTag(g.id, g.tags[i], -1); _tick(); },
                                ),
                                _MgBtn(
                                  label: '↓',
                                  onTap: () { _repo.moveTag(g.id, g.tags[i], 1); _tick(); },
                                ),
                                _MgBtn(
                                  label: '改名',
                                  onTap: () async {
                                    final old = g.tags[i];
                                    final n = await lPrompt(
                                      context,
                                      title: '标签名称',
                                      initial: old,
                                    );
                                    if (n == null || n == old) return;
                                    await _repo.renameTag(old, n);
                                    if (_sel.contains(old)) {
                                      _sel.remove(old);
                                      _sel.add(n);
                                    }
                                    _tick();
                                  },
                                ),
                                _MgBtn(
                                  label: '删',
                                  danger: true,
                                  onTap: () {
                                    _sel.remove(g.tags[i]);
                                    _repo.delTag(g.tags[i]);
                                    _tick();
                                  },
                                ),
                              ] else if (_sel.contains(g.tags[i]))
                                Icon(
                                  LIcons.resolve('check'),
                                  size: 16,
                                  color: tokens.accent,
                                ),
                            ],
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: OutlinedButton(
                          onPressed: () => _addTag(g.name),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(38),
                          ),
                          child: Text(
                            '＋ 在「${g.name}」下添加标签',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                  ),
                  child: const Text('取消'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 44,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: tokens.gradient,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: TextButton(
                      onPressed: () => Navigator.pop(context, _sel.toList()),
                      child: const Text(
                        '确定',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
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

// ============ S8 商家选择/管理（原型 openMerchPick） ============

Future<String?> showLMerchPick(BuildContext context, {String? value}) =>
    showLSheet<String>(
      context,
      _MerchPick(value: value),
      heightFactor: .56,
    );

class _MerchPick extends ConsumerStatefulWidget {
  const _MerchPick({this.value});

  final String? value;

  @override
  ConsumerState<_MerchPick> createState() => _MerchPickState();
}

class _MerchPickState extends ConsumerState<_MerchPick> {
  bool _mg = false;

  LedgerRepository get _repo => ref.read(ledgerRepositoryProvider);

  void _tick() => ref.read(ledgerTickProvider.notifier).state++;

  @override
  Widget build(BuildContext context) {
    final d = ref.watch(ledgerDataProvider).valueOrNull;
    if (d == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    String? sel;
    // 选中态由父级传入；管理操作不改变外部选择。
    sel = widget.value;
    Widget row(String label, String? value, {LedgerMerchant? m, int? idx}) {
      final on = sel == value && m == null;
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
        ),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () => Navigator.pop(context, value),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: on ? tokens.accent : null,
                    ),
                  ),
                ),
              ),
            ),
            if (_mg && m != null) ...[
              _MgBtn(label: '↑', onTap: () { _repo.moveMerchant(m.id, -1); _tick(); }),
              _MgBtn(label: '↓', onTap: () { _repo.moveMerchant(m.id, 1); _tick(); }),
              _MgBtn(
                label: '改名',
                onTap: () async {
                  final n = await lPrompt(
                    context,
                    title: '商家名称',
                    initial: m.name,
                  );
                  if (n == null) return;
                  await _repo.renameMerchant(m.id, n);
                  _tick();
                },
              ),
              _MgBtn(
                label: '删',
                danger: true,
                onTap: () { _repo.delMerchant(m.id); _tick(); },
              ),
            ] else if (on)
              Icon(LIcons.resolve('check'), size: 16, color: tokens.accent),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LSheetHead(
            title: '商家',
            trailing: LChip(
              label: '管理',
              small: true,
              on: _mg,
              onTap: () => setState(() => _mg = !_mg),
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                row('无商家', null),
                for (final m in d.merchants) row(m.name, m.name, m: m),
              ],
            ),
          ),
          const SizedBox(height: 8),
          EmptyDashRow(
            text: '＋ 添加商家',
            onTap: () async {
              final n = await lPrompt(context, title: '商家名称');
              if (n == null) return;
              final ok = await _repo.addMerchant(n);
              if (!ok && mounted) {
                AppToast.show(this.context, '该商家已存在');
                return;
              }
              _tick();
            },
          ),
        ],
      ),
    );
  }
}

// ============ S6 分类选择半屏（原型 renderCatPick · 68%） ============

/// 返回 (大类 id, 子分类名)。左大类纵列 + 右子分类宫格（首格=未细分）。
Future<({int catId, String sub})?> showLCatPick(
  BuildContext context, {
  required String kind,
  required int selCat,
  String selSub = '',
}) => showLSheet<({int catId, String sub})>(
  context,
  _CatPick(kind: kind, selCat: selCat, selSub: selSub),
  heightFactor: .68,
);

class _CatPick extends ConsumerStatefulWidget {
  const _CatPick({required this.kind, required this.selCat, required this.selSub});

  final String kind;
  final int selCat;
  final String selSub;

  @override
  ConsumerState<_CatPick> createState() => _CatPickState();
}

class _CatPickState extends ConsumerState<_CatPick> {
  late int _major = widget.selCat;
  late String _sub = widget.selSub;

  @override
  Widget build(BuildContext context) {
    final d = ref.watch(ledgerDataProvider).valueOrNull;
    if (d == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    final majors = d.majors(widget.kind);
    if (!majors.any((c) => c.id == _major) && majors.isNotEmpty) {
      _major = majors.first.id;
    }
    final cur = d.catById[_major];
    final subs = d.subsOf(_major);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
            child: Row(
              children: [
                Text(
                  widget.kind == LedgerCat.kExpense ? '支出' : '收入',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: '搜索分类',
                  icon: Icon(LIcons.resolve('search'), size: 18),
                  onPressed: () =>
                      AppToast.show(context, '搜索分类（模拟）'),
                ),
                IconButton(
                  tooltip: '新增子分类',
                  icon: Icon(LIcons.resolve('plus'), size: 18),
                  onPressed: () async {
                    await showLCatSheet(
                      context,
                      kind: widget.kind,
                      parentId: _major,
                    );
                    if (mounted) setState(() {});
                  },
                ),
                IconButton(
                  tooltip: '分类管理',
                  icon: Icon(LIcons.resolve('gear'), size: 18),
                  onPressed: () {
                    Navigator.pop(context);
                    ledgerNav(context, 'cats');
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 92,
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final c in majors)
                        InkWell(
                          onTap: () => setState(() {
                            _major = c.id;
                            _sub = '';
                          }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: c.id == _major
                                  ? tokens.accent.withValues(alpha: .07)
                                  : null,
                              border: Border(
                                left: BorderSide(
                                  width: 3,
                                  color: c.id == _major
                                      ? tokens.accent
                                      : Colors.transparent,
                                ),
                              ),
                            ),
                            child: Text(
                              c.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: c.id == _major
                                    ? tokens.accent
                                    : scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(6, 4, 14, 8),
                    child: Column(
                      children: [
                        if (cur != null)
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _CatCell(
                                icon: cur.icon,
                                color: cur.color,
                                label: cur.name,
                                on: _sub.isEmpty,
                                onTap: () => Navigator.pop(
                                  context,
                                  (catId: cur.id, sub: ''),
                                ),
                              ),
                              for (final s in subs)
                                _CatCell(
                                  icon: cur.icon,
                                  color: cur.color,
                                  label: s.name,
                                  alpha: .08,
                                  on: _sub == s.name,
                                  onTap: () => Navigator.pop(
                                    context,
                                    (catId: cur.id, sub: s.name),
                                  ),
                                ),
                            ],
                          ),
                        if (subs.isEmpty && cur != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: TextButton(
                              onPressed: () async {
                                await showLCatSheet(
                                  context,
                                  kind: widget.kind,
                                  parentId: cur.id,
                                );
                                if (mounted) setState(() {});
                              },
                              child: const Text(
                                '＋ 为该大类添加子分类',
                                style: TextStyle(fontSize: 11),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CatCell extends StatelessWidget {
  const _CatCell({
    required this.icon,
    required this.color,
    required this.label,
    required this.on,
    required this.onTap,
    this.alpha = .10,
  });

  final String icon;
  final String color;
  final String label;
  final bool on;
  final VoidCallback onTap;
  final double alpha;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        width: (MediaQuery.sizeOf(context).width - 92 - 40) / 2 - 6,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: on ? tokens.accent.withValues(alpha: .08) : null,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            LTile(iconKey: icon, color: color, size: 30, radius: 10),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============ S3 分类新增/编辑（原型 openCatSheet · z70）+ S3b 所属大类 ============

/// catId!=null 编辑大类；parentId!=null 新增子分类；都空=新增大类。
Future<void> showLCatSheet(
  BuildContext context, {
  required String kind,
  int? catId,
  int? parentId,
}) => showLSheet<void>(
  context,
  _CatSheet(kind: kind, catId: catId, parentId: parentId),
  heightFactor: .82,
);

class _CatSheet extends ConsumerStatefulWidget {
  const _CatSheet({required this.kind, this.catId, this.parentId});

  final String kind;
  final int? catId;
  final int? parentId;

  @override
  ConsumerState<_CatSheet> createState() => _CatSheetState();
}

class _CatSheetState extends ConsumerState<_CatSheet> {
  static const catIcons = [
    'food', 'car', 'bag', 'home', 'film', 'run', 'book', 'heart', 'plane',
    'gift', 'phone', 'paw', 'repeat', 'cup', 'wallet', 'star', 'laptop',
    'chart', 'receipt', 'redpack', 'target', 'cal', 'tag', 'dots',
  ];
  static const catColors = [
    '#f97316', '#0ea5e9', '#fb7185', '#6366f1', '#a855f7', '#22c55e',
    '#8b5cf6', '#ef4444', '#06b6d4', '#f59e0b', '#14b8a6', '#d946ef',
    '#64748b', '#94a3b8',
  ];

  late final TextEditingController _name;
  late String _icon;
  String? _color; // null=自动
  late int? _parent;

  LedgerCat? _catById;

  LedgerCat? get _editing => _catById;

  @override
  void initState() {
    super.initState();
    _parent = widget.parentId;
    _catById = widget.catId == null
        ? null
        : ref.read(ledgerDataProvider).valueOrNull?.catById[widget.catId];
    _name = TextEditingController(text: _catById?.name ?? '');
    _icon = _catById?.icon ?? 'dots';
  }

  Future<void> _save() async {
    final n = _name.text.trim();
    final repo = ref.read(ledgerRepositoryProvider);
    if (n.isEmpty) {
      AppToast.show(context, '请输入类别名称');
      return;
    }
    if (widget.catId != null) {
      await repo.renameMajorCat(widget.catId!, n);
      await repo.setCatStyle(
        widget.catId!,
        icon: _icon,
        color: _color ?? _editing?.color,
      );
      _tick();
      if (mounted) {
        Navigator.pop(context);
        AppToast.show(context, '已更新大类');
      }
    } else if (_parent != null) {
      final id = await repo.addSubCat(_parent!, n);
      if (_color != null) await repo.setCatStyle(id, color: _color, icon: _icon);
      _tick();
      if (mounted) {
        Navigator.pop(context);
        final pname = ref
            .read(ledgerDataProvider)
            .valueOrNull
            ?.catOf(_parent)
            .name;
        AppToast.show(context, '子分类「$n」已归入「$pname」');
      }
    } else {
      final col = _color ??
          catColors[math.Random().nextInt(catColors.length)];
      await repo.addMajorCat(
        widget.kind,
        n,
        _icon,
        col,
      );
      _tick();
      if (mounted) {
        Navigator.pop(context);
        AppToast.show(context, '已新建大类「$n」');
      }
    }
  }

  void _tick() => ref.read(ledgerTickProvider.notifier).state++;

  Future<void> _pickParent() async {
    final d = ref.read(ledgerDataProvider).valueOrNull;
    if (d == null) return;
    final id = await showLSheet<int>(
      context,
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LSheetHead(title: '所属大类'),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final c in d.majors(widget.kind))
                    ListTile(
                      dense: true,
                      title: Text(c.name),
                      trailing: c.id == _parent
                          ? Icon(
                              LIcons.resolve('check'),
                              size: 16,
                              color: context.tokens.accent,
                            )
                          : null,
                      onTap: () => Navigator.pop(context, c.id),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      heightFactor: .56,
    );
    if (id != null) setState(() => _parent = id);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = ref.watch(ledgerDataProvider).valueOrNull;
    if (d == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    final col = lColor(_color ?? catColors.first);
    final parentName = _parent == null ? null : d.catOf(_parent).name;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  widget.catId != null ? '编辑' : '新增',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: '保存',
                  icon: Icon(LIcons.resolve('check'), size: 24, color: const Color(0xFF10B981)),
                  onPressed: _save,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  LTile(iconKey: _icon, color: _color ?? catColors.first, size: 32, radius: 11),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _name,
                      maxLength: 8,
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        hintText: '请输入类别名称',
                        counterText: '',
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 所属大类行：仅「新增且预选了父级」时显示（原型同构）。
            if (widget.catId == null && _parent != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: _pickParent,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    decoration: context.cardDecoration,
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '所属大类',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          parentName ?? '请选择',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                        const Text(' ›'),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            const Text('颜色', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                InkWell(
                  onTap: () => setState(() => _color = null),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _color == null ? tokens.accent : scheme.outlineVariant,
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '自动',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: _color == null ? tokens.accent : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
                for (final c in catColors)
                  InkWell(
                    onTap: () => setState(() => _color = c),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: lColor(c),
                        shape: BoxShape.circle,
                        border: _color == c
                            ? Border.all(color: tokens.accent, width: 3)
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const Text('图标', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            GridView.count(
              crossAxisCount: 5,
              shrinkWrap: true,
              mainAxisSpacing: 6,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (final k in catIcons)
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => setState(() => _icon = k),
                    child: Center(
                      child: Icon(
                        LIcons.resolve(k),
                        size: 24,
                        color: _icon == k ? col : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => AppToast.show(context, '从相册自定义图标（V1.x）'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(42),
                    ),
                    child: const Text('自定义', style: TextStyle(fontSize: 12)),
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
