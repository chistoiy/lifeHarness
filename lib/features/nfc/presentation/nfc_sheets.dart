import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/schema/nfc.dart' show NfcTargetKind;
import '../../../core/platform/desktop_actions.dart';
import '../../../core/settings/settings_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/linkage/nfc_mounts.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../data/nfc_repo.dart';
import '../domain/nfc_card.dart';

/// 弹层形态（批1b §4 · 原型 `nfcEditMode`）。
///
/// 三形态各写各的字段，**互不串味**（N15 两向语义）：
/// · [full]＝新建/绑定态（卡片信息＋目标区一次填完）；
/// · [card]＝点列表**右节点**进入，**保存只写卡片字段，不动目标**；
/// · [target]＝点列表**左节点**进入，**只显示五段大类目标区，保存只写目标**。
enum NfcEditMode { full, card, target }

/// 新建/编辑卡片弹层（原型 `sheetNfcEdit` · LH-S41 · 批1b 两形态五段大类）。
///
/// 标题四态：新建卡片／编辑卡片／卡片信息／绑定目标（绑定态另加一行卡号提示 · B8）。
///
/// 目标区＝**五段横向大类 tab**（快捷动作／打卡／呵护宝宝／计时分类／阅读书目），
/// 一次只显示一区、**切 tab 不改变已选**（各区各自记住上次选择）；任一时点只有
/// 一份 `{kind, ref, sub}`（[NfcCard.targetSub] 承接二级参数）。
///
/// 返回值：`true`＝有落库（调用方据此刷新列表），`null`＝取消。
Future<bool?> showNfcEditSheet(
  BuildContext context, {
  NfcCard? card,
  String? bindTagKey,
  NfcEditMode mode = NfcEditMode.full,
  NfcRepo? repo,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _NfcEditSheet(
      card: card,
      bindTagKey: bindTagKey,
      mode: mode,
      repo: repo,
    ),
  );
}

/// 五段横向大类的固定顺序（批1b §1：顺序固定，不许改序）。
const List<(String, String)> kNfcTargetTabs = [
  ('nav', '快捷动作'),
  ('habit', '打卡'),
  ('care', '呵护宝宝'),
  ('timer_cat', '计时分类'),
  ('read_book', '阅读书目'),
];

class _NfcEditSheet extends StatefulWidget {
  const _NfcEditSheet({
    this.card,
    this.bindTagKey,
    this.mode = NfcEditMode.full,
    this.repo,
  });

  final NfcCard? card;

  /// 绑定态预填的卡号提示（B8：贴到未绑定的卡 → 自动打开绑定表单，预填卡号）。
  final String? bindTagKey;

  final NfcEditMode mode;

  /// 测试注入缝（widget 用例不碰真磁盘库）。
  final NfcRepo? repo;

  @override
  State<_NfcEditSheet> createState() => _NfcEditSheetState();
}

class _NfcEditSheetState extends State<_NfcEditSheet> {
  late final TextEditingController _name;
  late final TextEditingController _desc;
  late final TextEditingController _bookQuery = TextEditingController();
  late final NfcRepo _repo = widget.repo ?? NfcRepo(AppDatabase.instance.db);
  late final NfcEditMode _mode = widget.mode;

  /// 当前横向大类 + 各区记忆的选中值（nav＝动作 id／habit＝习惯名（已剥离）／
  /// care＝`<babyId>/<kindId>`／timer_cat＝分类 id／read_book＝书 id）。
  late String _tab = _tabOf(widget.card);
  late final Map<String, String?> _sel = _selFrom(widget.card);
  late int _color = widget.card?.colorIndex ?? 0;

  bool _saving = false;
  bool _nameError = false;
  bool _bookOpen = false;

  /// 卡片信息形态的目标摘要（既有卡的目标名，异步解析）。
  String _targetSummary = '—';

  List<NfcHabitOption> _habits = const [];
  List<NfcBabyOption> _babies = const [];
  List<NfcCareKindOption> _kinds = const [];
  List<NfcCategoryGroup> _catGroups = const [];
  List<NfcBookOption> _books = const [];

  /// 快捷动作＝动作表去掉「打卡」（打卡已独立成横向大类 · 批1b §1）。
  List<DesktopAction> get _actions =>
      [for (final a in kDesktopActions) if (a.id != 'habit') a];

  bool get _isBinding => (widget.bindTagKey ?? '').isNotEmpty;
  bool get _isEditing => widget.card != null;
  bool get _showCard => _mode != NfcEditMode.target;
  bool get _showTarget => _mode != NfcEditMode.card;
  bool get _showOps => _isEditing && _mode != NfcEditMode.target;

  String get _title {
    if (_isBinding) return '绑定这张卡';
    if (_mode == NfcEditMode.target) return '绑定目标';
    if (_mode == NfcEditMode.card) return '卡片信息';
    return _isEditing ? '编辑卡片' : '新建卡片';
  }

  static String _tabOf(NfcCard? c) {
    if (c == null || !c.hasTarget) return 'nav';
    if (c.isHabitTarget) return 'habit';
    if (c.isCareTarget) return 'care';
    if (c.targetKind == NfcTargetKind.nav) return 'nav';
    return c.targetKind;
  }

  static Map<String, String?> _selFrom(NfcCard? c) {
    final s = <String, String?>{
      'nav': null,
      'habit': null,
      'care': null,
      'timer_cat': null,
      'read_book': null,
    };
    if (c == null || !c.hasTarget) return s;
    if (c.isHabitTarget) {
      s['habit'] = c.targetSub;
    } else if (c.isCareTarget) {
      s['care'] = c.targetSub;
    } else if (c.targetKind == NfcTargetKind.nav) {
      s['nav'] = c.targetRef;
    } else {
      s[c.targetKind] = c.targetRef;
    }
    return s;
  }

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.card?.name ?? '');
    _desc = TextEditingController(text: widget.card?.descText ?? '');
    _loadOptions();
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _bookQuery.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    // 目标选择器的各区数据**一律经 linkage 出口**（守 R1：本 feature 不 import
    // features/calendar|read|habit|care）。
    final cats = await nfcCategoryTree();
    final books = await nfcBookOptions();
    final habits = await nfcHabitOptions();
    final babies = await nfcBabyOptions();
    final kinds = nfcCareKindOptions();
    final card = widget.card;
    final summary = card == null
        ? null
        : await nfcTargetStateOf(card).then((s) => nfcTargetLabelOf(
              card,
              targetName: s.name,
            ));
    if (!mounted) return;
    setState(() {
      _catGroups = cats;
      _books = books;
      _habits = habits;
      _babies = babies;
      _kinds = kinds;
      if (summary != null) _targetSummary = summary;
      _ensureTabDefault(_tab);
    });
  }

  /// 某区首次被访问时给一个默认选中（原型 `nfcTabTo` 同口径：进区即有唯一选中）。
  void _ensureTabDefault(String tab) {
    if (_sel[tab] != null) return;
    switch (tab) {
      case 'habit':
        if (_habits.isNotEmpty) _sel['habit'] = _habits.first.name;
      case 'care':
        if (_babies.isNotEmpty && _kinds.isNotEmpty) {
          _sel['care'] = nfcCareSubOf(_babies.first.id, _kinds.first.id);
        }
      case 'timer_cat':
        if (_catGroups.isNotEmpty) _sel['timer_cat'] = '${_catGroups.first.id}';
      case 'read_book':
        if (_books.isNotEmpty) _sel['read_book'] = _books.first.id;
      default:
        if (_actions.isNotEmpty) _sel['nav'] = _actions.first.id;
    }
  }

  /// 切区：**不改变已选**（各区各自记住），只把书目下拉收起。
  void _gotoTab(String tab) {
    setState(() {
      _tab = tab;
      if (tab != 'read_book') {
        _bookOpen = false;
        _bookQuery.clear();
      }
      _ensureTabDefault(tab);
    });
  }

  /// 唯一选中目标（当前区 × 该区记忆 · 原型 `nfcSync` 同口径）。
  (String, String?, String?) get _target {
    switch (_tab) {
      case 'habit':
        return (NfcTargetKind.nav, kNfcRefHabit, _sel['habit']);
      case 'care':
        return (NfcTargetKind.nav, kNfcRefCare, _sel['care']);
      case 'timer_cat':
        return (NfcTargetKind.timerCat, _sel['timer_cat'], null);
      case 'read_book':
        return (NfcTargetKind.readBook, _sel['read_book'], null);
      default:
        return (NfcTargetKind.nav, _sel['nav'], null);
    }
  }

  /// 计时分类的两级高亮：选中值可能是一级、也可能是子级（子级时一级随之高亮）。
  (int?, int?) get _catHi {
    final sel = _sel['timer_cat'];
    if (sel == null) return (null, null);
    for (final g in _catGroups) {
      if ('${g.id}' == sel) return (g.id, null);
      for (final c in g.children) {
        if ('${c.id}' == sel) return (g.id, c.id);
      }
    }
    return (null, null);
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (_mode != NfcEditMode.target && name.isEmpty) {
      // B13：保存被拒，框下一行红字「起个名字」，层保持打开（不做静默默认名）。
      setState(() => _nameError = true);
      return;
    }
    setState(() {
      _nameError = false;
      _saving = true;
    });
    final desc = _desc.text.trim();
    final (kind, ref, sub) = _target;
    try {
      final card = widget.card;
      if (card == null) {
        await _repo.create(
          name: name,
          targetKind: kind,
          targetRef: ref,
          targetSub: sub,
          descText: desc.isEmpty ? null : desc,
          color: _color,
        );
      } else {
        // 两形态各写各的字段（N15）：卡片信息形态不碰目标三列，绑定目标形态不碰卡片三列。
        if (_mode != NfcEditMode.target) {
          await _repo.updateCardInfo(card.id,
              name: name, descText: desc.isEmpty ? null : desc, color: _color);
        }
        if (_mode != NfcEditMode.card) {
          await _repo.updateTarget(card.id,
              targetKind: kind, targetRef: ref, targetSub: sub);
        }
      }
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      // catch-ok: 本地写库失败已在下面给用户一句「保存失败 · 请重试」；错误本身
      // （表结构/磁盘满）属开发期问题，无可执行的运行时动作，不进日志面。
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.show(context, '保存失败 · 请重试');
    }
  }

  /// 删除卡片（C7：不进回收站 ⇒ 确认层必须说清后果）。
  Future<void> _delete() async {
    final card = widget.card;
    if (card == null) return;
    final ok = await lhConfirm(context, '删除后原卡片会变成未绑定，重新绑定即可再用。');
    if (!ok) return;
    try {
      await _repo.delete(card.id);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      // catch-ok: 同 _save（本地写库失败给一句人话即可）。
      if (!mounted) return;
      AppToast.show(context, '删除失败 · 请重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final nameLen = _name.text.characters.length;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 34,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Center(
                child: Text(_title,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800)),
              ),
              if (_isBinding)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Center(
                    child: Text('这张卡还没绑定 · 卡号 ${widget.bindTagKey}',
                        style: TextStyle(
                            fontSize: 11, color: scheme.onSurfaceVariant)),
                  ),
                ),
              const SizedBox(height: 12),

              // ===== 卡片信息块（full / card 形态）=====
              if (_showCard) ...[
                _label('名称', scheme),
                TextField(
                  key: const ValueKey('nfc-name'),
                  controller: _name,
                  maxLength: kNfcNameMaxLen, // B14：超出不接收
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(kNfcNameMaxLen)
                  ],
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _save(),
                  decoration: InputDecoration(
                    hintText: '例如：出门记账卡',
                    counterText: '$nameLen/$kNfcNameMaxLen',
                    errorText: _nameError ? '起个名字' : null,
                  ),
                ),
                const SizedBox(height: 6),
                _label('默认描述（选填）', scheme),
                TextField(
                  key: const ValueKey('nfc-desc'),
                  controller: _desc,
                  maxLength: kNfcDescMaxLen,
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(kNfcDescMaxLen)
                  ],
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: '例如：坐下就计时',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 6),
                _label('颜色', scheme),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (var i = 0; i < kNfcColorCount; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: GestureDetector(
                          key: ValueKey<String>('nfc-color-$i'),
                          onTap: () => setState(() => _color = i),
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: Color(kNfcColors[i]),
                              borderRadius: BorderRadius.circular(10),
                              border: i == _color
                                  ? Border.all(
                                      color: scheme.onSurface, width: 2.5)
                                  : null,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                if (_isEditing) ...[
                  const SizedBox(height: 14),
                  _label('绑定目标', scheme),
                  const SizedBox(height: 4),
                  Text(_targetSummary,
                      key: const ValueKey('nfc-target-sum'),
                      style: TextStyle(
                          fontSize: 12.5, color: scheme.onSurfaceVariant)),
                ],
              ],

              // ===== 目标区（full / target 形态）=====
              if (_showTarget) ...[
                const SizedBox(height: 16),
                _label('贴卡后做什么', scheme),
                const SizedBox(height: 8),
                _tabRow(scheme),
                const SizedBox(height: 12),
                _tabBody(scheme),
              ],

              // ===== 编辑态两行（卡片信息 / 编辑形态；绑定目标形态不露）=====
              if (_showOps) ...[
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: scheme.outlineVariant),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        key: const ValueKey('nfc-edit-write'),
                        dense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 14),
                        title: const Text('写入卡片',
                            style: TextStyle(fontSize: 13)),
                        trailing: Text(
                          widget.card!.isReadOnlyTag
                              ? '只读卡'
                              : (widget.card!.isWritten ? '已写入' : '未写入'),
                          style: TextStyle(
                              fontSize: 11.5, color: scheme.onSurfaceVariant),
                        ),
                        onTap: () {
                          // 写卡流程属批2；批1b 只给一句明说，不假装能写。
                          AppToast.show(context, '写入卡片将在下一批开放');
                        },
                      ),
                      Divider(height: 1, color: scheme.outlineVariant),
                      ListTile(
                        key: const ValueKey('nfc-edit-del'),
                        dense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 14),
                        title: const Text('删除卡片',
                            style:
                                TextStyle(fontSize: 13, color: Color(0xFFF43F5E))),
                        trailing: Text('原卡片变未绑定',
                            style: TextStyle(
                                fontSize: 11, color: scheme.onSurfaceVariant)),
                        onTap: _delete,
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey('nfc-save'),
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? '保存中' : '保存'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String s, ColorScheme scheme) => Text(s,
      style: TextStyle(
          fontSize: 11.5, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant));

  Widget _grey(String s, ColorScheme scheme) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(s,
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
      );

  /// 五段横向大类（**一次只显示一区** · 顺序固定）。
  Widget _tabRow(ColorScheme scheme) {
    final tokens = context.tokens;
    return Row(
      children: [
        for (final (key, label) in kNfcTargetTabs)
          Expanded(
            child: GestureDetector(
              key: ValueKey<String>('nfc-tab-$key'),
              onTap: () => _gotoTab(key),
              child: Container(
                margin: const EdgeInsets.only(right: 4),
                padding: const EdgeInsets.symmetric(vertical: 7),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _tab == key ? tokens.accent : tokens.card,
                  borderRadius: BorderRadius.circular(999),
                  border: _tab == key ? null : Border.all(color: tokens.cardBorder),
                ),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: _tab == key ? FontWeight.w700 : FontWeight.w500,
                    color: _tab == key ? Colors.white : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _tabBody(ColorScheme scheme) {
    switch (_tab) {
      case 'habit':
        if (_habits.isEmpty) return _grey('还没有习惯条目', scheme);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _grey('习惯条目 · 贴卡即完成该习惯打卡', scheme),
            _chips([
              for (final h in _habits)
                _ChipOpt('habit', h.id, h.name,
                    sel: _sel['habit'] == h.name, value: h.name),
            ]),
          ],
        );
      case 'care':
        if (_babies.isEmpty) return _grey('还没有宝宝档案', scheme);
        final cur = nfcCareSubParse(_sel['care']);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _grey('宝宝', scheme),
            _chips([
              for (final b in _babies)
                _ChipOpt('care-baby', '${b.id}', b.name,
                    sel: cur?.$1 == b.id),
            ]),
            const SizedBox(height: 10),
            _grey('记录类型 · 贴卡即记一条', scheme),
            _chips([
              for (final k in _kinds)
                _ChipOpt('care-kind', k.id, k.name, sel: cur?.$2 == k.id),
            ]),
          ],
        );
      case 'timer_cat':
        if (_catGroups.isEmpty) return _grey('还没有分类', scheme);
        final (hiParent, hiChild) = _catHi;
        final group = _catGroups.where((g) => g.id == hiParent).toList();
        final subs = group.isEmpty ? const <NfcCategoryOption>[] : group.first.children;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _grey('一级分组', scheme),
            _chips([
              for (final g in _catGroups)
                _ChipOpt('cat', '${g.id}', g.name, sel: hiParent == g.id),
            ]),
            const SizedBox(height: 10),
            _grey('子分组 · 属于上方选中一级 · 再点可取消', scheme),
            if (subs.isEmpty)
              _grey('该分类无次级 · 可直接保存', scheme)
            else
              _chips([
                for (final c in subs)
                  _ChipOpt('cat', '${c.id}', c.name, sel: hiChild == c.id),
              ]),
          ],
        );
      default:
        if (_tab == 'read_book') return _bookBody(scheme);
        return _chips([
          for (final a in _actions)
            _ChipOpt('nav', a.id, a.label, sel: _sel['nav'] == a.id),
        ]);
    }
  }

  /// 阅读书目：收起态一行 ＋ 展开搜索框 ＋ 可滚列表（批1b §1）。
  Widget _bookBody(ColorScheme scheme) {
    final tokens = context.tokens;
    final sel = _sel['read_book'];
    final picked = _books.where((b) => b.id == sel).toList();
    final pickedTitle = picked.isEmpty ? null : picked.first.title;
    final q = _bookQuery.text.trim();
    final list = [
      for (final b in _books)
        if (q.isEmpty || b.title.contains(q)) b,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          key: const ValueKey('nfc-book-toggle'),
          onTap: () => setState(() {
            _bookOpen = !_bookOpen;
            if (_bookOpen) _bookQuery.clear();
          }),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: tokens.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: tokens.cardBorder),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    pickedTitle == null ? '选择书籍' : '《$pickedTitle》',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight:
                          pickedTitle == null ? FontWeight.w400 : FontWeight.w700,
                      color: pickedTitle == null
                          ? scheme.onSurfaceVariant
                          : scheme.onSurface,
                    ),
                  ),
                ),
                Text(_bookOpen ? '收起' : '展开',
                    style:
                        TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ),
        if (_bookOpen) ...[
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('nfc-book-q'),
            controller: _bookQuery,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(hintText: '搜索书名'),
          ),
          const SizedBox(height: 6),
          Container(
            constraints: const BoxConstraints(maxHeight: 176),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: list.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Center(
                      child: Text('没有匹配的书', style: TextStyle(fontSize: 11.5)),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final b = list[i];
                      final on = b.id == sel;
                      return InkWell(
                        key: ValueKey<String>('nfc-book-${b.id}'),
                        onTap: () => setState(() {
                          _sel['read_book'] = b.id;
                          _bookOpen = false; // 选书 → 下拉自动收起
                          _bookQuery.clear();
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            border: Border(
                                bottom: BorderSide(
                                    color: scheme.outlineVariant
                                        .withValues(alpha: .5))),
                          ),
                          child: Text(
                            b.title.isEmpty ? '未命名' : b.title,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: on ? FontWeight.w700 : FontWeight.w400,
                              color: on ? tokens.accent : scheme.onSurface,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ],
    );
  }

  Widget _chips(List<_ChipOpt> opts) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final o in opts)
            PillChip(
              key: ValueKey<String>('nfc-target-${o.kind}-${o.ref}'),
              label: o.label,
              selected: o.sel,
              onTap: () => setState(() => _pick(o)),
            ),
        ],
      );

  /// 点一枚 chip：写回**该区**的记忆值（唯一选中目标由 [_target] 现算）。
  void _pick(_ChipOpt o) {
    switch (o.kind) {
      case 'habit':
        // 打卡：存的是习惯名（已剥离装饰符）——与 target_sub 口径同源。
        _sel['habit'] = o.value;
      case 'care-baby':
        final cur = nfcCareSubParse(_sel['care']);
        _sel['care'] =
            nfcCareSubOf(int.parse(o.value), cur?.$2 ?? _kinds.first.id);
      case 'care-kind':
        final cur = nfcCareSubParse(_sel['care']);
        _sel['care'] =
            nfcCareSubOf(cur?.$1 ?? _babies.first.id, o.value);
      case 'cat':
        final id = int.parse(o.value);
        final parent =
            _catGroups.where((g) => g.children.any((c) => c.id == id)).toList();
        // 再点同一子类＝退回父级（§1）；点一级＝只选该一级（子级高亮随之消失）。
        if (parent.isNotEmpty && _sel['timer_cat'] == o.value) {
          _sel['timer_cat'] = '${parent.first.id}';
        } else {
          _sel['timer_cat'] = o.value;
        }
      default:
        _sel['nav'] = o.value;
    }
  }
}

class _ChipOpt {
  const _ChipOpt(this.kind, this.ref, this.label,
      {required this.sel, String? value})
      : value = value ?? ref;

  /// 区块标识（`nav`/`habit`/`care-baby`/`care-kind`/`cat`）——决定写回哪个区的记忆。
  final String kind;

  /// key 用 id（稳定 · 与显示名解耦）。
  final String ref;

  final String label;

  final bool sel;

  /// 写回记忆的值（缺省＝[ref]；打卡区＝习惯名）。
  final String value;
}

/// 「贴卡设置」弹层（原型 `sheetNfcSet` · 批1b §6）。
///
/// 原屏内「贴卡行为」卡收进这里（右上角齿轮进入）：两开关**默认态与语义不变**
/// （C5/B17：`nfc.confirmBeforeRun` 默认关／`nfc.promptUnbound` 默认开）。
///
/// ⚠ **保留总闸**：冻结档 C42 的总闸 `nfc.enabled`（默认开·关时完全静默）在
/// 原型 `sheetNfcSet` 里漏画了，但它是批1 已交付并过门的需求条目——本实现按
/// 「需求 > 原型」保留在设置层最上方，层级仍是「总闸 ＞ 明细」（任一关即不触发）。
Future<void> showNfcSettingsSheet(
  BuildContext context, {
  required SettingsRepository prefs,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _NfcSettingsSheet(prefs: prefs),
  );
}

class _NfcSettingsSheet extends StatefulWidget {
  const _NfcSettingsSheet({required this.prefs});

  final SettingsRepository prefs;

  @override
  State<_NfcSettingsSheet> createState() => _NfcSettingsSheetState();
}

class _NfcSettingsSheetState extends State<_NfcSettingsSheet> {
  late bool _enabled = widget.prefs.loadNfcEnabled();
  late bool _confirm = widget.prefs.loadNfcConfirmBeforeRun();
  late bool _prompt = widget.prefs.loadNfcPromptUnbound();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 34,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Center(
              child: Text('贴卡设置',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text('贴卡时的行为与提示',
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
            ),
            const SizedBox(height: 14),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: scheme.outlineVariant),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _row(
                    keyName: 'nfc-sw-enabled',
                    title: '启用 NFC 卡片',
                    sub: '关掉后贴卡完全静默无反应（总闸 · 优先于下面两条）',
                    value: _enabled,
                    onChanged: (v) async {
                      setState(() => _enabled = v);
                      await widget.prefs.saveNfcEnabled(v);
                    },
                    scheme: scheme,
                    top: false,
                  ),
                  _row(
                    keyName: 'nfc-sw-confirm',
                    title: '贴卡先确认再执行',
                    sub: '开启后每次贴卡先问一次，避免打断正在编辑的内容',
                    value: _confirm,
                    onChanged: (v) async {
                      setState(() => _confirm = v);
                      await widget.prefs.saveNfcConfirmBeforeRun(v);
                    },
                    scheme: scheme,
                    top: true,
                  ),
                  _row(
                    keyName: 'nfc-sw-unbound',
                    title: '未识别卡片提示绑定',
                    sub: '关掉后陌生卡片会静默忽略、不打扰',
                    value: _prompt,
                    onChanged: (v) async {
                      setState(() => _prompt = v);
                      await widget.prefs.saveNfcPromptUnbound(v);
                    },
                    scheme: scheme,
                    top: true,
                  ),
                ],
              ),
            ),
            if (!_enabled)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('总闸已关，贴卡不会有任何反应',
                    style:
                        TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
              ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                key: const ValueKey('nfc-set-done'),
                onPressed: () => Navigator.pop(context),
                child: const Text('完成'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row({
    required String keyName,
    required String title,
    required String sub,
    required bool value,
    required Future<void> Function(bool) onChanged,
    required ColorScheme scheme,
    required bool top,
  }) {
    return Container(
      decoration: top
          ? BoxDecoration(
              border: Border(top: BorderSide(color: scheme.outlineVariant)))
          : null,
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(sub,
                    style:
                        TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          Switch(
            key: ValueKey<String>(keyName),
            value: value,
            onChanged: (v) => onChanged(v),
          ),
        ],
      ),
    );
  }
}
