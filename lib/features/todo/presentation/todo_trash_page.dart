import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../domain/todo.dart';
import 'todo_providers.dart';
import 'widgets/todo_edit_sheet.dart' show dueLabel;

/// 垃圾箱条目剩余保留天数（与「记录管理 · 通用 · 回收站自动清理」同档）。
/// 返回 null＝设置为「不清理」；<=0＝已到期、下次启动清理（文案「待清理」）。
int? trashLeftDays(DateTime? deletedAt, int keepDays, DateTime now) {
  if (keepDays <= 0) return null;
  if (deletedAt == null) return keepDays;
  final ago = DateTime(now.year, now.month, now.day)
      .difference(DateTime(deletedAt.year, deletedAt.month, deletedAt.day))
      .inDays;
  return keepDays - ago;
}

/// 剩余天数文案（原型 ttLeftTxt：不清理 / 待清理 / 剩 N 天）。
String trashLeftTxt(DateTime? deletedAt, int keepDays, DateTime now) {
  final left = trashLeftDays(deletedAt, keepDays, now);
  if (left == null) return '不清理';
  return left <= 0 ? '待清理' : '剩 $left 天';
}

String _two(int v) => v.toString().padLeft(2, '0');

/// 「删于 09-19 14:20」（原型口径：月-日 时:分）。
String trashDelStamp(DateTime? deletedAt) => deletedAt == null
    ? '删于 --'
    : '删于 ${_two(deletedAt.month)}-${_two(deletedAt.day)} '
        '${_two(deletedAt.hour)}:${_two(deletedAt.minute)}';

/// /todo/trash · V1.57 E 批待办垃圾箱（软删条目 · 保留期内可恢复）。
///
/// 口径：行＝象限点＋标题＋截止／标签／删于时间／剩余天数（≤7 天标红）＋行内恢复·删除；
/// 右上「选择」或长按进批量（底栏 恢复／彻底删除／✕，与笔记·日记同款语言）；
/// 彻底删除走二次确认弹层并逐条列出；恢复＝回原象限原截止，不新建条目。
class TodoTrashPage extends ConsumerStatefulWidget {
  const TodoTrashPage({super.key});

  @override
  ConsumerState<TodoTrashPage> createState() => _TodoTrashPageState();
}

class _TodoTrashPageState extends ConsumerState<TodoTrashPage> {
  bool _selMode = false;
  final Set<int> _sel = {};

  void _toast(String m) {
    if (mounted) AppToast.show(context, m);
  }

  void _refresh() {
    ref.invalidate(todosProvider);
    ref.invalidate(overdueCountProvider);
    ref.invalidate(todoTrashProvider);
  }

  void _exitSel() => setState(() {
        _selMode = false;
        _sel.clear();
      });

  void _enterSel(int id) => setState(() {
        _selMode = true;
        _sel
          ..clear()
          ..add(id);
      });

  void _tapRow(int id) {
    if (!_selMode) return;
    setState(() {
      _sel.contains(id) ? _sel.remove(id) : _sel.add(id);
      if (_sel.isEmpty) _selMode = false;
    });
  }

  void _selAll(List<Todo> items) {
    setState(() {
      if (_sel.length == items.length) {
        _sel.clear();
      } else {
        _sel
          ..clear()
          ..addAll(items.map((t) => t.id!).whereType<int>());
      }
    });
  }

  /// 恢复（单条/批量）：回原象限原截止，即时补回清单/四象限/今日数字。
  Future<void> _restore(List<Todo> items) async {
    final repo = ref.read(todoRepositoryProvider);
    for (final t in items) {
      await repo.restore(t);
    }
    _refresh();
    if (!mounted) return;
    _toast(items.length == 1
        ? '已恢复到「${items.first.quadrant.label}」'
        : '已恢复 ${items.length} 项到原象限');
  }

  /// 彻底删除（真 DELETE）：先关确认弹层再给页面级提示条（模态层内挂 SnackBar 看不见）。
  Future<void> _purge(List<Todo> items) async {
    final n = await ref.read(todoRepositoryProvider).purge(
        items.map((t) => t.id!).whereType<int>().toList());
    _refresh();
    if (!mounted) return;
    _exitSel();
    _toast('已彻底删除 $n 条');
  }

  Future<void> _askPurge(List<Todo> items) async {
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

  @override
  Widget build(BuildContext context) {
    final keep = ref.watch(settingsControllerProvider).trashKeepTxt;
    final now = DateTime.now();
    final async = ref.watch(todoTrashProvider);
    final items = async.valueOrNull ?? const <Todo>[];
    final selItems =
        items.where((t) => _sel.contains(t.id)).toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('垃圾箱'),
            Text('删除的待办 · 保留期内可恢复',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.normal)),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                      children: [
                        TextSpan(
                          text: '${items.length} 项',
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
                    onPressed: items.isEmpty ? null : () => _selAll(items),
                    child: Text(_sel.length == items.length && items.isNotEmpty
                        ? '取消全选'
                        : '全选'),
                  ),
                TextButton(
                  key: const ValueKey('tt-pick'),
                  onPressed: items.isEmpty ? null : () {
                    if (_selMode) {
                      _exitSel();
                    } else {
                      setState(() => _selMode = true);
                    }
                  },
                  child: Text(_selMode ? '取消' : '选择'),
                ),
              ],
            ),
          ),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('加载失败：$e')),
              data: (list) => list.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.fromLTRB(20, 24, 20, 0),
                      child: Center(
                        child: Text('暂无已删除的待办',
                            key: ValueKey('tt-empty'),
                            style:
                                TextStyle(fontSize: 12, color: Colors.grey)),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _tile(list[i], now),
                    ),
            ),
          ),
          if (_selMode && _sel.isNotEmpty) _selBar(selItems),
        ],
      ),
    );
  }

  Widget _tile(Todo t, DateTime now) {
    final accent = context.tokens.accent;
    final left = trashLeftDays(t.deletedAt, ref.watch(settingsControllerProvider).trashKeepDays, now);
    final urgent = left != null && left <= 7;
    final selected = _sel.contains(t.id);
    return GestureDetector(
      key: ValueKey('tt-row-${t.id}'),
      behavior: HitTestBehavior.opaque,
      onLongPress: () => _enterSel(t.id!),
      onTap: () => _tapRow(t.id!),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: context.cardDecoration,
        child: Row(
          children: [
            if (_selMode)
              Container(
                key: ValueKey('tt-chk-${t.id}'),
                width: 18,
                height: 18,
                margin: const EdgeInsets.only(right: 8),
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
                key: ValueKey('tt-qdot-${t.id}'),
                width: 12,
                height: 12,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                    shape: BoxShape.circle, color: t.quadrant.colorOf(accent)),
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
                      if (t.dueAt != null)
                        _meta('⏰ ${dueLabel(t)}'),
                      if (t.tag != null) _meta('#${t.tag}'),
                      _meta(trashDelStamp(t.deletedAt)),
                      Text(
                        trashLeftTxt(t.deletedAt,
                            ref.watch(settingsControllerProvider).trashKeepDays, now),
                        key: ValueKey('tt-left-${t.id}'),
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: urgent ? FontWeight.w800 : FontWeight.w600,
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
              _btn('tt-restore-${t.id}', '恢复', accent, () => _restore([t])),
              const SizedBox(width: 4),
              _btn('tt-del-${t.id}', '删除', const Color(0xFFF43F5E),
                  () => _askPurge([t])),
            ],
          ],
        ),
      ),
    );
  }

  Widget _meta(String text) => Text(text,
      style: const TextStyle(fontSize: 10, color: Colors.grey));

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

  /// 批量底栏：已选 N 项 + 恢复 + 彻底删除 + ✕（笔记·日记同款语言）。
  Widget _selBar(List<Todo> selItems) {
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

/// sheetTrashPurge：彻底删除二次确认（逐条列出，确认才真 DELETE）。
class _PurgeSheet extends StatelessWidget {
  const _PurgeSheet({required this.items, required this.now, required this.keepDays});

  final List<Todo> items;
  final DateTime now;
  final int keepDays;

  @override
  Widget build(BuildContext context) {
    final accent = context.tokens.accent;
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
                      key: ValueKey('tp-item-${t.id}'),
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
                                shape: BoxShape.circle,
                                color: t.quadrant.colorOf(accent)),
                          ),
                          Expanded(
                            child: Text(t.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12)),
                          ),
                          Text(trashLeftTxt(t.deletedAt, keepDays, now),
                              style: const TextStyle(
                                  fontSize: 10, color: Colors.grey)),
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

/// 待办页底部入口行（清单/四象限两视图共用）：计数＋期限同源，点击 push 垃圾箱。
class TodoTrashEntry extends ConsumerWidget {
  const TodoTrashEntry({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.watch(todoTrashProvider).valueOrNull?.length ?? 0;
    final keep = ref.watch(settingsControllerProvider).trashKeepTxt;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: InkWell(
        key: const ValueKey('todo-trash-entry'),
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/todo/trash'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: context.cardDecoration,
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.delete_outline,
                    size: 18, color: Color(0xFF64748B)),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('垃圾箱',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text('$n 项 · $keep',
                        key: const ValueKey('todo-trash-meta'),
                        style: const TextStyle(
                            fontSize: 10, color: Color(0xFF94A3B8))),
                  ],
                ),
              ),
              const Text('›',
                  style: TextStyle(fontSize: 16, color: Color(0xFFCBD5E1))),
            ],
          ),
        ),
      ),
    );
  }
}
