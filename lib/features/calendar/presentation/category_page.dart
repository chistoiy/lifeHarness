import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/category.dart';
import 'calendar_providers.dart';

/// 分类管理（V1.19.1 · 原型 p-sub-cats/p-sub-catAdd）。
/// 两级树 · 长按拖拽=调整顺序/拖入其他父级换组 · 添加/编辑/删除即时全局同源生效
/// （速记列 / 统一添加弹层 / 时间账本统计共用）。
class CategoryPage extends ConsumerWidget {
  const CategoryPage({super.key});

  static const palette = <String, String>{
    '品牌蓝': '#6366F1',
    '紫罗兰': '#8B5CF6',
    '琥珀': '#F59E0B',
    '橙': '#F97316',
    '粉桃': '#F472B6',
    '靛夜': '#3730A3',
    '薄荷': '#34D399',
    '亚麻': '#B45309',
    '石墨': '#64748B',
    '雾灰': '#94A3B8',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cats = ref.watch(categoriesProvider).valueOrNull ?? const <Category>[];
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;

    final primary = cats.where((c) => c.isPrimary).toList();
    List<Category> subsOf(int id) => cats.where((c) => c.parentId == id).toList();
    final collapsed = ref.watch(catCollapsedProvider);

    // 扁平行序：一级 + 其展开的次级（拖拽重排后按"前邻一级"归组写回）。
    final rows = <Category>[];
    final isSub = <bool>[];
    for (final p in primary) {
      rows.add(p);
      isSub.add(false);
      if (!collapsed.contains(p.id)) {
        for (final s in subsOf(p.id!)) {
          rows.add(s);
          isSub.add(true);
        }
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('分类管理'),
        actions: [
          IconButton(
              tooltip: '添加分类',
              icon: const Icon(Icons.add),
              onPressed: () => _showAddSheet(context, ref)),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
            child: Row(
              children: [
                Expanded(
                  child: Text('🖐 长按拖拽 = 调整顺序 / 拖入其他父级换组 · 计数=次级数',
                      style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant)),
                ),
                TextButton(
                  onPressed: () => ref
                      .read(catCollapsedProvider.notifier)
                      .state = collapsed.length == primary.length
                          ? <int>{}
                          : primary.map((c) => c.id!).toSet(),
                  child: Text(collapsed.length == primary.length ? '全部展开' : '全部折叠',
                      style: const TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              itemCount: rows.length,
              onReorder: (oldIndex, newIndex) => _reorder(ref, rows, isSub, oldIndex, newIndex),
              itemBuilder: (context, i) {
                final c = rows[i];
                final sub = isSub[i];
                final subs = sub ? const <Category>[] : subsOf(c.id!);
                return Dismissible(
                  key: ValueKey('${sub ? 's' : 'p'}-${c.id}'),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(16)),
                    child: const Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
                  ),
                  onDismissed: (_) async {
                    await ref.read(categoryDaoProvider).deleteWithChildren(c);
                    ref.invalidate(categoriesProvider);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: sub
                            ? () => _showEditSheet(context, ref, c)
                            : () => ref.read(catCollapsedProvider.notifier).state =
                                collapsed.contains(c.id)
                                    ? ({...collapsed}..remove(c.id)).toSet()
                                    : {...collapsed, c.id!},
                        onLongPress: sub ? () => _showEditSheet(context, ref, c) : null,
                        child: Container(
                          padding: EdgeInsets.fromLTRB(sub ? 40 : 12, 12, 8, 12),
                          decoration: context.cardDecoration,
                          child: Row(
                            children: [
                              Container(
                                width: sub ? 15 : 20,
                                height: sub ? 15 : 20,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: c.name == '工作'
                                      ? tokens.accent
                                      : _hex(c.colorHex ?? parentHex(cats, c.parentId)),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                  child: Text(c.name,
                                      style: TextStyle(
                                          fontSize: sub ? 13 : 14,
                                          fontWeight: sub ? FontWeight.w600 : FontWeight.w700))),
                              if (c.tag != null && c.tag!.isNotEmpty)
                                Container(
                                  margin: const EdgeInsets.only(right: 6),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                      color: const Color(0xFF334155),
                                      borderRadius: BorderRadius.circular(6)),
                                  child: Text(c.tag!,
                                      style: const TextStyle(
                                          fontSize: 9, color: Colors.white)),
                                ),
                              if (!sub && subs.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7),
                                  decoration: BoxDecoration(
                                      color: scheme.onSurface.withValues(alpha: .06),
                                      shape: BoxShape.circle),
                                  child: Text('${subs.length}',
                                      style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          color: scheme.onSurfaceVariant)),
                                ),
                              if (!sub)
                                Icon(collapsed.contains(c.id)
                                    ? Icons.expand_more
                                    : Icons.expand_less,
                                    size: 18, color: scheme.onSurfaceVariant),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static String parentHex(List<Category> cats, int? pid) {
    for (final c in cats) {
      if (c.id == pid && c.colorHex != null) return c.colorHex!;
    }
    return '#94A3B8';
  }

  static Color _hex(String h) {
    final v = int.tryParse(h.replaceFirst('#', ''), radix: 16) ?? 0x94A3B8;
    return Color(0xFF000000 | v);
  }

  /// 拖拽重排：按新行序重建 sort，次级的新父级=其上方最近的一级（拖入其他组即换组）。
  Future<void> _reorder(
      WidgetRef ref, List<Category> rows, List<bool> isSub, int oldIndex, int newIndex) async {
    if (oldIndex == newIndex) return;
    final list = [...rows];
    final flags = [...isSub];
    final item = list.removeAt(oldIndex);
    final flag = flags.removeAt(oldIndex);
    final target = (newIndex > oldIndex ? newIndex - 1 : newIndex).clamp(0, list.length);
    list.insert(target, item);
    flags.insert(target, flag);

    final dao = ref.read(categoryDaoProvider);
    var sortP = 0, sortS = 0;
    for (var i = 0; i < list.length; i++) {
      final c = list[i];
      if (!flags[i]) {
        sortP++;
        sortS = 0;
        await dao.update(c, clearParent: true, sort: sortP);
      } else {
        // 前邻一级即新父组
        var j = i - 1;
        while (j >= 0 && flags[j]) {
          j--;
        }
        final parent = j >= 0 ? list[j].id : null;
        sortS++;
        await dao.update(c, parentId: parent, sort: sortS);
      }
    }
    ref.invalidate(categoriesProvider);
  }

  void _showAddSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _CatAddSheet(),
    );
  }

  void _showEditSheet(BuildContext context, WidgetRef ref, Category c) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CatAddSheet(existing: c),
    );
  }
}

/// 折叠态集合（页面级）。
final catCollapsedProvider = StateProvider<Set<int>>((ref) => {});

class _CatAddSheet extends ConsumerStatefulWidget {
  const _CatAddSheet({this.existing});
  final Category? existing;

  @override
  ConsumerState<_CatAddSheet> createState() => _CatAddSheetState();
}

class _CatAddSheetState extends ConsumerState<_CatAddSheet> {
  late bool _primary = widget.existing == null ? true : widget.existing!.isPrimary;
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late String? _parent = widget.existing?.parentId?.toString();
  late String? _tag = widget.existing?.tag;
  late String? _color = widget.existing?.colorHex;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final n = _name.text.trim();
    if (n.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先输入分类名称')));
      return;
    }
    final dao = ref.read(categoryDaoProvider);
    if (_primary) {
      if (widget.existing != null) {
        await dao.update(widget.existing!.copyWith(name: n, tag: _tag, colorHex: _color));
      } else {
        final cats = ref.read(categoriesProvider).valueOrNull ?? const [];
        await dao.insert(Category(
            name: n, colorHex: _color, tag: _tag, sort: cats.length + 1));
      }
    } else {
      final pid = int.tryParse(_parent ?? '');
      if (pid == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请选择上级分类')));
        return;
      }
      if (widget.existing != null) {
        await dao.update(widget.existing!.copyWith(name: n, tag: _tag), parentId: pid, sort: widget.existing!.sort);
      } else {
        await dao.insert(Category(name: n, parentId: pid, tag: _tag));
      }
    }
    ref.invalidate(categoriesProvider);
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✔ 已保存分类「$n」· 速记列/添加弹层/账本同源生效')));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final cats = ref.watch(categoriesProvider).valueOrNull ?? const <Category>[];
    final primaries = cats.where((c) => c.isPrimary).toList();
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 14, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                    child: Text(widget.existing == null ? '添加分类' : '编辑分类',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('一级', style: TextStyle(fontSize: 11))),
                    ButtonSegment(value: false, label: Text('次级', style: TextStyle(fontSize: 11))),
                  ],
                  selected: {_primary},
                  onSelectionChanged: (s) => setState(() => _primary = s.first),
                ),
              ],
            ),
            if (!_primary) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _parent,
                decoration: const InputDecoration(labelText: '上级分类', isDense: true),
                items: [for (final p in primaries) DropdownMenuItem(value: '${p.id}', child: Text(p.name))],
                onChanged: (v) => setState(() => _parent = v),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: '分类名称', isDense: true),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _tag,
              decoration: const InputDecoration(labelText: '默认标签（可选）', isDense: true),
              items: const [
                DropdownMenuItem(value: null, child: Text('无')),
                DropdownMenuItem(value: '#工作', child: Text('#工作')),
                DropdownMenuItem(value: '#开会', child: Text('#开会')),
                DropdownMenuItem(value: '#加班', child: Text('#加班')),
                DropdownMenuItem(value: '#睡觉', child: Text('#睡觉')),
                DropdownMenuItem(value: '#摸鱼', child: Text('#摸鱼')),
              ],
              onChanged: (v) => setState(() => _tag = v),
            ),
            const SizedBox(height: 12),
            Text('颜色（次级留空=继承父级）',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: tokens.accent)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in CategoryPage.palette.entries)
                  InkWell(
                    onTap: () => setState(() => _color = e.value),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFF000000 | (int.tryParse(e.value.replaceFirst('#', ''), radix: 16) ?? 0)),
                          border: _color == e.value
                              ? Border.all(color: tokens.accent, width: 3)
                              : null),
                      child: _color == e.value
                          ? const Icon(Icons.check, size: 15, color: Colors.white)
                          : null,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: tokens.accent),
                onPressed: _save,
                child: Text(widget.existing == null ? '保 存' : '保存修改'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
