part of 'shelf_page.dart';

// 治理G7d1a：长按菜单（kLpAll / kLpDefault / showLongPressSheet）自 shelf_page
// 顶层整块外提（同库 part·外部 import shelf_page.dart 的 show 名单不受影响）。
// 项与顺序来自设置（read.longPress · §6 · 弹层自带「调整长按菜单」入口）。
/// 长按书籍菜单：项与顺序来自设置（read.longPress · §6 · sheetLongPress 弹层自带
/// 「调整长按菜单」入口）。可选全集＝LP_ALL，未勾选项不渲染；尾行「查看书籍详情」（原型 5059）。
const kLpAll = ['计时', '记摘录', '改分区', '移书单', '标记读完', '多选', '删除'];
const kLpDefault = '计时,记摘录,改分区,移书单,删除';

Future<void> showLongPressSheet(BuildContext context, WidgetRef ref, Book b) {
  return showModalBottomSheet<void>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetCtx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        child: Consumer(
          builder: (_, ref2, _) {
            final raw =
                ref2
                    .watch(readKvProvider(('read.longPress', kLpDefault)))
                    .valueOrNull ??
                kLpDefault;
            final items = raw.split(',').where(kLpAll.contains).toList();
            Widget row(String key, String label, VoidCallback onTap) =>
                ListTile(
                  key: ValueKey(key),
                  dense: true,
                  title: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onTap: onTap,
                );
            Widget rowFor(String name) => switch (name) {
              '计时' => row('lp-timer', '计时', () {
                Navigator.of(sheetCtx).pop();
                readTimerTap(ref2, context, target: b);
              }),
              '记摘录' => row('lp-quote', '记摘录', () {
                Navigator.of(sheetCtx).pop();
                showQuoteSheet(context, ref2, bookId: b.id);
              }),
              '改分区' => row('lp-state', '改分区 · ${b.state}', () {
                Navigator.of(sheetCtx).pop();
                cycleBookState(context, ref2, b);
              }),
              '移书单' => row('lp-list', '移书单', () {
                Navigator.of(sheetCtx).pop();
                showMoveToListSheet(context, ref2, b);
              }),
              '标记读完' => row('lp-done', '标记读完', () async {
                await ref2.read(readRepositoryProvider).bulkSetState(
                  [b.id],
                  Book.kStateDone,
                );
                ref2.read(readTickProvider.notifier).state++;
                if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
                if (context.mounted) {
                  readToast(context, '《${b.title}》已标记读完 · 自动进年度书单');
                }
              }),
              '多选' => row('lp-multi', '多选', () {
                ref2.read(shelfUiProvider.notifier).state =
                    ref2.read(shelfUiProvider).copyWith(
                      batch: true,
                      sel: {b.id},
                    );
                if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
              }),
              _ => row('lp-del', '删除', () async {
                // 轮4⑤：长按删除与详情页「删除本地书」共用去留询问（保留/全删），
                // 不再静默软删；书籍行进回收站的处置在弹层提交里统一做。
                if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
                if (!context.mounted) return;
                await showBrDelSheet(context, ref2, b);
              }),
            };
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '《${b.title}》',
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  // V1.54 批A · 屏2（js.frag xrLpLabel/xrLpGo）：全书索引入口置顶。
                  if (b.local)
                    GestureDetector(
                      key: const ValueKey('lp-xray'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () async {
                        Navigator.of(sheetCtx).pop();
                        if (!context.mounted) return;
                        // 存量书懒补算指纹（批A-3）；随后进阅读页自动开 X-Ray 段。
                        await ref2.read(xraySchedulerProvider).ensureMd5(b);
                        if (!context.mounted) return;
                        ref2.read(readerXrOpenTabProvider.notifier).state = b.id;
                        context.push('/read/reader/${b.id}');
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(
                            vertical: 10, horizontal: 12),
                        decoration: BoxDecoration(
                          border: Border.all(
                              color: Theme.of(context).dividerColor),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.travel_explore_outlined, size: 14),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _xrLpLabel(
                                  ref2.read(xraySchedulerProvider).live(b.id),
                                  ref2.read(xrayTaskBadgeProvider)
                                      .valueOrNull?[b.id],
                                ),
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  // 原型 shLongMenu 包装器：本地书置顶「开始阅读 · 本地 EPUB」渐变钮。
                  // 批3.5：钮走状态守卫（预载中提示 / 已清缓存分流三态弹层）。
                  if (b.local) ...[
                    GestureDetector(
                      key: const ValueKey('lp-read'),
                      onTap: () async {
                        Navigator.of(sheetCtx).pop();
                        if (!context.mounted) return;
                        if (await brTapGuarded(context, ref2, b)) return;
                        if (context.mounted) {
                          context.push('/read/reader/${b.id}');
                        }
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          gradient: context.tokens.gradient,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.play_arrow_rounded,
                              size: 15,
                              color: Colors.white,
                            ),
                            SizedBox(width: 6),
                            Text(
                              '开始阅读 · 本地 EPUB',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                  ],
                  for (final n in items) rowFor(n),
                  // 原型 5059 尾行灰钮：查看书籍详情
                  TextButton(
                    key: const ValueKey('lp-detail'),
                    onPressed: () {
                      Navigator.of(sheetCtx).pop();
                      if (context.mounted) context.push('/read/book/${b.id}');
                    },
                    child: Text(
                      '查看书籍详情',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('lp-edit-menu'),
                    onPressed: () {
                      Navigator.of(sheetCtx).pop();
                      // 设置页就地内嵌长按编辑：直达「内容显示与排序」组（sec=1）。
                      if (context.mounted) {
                        context.push('/read/settings?sec=1');
                      }
                    },
                    child: Text(
                      '调整长按菜单',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ),
  );
}

/// 长按菜单「生成/管理全书索引」行文案（原型 js.frag `xrLpLabel` 1:1；
/// live＝本次会话内的实时态，回落任务表态＝跨重启可见）。
String _xrLpLabel(XrayLive? live, XrayTaskRow? t) {
  if (live != null && live.running) return '索引解析中 · ${live.pct}% · 管理';
  if (live != null && live.error != null) return '索引上次失败 · 重试';
  if (t == null) return '生成全书索引';
  return switch (t.status) {
    'running' => '索引解析中 · 管理',
    'pause' => '索引已暂停 · 管理',
    'failed' => '索引上次失败 · 重试',
    'success' => '管理全书索引 · 已解析 ${t.processedCh}/${t.totalCh}',
    _ => '生成全书索引',
  };
}
