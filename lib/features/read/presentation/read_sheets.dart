import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/image_attach.dart';
import '../domain/book.dart';
import '../domain/book_dict.dart';
import '../domain/book_progress.dart';
import '../domain/book_quote.dart';
import '../domain/book_session.dart';
import '../domain/book_toc.dart';
import 'read_providers.dart';
import 'widgets/bs_cover.dart';

part 'read_sheets_b2.dart';
part 'read_sheets_b3.dart';

/// 阅读模块弹层集合（M1批3 · 原型 sheet* 系列）。
/// 批1 落：新书 / 唯一摘录表单（最小字段版，批3 补章节/创建时间/标签/识图）/
/// 书籍操作 / 年度目标 / 摘录复习（批3 升级翻面与档位）。
/// 批2（read_sheets_b2.dart）：书籍表单（含更多资料）/ 记进度四方式 /
/// 计时明细可改（sheetSess）/ 目录粘贴导入（sheetTocImport）。

void readToast(BuildContext context, String msg) =>
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          duration: const Duration(milliseconds: 1300),
        ),
      );

Future<T?> _sheet<T>(BuildContext context, Widget child) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 20,
          right: 20,
          top: 14,
        ),
        child: SafeArea(child: child),
      ),
    );

class _SheetTitle extends StatelessWidget {
  const _SheetTitle(this.text, {this.onSave});
  final String text;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = context.tokens.accent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: cs.onSurface,
              ),
            ),
          ),
          if (onSave != null)
            TextButton(
              onPressed: onSave,
              child: Text(
                '保存',
                style: TextStyle(fontWeight: FontWeight.w800, color: accent),
              ),
            ),
        ],
      ),
    );
  }
}

/// 标签/分区 chips 行。
class _Chips extends StatelessWidget {
  const _Chips({
    required this.items,
    required this.selected,
    required this.onPick,
    this.keys,
  });
  final List<String> items;
  final Set<String> selected;
  final ValueChanged<String> onPick;
  final List<String>? keys;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < items.length; i++)
          GestureDetector(
            key: ValueKey(keys?[i] ?? items[i]),
            onTap: () => onPick(items[i]),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: selected.contains(items[i])
                    ? tokens.accent.withValues(alpha: .12)
                    : cs.surfaceContainerHighest,
                border: Border.all(
                  color: selected.contains(items[i])
                      ? tokens.accent
                      : tokens.cardBorder,
                ),
              ),
              child: Text(
                items[i],
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected.contains(items[i])
                      ? tokens.accent
                      : cs.onSurfaceVariant,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

TextField _field(
  TextEditingController c,
  String label, {
  int? lines,
  String? keyName,
}) => TextField(
  key: keyName == null ? null : ValueKey(keyName),
  controller: c,
  maxLines: lines ?? 1,
  decoration: InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(fontSize: 12.5),
    filled: true,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide.none,
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  ),
);

/// 新增书籍（书架 FAB＋ / 工作台空态「添加一本」）。
/// 批2 起与「编辑信息」共用同一张完整表单（更多资料折叠＋封面上传）。
Future<void> showAddBookSheet(
  BuildContext context,
  WidgetRef ref, {
  String defaultState = Book.kStateReading,
}) => showBookFormSheet(context, ref, defaultState: defaultState);

/// 唯一一张摘录录入表单（FAB 与详情页共用 · §3.3；默认书=在读最近那本）。
/// 批3 起为完整字段版（书/章节/页码/创建时间/原文/想法/识图·加图·剪贴板/
/// 颜色分类/标签多选），与「编辑笔记」共用同一张（read_sheets_b3.dart）。
Future<void> showQuoteSheet(
  BuildContext context,
  WidgetRef ref, {
  String? bookId,
}) => showQuoteEditSheet(context, ref, bookId: bookId);

/// 分区循环：在读→想读→已读→弃读（LH-K17 角标点按 · §3.3）。
String nextState(String state) => switch (state) {
  Book.kStateReading => Book.kStateWant,
  Book.kStateWant => Book.kStateDone,
  Book.kStateDone => Book.kStateDropped,
  _ => Book.kStateReading,
};

Future<void> cycleBookState(BuildContext context, WidgetRef ref, Book b) async {
  final next = nextState(b.state);
  await ref.read(readRepositoryProvider).setBookState(b.id, next);
  ref.read(readTickProvider.notifier).state++;
  if (context.mounted) readToast(context, '《${b.title}》· $next');
}

/// 书籍操作弹层（sheetBookOps 批1 子集：改分区 / 移除）。返回 true=已移除。
Future<bool?> showBookOpsSheet(BuildContext context, WidgetRef ref, Book b) =>
    _sheet<bool>(
      context,
      Consumer(
        builder: (sheetCtx, ref, _) {
          final cs = Theme.of(sheetCtx).colorScheme;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SheetTitle('《${b.title}》'),
              Text(
                '改分区',
                style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 6),
              _Chips(
                items: Book.states,
                selected: {b.state},
                keys: Book.states.map((s) => 'ops-st-$s').toList(),
                onPick: (s) async {
                  await ref.read(readRepositoryProvider).setBookState(b.id, s);
                  ref.read(readTickProvider.notifier).state++;
                  if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
                  if (context.mounted) readToast(context, '《${b.title}》· $s');
                },
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                key: const ValueKey('ops-edit'),
                onPressed: () {
                  Navigator.of(sheetCtx).pop();
                  showBookFormSheet(context, ref, editing: b);
                },
                icon: const Icon(Icons.edit_outlined, size: 17),
                label: const Text('编辑信息'),
              ),
              if (b.state != Book.kStateDone) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const ValueKey('ops-finish'),
                  onPressed: () async {
                    await ref
                        .read(readRepositoryProvider)
                        .setBookState(b.id, Book.kStateDone);
                    ref.read(readTickProvider.notifier).state++;
                    if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
                    if (context.mounted) {
                      readToast(context, '《${b.title}》· 已读完');
                    }
                  },
                  icon: const Icon(Icons.done_all_rounded, size: 17),
                  label: const Text('标记读完'),
                ),
              ],
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const ValueKey('ops-sess'),
                onPressed: () {
                  Navigator.of(sheetCtx).pop();
                  showSessionsSheet(context, ref, b);
                },
                icon: const Icon(BsIcons.time, size: 17),
                label: const Text('计时明细'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const ValueKey('ops-del'),
                onPressed: () async {
                  await ref.read(readRepositoryProvider).softDeleteBooks([
                    b.id,
                  ]);
                  ref.read(readTickProvider.notifier).state++;
                  if (sheetCtx.mounted) Navigator.of(sheetCtx).pop(true);
                  if (context.mounted) readToast(context, '已移除《${b.title}》');
                },
                icon: const Icon(BsIcons.trash, size: 17),
                label: const Text('移除书架'),
              ),
              const SizedBox(height: 12),
            ],
          );
        },
      ),
    );

/// 就地内嵌数字滚轮（反馈记忆「时间数值选择就地内嵌滚轮」·步长 5）。
class _NumWheel extends StatefulWidget {
  const _NumWheel({
    required this.value,
    required this.max,
    required this.onChanged,
  });
  final int value;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  State<_NumWheel> createState() => _NumWheelState();
}

class _NumWheelState extends State<_NumWheel> {
  late final FixedExtentScrollController _ctl = FixedExtentScrollController(
    initialItem: ((widget.value ~/ 5) - 1).clamp(0, widget.max ~/ 5 - 1),
  );

  @override
  Widget build(BuildContext context) {
    return ListWheelScrollView(
      controller: _ctl,
      itemExtent: 30,
      squeeze: 1.05,
      diameterRatio: 2.4,
      physics: const FixedExtentScrollPhysics(),
      onSelectedItemChanged: (i) => widget.onChanged((i + 1) * 5),
      children: [
        for (var i = 0; i < widget.max ~/ 5; i++)
          Center(
            child: Text(
              '${(i + 1) * 5}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
      ],
    );
  }
}

/// 年度目标调整（sheetGoal · 就地滚轮）。
Future<void> showGoalSheet(BuildContext context, WidgetRef ref) {
  return _sheet<void>(
    context,
    Consumer(
      builder: (sheetCtx, ref, _) {
        final w = ref.watch(workbenchProvider).valueOrNull;
        var books = w?.goalBooks ?? 50;
        var dayMin = w?.goalDay ?? 30;
        final cs = Theme.of(sheetCtx).colorScheme;
        return StatefulBuilder(
          builder: (_, setSt) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SheetTitle(
                '阅读目标',
                onSave: () async {
                  final repo = ref.read(readRepositoryProvider);
                  await repo.setKv('read.goalBooks', '$books');
                  await repo.setKv('read.goalDayMin', '$dayMin');
                  ref.read(readTickProvider.notifier).state++;
                  if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
                  if (context.mounted) readToast(context, '目标已更新');
                },
              ),
              for (final (label, val, max, cb) in [
                ('全年读完（本）', books, 200, (int v) => setSt(() => books = v)),
                ('每日分钟', dayMin, 180, (int v) => setSt(() => dayMin = v)),
              ])
                Row(
                  children: [
                    SizedBox(
                      width: 96,
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                    Expanded(
                      child: SizedBox(
                        height: 92,
                        child: _NumWheel(value: val, max: max, onChanged: cb),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    ),
  );
}
