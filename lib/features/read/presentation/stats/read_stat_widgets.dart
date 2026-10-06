import 'dart:math';

import 'package:flutter/material.dart';

import '../../domain/book.dart' show Book;
import '../read_providers.dart' show bsFmt;

/// 阅读统计页的复用件（治理体积棘轮：自 read_stat_page.dart 1383 登记面抽出，
/// 行为零改动·纯移动）。

/// ⑦ 按书累计时长的行数据（时长降序由调用方排好）。
class ReadStatBookMinute {
  const ReadStatBookMinute({
    required this.id,
    required this.title,
    required this.minutes,
    required this.quotes,
    required this.percent,
  });

  final String id;
  final String title;
  final int minutes;
  final int quotes;
  final int percent;

  static List<ReadStatBookMinute> rowsOf(
    List<Book> books,
    Map<String, int> minutesByBook,
    Map<String, int> quotesByBook,
  ) {
    final rows = [
      for (final b in books)
        if ((minutesByBook[b.id] ?? 0) > 0)
          ReadStatBookMinute(
            id: b.id,
            title: b.title,
            minutes: minutesByBook[b.id]!,
            quotes: quotesByBook[b.id] ?? 0,
            percent: b.percent,
          ),
    ]..sort((a, e) => e.minutes.compareTo(a.minutes));
    return rows;
  }
}

/// ⑦ 按书累计时长卡（工单20261001轮2 · 原型 p-readstat 新增 rsBooks 段）：
/// 时长降序 · 行内＝书名 · bsFmt 累计 · 摘录数 · 进度；点行进书籍资料页
/// （复用 /read/info/:id 的「累计时长→计时明细」链，不另建单书统计页）。
class ReadStatBooksTimeCard extends StatelessWidget {
  const ReadStatBooksTimeCard({
    super.key,
    required this.rows,
    required this.onOpen,
  });

  final List<ReadStatBookMinute> rows;
  final void Function(String bookId) onOpen;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('rs-bookstime'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: .4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '按书累计时长',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                ),
              ),
              const Spacer(),
              Text(
                '时长 / 摘录 / 进度',
                style: TextStyle(fontSize: 9.5, color: cs.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (rows.isEmpty)
            Text(
              '还没有计时的书',
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            )
          else
            for (final e in rows)
              InkWell(
                key: ValueKey('rs-bt-${e.id}'),
                onTap: () => onOpen(e.id),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 2,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          e.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Text(
                        bsFmt(e.minutes),
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(
                        width: 46,
                        child: Text(
                          '${e.quotes} 条',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 10,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 40,
                        child: Text(
                          '${e.percent}%',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 10,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

/// 构成环画师（原 _DonutPainter 原名迁出，绘制逻辑逐行不变）。
class ReadStatDonutPainter extends CustomPainter {
  ReadStatDonutPainter({required this.fracs, required this.colors});
  final List<double> fracs;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 6;
    final total = fracs.fold<double>(0, (t, f) => t + f);
    if (total <= 0) {
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 12
          ..color = const Color(0xFFE2E8F0),
      );
      return;
    }
    var start = -pi / 2;
    for (var i = 0; i < fracs.length && fracs[i] > 0; i++) {
      final sweep = fracs[i] / total * 2 * pi;
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        start,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 12
          ..color = colors[i],
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(ReadStatDonutPainter old) =>
      old.fracs.join() != fracs.join();
}

/// 原型 `.mini-btn` 对译：小描边胶囊＋11.5 字，配 `Wrap` 用（U11）。
///
/// 为什么单独一件：目标卡那三枚按钮原来用默认样式的 `OutlinedButton`，
/// 390dp 下三枚合计超出卡内宽度直接 `RenderFlex overflow`；原型同位置实测
/// 单行有余量（390 宽余 64px）＝**实现漂移**，不是设计要换行。本件把尺寸收到
/// 原型档位，并用 `Wrap` 兜住更窄的窗口，溢出这条路彻底封掉。
class ReadStatMiniBtn extends StatelessWidget {
  const ReadStatMiniBtn({
    super.key,
    required this.text,
    required this.onTap,
  });

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
      child: Text(text, style: const TextStyle(fontSize: 11.5)),
    );
  }
}
