// 轮盘抽签设置弹层（原型 `sheetWheelCfg` / `wheelSet*` / `wheelList*` 同源 · 批2）。
//
// 真机轮2 拍板：数据管理（套、批量粘贴、选项与权重）整体收进本弹层，
// 工具主屏只留轮盘与结果。弹层内改动即时反映到轮盘预览，「完成」时
// 由主屏统一落库（取消则丢弃，与 hero 数据位草稿制同口径）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/kit_color.dart' show KitRgb, kitHexToRgb;
import '../../domain/kit_models.dart';
import '../kit_providers.dart';
import '../../domain/kit_wheel.dart';
import 'kit_tools_kit.dart';

/// 弹层返回值：编辑后的整套数据。
typedef KitWheelCfgResult = ({List<KitWheelSet> sets, String curId});

/// 打开设置弹层（`Navigator.pop` 带 [KitWheelCfgResult]）。
Future<KitWheelCfgResult?> kitOpenWheelCfg(
  BuildContext context, {
  required List<KitWheelSet> sets,
  required String curId,
}) =>
    showModalBottomSheet<KitWheelCfgResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => KitWheelCfgSheet(sets: sets, curId: curId),
    );

class KitWheelCfgSheet extends ConsumerStatefulWidget {
  const KitWheelCfgSheet({super.key, required this.sets, required this.curId});

  final List<KitWheelSet> sets;
  final String curId;

  @override
  ConsumerState<KitWheelCfgSheet> createState() => _KitWheelCfgSheetState();
}

class _KitWheelCfgSheetState extends ConsumerState<KitWheelCfgSheet> {
  late List<KitWheelSet> _sets = List.of(widget.sets);
  late String _curId = widget.curId;
  late final TextEditingController _name =
      TextEditingController(text: _cur.name);
  final TextEditingController _paste = TextEditingController();
  final TextEditingController _newItem = TextEditingController();
  int _newWeight = 1;
  int _renameIdx = -1;
  String _hint = '';

  @override
  void dispose() {
    _name.dispose();
    _paste.dispose();
    _newItem.dispose();
    super.dispose();
  }

  KitWheelSet get _cur {
    for (final s in _sets) {
      if (s.id == _curId) return s;
    }
    return _sets.first;
  }

  void _replace(List<KitWheelSet> next, {String? curId}) {
    setState(() {
      _sets = next;
      if (curId != null) _curId = curId;
      _name.text = (curId == null ? _cur : next.firstWhere((s) => s.id == curId)).name;
      _hint = '';
    });
    _persist();
  }

  /// 即时落库（原型 `kitSave` 每个动作即写 localStorage；取消弹层不回滚）。
  Future<void> _persist() => ref.read(kitRepositoryProvider).setToolData(
        kitToolKeyWheel,
        kitWheelEncode(_sets, _curId),
      );

  void _toast(String text) => setState(() => _hint = text);

  List<KitWheelSet> _mapCur(KitWheelSet Function(KitWheelSet s) f) => [
        for (final s in _sets) if (s.id == _curId) f(s) else s,
      ];

  // ---- 套管理 ----

  void _useSet(String id) => _replace(_sets, curId: id);

  void _newSet() {
    if (_sets.length >= kKitWheelMaxSets) {
      _toast('最多 $kKitWheelMaxSets 套 · 先删除一套');
      return;
    }
    final nm = _name.text.trim().isEmpty
        ? '新套 ${_sets.length + 1}'
        : _name.text.trim();
    final id = 'w${DateTime.now().microsecondsSinceEpoch}';
    _replace(
      [
        ..._sets,
        KitWheelSet(
          id: id,
          name: nm,
          items: const [KitWheelItem('选项一', 1), KitWheelItem('选项二', 1)],
        ),
      ],
      curId: id,
    );
    setState(() => _hint = '已新建套「$nm」');
  }

  void _renameSet() {
    final nm = _name.text.trim();
    if (nm.isEmpty) {
      _toast('请先填名称');
      return;
    }
    _replace(_mapCur((s) => KitWheelSet(
          id: s.id,
          name: nm,
          items: s.items,
          history: s.history,
        )));
    _toast('已改名为「$nm」');
  }

  void _delSet() {
    if (_sets.length <= 1) {
      _toast('至少保留一套');
      return;
    }
    final cur = _cur;
    if (cur.items.length < kKitWheelMinItems) {
      _toast('当前套不足 $kKitWheelMinItems 个选项 · 无法删除');
      return;
    }
    final nm = cur.name;
    final rest = _sets.where((s) => s.id != cur.id).toList();
    _replace(rest, curId: rest.first.id);
    _toast('已删除套「$nm」· 其余套不受影响');
  }

  // ---- 批量粘贴 ----

  void _pasteExample() {
    if (_paste.text.trim().isEmpty) {
      _paste.text = '可乐:3\n健身:1\n阅读:2\n打游戏:1\n散步:1';
      _toast('已填入示例 · 每行「选项:权重」');
    } else {
      _paste.clear();
      _toast('');
    }
  }

  void _pasteInto() {
    final list = kitWheelParsePaste(_paste.text);
    if (list.isEmpty) {
      _toast('粘贴框为空');
      return;
    }
    final r = kitWheelAppend(_cur.items, list);
    if (r.added.isEmpty) {
      _toast('当前套已满 $kKitWheelMaxItems 项 · 请新建一套再粘贴');
      return;
    }
    _replace(_mapCur((s) => KitWheelSet(
          id: s.id,
          name: s.name,
          items: [...s.items, ...r.added],
          history: s.history,
        )));
    _toast('已追加 ${r.added.length} 项${r.skipped > 0 ? '（超上限部分未加入）' : ''}');
  }

  void _pasteReplace() {
    final list = kitWheelParsePaste(_paste.text);
    if (list.length < kKitWheelMinItems) {
      _toast('至少 $kKitWheelMinItems 项才能成盘');
      return;
    }
    final take = list.take(kKitWheelMaxItems).toList();
    _replace(_mapCur((s) => KitWheelSet(
          id: s.id,
          name: s.name,
          items: take,
          history: s.history,
        )));
    _toast(list.length > take.length
        ? '最多 $kKitWheelMaxItems 项 · 已截取前 ${take.length} 项'
        : '「${_cur.name}」已替换为 ${take.length} 项 · 扇区按权重分配');
  }

  // ---- 选项增删改 ----

  void _add() {
    final t = _newItem.text.trim();
    if (t.isEmpty) {
      _toast('请先输入选项');
      return;
    }
    if (_cur.items.length >= kKitWheelMaxItems) {
      _toast('最多 $kKitWheelMaxItems 项 · 请新建一套或删项');
      return;
    }
    _newItem.clear();
    _replace(_mapCur((s) => KitWheelSet(
          id: s.id,
          name: s.name,
          items: [...s.items, KitWheelItem(kitWheelClampText(t), _newWeight)],
          history: s.history,
        )));
    _toast('已添加「$t」');
  }

  void _del(int i) {
    if (_cur.items.length <= kKitWheelMinItems) {
      _toast('至少保留 $kKitWheelMinItems 个选项');
      return;
    }
    final items = [..._cur.items]..removeAt(i);
    _replace(_mapCur((s) => KitWheelSet(
          id: s.id,
          name: s.name,
          items: items,
          history: s.history,
        )));
  }

  void _weight(int i, int d) {
    final items = [..._cur.items];
    final x = items[i];
    items[i] = KitWheelItem(x.text, kitWheelClampWeight(x.weight + d));
    _replace(_mapCur((s) => KitWheelSet(
          id: s.id,
          name: s.name,
          items: items,
          history: s.history,
        )));
  }

  void _move(int i, int d) {
    final j = i + d;
    final items = [..._cur.items];
    if (i < 0 || j < 0 || j >= items.length) return;
    final t = items[j];
    items[j] = items[i];
    items[i] = t;
    _replace(_mapCur((s) => KitWheelSet(
          id: s.id,
          name: s.name,
          items: items,
          history: s.history,
        )));
  }

  void _resetDefault() {
    _replace(_mapCur((s) => KitWheelSet(
          id: s.id,
          name: s.name,
          items: kKitWheelDefaultItems,
          history: s.history,
        )));
    _toast('「${_cur.name}」已恢复默认 ${kKitWheelDefaultItems.length} 项 · 权重归 1');
  }

  void _commitRename(int i, String text) {
    final t = text.trim();
    if (t.isEmpty) {
      _del(i);
    } else {
      final items = [..._cur.items];
      items[i] = KitWheelItem(kitWheelClampText(t), items[i].weight);
      _replace(_mapCur((s) => KitWheelSet(
            id: s.id,
            name: s.name,
            items: items,
            history: s.history,
          )));
    }
    setState(() => _renameIdx = -1);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final cur = _cur;
    final colors = kitWheelColors(cur.items.length);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: tokens.cardBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '选项与数据 · 当前套「${cur.name}」',
                    key: const ValueKey('kit-wheel-cfg-head'),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                ),
                TextButton(
                  key: const ValueKey('kit-wheel-cfg-done'),
                  onPressed: () =>
                      Navigator.of(context).pop((sets: _sets, curId: _curId)),
                  child: const Text('完成', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    kitToolSubCard(
                      context,
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                for (final s in _sets)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: KitToolChip(
                                      keyName: 'kit-wheel-set-${s.id}',
                                      label: '${s.name} ${s.items.length}',
                                      on: s.id == _curId,
                                      onTap: () => _useSet(s.id),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  key: const ValueKey('kit-wheel-set-name'),
                                  controller: _name,
                                  style: const TextStyle(fontSize: 12),
                                  onSubmitted: (_) => _renameSet(),
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    hintText: '当前套名称 · 改名后回车',
                                    hintStyle:
                                        TextStyle(fontSize: 11.5, color: Colors.grey),
                                  ),
                                ),
                              ),
                              kitToolBtn(context, '＋ 新建套', _newSet,
                                  keyName: 'kit-wheel-set-new', small: true),
                              kitToolBtn(context, '改名', _renameSet,
                                  keyName: 'kit-wheel-set-rename', small: true),
                              kitToolBtn(context, '删除套', _delSet,
                                  keyName: 'kit-wheel-set-del', small: true,
                                  color: Colors.redAccent),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            key: const ValueKey('kit-wheel-paste'),
                            controller: _paste,
                            maxLines: 3,
                            style: const TextStyle(fontSize: 11.5),
                            decoration: const InputDecoration(
                              isDense: true,
                              hintText:
                                  '批量粘贴：每行一项\n可乐:3\n健身:1\n（冒号后为权重，不填按 1）',
                              hintStyle: TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              kitToolBtn(context, '粘贴录入', _pasteExample,
                                  keyName: 'kit-wheel-paste-demo', small: true),
                              kitToolBtn(context, '追加到当前套', _pasteInto,
                                  keyName: 'kit-wheel-paste-into', small: true),
                              kitToolBtn(context, '替换整套', _pasteReplace,
                                  keyName: 'kit-wheel-paste-replace', small: true),
                            ],
                          ),
                          const SizedBox(height: 4),
                          kitToolNote('支持 逗号 / 顿号 / 换行 分隔'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    kitToolSubCard(
                      context,
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          kitToolSection(
                            '选项与权重 · ${cur.items.length} 项 · 合计 ${cur.totalWeight}',
                            trailing: [
                              kitToolBtn(context, '恢复默认', _resetDefault,
                                  keyName: 'kit-wheel-reset', small: true),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  key: const ValueKey('kit-wheel-new'),
                                  controller: _newItem,
                                  style: const TextStyle(fontSize: 12),
                                  onSubmitted: (_) => _add(),
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    hintText: '新选项 · 回车添加',
                                    hintStyle:
                                        TextStyle(fontSize: 11.5, color: Colors.grey),
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 48,
                                child: KitToolNumberField(
                                  value: _newWeight,
                                  onChanged: (v) =>
                                      setState(() => _newWeight = v.clamp(1, 9)),
                                  width: 48,
                                  min: 1,
                                  max: 9,
                                ),
                              ),
                              kitToolBtn(context, '＋ 添加', _add,
                                  keyName: 'kit-wheel-add', small: true),
                            ],
                          ),
                          const SizedBox(height: 4),
                          for (var i = 0; i < cur.items.length; i++)
                            _itemRow(context, cur, colors, i),
                          const SizedBox(height: 4),
                          if (_hint.isNotEmpty)
                            Text(
                              _hint,
                              key: const ValueKey('kit-wheel-cfg-hint'),
                              style: const TextStyle(
                                  fontSize: 11, color: Color(0xE6F43F5E)),
                            ),
                          const SizedBox(height: 4),
                          kitToolNote(
                              '$kKitWheelMinItems~$kKitWheelMaxItems 项 · 扇区面积按权重分配 · 结果可写日记 / 存笔记'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _itemRow(
    BuildContext context,
    KitWheelSet cur,
    List<String> colors,
    int i,
  ) {
    final x = cur.items[i];
    final rgb = kitHexToRgb(colors[i % colors.length]) ?? const KitRgb(0, 0, 0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: Color(0xFF000000 | (rgb.r << 16) | (rgb.g << 8) | rgb.b),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          if (_renameIdx == i)
            Expanded(
              child: TextField(
                key: ValueKey('kit-wheel-item-edit-$i'),
                autofocus: true,
                style: const TextStyle(fontSize: 11.5),
                onSubmitted: (v) => _commitRename(i, v),
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: '留空则删除该项',
                  hintStyle: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ),
            )
          else
            Expanded(
              child: GestureDetector(
                key: ValueKey('kit-wheel-item-$i'),
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _renameIdx = i),
                child: Text(
                  x.text,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5),
                ),
              ),
            ),
          SizedBox(
            width: 34,
            child: Text(
              '${cur.percentOf(i)}%',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 9.5, color: Colors.grey),
            ),
          ),
          const SizedBox(width: 4),
          _mini('kit-wheel-w-$i-minus', '−', () => _weight(i, -1)),
          SizedBox(
            width: 20,
            child: Text(
              '${x.weight}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
            ),
          ),
          _mini('kit-wheel-w-$i-plus', '＋', () => _weight(i, 1)),
          _mini('kit-wheel-m-$i-up', '↑', () => _move(i, -1)),
          _mini('kit-wheel-m-$i-down', '↓', () => _move(i, 1)),
          _mini('kit-wheel-del-$i', '✕', () => _del(i), color: Colors.redAccent),
        ],
      ),
    );
  }

  Widget _mini(String key, String label, VoidCallback onTap, {Color? color}) =>
      GestureDetector(
        key: ValueKey(key),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: color ?? Colors.grey,
            ),
          ),
        ),
      );
}
