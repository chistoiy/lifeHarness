/// 小组件模块 批A · 选择层：共享五段目标选择器（工单 §2 选择层 · 评估件 §2.3 层2）。
///
/// 规格＝`docs/handoff/小组件模块-批A按实例绑定与打卡试点.md` §0 ②/§2＋
/// `docs/handoff/评估结论-20261017-小组件Glance裁定与内容对齐NFC分类评估.md` §2.3。
///
/// **为什么另立新组件而不参数化 `nfc_sheets.dart`**：工单 §7「新组件不碰
/// nfc_sheets.dart」——NFC 在飞线收口前两边不共享文件；本组件与 NFC 编辑层
/// 「绑定目标」形态**同构不同文件**，靠 [test/widget_picker_test.dart] 的
/// 逐字节同源守护（tab 序／标签／ref 常量／care 子格式）防漂移；NFC 侧将来
/// 参数化时（R7）以本组件或反向合并为准，届时二选一销掉另一份。
///
/// **模式参数只影响按钮文案与区标签**（回调去向在调用点：NFC 侧保存进卡片表、
/// widget 侧绑定进实例键——本组件只「选」，不「写」）；写卡专属分支（探卡／
/// 写入状态机／卡号提示）一概不进本组件（评估件 §2.3 层2）。
///
/// **数据同源**：各区选项一律经 `shared/linkage/nfc_mounts.dart`（与 NFC 目标
/// 选择器同一批出口·守 R1：widget feature 禁 import 其他 feature，故不直连
/// 习惯/母婴/阅读/时间模块，也不 import `features/nfc/**`）。
library;

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart' show Database;

import '../../../core/platform/desktop_actions.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/linkage/nfc_mounts.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../domain/widget_binding.dart';

/// 选择器模式（评估件 §2.3 层2：模式参数只影响文案与回调去向）。
enum WidgetPickerMode {
  /// NFC 绑定目标形态（保存进卡片表·由 NFC 侧调用点落库）。
  nfc,

  /// 小组件添加形态（按钮「添加到桌面」·由设置页调用点走先选后 pin）。
  widget,
}

extension _WidgetPickerModeX on WidgetPickerMode {
  /// 目标区标签（NFC 原文案不动；widget 侧同构改「点击后做什么」）。
  String get zoneLabel => switch (this) {
        WidgetPickerMode.nfc => '贴卡后做什么',
        WidgetPickerMode.widget => '点击后做什么',
      };

  /// 确认按钮文案（原型 `dt-widget` 先选后落步2：按钮随模式变「添加到桌面」）。
  String get confirmLabel => switch (this) {
        WidgetPickerMode.nfc => '保存',
        WidgetPickerMode.widget => '添加到桌面',
      };
}

/// 五段横向大类的固定顺序（批1b §1：顺序固定，不许改序）。
///
/// ⚠ 与 `features/nfc/presentation/nfc_sheets.dart` 的 `kNfcTargetTabs`
/// **两处登记**（理由见 library 注）：`test/widget_picker_test.dart` 有逐字节
/// 同源守护——NFC 改序/改标签 ⇒ 该测试转红，逼两边同步，禁悄悄漂移。
const List<(String, String)> kWidgetPickerTabs = [
  ('nav', '快捷动作'),
  ('habit', '打卡'),
  ('care', '呵护宝宝'),
  ('timer_cat', '计时分类'),
  ('read_book', '阅读书目'),
];

/// 打卡/呵护两项目标的 `target_ref` 字面量（`nav` 前缀形态的具体哪一枚）。
///
/// 与 `features/nfc/domain/nfc_card.dart` 的 [kNfcRefHabit]/[kNfcRefCare]
/// 同值（同样两处登记＋测试守护·禁两套常量）。
const String kWidgetRefHabit = 'habit';
const String kWidgetRefCare = 'care';

/// 呵护宝宝二级参数编码（`<babyId>/<kindId>`·与 `nfcCareSubOf` 同格式）。
String widgetCareSubOf(int babyId, String kindId) => '$babyId/$kindId';

/// 呵护宝宝二级参数解码（与 `nfcCareSubParse` 同格式·脏数据返回 null）。
(int babyId, String kindId)? widgetCareSubParse(String? sub) {
  final s = (sub ?? '').trim();
  if (s.isEmpty) return null;
  final f = s.split('/');
  if (f.length != 2) return null;
  final id = int.tryParse(f[0].trim());
  final kind = f[1].trim();
  if (id == null || kind.isEmpty) return null;
  return (id, kind);
}

/// 初始目标 →（落哪个 tab，各区记忆值）。
///
/// 与 NFC 弹层 `_tabOf`/`_selFrom` 同口径（纯函数·无 widget 依赖，直接单测）。
(String, Map<String, String?>) widgetPickerTabSelOf(WidgetTarget? t) {
  final sel = <String, String?>{
    'nav': null,
    'habit': null,
    'care': null,
    'timer_cat': null,
    'read_book': null,
  };
  if (t == null || !t.isValid) return ('nav', sel);
  if (t.kind == 'nav' && t.ref == kWidgetRefHabit) {
    sel['habit'] = t.sub;
    return ('habit', sel);
  }
  if (t.kind == 'nav' && t.ref == kWidgetRefCare) {
    sel['care'] = t.sub;
    return ('care', sel);
  }
  if (t.kind == 'nav') {
    sel['nav'] = t.ref;
    return ('nav', sel);
  }
  sel[t.kind] = t.ref;
  return (t.kind, sel);
}

/// 目标的人话标签（设置页 toast／绑定回显用）。
///
/// 只做「大类 · 具体项」两层，不做二次加工：
/// - 打卡：`打卡 · 早起`（二级参数本身就是习惯名，直接可读）
/// - 快捷动作：`快捷动作 · 记一笔`（取动作表标签）
/// - 呵护宝宝：`呵护宝宝`（二级参数是 `<babyId>/<kindId>`，机器码不上屏）
/// - 计时分类／阅读书目：只给大类（ref 是分类 id／书 id，上屏得查库）
String widgetTargetLabel(WidgetTarget t) {
  final tabKey =
      (t.ref == kWidgetRefHabit || t.ref == kWidgetRefCare) ? t.ref : t.kind;
  var zone = '目标';
  for (final e in kWidgetPickerTabs) {
    if (e.$1 == tabKey) {
      zone = e.$2;
      break;
    }
  }
  final sub = t.sub;
  if (t.ref == kWidgetRefHabit && sub != null && sub.isNotEmpty) {
    return '$zone · $sub';
  }
  if (t.kind == 'nav' && t.ref != kWidgetRefHabit && t.ref != kWidgetRefCare) {
    final a = desktopActionById[t.ref];
    if (a != null) return '$zone · ${a.label}';
  }
  return zone;
}

/// 打开共享五段目标选择器；返回选中的目标三件套（取消/拖下＝null）。
///
/// [initialTab]＝无初始目标时落的 tab（批A 设置页入口传 `'habit'`：
/// 打卡段预开·原型先选后落步2「开五段选择（打卡段）」）。
/// [db]＝测试注入缝（不传走 `AppDatabase.instance.db`·与 linkage 各口同口径）。
Future<WidgetTarget?> showWidgetTargetPicker(
  BuildContext context, {
  WidgetPickerMode mode = WidgetPickerMode.widget,
  WidgetTarget? initial,
  String initialTab = 'nav',
  Database? db,
}) {
  return showModalBottomSheet<WidgetTarget>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _WidgetTargetPicker(
      mode: mode,
      initial: initial,
      initialTab: initialTab,
      db: db,
    ),
  );
}

class _WidgetTargetPicker extends StatefulWidget {
  const _WidgetTargetPicker({
    required this.mode,
    this.initial,
    required this.initialTab,
    this.db,
  });

  final WidgetPickerMode mode;
  final WidgetTarget? initial;
  final String initialTab;
  final Database? db;

  @override
  State<_WidgetTargetPicker> createState() => _WidgetTargetPickerState();
}

class _WidgetTargetPickerState extends State<_WidgetTargetPicker> {
  late final TextEditingController _bookQuery = TextEditingController();
  late final (String, Map<String, String?>) _seed =
      widgetPickerTabSelOf(widget.initial);
  // 有有效初始目标 ⇒ 落它的区；否则落调用点指定的 [initialTab]
  // （批A 设置页入口传 `'habit'`：打卡段预开·原型先选后落步2）。
  late String _tab = (widget.initial != null && widget.initial!.isValid)
      ? _seed.$1
      : widget.initialTab;
  late final Map<String, String?> _sel = _seed.$2;
  bool _bookOpen = false;

  List<NfcHabitOption> _habits = const [];
  List<NfcBabyOption> _babies = const [];
  List<NfcCareKindOption> _kinds = const [];
  List<NfcCategoryGroup> _catGroups = const [];
  List<NfcBookOption> _books = const [];

  /// 快捷动作＝动作表去掉「打卡」（打卡已独立成横向大类·批1b §1·与 NFC 弹层同口径）。
  List<DesktopAction> get _actions =>
      [for (final a in kDesktopActions) if (a.id != kWidgetRefHabit) a];

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  @override
  void dispose() {
    _bookQuery.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    // 数据一律经 linkage 出口（与 NFC 目标选择器同一批函数·同一数据源）。
    final cats = await nfcCategoryTree(widget.db);
    final books = await nfcBookOptions(widget.db);
    final habits = await nfcHabitOptions(widget.db);
    final babies = await nfcBabyOptions(widget.db);
    final kinds = nfcCareKindOptions();
    if (!mounted) return;
    setState(() {
      _catGroups = cats;
      _books = books;
      _habits = habits;
      _babies = babies;
      _kinds = kinds;
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
          _sel['care'] = widgetCareSubOf(_babies.first.id, _kinds.first.id);
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

  /// 当前唯一选中目标（当前区 × 该区记忆·原型 `nfcSync` 同口径）。
  ///
  /// 与 NFC 弹层 `_target` 逐分支同构：habit/care 是 `nav` 前缀形态
  /// （ref＝habit/care、二级参数进 sub），timer_cat/read_book 直接 kind。
  WidgetTarget get _target => switch (_tab) {
        'habit' => WidgetTarget(
            kind: 'nav', ref: kWidgetRefHabit, sub: _sel['habit']),
        'care' => WidgetTarget(
            kind: 'nav', ref: kWidgetRefCare, sub: _sel['care']),
        'timer_cat' =>
          WidgetTarget(kind: 'timer_cat', ref: _sel['timer_cat'] ?? ''),
        'read_book' =>
          WidgetTarget(kind: 'read_book', ref: _sel['read_book'] ?? ''),
        _ => WidgetTarget(kind: 'nav', ref: _sel['nav'] ?? ''),
      };

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

  /// 确认键是否可点：目标有效 **且** 带二级参数的两类（打卡/呵护）sub 非空。
  ///
  /// 为什么不能只靠 [WidgetTarget.isValid]：habit/care 是 `nav` 前缀形态，
  /// kind/ref 恒非空——该区**没有条目**时（没建习惯/没建宝宝档案）ref 照样
  /// 合法，放它过去就会绑出一个「打卡但没有习惯名」的死目标。与 NFC 弹层
  /// 的差异：NFC 侧保存进卡片表由仓库层兜底，本组件直接决定桌面绑定，
  /// 空 sub 必须在按钮上拦住。
  bool get _canConfirm {
    final t = _target;
    if (!t.isValid) return false;
    if (t.ref == kWidgetRefHabit || t.ref == kWidgetRefCare) {
      final sub = t.sub;
      if (sub == null || sub.isEmpty) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
              const Center(
                child: Text('绑定目标',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 12),
              _label(widget.mode.zoneLabel, scheme),
              const SizedBox(height: 8),
              _tabRow(scheme),
              const SizedBox(height: 12),
              _tabBody(scheme),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey('wg-confirm'),
                  onPressed: _canConfirm
                      ? () => Navigator.pop(context, _target)
                      : null,
                  child: Text(widget.mode.confirmLabel),
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
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: scheme.onSurfaceVariant));

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
        for (final (key, label) in kWidgetPickerTabs)
          Expanded(
            child: GestureDetector(
              key: ValueKey<String>('wg-tab-$key'),
              onTap: () => _gotoTab(key),
              child: Container(
                margin: const EdgeInsets.only(right: 4),
                padding: const EdgeInsets.symmetric(vertical: 7),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _tab == key ? tokens.accent : tokens.card,
                  borderRadius: BorderRadius.circular(999),
                  border:
                      _tab == key ? null : Border.all(color: tokens.cardBorder),
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
            _grey('习惯条目 · 点一下即完成该习惯打卡', scheme),
            _chips([
              for (final h in _habits)
                _ChipOpt('habit', h.id, h.name,
                    sel: _sel['habit'] == h.name, value: h.name),
            ]),
          ],
        );
      case 'care':
        if (_babies.isEmpty) return _grey('还没有宝宝档案', scheme);
        final cur = widgetCareSubParse(_sel['care']);
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
            _grey('记录类型 · 点一下即记一条', scheme),
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
              _grey('该分类无次级 · 可直接选择', scheme)
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

  /// 阅读书目：收起态一行 ＋ 展开搜索框 ＋ 可滚列表（批1b §1 同款）。
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
          key: const ValueKey('wg-book-toggle'),
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
            key: const ValueKey('wg-book-q'),
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
                        key: ValueKey<String>('wg-book-${b.id}'),
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
              key: ValueKey<String>('wg-target-${o.kind}-${o.ref}'),
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
        final cur = widgetCareSubParse(_sel['care']);
        _sel['care'] =
            widgetCareSubOf(int.parse(o.value), cur?.$2 ?? _kinds.first.id);
      case 'care-kind':
        final cur = widgetCareSubParse(_sel['care']);
        _sel['care'] =
            widgetCareSubOf(cur?.$1 ?? _babies.first.id, o.value);
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
