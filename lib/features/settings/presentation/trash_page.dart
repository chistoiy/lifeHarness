import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/trash/trash_models.dart';
import '../../../shared/trash/trash_providers.dart';
import '../../../shared/widgets/ui_kit.dart';

/// /settings/trash · V1.60 全局回收站（原型 p-sub-trash · 需求 §四 末条）。
///
/// 口径：六类全纳（待办/笔记/习惯/书籍/划线书摘/书单）· 家＝设置·记录管理二级；
/// 行＝模块标签＋正文＋副信息＋删于＋剩余天数（≤7 天标红）＋行内恢复·删除；
/// 右上「选择」或长按进批量；彻底删除走二次确认并逐条列出（书籍写明连带数量）；
/// 父书已不在架的划线＝孤行，置灰「不可单独恢复」（需求防幽灵口径）。
class TrashPage extends ConsumerStatefulWidget {
  const TrashPage({super.key, this.initialSeg});

  /// 深链直达分段（?seg=note；null/未知＝全部段）。
  final String? initialSeg;

  @override
  ConsumerState<TrashPage> createState() => _TrashPageState();
}

class _TrashPageState extends ConsumerState<TrashPage> {
  TrashKind? _seg;
  bool _selMode = false;
  final Set<String> _sel = {};

  @override
  void initState() {
    super.initState();
    _seg = _kindOf(widget.initialSeg);
  }

  static TrashKind? _kindOf(String? name) {
    for (final k in TrashKind.values) {
      if (k.name == name) return k;
    }
    return null;
  }

  List<TrashItem> _visible(List<TrashItem> all) => _seg == null
      ? all
      : all.where((e) => e.kind == _seg).toList(growable: false);

  void _exitSel() => setState(() {
        _selMode = false;
        _sel.clear();
      });

  void _enterSel(String key) => setState(() {
        _selMode = true;
        _sel
          ..clear()
          ..add(key);
      });

  void _tapRow(TrashItem it) {
    if (!_selMode) return;
    setState(() {
      _sel.contains(it.key) ? _sel.remove(it.key) : _sel.add(it.key);
      if (_sel.isEmpty) _selMode = false;
    });
  }

  void _selAll(List<TrashItem> visible) => setState(() {
        if (_sel.length == visible.length && visible.isNotEmpty) {
          _sel.clear();
        } else {
          _sel
            ..clear()
            ..addAll(visible.map((e) => e.key));
        }
      });

  void _toast(String m) {
    if (mounted) AppToast.show(context, m);
  }

  Future<void> _restore(List<TrashItem> items) async {
    final picked = items.where((e) => !e.orphan).toList(growable: false);
    if (picked.isEmpty) return;
    final svc = ref.read(trashServiceProvider);
    await svc.restore(picked);
    if (!mounted) return;
    _exitSel();
    _toast(picked.length == 1
        ? svc.restoreToastFor(picked.first)
        : '已恢复 ${picked.length} 项到各自模块');
  }

  Future<void> _purge(List<TrashItem> items) async {
    await ref.read(trashServiceProvider).purge(items);
    if (!mounted) return;
    _exitSel();
    final n = items.length;
    _toast(items.any((e) => e.kind == TrashKind.book)
        ? '已彻底删除 $n 条 · 该书名下划线书摘不可再单独恢复'
        : '已彻底删除 $n 条');
  }

  Future<void> _askPurge(List<TrashItem> items) async {
    final keep = ref.read(settingsControllerProvider).trashKeepDays;
    final now = DateTime.now();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _PurgeSheet(items: items, now: now, keepDays: keep),
    );
    if (ok == true) await _purge(items);
  }

  /// F5-3（轮5③·原型已过门）：保留期档位入口从「记录管理 › 通用」挪到本屏右上角图标钮。
  /// 档位取值与写通道一字未动（30/7/90 天 · 不清理，默认 30）；顺序与副注照原型 `sheetTrashKeep`。
  Future<void> _askKeep() async {
    final cur = ref.read(settingsControllerProvider).trashKeepDays;
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      // 四档带副注比旧版高，窄视口下会溢出（widget 实测 7.5px）——照原型
      // `sheetTrashKeep` 的 max-h-[80vh] overflow-y-auto 口径改成可滚。
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (bc) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text('自动清理保留期',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            ),
            for (final (v, lab, note) in const [
              (7, '7 天', '到期当日晚清理'),
              (30, '30 天', '默认档'),
              (90, '90 天', '长期保留'),
              (0, '不清理', '只在回收站里手动彻底删除'),
            ])
              ListTile(
                key: ValueKey('tt-keep-$v'),
                dense: true,
                title: Text(lab),
                subtitle: Text(note, style: const TextStyle(fontSize: 11)),
                trailing: v == cur
                    ? Icon(Icons.check,
                        size: 18, color: Theme.of(bc).colorScheme.primary)
                    : null,
                onTap: () => Navigator.of(bc).pop(v),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (picked == null) return;
    await ref.read(settingsControllerProvider.notifier).setTrashKeepDays(picked);
    if (!mounted) return;
    _toast(picked > 0 ? '回收站内容保留 $picked 天后自动彻底删除' : '回收站不再自动清理');
  }

  @override
  Widget build(BuildContext context) {
    final keep = ref.watch(settingsControllerProvider).trashKeepTxt;
    final now = DateTime.now();
    final async = ref.watch(trashItemsProvider);
    final all = async.valueOrNull ?? const <TrashItem>[];
    final counts = ref.watch(trashCountsProvider);
    final visible = _visible(all);
    final selItems =
        all.where((t) => _sel.contains(t.key)).toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('回收站'),
            Text('八类删除内容 · 保留期内可恢复',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.normal)),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 2),
            child: Row(
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                      children: [
                        TextSpan(
                          text: '${visible.length} 项',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF475569)),
                        ),
                        TextSpan(text: ' · $keep'),
                      ],
                    ),
                  ),
                ),
                if (_selMode)
                  TextButton(
                    key: const ValueKey('tt-all'),
                    onPressed: visible.isEmpty ? null : () => _selAll(visible),
                    child: Text(_sel.isNotEmpty &&
                            _sel.length ==
                                visible.where((e) => !e.orphan).length
                        ? '取消全选'
                        : '全选'),
                  ),
                TextButton(
                  key: const ValueKey('tt-pick'),
                  onPressed: all.isEmpty
                      ? null
                      : () => setState(() => _selMode = !_selMode),
                  child: Text(_selMode ? '取消' : '选择'),
                ),
                // F5-3：档位入口＝右上角时钟图标钮（线性图标·无教学文案），
                // 当前档由左侧期限行读出，不在钮上重复标数。
                IconButton(
                  key: const ValueKey('tt-keep'),
                  tooltip: '自动清理保留期',
                  onPressed: _askKeep,
                  icon: const Icon(Icons.schedule_outlined, size: 20),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
            child: Wrap(
              key: const ValueKey('tt-segs'),
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final e in _segEntries(counts))
                  _chip(e.$1, e.$2, e.$1 == null ? _seg == null : _seg == e.$1,
                      () => setState(() {
                            _exitSel();
                            _seg = e.$1;
                          }))
              ],
            ),
          ),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('加载失败：$e')),
              data: (_) => visible.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                      child: Center(
                        child: Text(
                            _seg == null ? '回收站是空的' : '该分类回收站是空的',
                            key: const ValueKey('tt-empty'),
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey)),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      itemCount: visible.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _tile(visible[i], now),
                    ),
            ),
          ),
          if (_selMode && _sel.isNotEmpty) _selBar(selItems),
        ],
      ),
    );
  }

  /// 分段 chips：全部＋六类（计数随动作同步 · 原型 gtSegs）。
  List<(TrashKind?, int)> _segEntries(({int total, Map<TrashKind, int> byKind}) c) =>
      [(null, c.total), for (final k in TrashKind.values) (k, c.byKind[k] ?? 0)];

  Widget _chip(TrashKind? kind, int n, bool on, VoidCallback onTap) {
    final tokens = context.tokens;
    return InkWell(
      key: ValueKey('tt-seg-${kind?.name ?? 'all'}'),
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: on ? tokens.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
              color: on ? tokens.accent : const Color(0xFFCBD5E1), width: 1),
        ),
        child: Text(
          '${kind?.label ?? '全部'} $n',
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: on ? Colors.white : const Color(0xFF64748B)),
        ),
      ),
    );
  }

  Widget _tile(TrashItem t, DateTime now) {
    final accent = context.tokens.accent;
    final keep = ref.watch(settingsControllerProvider).trashKeepDays;
    final left = trashLeftDays(t.deletedAt, keep, now);
    final urgent = left != null && left <= 7;
    final selected = _sel.contains(t.key);
    return GestureDetector(
      key: ValueKey('tt-row-${t.key}'),
      behavior: HitTestBehavior.opaque,
      onLongPress: () => _enterSel(t.key),
      onTap: () => _tapRow(t),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: context.cardDecoration,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_selMode)
              Container(
                key: ValueKey('tt-chk-${t.key}'),
                width: 18,
                height: 18,
                margin: const EdgeInsets.only(right: 8, top: 2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? accent : Colors.transparent,
                  border: Border.all(
                      color: selected ? accent : const Color(0xFFCBD5E1),
                      width: 2),
                ),
                child: selected
                    ? const Icon(Icons.check, size: 12, color: Colors.white)
                    : null,
              )
            else
              Container(
                key: ValueKey('tt-dot-${t.key}'),
                width: 12,
                height: 12,
                margin: const EdgeInsets.only(right: 8, top: 4),
                decoration: BoxDecoration(
                    shape: BoxShape.circle, color: t.kind.dot),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Wrap(
                    spacing: 8,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _kindTag(t.kind),
                      for (final s in t.subs)
                        s.startsWith('含在库划线')
                            ? Text(s,
                                key: ValueKey('tt-cascade-${t.key}'),
                                style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFFD97706)))
                            : _meta(s),
                      _meta(trashDelStamp(t.deletedAt)),
                      Text(
                        trashLeftTxt(t.deletedAt, keep, now),
                        key: ValueKey('tt-left-${t.key}'),
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight:
                                urgent ? FontWeight.w800 : FontWeight.w600,
                            color: urgent
                                ? const Color(0xFFF43F5E)
                                : Colors.grey),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (!_selMode) ...[
              const SizedBox(width: 6),
              if (t.orphan)
                _orphanTag(t)
              else ...[
                _btn('tt-restore-${t.key}', '恢复', accent, () => _restore([t])),
                const SizedBox(width: 4),
                _btn('tt-del-${t.key}', '删除', const Color(0xFFF43F5E),
                    () => _askPurge([t])),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _kindTag(TrashKind kind) => Container(
        key: ValueKey('tt-kind-${kind.name}'),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        color: const Color(0xFFF1F5F9),
        child: Text(kind.label,
            style: const TextStyle(fontSize: 10, color: Color(0xFF64748B))),
      );

  /// 孤行说明（需求：置灰并说明连带，不许静默）。
  Widget _orphanTag(TrashItem t) => Tooltip(
        message: t.orphanHint ?? '所属书已彻底删除',
        child: Container(
          key: ValueKey('tt-orphan-${t.key}'),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: const Text('不可单独恢复',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF94A3B8))),
        ),
      );

  Widget _meta(String text) =>
      Text(text, style: const TextStyle(fontSize: 10, color: Colors.grey));

  Widget _btn(String key, String label, Color color, VoidCallback onTap) =>
      InkWell(
        key: ValueKey(key),
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: .35)),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w800, color: color)),
        ),
      );

  /// 批量底栏：已选 N 项 + 恢复 + 彻底删除 + ✕（与待办垃圾箱同款语言）。
  Widget _selBar(List<TrashItem> selItems) {
    final tokens = context.tokens;
    return Container(
      key: const ValueKey('tt-sel-bar'),
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      decoration: BoxDecoration(
        color: tokens.card,
        border: Border(top: BorderSide(color: tokens.cardBorder)),
      ),
      child: Row(
        children: [
          Text('已选 ${selItems.length} 项',
              key: const ValueKey('tt-sel-count'),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
          const Spacer(),
          if (selItems.isNotEmpty)
            TextButton(
              key: const ValueKey('tt-restore-batch'),
              onPressed: () => _restore(selItems),
              child: const Text('恢复'),
            ),
          IconButton(
            key: const ValueKey('tt-purge-batch'),
            tooltip: '彻底删除',
            onPressed: selItems.isEmpty ? null : () => _askPurge(selItems),
            icon: const Icon(Icons.delete_outline,
                size: 22, color: Color(0xFFF43F5E)),
          ),
          IconButton(
            key: const ValueKey('tt-sel-exit'),
            tooltip: '取消',
            onPressed: _exitSel,
            icon: const Icon(Icons.close, size: 20),
          ),
        ],
      ),
    );
  }
}

/// sheetTrashPurge：彻底删除二次确认（逐条列出；书籍行写明连带清除内容）。
class _PurgeSheet extends StatelessWidget {
  const _PurgeSheet(
      {required this.items, required this.now, required this.keepDays});

  final List<TrashItem> items;
  final DateTime now;
  final int keepDays;

  /// 弹层行尾：逐类写清后果（原型 tpAsk tail 同分支·不许静默糊过）。
  Widget _tail(TrashItem t) {
    switch (t.kind) {
      case TrashKind.book:
        return Flexible(
          child: Text(
              '连带清 在库划线·笔记 ${t.cascadeQuotes ?? 0} 条 · 计时 · 进度',
              key: ValueKey('tp-cascade-${t.key}'),
              style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFF43F5E))),
        );
      case TrashKind.habit:
        return const Text('只清定义 · 历史流水保留',
            key: ValueKey('tp-habit-note'),
            style: TextStyle(fontSize: 10, color: Colors.grey));
      case TrashKind.list:
        return const Text('连成员行一起清 · 书本身保留',
            key: ValueKey('tp-list-note'),
            style: TextStyle(fontSize: 10, color: Colors.grey));
      case TrashKind.item:
        return Text(t.cascadeNotes ?? '连带清 成本时间轴与按次用量 · 关联流水保留',
            key: ValueKey('tp-item-note'),
            style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Color(0xFFF43F5E)));
      case TrashKind.todo:
      case TrashKind.note:
      case TrashKind.quote:
        return Text(trashLeftTxt(t.deletedAt, keepDays, now),
            style: const TextStyle(fontSize: 10, color: Colors.grey));
      // 语义断链批（2026-10-12）·日记第八类：连带清分节行（恢复可回）。
      case TrashKind.journal:
        return Text(t.cascadeNotes ?? '连带清 分节行（恢复可回；图片文件保留）',
            key: ValueKey('tp-journal-note'),
            style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Color(0xFFF43F5E)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        key: const ValueKey('tp-sheet'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('彻底删除',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('共 ${items.length} 条 · 删除后不可恢复',
              key: const ValueKey('tp-msg'),
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFF43F5E))),
          const SizedBox(height: 10),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (final t in items)
                    Container(
                      key: ValueKey('tp-item-${t.key}'),
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                                shape: BoxShape.circle, color: t.kind.dot),
                          ),
                          Expanded(
                            child: Text(t.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12)),
                          ),
                          const SizedBox(width: 6),
                          _tail(t),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('tp-cancel'),
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('取消'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  key: const ValueKey('tp-go'),
                  style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFF43F5E)),
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('彻底删除'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
