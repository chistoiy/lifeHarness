// 一次性脚本：showSessionsSheet 入口改跳 /read/log/:id（真机验收轮1e）。用完即删。
const fs = require('fs');
function rep(p, pairs) {
  let s = fs.readFileSync(p, 'utf8');
  for (const [a, b] of pairs) {
    const n = s.split(a).length - 1;
    if (n !== 1) {
      console.error('FAIL', p, JSON.stringify(a.slice(0, 60)), 'hits=' + n);
      process.exit(1);
    }
    s = s.replace(a, () => b);
  }
  fs.writeFileSync(p, s);
  console.log('OK', p);
}
rep('lib/features/read/presentation/book_detail.dart', [
  [
    `                                            () => showSessionsSheet(
                                              context,
                                              ref,
                                              b,
                                            ),`,
    `                                            () => context.push(
                                              '/read/log/\${b.id}',
                                            ),`,
  ],
]);
rep('lib/features/read/presentation/book_info_page.dart', [
  [
    `                () => showSessionsSheet(context, ref, b),
              ),
              const SizedBox(width: 8),
              _dataCard(
                context,
                'bi-times',`,
    `                () => context.push('/read/log/\${b.id}'),
              ),
              const SizedBox(width: 8),
              _dataCard(
                context,
                'bi-times',`,
  ],
  [
    `                () => showSessionsSheet(context, ref, b),
              ),
              const SizedBox(width: 8),
              _dataCard(context, null, '分钟/页'`,
    `                () => context.push('/read/log/\${b.id}'),
              ),
              const SizedBox(width: 8),
              _dataCard(context, null, '分钟/页'`,
  ],
  [
    `                      key: const ValueKey('trk-detail'),
                      onTap: () => showSessionsSheet(context, ref, b),`,
    `                      key: const ValueKey('trk-detail'),
                      onTap: () => context.push('/read/log/\${b.id}'),`,
  ],
]);
rep('lib/features/read/presentation/read_sheets.dart', [
  [
    `                onPressed: () {
                  Navigator.of(sheetCtx).pop();
                  showSessionsSheet(context, ref, b);
                },
                icon: const Icon(BsIcons.time, size: 17),
                label: const Text('计时明细'),`,
    `                onPressed: () {
                  Navigator.of(sheetCtx).pop();
                  // 真机验收轮1e：计时明细半屏层改全屏阅读记录页。
                  GoRouter.of(context).push('/read/log/\${b.id}');
                },
                icon: const Icon(BsIcons.time, size: 17),
                label: const Text('计时明细'),`,
  ],
]);
