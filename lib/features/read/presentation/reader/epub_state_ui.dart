import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/database/schema/xray.dart'
    show
        xrayStatusRunning,
        xrayStatusPause,
        xrayStatusFailed,
        xrayStatusSuccess;
import '../../data/epub_cache.dart';
import '../../data/epub_doc.dart';
import '../../domain/book.dart';
import '../../domain/reader_cfg.dart';
import '../read_providers.dart';
import '../read_sheets.dart' show readToast;
import './reader_pager.dart';
import './reader_search_page.dart' show ReaderSearchPage;

/// 批3.5 · 预载/清缓存共享 UI：入口守卫、三态弹层、封面状态覆盖层、
/// 预载启动器。事实源 `prototype/index-bookshelf.html` 批3.5 增量
/// （?br35=pre/frozen/cl/detail/lost 五演示态）。

/// 预载布局基准：与阅读主屏同构（全屏视口 + reader.cfg 外观值·V1.53 起含 font/indent）。
ReaderLayout brPreloadLayout(String? cfgJson, Size vp) {
  final c = ReaderCfg.decode(cfgJson);
  return ReaderLayout(
    width: vp.width,
    height: vp.height,
    fs: c.fs,
    lh: c.lh,
    ls: c.ls,
    mar: c.mar,
    font: c.font,
    indent: c.indent,
  );
}

/// MB 展示（一位小数 · 原型「约释放 N MB」口径）。
String brFmtMb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);

/// 启动整本预载（fire-and-forget）：导入提交 / 重新载入 / 挂回后调用。
void brStartPreload(WidgetRef ref, Book b, BuildContext context) {
  final svc = ref.read(epubPreloadProvider);
  unawaited(
    () async {
      final cfg = await ref.read(readRepositoryProvider).kv('reader.cfg');
      if (!context.mounted) return;
      await svc.preload(b, brPreloadLayout(cfg, MediaQuery.sizeOf(context)));
    }(),
  );
}

/// 本地书入口守卫（原型 shOpen 包装器同语义）。
/// 返回 true＝本次点击已被状态态消化（预载中提示 / 已清缓存分流弹层）。
Future<bool> brTapGuarded(BuildContext context, WidgetRef ref, Book b) async {
  final ep = b.epub;
  if (!b.local || ep == null) return false;
  if (ep.state == EpubRef.stPreload) {
    readToast(context, '正在预载整本书 · 完成后可进入');
    return true;
  }
  if (ep.cleared) {
    final kind = await ref.read(epubCacheServiceProvider).restoreKind(b);
    if (!context.mounted) return true;
    if (kind == EpubRestore.reloadFromSource) {
      await brShowReloadSheet(context, ref, b);
    } else {
      await brShowLostSheet(context, ref, b);
    }
    return true;
  }
  return false;
}

const _sheetShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
);

Widget _sheetTitle(String t, {Color? color}) => Padding(
  padding: const EdgeInsets.only(bottom: 10),
  child: Text(
    t,
    style: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w800,
      color: color,
    ),
  ),
);

/// 清理缓存确认弹层（原型 sheetBrCache：保留/不动/释放 三行 + 约释放 N MB）。
Future<void> brShowCacheSheet(BuildContext context, WidgetRef ref, Book b) async {
  final ep = b.epub;
  if (ep == null) return;
  final svc = ref.read(epubCacheServiceProvider);
  final bytes = await svc.estimateRelease(b);
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    shape: _sheetShape,
    builder: (sc) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sheetTitle('清理缓存 · 《${b.title}》'),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(sc).colorScheme.surfaceContainerHighest.withValues(alpha: .5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      text: '当前本地副本与分页缓存约 ',
                      style: TextStyle(fontSize: 11, color: Theme.of(sc).colorScheme.onSurface),
                      children: [
                        TextSpan(
                          text: '${brFmtMb(bytes)} MB',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${ep.srcPath ?? ep.path} · 源文件保留原位',
                    style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(sc).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            for (final (tag, c, txt) in const [
              ('保留', Color(0xFF10B981), '阅读记录 · 进度与位置 · 外观记忆 · 划线与书摘 · 计时'),
              ('不动', Color(0xFF0EA5E9), '源文件（不删除、不移动原文件本体）'),
              ('释放', Color(0xFFD97706), '本地副本 · 封面衍生图 · 分页缓存'),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tag,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: c,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        txt,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.5,
                          color: Theme.of(sc).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('brCacheCancel'),
                    onPressed: () => Navigator.of(sc).pop(),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    key: const ValueKey('brCacheOk'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFF59E0B),
                    ),
                    onPressed: () async {
                      Navigator.of(sc).pop();
                      // 先释放内存驻留（Windows 下打开的句柄会挡住副本删除）。
                      ref.read(epubPreloadProvider).docs.remove(b.id);
                      await svc.clear(b);
                      ref.read(readTickProvider.notifier).state++;
                      if (context.mounted) {
                        readToast(context, '已释放约 ${brFmtMb(bytes)} MB · 记录与书摘保留 · 源文件未删除');
                      }
                    },
                    child: Text('清理缓存 · 约释放 ${brFmtMb(bytes)} MB'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// 重新载入弹层（原型 sheetBrReload：源文件仍可读 → 重新拷贝 + 预载）。
Future<void> brShowReloadSheet(BuildContext context, WidgetRef ref, Book b) async {
  final ep = b.epub;
  if (ep == null) return;
  await showModalBottomSheet<void>(
    context: context,
    shape: _sheetShape,
    builder: (sc) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sheetTitle('重新载入 · 《${b.title}》'),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(sc).colorScheme.surfaceContainerHighest.withValues(alpha: .5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('源文件仍可读：', style: TextStyle(fontSize: 11)),
                  Text(
                    ep.srcPath ?? ep.path,
                    style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(sc).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '重新拷贝本地副本并预载分页 · 书摘与进度不动',
                    style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(sc).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('brReloadCancel'),
                    onPressed: () => Navigator.of(sc).pop(),
                    child: const Text('稍后'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    key: const ValueKey('brReloadOk'),
                    onPressed: () async {
                      Navigator.of(sc).pop();
                      final svc = ref.read(epubCacheServiceProvider);
                      await svc.recopyFromSource(b);
                      await ref.read(readRepositoryProvider).updateBook(
                        b.copyWith(epub: ep.copyWith(st: EpubRef.stPreload, pr: 0)),
                      );
                      ref.read(readTickProvider.notifier).state++;
                      if (context.mounted) {
                        brStartPreload(ref, b, context);
                        readToast(context, '正在重新拷贝并预载《${b.title}》');
                      }
                    },
                    child: const Text('重新拷贝并预载'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// 源文件丢失弹层（原型 sheetBrLost：引导重选文件 → 合并导入挂回原记录）。
Future<void> brShowLostSheet(BuildContext context, WidgetRef ref, Book b) async {
  final ep = b.epub;
  if (ep == null) return;
  await showModalBottomSheet<void>(
    context: context,
    shape: _sheetShape,
    builder: (sc) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sheetTitle('源文件已不存在 · 《${b.title}》', color: const Color(0xFFD97706)),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(sc).colorScheme.surfaceContainerHighest.withValues(alpha: .5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '原位置：${ep.srcPath ?? '未知'}',
                style: TextStyle(
                  fontSize: 10,
                  height: 1.5,
                  color: Theme.of(sc).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '阅读记录已全部保留。重新选择该书的 EPUB 文件后，本地副本与预载会自动挂回原记录。',
              style: TextStyle(
                fontSize: 10,
                height: 1.5,
                color: Theme.of(sc).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('brLostCancel'),
                    onPressed: () => Navigator.of(sc).pop(),
                    child: const Text('知道了'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    key: const ValueKey('brLostGo'),
                    onPressed: () {
                      Navigator.of(sc).pop();
                      context.push('/read/import-epub?reattach=${b.id}');
                    },
                    child: const Text('重新选择文件'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// 封面状态覆盖层（原型 brCovOvl）：预载中＝渐变底+进度条+百分比；
/// 已清缓存＝暗罩+琥珀 chip。就绪/非本地＝空。调用方以
/// `Positioned.fill(child: BrCoverStateOverlay(book: b))` 挂进封面 Stack。
/// V1.54 批A · F7：右上角另挂 X-Ray 四态小徽标（解析中%/已暂停/已索引/失败·重试），
/// 与整本预载态互不遮蔽（轻抽取档全部不锁阅读）。
class BrCoverStateOverlay extends ConsumerWidget {
  const BrCoverStateOverlay({super.key, required this.book});

  final Book book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ep = book.epub;
    if (!book.local || ep == null) return const SizedBox.shrink();
    final st = ep.state;
    final base = (st != EpubRef.stPreload && !ep.cleared)
        ? null
        : _epubLayer(ref, ep, st);
    final xr = _xrChipText(ref);
    if (base == null && xr == null) return const SizedBox.shrink();
    return Stack(
      children: [
        if (base != null) Positioned.fill(child: base),
        if (xr != null)
          Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Container(
                key: ValueKey('xr-badge-${book.id}'),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: xr.$2,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  xr.$1,
                  style: const TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// X-Ray 角标文案与底色（live 优先＝实时进度；回落库内任务态·跨重启可见）。
  (String, Color)? _xrChipText(WidgetRef ref) {
    ref.watch(xraySchedulerProvider); // 逐章进度刷新驱动
    final live = ref.read(xraySchedulerProvider).live(book.id);
    if (live != null) {
      if (live.running) {
        return ('解析中 ${live.pct}%', const Color(0xCC0F172A));
      }
      if (live.error != null) return ('失败 · 重试', const Color(0xEAF43F5E));
      if (live.doneCh > 0 &&
          live.totalCh > 0 &&
          live.doneCh < live.rangeTo - live.rangeFrom + 1) {
        return ('已暂停 ${live.pct}%', const Color(0xE694A3B8));
      }
    }
    final t = ref.watch(xrayTaskBadgeProvider).valueOrNull?[book.id];
    if (t == null) return null;
    return switch (t.status) {
      xrayStatusRunning => (
          '解析中 ${t.totalCh == 0 ? 0 : (t.processedCh * 100 / t.totalCh).round()}%',
          const Color(0xCC0F172A)
        ),
      xrayStatusPause => (
          '已暂停 ${t.totalCh == 0 ? 0 : (t.processedCh * 100 / t.totalCh).round()}%',
          const Color(0xE694A3B8)
        ),
      xrayStatusFailed => ('失败 · 重试', const Color(0xEAF43F5E)),
      xrayStatusSuccess => ('已索引', const Color(0xEB6366F1)),
      _ => null,
    };
  }

  Widget _epubLayer(WidgetRef ref, EpubRef ep, String st) {
    // 预载进度：内存态优先（实时），回落库内值（跨重启可见）。
    ref.watch(epubPreloadProvider);
    final live = ref.read(epubPreloadProvider).info(book.id)?.pr;
    if (st == EpubRef.stPreload) {
      final pr = (live ?? ep.pr).clamp(0, 100) / 100;
      return ColoredBox(
        key: ValueKey('brCovPre-${book.id}'),
        color: const Color(0xB30F172A),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 54,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: pr,
                    minHeight: 4,
                    backgroundColor: Colors.white24,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '预载中 ${(pr * 100).round()}%',
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return ColoredBox(
      key: ValueKey('brCovCleared-${book.id}'),
      color: const Color(0x800F172A),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xEFD97706),
            borderRadius: BorderRadius.circular(99),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.import_export_outlined, size: 10, color: Colors.white),
              SizedBox(width: 3),
              Text(
                '已清缓存',
                style: TextStyle(
                  fontSize: 8.5,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 本地书状态一句话（详情本地卡副行）。
String brLocalStateLine(Book b) {
  final ep = b.epub;
  if (ep == null) return '—';
  return switch (ep.state) {
    EpubRef.stPreload => '整本预载中 · 完成前不可进入阅读',
    EpubRef.stCleared => File(ep.srcPath ?? '').existsSync()
        ? '本地副本已清理 · 源文件仍可读 · 记录与书摘完整保留'
        : '本地副本已清理 · 原文件已不存在 · 记录与书摘完整保留',
    _ => '就绪 · 点封面秒进',
  };
}

// ---------- 批4 · 删除本地书两口径（原型 sheetBrDel） ----------

/// cache＝仅清除阅读数据（保留源文件与书摘计时）；src＝连同源文件一起删除。
enum BrDelOpt { cache, src }

Future<void> showBrDelSheet(BuildContext context, WidgetRef ref, Book b) async {
  var opt = BrDelOpt.cache;
  await showModalBottomSheet<void>(
    context: context,
    shape: _sheetShape,
    builder: (sc) => StatefulBuilder(
      builder: (_, setSel) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sheetTitle('删除《${b.title}》', color: const Color(0xFFE11D48)),
              const SizedBox(height: 4),
              for (final (k, label, sub) in const [
                (
                  BrDelOpt.cache,
                  '仅清除阅读数据',
                  '进度 · 外观记忆 · 分页缓存清除 · 保留 EPUB 源文件与书摘',
                ),
                (
                  BrDelOpt.src,
                  '连同源文件一起删除',
                  '移除 .epub 文件本体 · 书摘与计时保留',
                ),
              ])
                RadioListTile<BrDelOpt>(
                  key: ValueKey('brDelOpt-${k.name}'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: k,
                  groupValue: opt,
                  title: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  subtitle: Text(
                    sub,
                    style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(sc).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  onChanged: (v) => setSel(() => opt = v!),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 10),
                child: Text(
                  '书摘与计时保留在书架数据中（与「移出书架」同口径）；阅读位置与外观记忆随删除清除。',
                  style: TextStyle(
                    fontSize: 10,
                    height: 1.5,
                    color: Theme.of(sc).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const ValueKey('brDelCancel'),
                      onPressed: () => Navigator.of(sc).pop(),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      key: const ValueKey('brDelOk'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFEF4444),
                      ),
                      onPressed: () {
                        Navigator.of(sc).pop();
                        unawaited(brDelCommit(context, ref, b, opt));
                      },
                      child: const Text('确认删除'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// 执行删除：释放内存句柄与逐书键、回收分页表/私有副本（src 口径再删源文件），
/// 书籍行与书摘/计时保留、local 标记摘除。
Future<void> brDelCommit(
  BuildContext context,
  WidgetRef ref,
  Book b,
  BrDelOpt opt,
) async {
  final ep = b.epub;
  if (ep == null) return;
  final repo = ref.read(readRepositoryProvider);
  final preload = ref.read(epubPreloadProvider);
  preload.docs.remove(b.id); // 释放懒归档句柄（Windows 句柄锁教训）
  if (opt == BrDelOpt.src) {
    try {
      final copy = File(ep.path);
      if (await copy.exists()) await copy.delete();
    } catch (_) {}
    final src = ep.srcPath;
    if (src != null && src.isNotEmpty) {
      var failed = false;
      try {
        final f = File(src);
        if (await f.exists()) await f.delete();
      } catch (_) {
        failed = true;
      }
      if (failed && context.mounted) {
        readToast(context, '源文件被系统保护 · 请在文件管理器手动删除：$src');
      }
    }
  }
  await repo.removeKv('reader.pos.${b.id}');
  await repo.removeKv('reader.cfg.${b.id}');
  await preload.removePag(b.id);
  await preload.removeSnap(b.id);
  await repo.updateBook(b.copyWith(local: false, clearEpub: true));
  ref.read(readTickProvider.notifier).state++;
  if (context.mounted) {
    readToast(
      context,
      '《${b.title}》${opt == BrDelOpt.src ? '源文件已删除' : '仅清除阅读数据 · 源文件保留'} · 书摘与计时保留',
    );
  }
}

/// 详情本地卡「全书检索」：预载缓存/懒归档取档后进检索页（与阅读器顶栏同页）。
Future<void> brOpenBookSearch(
  BuildContext context,
  WidgetRef ref,
  Book b,
) async {
  final ep = b.epub;
  if (ep == null) return;
  EpubDoc doc;
  final cached = ref.read(epubPreloadProvider).docs.get(b.id);
  if (cached != null) {
    doc = cached;
  } else {
    try {
      doc = await ref.read(epubDocLoaderProvider)(ep.path);
    } catch (_) {
      if (context.mounted) {
        readToast(context, '文件无法读取 · 可点封面走重新载入');
      }
      return;
    }
  }
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ReaderSearchPage(doc: doc, title: b.title),
    ),
  );
  // 临时打开的档（不在预载缓存里）用完即释放句柄。
  if (ref.read(epubPreloadProvider).docs.get(b.id) == null) {
    doc.lazy?.dispose();
  }
}
