import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/tag.dart';
import 'journal_providers.dart';
import 'widgets/tag_chip.dart';

/// 日记选标签弹层（原型 `sheetDiaryTag`）。
///
/// 只列 `scopes` 含 `diary` 的标签（口径③）；**不新建、不改名**——
/// 池全局唯一，维护入口只有「标签管理」（底行「管理 ›」直达）。
///
/// [onChanged] 是**实时回调**（原型同款：点一枚立刻反映到编辑页标签行），
/// 弹层本身不持有真值，关闭与否都不丢选择。
Future<void> showDiaryTagSheet({
  required BuildContext context,
  required WidgetRef ref,
  required List<String> selected,
  required ValueChanged<List<String>> onChanged,
  VoidCallback? onManage,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _DiaryTagSheet(
      selected: selected,
      onChanged: onChanged,
      onManage: onManage,
    ),
  );
}

class _DiaryTagSheet extends ConsumerStatefulWidget {
  const _DiaryTagSheet({
    required this.selected,
    required this.onChanged,
    this.onManage,
  });

  final List<String> selected;
  final ValueChanged<List<String>> onChanged;
  final VoidCallback? onManage;

  @override
  ConsumerState<_DiaryTagSheet> createState() => _DiaryTagSheetState();
}

class _DiaryTagSheetState extends ConsumerState<_DiaryTagSheet> {
  late final List<String> _sel = [...widget.selected];

  void _toggle(String name) {
    setState(() {
      if (_sel.contains(name)) {
        _sel.remove(name);
      } else {
        _sel.add(name);
      }
    });
    widget.onChanged([..._sel]);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final pool = ref.watch(diaryTagPoolProvider).valueOrNull ?? const <Tag>[];
    return Container(
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * .7),
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: tokens.text2.withValues(alpha: .25),
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 14),
              Row(children: [
                const Expanded(
                  child: Text('选择标签',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                ),
                IconButton(
                  key: const ValueKey('dtag-sheet-close'),
                  tooltip: '关闭',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, size: 18),
                ),
              ]),
              const SizedBox(height: 2),
              Text('全部标签',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: tokens.text2)),
              const SizedBox(height: 8),
              Flexible(
                child: pool.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 22),
                        child: Center(
                          child: Text('池里还没有日记标签 · 去「标签管理」添加',
                              style:
                                  TextStyle(fontSize: 11, color: tokens.text2)),
                        ),
                      )
                    : SingleChildScrollView(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (var i = 0; i < pool.length; i++)
                              TagChip(
                                key: ValueKey('dtag-pick-${pool[i].name}'),
                                name: pool[i].name,
                                toneIndex: i,
                                count: pool[i].useCount,
                                onTap: () => _toggle(pool[i].name),
                              ),
                          ],
                        ),
                      ),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: Text('已选 ${_sel.length} 个 · 可选 ${pool.length} 个',
                      style: TextStyle(fontSize: 11, color: tokens.text2)),
                ),
                if (widget.onManage != null)
                  TextButton(
                    key: const ValueKey('dtag-sheet-manage'),
                    onPressed: widget.onManage,
                    child: const Text('管理 ›', style: TextStyle(fontSize: 12)),
                  ),
                const SizedBox(width: 4),
                FilledButton(
                  key: const ValueKey('dtag-sheet-done'),
                  style: FilledButton.styleFrom(
                    backgroundColor: tokens.accent,
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18)),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('完成',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
