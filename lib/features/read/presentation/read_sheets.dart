import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/image_attach.dart';
import '../data/isbn_enrich.dart';
import '../domain/book.dart';
import '../domain/book_dict.dart';
import '../domain/book_progress.dart';
import '../domain/book_list.dart';
import '../domain/book_quote.dart';
import '../domain/book_toc.dart';
import './reader/epub_state_ui.dart' show showBrDelSheet;
import './shelf/book_form_page.dart' show openBiblioSearch, openBookForm;
import 'read_providers.dart';
import 'widgets/bs_cover.dart';

part 'read_sheets_b2.dart';
part 'read_sheets_b3.dart';
part 'read_sheets_b4.dart';

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
      // 真机验收轮2：限高到状态栏以下（作为 sheet 约束参与布局，长表单不再顶进通知栏）。
      constraints: BoxConstraints(
        maxHeight:
            MediaQuery.of(context).size.height - MediaQuery.of(context).padding.top - 24,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      // 真机验收轮1：viewInsets 必须取弹层自身 context（调用方 context 会把键盘高度定格为 0，输入法盖住输入框）。
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetCtx).bottom,
          left: 20,
          right: 20,
          top: 14,
        ),
        child: SafeArea(child: child),
      ),
    );

class _SheetTitle extends StatelessWidget {
  const _SheetTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
  bool autofocus = false,
  ValueChanged<String>? onChanged,
}) => TextField(
  key: keyName == null ? null : ValueKey(keyName),
  controller: c,
  maxLines: lines ?? 1,
  autofocus: autofocus,
  onChanged: onChanged,
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

/// 新增书籍（书架 FAB / 工作台空态「添加一本」/ 摘录表单「添加一本」）。
/// V1.44 先搜后加：入口统一改道豆瓣书目搜索页（原型 shNewOpen→bsrOpen），
/// 旧底部弹窗退居死代码待收口批删除；[defaultState] 仅保留签名兼容
/// （搜索页「手动输入」恒默认「想读」，与原型一致）。
Future<void> showAddBookSheet(
  BuildContext context,
  WidgetRef ref, {
  String defaultState = Book.kStateWant,
}) => openBiblioSearch(context);

/// 唯一一张摘录录入表单（FAB 与详情页共用 · §3.3；默认书=在读最近那本）。
/// 批3 起为完整字段版（书/章节/页码/创建时间/原文/想法/识图·加图·剪贴板/
/// 颜色分类/标签多选），与「编辑笔记」共用同一张（read_sheets_b3.dart）。
Future<void> showQuoteSheet(
  BuildContext context,
  WidgetRef ref, {
  String? bookId,
}) => showQuoteEditPage(context, ref, bookId: bookId);

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
                  // V1.44：编辑改整页表单（原型 shEditOpen→bfOpenEdit）。
                  openBookForm(context, bookId: b.id);
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
                  // 真机验收轮1e：计时明细半屏层改全屏阅读记录页。
                  GoRouter.of(context).push('/read/log/${b.id}');
                },
                icon: const Icon(BsIcons.time, size: 17),
                label: const Text('计时明细'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const ValueKey('ops-list'),
                onPressed: () {
                  Navigator.of(sheetCtx).pop();
                  showMoveToListSheet(context, ref, b);
                },
                icon: const Icon(BsIcons.book, size: 17),
                label: const Text('移入书单'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const ValueKey('ops-del'),
                onPressed: () async {
                  // 轮4⑤ 收口：本入口此前绕过询问直接软删（＝「删了还在/角标不消」
                  // 第三入口），现与长按/详情统一走「保留/全删」去留弹层；
                  // 弹层 resolve 时提交已落库，据书行真态回传 gone。
                  await showBrDelSheet(context, ref, b);
                  if (!sheetCtx.mounted) return;
                  final nb = await ref.read(readRepositoryProvider).bookById(b.id);
                  if (sheetCtx.mounted) {
                    Navigator.of(sheetCtx).pop(nb == null || nb.isDeleted);
                  }
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
    this.keyName,
    required this.value,
    required this.max,
    required this.onChanged,
  });
  final String? keyName;
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
      // 显式 ValueKey<String>：字段访问不经提升会推成 ValueKey<String?>，与 finder 的
      // ValueKey<String> runtimeType 不同 → == 恒 false（Dart 泛型陷阱）。
      key: widget.keyName == null ? null : ValueKey<String>(widget.keyName!),
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

/// 年度目标调整（sheetGoal · 就地滚轮 · 批4 起为五路 L7，见 read_sheets_b4.dart）。
Future<void> showGoalSheet(BuildContext context, WidgetRef ref) =>
    showGoalSheetV2(context, ref);
