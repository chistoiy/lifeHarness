part of 'journal_page.dart';

/// 日记篇卡家族（`journal_page.dart` 拆 part · 2026-10-19）。
/// 为什么拆：主文件 1187 行贴到 size 红线 1200（余 13 行），批2 开工前须腾出余量。
/// 迁出的是「一篇日记怎么显示」这一类：当日阅读摘录 provider、底部标签/关联块、缩略条、
/// 以及它们共用的文本截断扩展。与 `_DiaryTabState` 的状态机零耦合，故不走 extension 派系
/// （与 `journal_page_track.dart` 不同：那边搬的是 State 的方法群）。
/// 轮12-11 · 列表行底栏：标签 chips + 关联小图标（☑ N 收起态·点击展开明细）+ 保存时间。
/// 语义断链批（L5 · 2026-10-12）：关联块补当日阅读摘录（原型 ins-ref「📚 摘录…」行）。

/// 当日阅读摘录（按自然日分组；摘录变动随 readTick 失效）。
final dayQuotesProvider =
    FutureProvider<Map<int, List<({BookQuote q, String book})>>>((ref) async {
  ref.watch(readTickProvider);
  return ref.read(readRepositoryProvider).quotesGroupedByDay();
});

class _DiaryMeta extends ConsumerStatefulWidget {
  const _DiaryMeta({required this.entry});

  final JournalEntry entry;

  @override
  ConsumerState<_DiaryMeta> createState() => _DiaryMetaState();
}

class _DiaryMetaState extends ConsumerState<_DiaryMeta> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final n = e.todoLines().length;
    // L5：当日新建的阅读摘录（划线/感想）＝本页关联素材（原型关联块同口径）。
    final quotes = ref
            .watch(dayQuotesProvider)
            .valueOrNull?[JournalEntry.dayStart(e.day).millisecondsSinceEpoch] ??
        const <({BookQuote q, String book})>[];
    final qm = quotes.length;
    String two(int v) => v.toString().padLeft(2, '0');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (final t in e.tags.take(3))
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: tokens.cardBorder),
                  ),
                  child: Text('#$t',
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700)),
                ),
              ),
            const Spacer(),
            if (n + qm > 0)
              IconButton(
                key: ValueKey('jref-${e.id}'),
                tooltip: '本页关联',
                visualDensity: VisualDensity.compact,
                constraints:
                    const BoxConstraints(minWidth: 40, minHeight: 28),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                onPressed: () => setState(() => _open = !_open),
                icon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.link,
                        size: 14,
                        color: _open ? tokens.accent : scheme.onSurfaceVariant),
                    const SizedBox(width: 3),
                    Text('${n + qm}',
                        style: TextStyle(
                            fontSize: 10,
                            color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            Text(
              '${two(e.updatedAt.hour)}:${two(e.updatedAt.minute)} 保存',
              style: TextStyle(
                  fontSize: 10, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        if (_open && n + qm > 0)
          Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: tokens.accent.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(10),
              border:
                  Border(left: BorderSide(color: tokens.accent, width: 3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (n > 0)
                  Text('本页关联 · ☑ $n 个待办同步',
                      style: TextStyle(
                          fontSize: 11, color: scheme.onSurfaceVariant)),
                // L5：摘录行（最多展示 3 条，全量去阅读模块看——不做第二入口）。
                for (final (:q, :book) in quotes.take(3))
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      '📚 「${q.body.replaceAll('\n', ' ').clampText(20)}」'
                      '${book.isEmpty ? '' : ' · $book'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11, color: scheme.onSurfaceVariant),
                    ),
                  ),
                if (qm > 3)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text('📚 …共 $qm 条当日摘录',
                        style: TextStyle(
                            fontSize: 11, color: scheme.onSurfaceVariant)),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 批2a · 日记行缩略条：一行 4 枚 44×44（>4 末格盖 +N · 点图看大图）。
class _DiaryThumbs extends StatelessWidget {
  const _DiaryThumbs({required this.entry});

  final JournalEntry entry;

  @override
  Widget build(BuildContext context) {
    final paths = entry.imagePaths;
    final shown = paths.take(4).toList();
    return Row(
      children: [
        for (var i = 0; i < shown.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          GestureDetector(
            key: ValueKey('jimg-${entry.id}-$i'),
            onTap: () => showImageLightbox(context, shown[i]),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 44,
                height: 44,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(File(shown[i]),
                        fit: BoxFit.cover,
                        // UI/流畅批：44px 缩略降采样（原整图解码，多图长列表滚动偏重）。
                        cacheWidth:
                            (MediaQuery.devicePixelRatioOf(context) * 96).round(),
                        errorBuilder: (_, _, _) => const ColoredBox(
                            color: Color(0x14000000),
                            child: Center(
                                child: Text('丢失',
                                    style: TextStyle(fontSize: 9))))),
                    if (i == 3 && paths.length > 4)
                      Positioned.fill(
                        child: ColoredBox(
                          color: const Color(0x73000000),
                          child: Center(
                              child: Text('+${paths.length - 4}',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12))),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
        const Spacer(),
      ],
    );
  }
}

extension on String {
  String clampText(int n) => length <= n ? this : '${substring(0, n)}…';
}
