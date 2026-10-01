# tools/attic/xr_batchC_wire.py — 批C 接线：provider / 设置行 / 备份半屏 / 复用提示
import io

CRLF = chr(13) + chr(10)


def patch(p, pairs):
    s = io.open(p, encoding='utf-8', newline='').read()
    crlf = CRLF in s

    def n(x):
        return x.replace(chr(10), CRLF) if crlf else x

    for a, b in pairs:
        a, b = n(a), n(b)
        assert s.count(a) == 1, (p, a[:40].encode('unicode_escape'), s.count(a))
        s = s.replace(a, b)
    io.open(p, 'w', encoding='utf-8', newline='').write(s)


# 1) providers
patch('lib/features/read/presentation/read_providers.dart', [
    ("""import '../data/xray/xray_dao.dart';
import '../data/xray/xray_scheduler.dart';""",
     """import '../data/xray/xray_backup.dart';
import '../data/xray/xray_dao.dart';
import '../data/xray/xray_scheduler.dart';"""),
    ("""/// 某架位的内容指纹（懒补算不在这里做——被动渲染只读库，起解析动作才 ensureMd5）。""",
     """/// 单书索引备份服务（F10 · .xraybak 导出/导入；测试 override 注钩子）。
final xrayBackupServiceProvider = Provider<XrayBackupService>(
  (ref) => XrayBackupService(ref.watch(xrayDaoProvider)),
);

/// 某架位的内容指纹（懒补算不在这里做——被动渲染只读库，起解析动作才 ensureMd5）。"""),
])

# 2) 设置行 + go2 分支 + import
patch('lib/features/read/presentation/read_settings_page.dart', [
    ("""    _Row('exportMd', '导出全部书摘', _T.go2, desc: 'Markdown · 按书分组'),""",
     """    // V1.54 批C（屏6 · sheets.frag sheetXrBak）：单书 .xraybak 供跨设备与分享。
    _Row('xrBak', 'X-Ray 索引备份', _T.go2,
        desc: '导出 .xraybak / 从备份导入 · MD5 校验 · 整包备份已含索引数据'),
    _Row('exportMd', '导出全部书摘', _T.go2, desc: 'Markdown · 按书分组'),"""),
    ("""  Future<void> _export(String key) async {
    // 轮5：真机「点了没反应」——点击即回反馈，异常也要说出来。
    readToast(context, '导出中…');""",
     """  Future<void> _export(String key) async {
    if (key == 'xrBak') {
      showXrBakSheet(context, ref);
      return;
    }
    // 轮5：真机「点了没反应」——点击即回反馈，异常也要说出来。
    readToast(context, '导出中…');"""),
])

# 3) 复用提示（两处 commit 调用点）
patch('lib/features/read/presentation/import/local_import_page.dart', [
    ("""    if (!mounted) return;
    ref.read(readTickProvider.notifier).state++;
    // 批3.5：落库即后台整本预载（完成前封面显进度、不可点进）。
    brStartPreload(ref, b, context);
    readToast(
      context,
      _dup != null
          ? '《${b.title}》已${_reattach != null ? '重新挂回 · 正在预载' : '附本地文件 · 正在预载'}'
          : '《${b.title}》已加入书架 · 正在后台预载整本 · 源文件保留原位',
    );""",
     """    if (!mounted) return;
    ref.read(readTickProvider.notifier).state++;
    // 批3.5：落库即后台整本预载（完成前封面显进度、不可点进）。
    brStartPreload(ref, b, context);
    readToast(
      context,
      _dup != null
          ? '《${b.title}》已${_reattach != null ? '重新挂回 · 正在预载' : '附本地文件 · 正在预载'}'
          : '《${b.title}》已加入书架 · 正在后台预载整本 · 源文件保留原位',
    );
    // V1.54 批C F9：同内容指纹已有解析 → 索引整体复用（含用户整理结果）。
    if (svc.lastReuseHits.isNotEmpty && mounted) {
      readToast(context, '检测到同文件书籍 · 全书索引已直接复用');
    }"""),
])

# 4) open_with 复用提示
patch('lib/features/read/presentation/open_with.dart', [
    ("""  brStartPreload(ref, book, context);
  readToast(context, '《${book.title}》已加入书架 · 正在后台预载整本');""",
     """  brStartPreload(ref, book, context);
  readToast(context, '《${book.title}》已加入书架 · 正在后台预载整本');
  // V1.54 批C F9：同文件指纹命中 → X-Ray 索引直接复用（含用户整理结果）。
  if (svc.lastReuseHits.isNotEmpty && context.mounted) {
    readToast(context, '检测到同文件书籍 · 全书索引已直接复用');
  }"""),
])

# 5) import service: lastReuseHits 字段 + _stampMd5 记录
patch('lib/features/read/data/epub_import.dart', [
    ("""  /// 测试注入：替换文件指纹计算（FakeAsync 禁真 IO）。
  final Future<String> Function(String path)? md5Hook;""",
     """  /// 测试注入：替换文件指纹计算（FakeAsync 禁真 IO）。
  final Future<String> Function(String path)? md5Hook;

  /// F9 复用提示：最近一次 commit 命中的同指纹其它架位（该指纹已有解析任务才非空）。
  List<String> lastReuseHits = const [];"""),
    ("""  Future<void> _stampMd5(String bookId, String copyPath) async {
    final dao = xray;
    if (dao == null) return;
    try {
      final m = await (md5Hook ?? xrayFileMd5)(copyPath);
      await dao.setBookMd5(bookId, m);
    } catch (_) {}
  }""",
     """  Future<void> _stampMd5(String bookId, String copyPath) async {
    final dao = xray;
    if (dao == null) return;
    lastReuseHits = const [];
    try {
      final m = await (md5Hook ?? xrayFileMd5)(copyPath);
      await dao.setBookMd5(bookId, m);
      // 已有解析任务的同指纹架位＝索引直接复用（F9 路径 A，UI 拿字段发提示）。
      if (await dao.task(m) != null) {
        lastReuseHits = await dao.bookIdsWithMd5(m, exceptBookId: bookId);
      }
    } catch (_) {}
  }"""),
])
print('wire ok')
