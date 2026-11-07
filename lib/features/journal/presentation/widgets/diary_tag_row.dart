import 'package:flutter/material.dart';

import '../../domain/tag.dart';
import 'tag_chip.dart';

/// 日记编辑页的标签行（原型 `#diaryTagRow`）。
///
/// 位置：心情轨之下、正文之上。内容＝已选胶囊（可 ✕ 就地移除）＋末尾「＋ 标签」。
/// 池里查不到的颜色位按行内次序兜底（历史篇可能挂着已被删除的标签名）。
class DiaryTagRow extends StatelessWidget {
  const DiaryTagRow({
    super.key,
    required this.tags,
    required this.pool,
    required this.onRemove,
    required this.onAdd,
  });

  final List<String> tags;
  final List<Tag> pool;
  final ValueChanged<String> onRemove;
  final VoidCallback onAdd;

  int _toneOf(String name) {
    final i = pool.indexWhere((t) => t.name == name);
    return i >= 0 ? i : tags.indexOf(name);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            for (final n in tags) ...[
              TagChip(
                key: ValueKey('dtag-chip-$n'),
                name: n,
                toneIndex: _toneOf(n),
                onRemove: () => onRemove(n),
              ),
              const SizedBox(width: 6),
            ],
            TagAddChip(onTap: onAdd),
          ],
        ),
      ),
    );
  }
}
