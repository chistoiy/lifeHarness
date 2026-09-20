import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/journal_entry.dart';
import '../journal_providers.dart';

/// INS 卡片流单卡（原型 ins-card：头像行 · 正文 · 回望操作 · 次数与标签）。
class InsDiaryCard extends ConsumerWidget {
  const InsDiaryCard({super.key, required this.entry, this.onOpen});

  final JournalEntry entry;
  final VoidCallback? onOpen;

  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final d = entry.day;
    final wd = _weekdays[d.weekday - 1];
    final emo = moodEmoji(entry.mood);

    void react(bool liked, bool starred) {
      ref.read(journalRepositoryProvider).setFlags(entry.id!,
          liked: liked, starred: starred);
      ref.invalidate(journalsProvider);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(tokens.cardRadius),
        border: Border.all(color: tokens.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 4),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration:
                      BoxDecoration(shape: BoxShape.circle, gradient: tokens.gradient),
                  child: const Text('C',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 13)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('CHIST · ${_two(d.month)}-${_two(d.day)}',
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700)),
                      Text(
                          '周$wd${emo == null ? '' : ' · 心情 $emo ${moodLabel(entry.mood)}'}',
                          style: TextStyle(
                              fontSize: 10,
                              color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                IconButton(
                    onPressed: () => ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(
                            content: Text('分享日记卡片 · 规划 V1.x'))),
                    icon: const Icon(Icons.ios_share, size: 16)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 6),
            child: Text(
              entry.content.isEmpty ? '（今天还没写正文）' : entry.content,
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, height: 1.75),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                IconButton(
                  key: ValueKey('ins-like-${entry.id}'),
                  onPressed: () => react(!entry.liked, entry.starred),
                  icon: Text(entry.liked ? '❤️' : '🤍',
                      style: const TextStyle(fontSize: 17)),
                ),
                IconButton(
                  key: ValueKey('ins-star-${entry.id}'),
                  onPressed: () => react(entry.liked, !entry.starred),
                  icon: Text(entry.starred ? '⭐' : '☆',
                      style: const TextStyle(fontSize: 17)),
                ),
                IconButton(
                    onPressed: () => ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(
                            content: Text('评论/批注 · 规划 V1.x'))),
                    icon: const Text('💬', style: TextStyle(fontSize: 17))),
                const Spacer(),
                TextButton(
                  onPressed: onOpen,
                  child: const Text('⛶ 全屏',
                      style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: Text(
              '${entry.viewCount} 次回望'
              '${entry.tags.isEmpty ? '' : ' · ${entry.tags.map((t) => '#$t').join(' ')}'}',
              style: TextStyle(
                  fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
}
