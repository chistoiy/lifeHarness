// V1.53.4⑥ 系统「打开方式」接收本地 EPUB → 导入/定位（原型 sheetBrOpen 两态·
// index-bookshelf.html ?br57=open|dup 已放行，文案与形态按原型钉死）。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../../core/theme/app_theme.dart';
import '../data/epub_doc.dart';
import '../data/epub_import.dart';
import '../domain/book.dart';
import 'read_providers.dart';
import 'read_sheets.dart' show readToast;
import 'reader/epub_state_ui.dart' show brStartPreload;

/// 原生侧暂存意图通道（MainActivity.kt 同约定）：
/// takeEpubUri 单次消费——null=无待处理文件；''=收到非 EPUB（toast「只支持 EPUB」）；
/// 其余=已拷入 cacheDir/lh_open/ 的绝对路径。通道缺失（测试/桌面）按无处理返回。
const _intentsChannel = MethodChannel('lh/intents');

Future<String?> takeEpubUri() async {
  try {
    return await _intentsChannel.invokeMethod<String>('takeEpubUri');
  } catch (_) {
    return null;
  }
}

/// 书架待定位书 id（「前往书架定位」/导入成功后置位，ShelfPage 消费后清空）。
final locateBookProvider = StateProvider<String?>((_) => null);

/// 文件大小读取位：widget 测试替换，避免 FakeAsync 下真磁盘 IO 挂死
/// （既有踩坑：测禁真异步 I/O）。
Future<int> Function(String path) brOpenFileSize = (path) => File(path).length();

/// 根壳层每次「首帧后 / resumed」调用一次：取值→两态弹层→导入或定位。
Future<void> brOpenConsumeOnce(BuildContext context, WidgetRef ref) async {
  final v = await takeEpubUri();
  if (v == null) return;
  if (v.isEmpty) {
    if (context.mounted) readToast(context, '只支持 EPUB');
    return;
  }
  if (context.mounted) await handleOpenWithEpub(context, ref, v);
}

Future<void> handleOpenWithEpub(
  BuildContext context,
  WidgetRef ref,
  String path,
) async {
  final name = p.basename(path);
  int size = 0;
  try {
    size = await brOpenFileSize(path);
  } catch (_) {}
  final pick = EpubPick(name: name, size: size, path: path);
  EpubDoc doc;
  try {
    doc = await ref.read(epubDocLoaderProvider)(path);
  } on EpubFormatException catch (e) {
    if (context.mounted) readToast(context, e.reason);
    return;
  } catch (_) {
    if (context.mounted) readToast(context, '文件无法读取');
    return;
  }
  final svc = ref.read(epubImportServiceProvider);
  Book? dup;
  try {
    dup = await svc.findDup(doc);
  } catch (_) {
    dup = null;
  }
  if (!context.mounted) {
    doc.lazy?.dispose();
    return;
  }
  if (dup != null) {
    // 已入库：不再引入第二份记录（口径同向导 findDup 判重），只提醒+定位。
    doc.lazy?.dispose();
    final go = await _brShowDupSheet(context, dup: dup, fileName: name);
    if (go && context.mounted) _brGoShelf(context, ref, dup.id);
    return;
  }
  final go = await _brShowImportSheet(context, doc: doc, fileName: name, size: size);
  if (!go) {
    doc.lazy?.dispose();
    return;
  }
  final book = await svc.commit(
    pick: pick,
    doc: doc,
    draft: EpubMetaDraft.from(doc),
  );
  doc.lazy?.dispose();
  if (!context.mounted) return;
  ref.read(readTickProvider.notifier).state++;
  brStartPreload(ref, book, context);
  readToast(context, '《${book.title}》已加入书架 · 正在后台预载整本');
  // V1.54 批C F9：同文件指纹命中 → X-Ray 索引直接复用（含用户整理结果）。
  if (svc.lastReuseHits.isNotEmpty && context.mounted) {
    readToast(context, '检测到同文件书籍 · 全书索引已直接复用');
  }
  _brGoShelf(context, ref, book.id);
}

void _brGoShelf(BuildContext context, WidgetRef ref, String bookId) {
  ref.read(locateBookProvider.notifier).state = bookId;
  // R6：/read/shelf 是栈路由，push 保栈（go 清栈会致返回键直接退 app）。
  context.push('/read/shelf');
}

String _brSizeLabel(int bytes) => bytes <= 0
    ? '—'
    : bytes >= 1024 * 1024
    ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB'
    : '${(bytes / 1024).ceil()} KB';

String _brDash(String v) => v.trim().isEmpty ? '佚名' : v;

// ---------------- 两态弹层（原型 brOpenEpub 模板逐行对齐） ----------------

Future<bool> _brShowDupSheet(
  BuildContext context, {
  required Book dup,
  required String fileName,
}) async {
  final line =
      '${_brDash(dup.title)}（${_brDash(dup.author)}）· ${dup.state}'
      '${dup.isReading ? ' ${dup.percent}%' : ''}';
  return (await _brSheet(
        context,
        title: '这本书已在书架',
        infoMain: line,
        infoSub: '来自文件：$fileName',
        primaryLabel: '前往书架定位',
        footnote: '同一本书不再重复入库 · 书摘与进度沿用书架记录',
      )) ==
      true;
}

Future<bool> _brShowImportSheet(
  BuildContext context, {
  required EpubDoc doc,
  required String fileName,
  required int size,
}) async {
  return (await _brSheet(
        context,
        title: '导入这本书？',
        infoMain:
            '${_brDash(doc.title)}（${_brDash(doc.author)}）· ${_brSizeLabel(size)}',
        infoSub: '$fileName · 元数据从 EPUB 自动读取',
        primaryLabel: '加入书架 · 预载',
        footnote: '导入后可在核对页修改书名与作者 · 源文件保留原位',
      )) ==
      true;
}

Future<bool?> _brSheet(
  BuildContext context, {
  required String title,
  required String infoMain,
  required String infoSub,
  required String primaryLabel,
  required String footnote,
}) =>
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight:
            MediaQuery.of(context).size.height -
            MediaQuery.of(context).padding.top -
            24,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        final cs = Theme.of(sheetCtx).colorScheme;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: SafeArea(
            child: Column(
              key: ValueKey('br-open-sheet-$title'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                    Text(
                      '打开方式',
                      style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  key: const ValueKey('br-open-info'),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        infoMain,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        infoSub,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _brBtn(
                        key: 'br-open-cancel',
                        label: '取消',
                        onTap: () => Navigator.of(sheetCtx).pop(false),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _brBtn(
                        key: 'br-open-confirm',
                        label: primaryLabel,
                        gradient: true,
                        onTap: () => Navigator.of(sheetCtx).pop(true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Center(
                  child: Text(
                    footnote,
                    style: TextStyle(
                      fontSize: 9,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

Widget _brBtn({
  required String key,
  required String label,
  required VoidCallback onTap,
  bool gradient = false,
}) {
  return Builder(
    builder: (context) {
      final cs = Theme.of(context).colorScheme;
      final tokens = context.tokens;
      return GestureDetector(
        key: ValueKey(key),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: gradient ? tokens.gradient : null,
            color: gradient ? null : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: gradient
                ? null
                : Border.all(color: cs.outlineVariant.withValues(alpha: .6)),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: gradient ? Colors.white : cs.onSurface,
            ),
          ),
        ),
      );
    },
  );
}
