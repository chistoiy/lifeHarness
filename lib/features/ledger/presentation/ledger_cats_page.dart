import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/schema.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../data/ledger_repository.dart';
import '../domain/ledger_models.dart';
import 'ledger_pick_sheets.dart';
import 'ledger_providers.dart';
import 'widgets/ledger_kit.dart';

/// L8 分类管理（原型 p-cats · TITLES ['分类管理','两级分类 · 图标与颜色']；
/// renderLcats V2·图4 全量：左大类纵列（可拖/点标题改名）＋右子分类行
/// （改名/星标收藏/上下移/删除）＋常用类别卡＋搜索/菜单钮（toast 占位逐字）。
///
/// Flutter 语义映射：原型 HTML5 drag（长按拖动排序）= ReorderableListView
/// 长按拖拽（大类左栏与子分类列表各自同列表内重排，九·补2 ③）；
/// 原型 prompt = lPrompt；原型 delCat 两段式「再点删除」armed 交互逐字保留。
/// 隐藏/恢复：任务规格补充入口（原型无隐藏钮，hidden 列既有；种子恒 0）。
class LedgerCatsPage extends ConsumerStatefulWidget {
  const LedgerCatsPage({super.key});

  @override
  ConsumerState<LedgerCatsPage> createState() => _LedgerCatsPageState();
}

class _LedgerCatsPageState extends ConsumerState<LedgerCatsPage> {
  /// 原型 catKind / cmSel / _catArm（两段删除）。
  String _kind = LedgerCat.kExpense;
  int? _cmSel;
  int? _armedDelId;

  LedgerRepository get _repo => ref.read(ledgerRepositoryProvider);

  void _tick() => ref.read(ledgerTickProvider.notifier).state++;

  void _toast(String m) => AppToast.show(context, m);

  List<LedgerCat> _majors(LedgerData d, {bool hidden = false}) => d.cats
      .where((c) => c.isMajor && c.kind == _kind && c.hidden == hidden)
      .toList();

  List<LedgerCat> _subsOf(LedgerData d, int majorId, {bool hidden = false}) =>
      d.cats
          .where((c) => c.parentId == majorId && c.hidden == hidden)
          .toList();

  /// 当前选中大类（数据刷新后失效回落首个可见大类）。
  LedgerCat? _curMajor(LedgerData d) {
    final list = _majors(d);
    if (list.isEmpty) return null;
    if (_cmSel == null || !list.any((c) => c.id == _cmSel)) {
      _cmSel = list.first.id;
    }
    return list.firstWhere((c) => c.id == _cmSel);
  }

  // ---- 写路径 ----

  /// 原型 cmTap：已选中大类再点 → prompt 改名。
  Future<void> _tapMajor(LedgerCat c) async {
    if (_cmSel == c.id) {
      final n = await _prompt(context, title: '大类名称', initial: c.name);
      if (n == null) return;
      await _repo.renameMajorCat(c.id, n);
      _tick();
    } else {
      setState(() {
        _cmSel = c.id;
        _armedDelId = null;
      });
    }
  }

  /// 原型 catMove(id,±1) + 左栏 drag（cmDropE）：同列表内重排回写 sort。
  Future<void> _moveMajor(LedgerData d, int id, int delta) async {
    final ids = _majors(d).map((c) => c.id).toList();
    final i = ids.indexOf(id);
    final j = i + delta;
    if (i < 0 || j < 0 || j >= ids.length) return;
    final tmp = ids[i]; // 相邻交换（原型 [list[i],list[i+d]]=[list[i+d],list[i]]）
    ids[i] = ids[j];
    ids[j] = tmp;
    await _repo.reorderMajors(_kind, ids);
    _tick();
  }

  Future<void> _reorderMajors(LedgerData d, int oldIndex, int newIndex) async {
    var to = newIndex;
    if (to > oldIndex) to -= 1; // ReorderableListView 下移语义修正
    final ids = _majors(d).map((c) => c.id).toList();
    ids.insert(to, ids.removeAt(oldIndex));
    await _repo.reorderMajors(_kind, ids);
    _tick();
  }

  Future<void> _moveSub(LedgerData d, int parentId, int id, int delta) async {
    final ids = _subsOf(d, parentId).map((c) => c.id).toList();
    final i = ids.indexOf(id);
    final j = i + delta;
    if (i < 0 || j < 0 || j >= ids.length) return;
    final tmp = ids[i];
    ids[i] = ids[j];
    ids[j] = tmp;
    await _repo.reorderSubs(parentId, ids);
    _tick();
  }

  Future<void> _reorderSubs(
      LedgerData d, int parentId, int oldIndex, int newIndex) async {
    var to = newIndex;
    if (to > oldIndex) to -= 1;
    final ids = _subsOf(d, parentId).map((c) => c.id).toList();
    ids.insert(to, ids.removeAt(oldIndex));
    await _repo.reorderSubs(parentId, ids);
    _tick();
  }

  /// 原型 cmSubRename：prompt('子分类名称') → 分类行改名 + 同步流水 sub 与收藏。
  Future<void> _renameSub(LedgerCat s) async {
    final n = await _prompt(context, title: '子分类名称', initial: s.name);
    if (n == null || n == s.name) return;
    await _repo.renameCat(s.id, n);
    await _repo.renameSubCat(s.parentId!, s.name, n);
    _tick();
  }

  /// 原型 delCat 两段式：兜底不可删 → 有流水首次 armed toast → 再点迁移「其他」。
  Future<void> _delMajor(LedgerData d, LedgerCat c) async {
    if (c.id == DbSchema.ledgerCatOtherExpense ||
        c.id == DbSchema.ledgerCatOtherIncome) {
      _armedDelId = null;
      _toast('兜底分类不可删除');
      return;
    }
    final n = await _repo.catTxnCount(c.id, d.curBook.id);
    if (!mounted) return;
    if (n > 0 && _armedDelId != c.id) {
      setState(() => _armedDelId = c.id);
      _toast('该分类下有 $n 笔流水 · 再点删除并迁移至「其他」');
      return;
    }
    final r = await _repo.delCat(c.id);
    _armedDelId = null;
    _tick();
    _toast(r.migrated > 0 ? '已删除并迁移流水至「其他」' : '已删除分类');
  }

  /// 原型 delSub：流水回落未细分（无确认、无 toast）。
  Future<void> _delSub(LedgerCat s) async {
    await _repo.delSubCat(s.parentId!, s.name);
    _tick();
  }

  Future<void> _hide(LedgerCat c) async {
    await _repo.setCatHidden(c.id, true);
    _tick();
    _toast('已隐藏「${c.name}」');
  }

  Future<void> _restore(LedgerCat c) async {
    await _repo.setCatHidden(c.id, false);
    _tick();
    _toast('已恢复「${c.name}」');
  }

  // ---- UI ----

  @override
  Widget build(BuildContext context) {
    final d = ref.watch(ledgerDataProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('分类管理'),
            Text(
              '两级分类 · 图标与颜色',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.normal),
            ),
          ],
        ),
      ),
      body: d == null
          ? const Center(child: CircularProgressIndicator())
          : _body(d),
    );
  }

  Widget _body(LedgerData d) {
    final cur = _curMajor(d);
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    return Column(
      children: [
        // 原型顶行：catMgmtTitle（点标题切收支）＋搜索＋三点菜单（均 toast 占位逐字）。
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 12, 0),
          child: Row(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => setState(() {
                  _kind = _kind == LedgerCat.kExpense
                      ? LedgerCat.kIncome
                      : LedgerCat.kExpense;
                  _cmSel = null;
                  _armedDelId = null;
                }),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                  child: Text(
                    '${_kind == LedgerCat.kExpense ? '支出' : '收入'}分类管理',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: '搜索',
                icon: Icon(LIcons.resolve('search'), size: 18,
                    color: scheme.onSurfaceVariant),
                onPressed: () => _toast('搜索分类（模拟）'),
              ),
              IconButton(
                tooltip: '菜单',
                icon: Icon(LIcons.resolve('dots'), size: 18,
                    color: scheme.onSurfaceVariant),
                onPressed: () => _toast(
                    '收入/支出切换 · 点标题「${_kind == LedgerCat.kExpense ? '支出' : '收入'}」处切换'),
              ),
            ],
          ),
        ),
        // 常用类别卡（showFavCats toast 逐字）。
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () =>
                _toast('常用类别 = 星标收藏的子分类 · 显示在记一笔快捷行'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: context.cardDecoration,
              child: Row(
                children: [
                  const Expanded(
                      child: Text('常用类别',
                          style:
                              TextStyle(fontSize: 13, fontWeight: FontWeight.w800))),
                  Text('${d.favs.length}',
                      style: TextStyle(
                          fontSize: 11, color: scheme.onSurfaceVariant)),
                  const Text(' ›'),
                ],
              ),
            ),
          ),
        ),
        // 双栏：左大类纵列（拖排）＋右选中大类子分类行。
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 96,
                child: ReorderableListView(
                  buildDefaultDragHandles: true,
                  padding: EdgeInsets.zero,
                  onReorder: (o, n) => _reorderMajors(d, o, n),
                  children: [
                    for (final c in _majors(d))
                      InkWell(
                        key: ValueKey('major-${c.id}'),
                        onTap: () => _tapMajor(c),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 13),
                          decoration: BoxDecoration(
                            color: c.id == cur?.id
                                ? tokens.accent.withValues(alpha: .07)
                                : null,
                            border: Border(
                              left: BorderSide(
                                width: 3,
                                color: c.id == cur?.id
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
                              color: c.id == cur?.id
                                  ? tokens.accent
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    InkWell(
                      key: const ValueKey('major-add'),
                      onTap: () => showLCatSheet(context, kind: _kind),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: 10, vertical: 13),
                        child: Text(
                          '＋ 大类',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(8, 4, 14, 24),
                  children: [
                    if (cur != null) ..._majorRows(d, cur),
                    _hiddenRows(d),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _majorRows(LedgerData d, LedgerCat c) {
    final scheme = Theme.of(context).colorScheme;
    final subs = _subsOf(d, c.id);
    return [
      // 右栏头部（原型：图标+名+编辑/↑/↓/删除；隐藏=任务规格补充钮）。
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 0, 8),
        child: Row(
          children: [
            LTile(iconKey: c.icon, color: c.color, size: 32, radius: 11),
            const SizedBox(width: 10),
            Expanded(
              child: Text(c.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
            ),
            _IconBtn(
              key: ValueKey('major-edit-${c.id}'),
              icon: 'edit',
              onTap: () => showLCatSheet(context, kind: _kind, catId: c.id),
            ),
            _IconBtn(
                key: ValueKey('major-up-${c.id}'),
                icon: 'up',
                onTap: () => _moveMajor(d, c.id, -1)),
            _IconBtn(
                key: ValueKey('major-down-${c.id}'),
                icon: 'down',
                onTap: () => _moveMajor(d, c.id, 1)),
            _IconBtn(
                key: ValueKey('major-hide-${c.id}'),
                icon: 'eyeOff',
                onTap: () => _hide(c)),
            _IconBtn(
                key: ValueKey('major-del-${c.id}'),
                icon: 'trash',
                onTap: () => _delMajor(d, c)),
          ],
        ),
      ),
      // 子分类行（长按拖排 + 原型 ↑↓；改名/星标/删除）。
      ReorderableListView(
        shrinkWrap: true,
        buildDefaultDragHandles: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,        onReorder: (o, n) => _reorderSubs(d, c.id, o, n),
        children: [
          for (var i = 0; i < subs.length; i++)
            Container(
              key: ValueKey('sub-${subs[i].id}'),
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                border: Border(
                    bottom: BorderSide(color: scheme.outlineVariant, width: .6)),
              ),
              child: Row(
                children: [
                  LTile(
                      iconKey: subs[i].icon,
                      color: subs[i].color,
                      size: 28,
                      radius: 9),
                  const SizedBox(width: 10),
                  Expanded(
                    child: InkWell(
                      onTap: () => _renameSub(subs[i]),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(subs[i].name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                  // 星标收藏（toggleFav；on=琥珀色，同原型 text-amber-400）。
                  InkWell(
                    key: ValueKey('fav-${subs[i].id}'),
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      _repo.toggleFav(c.id, subs[i].name);
                      _tick();
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        LIcons.resolve('star'),
                        size: 17,
                        color: d.isFav(c.id, subs[i].name)
                            ? const Color(0xFFFBBF24)
                            : scheme.onSurfaceVariant.withValues(alpha: .5),
                      ),
                    ),
                  ),
                  if (i > 0)
                    _IconBtn(
                        key: ValueKey('sub-up-${subs[i].id}'),
                        icon: 'up',
                        onTap: () => _moveSub(d, c.id, subs[i].id, -1)),
                  if (i < subs.length - 1)
                    _IconBtn(
                        key: ValueKey('sub-down-${subs[i].id}'),
                        icon: 'down',
                        onTap: () => _moveSub(d, c.id, subs[i].id, 1)),
                  _IconBtn(
                      key: ValueKey('sub-hide-${subs[i].id}'),
                      icon: 'eyeOff',
                      onTap: () => _hide(subs[i])),
                  _IconBtn(
                      key: ValueKey('sub-del-${subs[i].id}'),
                      icon: 'trash',
                      onTap: () => _delSub(subs[i])),
                ],
              ),
            ),
        ],
      ),
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: EmptyDashRow(
          text: '＋ 子分类',
          onTap: () => showLCatSheet(context, kind: _kind, parentId: c.id),
        ),
      ),
    ];
  }

  /// 已隐藏分组（任务规格补充恢复入口；点按行恢复）。
  Widget _hiddenRows(LedgerData d) {
    final hidden = [
      ...d.cats.where((c) => c.kind == _kind && c.hidden),
    ];
    if (hidden.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 14, 0, 4),
          child: Text(
            '已隐藏 ${hidden.length} 项 · 点按恢复',
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant),
          ),
        ),
        for (final h in hidden)
          InkWell(
            key: ValueKey('restore-${h.id}'),
            borderRadius: BorderRadius.circular(10),
            onTap: () => _restore(h),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Row(
                children: [
                  Text(
                    d.catOf(h.parentId).name,
                    style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      h.name,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF94A3B8)),
                    ),
                  ),
                  Icon(LIcons.resolve('plus'), size: 14, color: scheme.onSurfaceVariant),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// 单行输入对话框（原型 prompt 等价；与 ledger_pick_sheets.lPrompt 同文案同构，
/// 控制器改由对话框自身 State 持有并在路由销毁时释放——规避退出动画期 dispose
/// 竞态，不触碰既有 lPrompt 行为）。
Future<String?> _prompt(
  BuildContext context, {
  required String title,
  String? initial,
}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _PromptDialog(title: title, initial: initial),
    );

class _PromptDialog extends StatefulWidget {
  const _PromptDialog({required this.title, this.initial});

  final String title;
  final String? initial;

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  late final TextEditingController _ctl =
      TextEditingController(text: widget.initial ?? '');

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _ok() {
    final v = _ctl.text.trim();
    Navigator.pop(context, v.isNotEmpty ? v : null);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _ctl,
        autofocus: true,
        maxLength: 12,
        decoration: const InputDecoration(counterText: ''),
        onSubmitted: (_) => _ok(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _ok,
          child: const Text('确定'),
        ),
      ],
    );
  }
}

/// 行内小图标钮（原型 text-slate-400 小钮；up/down 以文字箭头保真）。
class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, required this.onTap, super.key});

  final String icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isArrow = icon == 'up' || icon == 'down';
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
        child: isArrow
            ? Text(
                icon == 'up' ? '↑' : '↓',
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              )
            : Icon(
                switch (icon) {
                  'edit' => Icons.edit_outlined,
                  'eyeOff' => Icons.visibility_off_outlined,
                  'trash' => LIcons.resolve('trash'),
                  _ => Icons.circle_outlined,
                },
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
      ),
    );
  }
}
