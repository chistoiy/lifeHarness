import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/journal_entry.dart';
import '../diary_edit_page.dart';
import '../journal_providers.dart';

/// M1批2c · 回顾底部弹层（原型 sheetDiaryReview）：
/// 月份切换 ‹ YYYY年M月 › + 心情趋势柱状（CustomPaint·高度=心情1~7）
/// + 词云（高频词字号分级·无图表依赖）+ 去年本月卡（点按打开该篇）。
Future<void> openDiaryReview(BuildContext context, {DateTime? month}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.tokens.page,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.78,
        minChildSize: 0.5,
        maxChildSize: 0.92,
        builder: (bc, scrollCtrl) =>
            _DiaryReview(month ?? DateTime.now(), scrollCtrl),
      ),
    );

class _DiaryReview extends ConsumerStatefulWidget {
  const _DiaryReview(this.month, this.scrollCtrl);

  final DateTime month;
  final ScrollController scrollCtrl;

  @override
  ConsumerState<_DiaryReview> createState() => _DiaryReviewState();
}

class _DiaryReviewState extends ConsumerState<_DiaryReview> {
  static const _palette = [
    Color(0xFF6366F1), Color(0xFF2DD4BF), Color(0xFFF59E0B),
    Color(0xFFFB7185), Color(0xFF8B5CF6), Color(0xFF0EA5E9), Color(0xFFF43F5E),
  ];

  late DateTime _m = widget.month;

  Future<List<JournalEntry>> _load() =>
      ref.read(journalRepositoryProvider).month(_m);

  void _shift(int delta) => setState(() {
        _m = DateTime(_m.year, _m.month + delta);
      });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<List<JournalEntry>>(
      key: ValueKey('${_m.year}-${_m.month}'),
      future: _load(),
      builder: (bc, snap) {
        final entries = snap.data ?? const <JournalEntry>[];
        return ListView(
          controller: widget.scrollCtrl,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: scheme.onSurfaceVariant.withValues(alpha: .3),
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 12),
            // 标题 + 月份切换
            Row(
              children: [
                const Text('回顾',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                const Spacer(),
                IconButton(
                    key: const ValueKey('dr-prev'),
                    onPressed: () => _shift(-1),
                    icon: const Icon(Icons.chevron_left)),
                Text('${_m.year}年${_m.month}月',
                    key: const ValueKey('dr-month-label'),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800)),
                IconButton(
                    key: const ValueKey('dr-next'),
                    onPressed: () => _shift(1),
                    icon: const Icon(Icons.chevron_right)),
              ],
            ),
            const SizedBox(height: 8),
            _card(bc, tokens, scheme, '心情趋势', [
              SizedBox(
                key: const ValueKey('dr-trend'),
                height: 96,
                child: CustomPaint(
                    size: const Size(double.infinity, 96),
                    painter: _TrendPainter(month: _m, entries: entries)),
              ),
              const SizedBox(height: 8),
              // 心情图例（7 表情·线性文字）
              Wrap(
                key: const ValueKey('dr-legend'),
                spacing: 10,
                children: [
                  for (var i = 0; i < kJournalMoods.length; i++)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                                color: _palette[i],
                                borderRadius: BorderRadius.circular(2))),
                        const SizedBox(width: 3),
                        Text('${kJournalMoods[i].$1}${kJournalMoods[i].$2}',
                            style: TextStyle(
                                fontSize: 10,
                                color: scheme.onSurfaceVariant)),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(_summary(entries),
                  style: TextStyle(
                      fontSize: 11.5,
                      height: 1.7,
                      color: scheme.onSurfaceVariant)),
            ]),
            const SizedBox(height: 12),
            _card(bc, tokens, scheme, '高频词云', [
              Wrap(
                key: const ValueKey('dr-cloud'),
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final (w, freq) in _topWords(entries))
                    Text(w,
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: _fs(freq),
                            height: 1.3,
                            color: Color.lerp(scheme.onSurface,
                                tokens.accent, _fs(freq) / 24))),
                ],
                // 空月份兜底
              ),
              if (_topWords(entries).isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('本月文字还太少 · 多写几篇再回来看',
                      style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant)),
                ),
            ]),
            const SizedBox(height: 12),
            _lastYearCard(bc, tokens, scheme),
          ],
        );
      },
    );
  }

  Widget _card(
      BuildContext bc, ThemeTokens tokens, ColorScheme scheme, String title,
      List<Widget> body) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tokens.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          ...body,
        ],
      ),
    );
  }

  /// 去年本月卡：repo.range 取去年同月条目，点最新一篇进编辑。
  Widget _lastYearCard(
      BuildContext bc, ThemeTokens tokens, ColorScheme scheme) {
    return FutureBuilder<List<JournalEntry>>(
      future: ref
          .read(journalRepositoryProvider)
          .month(DateTime(_m.year - 1, _m.month, 1)),
      builder: (bc2, snap) {
        final old = snap.data ?? const <JournalEntry>[];
        if (old.isEmpty) return const SizedBox.shrink();
        final latest = old.last; // range 升序 → 末条=最新
        return Container(
          key: const ValueKey('dr-yoy'),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: tokens.accent.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(16),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              Navigator.of(bc2).pop();
              bc.push('/journal/edit',
                  extra: DiaryEditArg(entryId: latest.id));
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('去年${_m.month}月 · 共 ${old.length} 篇',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: tokens.accent)),
                const SizedBox(height: 4),
                Text(
                  '「${latest.previewText.replaceAll('\n', ' ')}」'
                  .clamp40(),
                  style: TextStyle(
                      fontSize: 11.5,
                      height: 1.7,
                      color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _summary(List<JournalEntry> entries) {
    final counts = <int, int>{};
    var chars = 0;
    for (final e in entries) {
      if (e.mood != null) counts[e.mood!] = (counts[e.mood!] ?? 0) + 1;
      chars += e.plainBody.replaceAll(RegExp(r'\s'), '').length;
    }
    if (entries.isEmpty) return '本月还没有记录 · 从写今天的日记开始';
    final top = counts.entries.isEmpty
        ? null
        : counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    return '本月记录 ${entries.length} 篇 · 共 $chars 字'
        '${top == null ? '' : ' · 心情以 ${moodEmoji(top)} ${moodLabel(top)} 居多'}';
  }

  /// 高频词：ASCII 词 + 中文 2-gram（去停用字），按频次取前 12。
  static List<(String, int)> _topWords(List<JournalEntry> entries) {
    const stop = {
      '的', '了', '是', '在', '我', '有', '和', '就', '不', '人', '都', '一',
      '上', '也', '很', '到', '说', '要', '去', '会', '着', '没', '看', '好',
      '自己', '这', '那', '他', '她', '它', '们', '个', '吗', '呢', '吧', '把',
    };
    final freq = <String, int>{};
    final re = RegExp(r"[a-zA-Z]{2,}|[\u4e00-\u9fff]+");
    for (final e in entries) {
      for (final m in re.allMatches(e.plainBody)) {
        final t = m.group(0)!;
        if (t.codeUnitAt(0) < 0x4e00) {
          final w = t.toLowerCase();
          freq[w] = (freq[w] ?? 0) + 1;
        } else if (t.length == 1 && !stop.contains(t)) {
          freq[t] = (freq[t] ?? 0) + 1;
        } else {
          for (var i = 0; i + 2 <= t.length; i++) {
            final g = t.substring(i, i + 2);
            if (!stop.contains(g[0]) || !stop.contains(g[1])) {
              freq[g] = (freq[g] ?? 0) + 1;
            }
          }
        }
      }
    }
    final list = freq.entries.where((x) => x.value >= 2).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [for (final x in list.take(12)) (x.key, x.value)];
  }

  static double _fs(int freq) =>
      freq >= 8 ? 22 : freq >= 5 ? 17 : freq >= 3 ? 14 : 11.5;
}

/// 心情趋势柱：当月每天一根，高度=心情 1~7（无记录=12% 淡条）。
class _TrendPainter extends CustomPainter {
  _TrendPainter({required this.month, required this.entries});

  final DateTime month;
  final List<JournalEntry> entries;

  static const _palette = [
    Color(0xFF6366F1), Color(0xFF2DD4BF), Color(0xFFF59E0B),
    Color(0xFFFB7185), Color(0xFF8B5CF6), Color(0xFF0EA5E9), Color(0xFFF43F5E),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final days = DateTime(month.year, month.month + 1, 0).day;
    final byDay = <int, JournalEntry>{};
    for (final e in entries) {
      byDay.putIfAbsent(e.day.day, () => e); // 同日多篇取首篇（列表新→旧）
    }
    final slot = size.width / days;
    final w = (slot * 0.62).clamp(2.0, 14.0);
    for (var d = 1; d <= days; d++) {
      final e = byDay[d];
      final mood = e?.mood;
      final h = mood == null
          ? size.height * 0.12
          : size.height * (0.3 + mood / kJournalMoods.length * 0.7);
      final paint = Paint()
        ..color = mood == null
            ? const Color(0x1F000000)
            : _palette[(mood - 1) % _palette.length];
      final r = RRect.fromRectAndCorners(
        Rect.fromLTWH((d - 1) * slot + (slot - w) / 2, size.height - h, w, h),
        topLeft: const Radius.circular(3),
        topRight: const Radius.circular(3),
      );
      canvas.drawRRect(r, paint);
    }
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.month != month || old.entries != entries;
}

extension on String {
  String clamp40() => length <= 40 ? this : '${substring(0, 40)}…';
}
