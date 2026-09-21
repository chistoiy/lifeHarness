import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../../core/providers.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../domain/note.dart';
import '../journal_providers.dart';

String _snapTimeLabel(int ms) {
  final t = DateTime.fromMillisecondsSinceEpoch(ms);
  final now = DateTime.now();
  final hm = DateFormat('HH:mm').format(t);
  final day = DateTime(t.year, t.month, t.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return '今天 $hm';
  if (diff == 1) return '昨天 $hm';
  return DateFormat('M月d日 HH:mm').format(t);
}

/// 🕘 版本快照弹层（原型 sheetSnapshot · V1.29轮1③）：
/// 恢复方式默认=直接替换当前正文（替换前自动留快照），可在 记录管理 切为新增副本。
Future<void> showSnapshotSheet(BuildContext context, WidgetRef ref, Note? note,
    Color bg, Color fg,
    {String currentBody = '', void Function(String content)? onReplace}) async {
  final snaps = note?.id == null
      ? const <Map<String, Object?>>[]
      : await ref.read(noteDaoProvider).snapshotsOf(note!.id!);
  final mode = ref.read(settingsControllerProvider).noteRestoreMode;
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: bg,
    isScrollControlled: true,
    builder: (bc) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                    color: fg.withValues(alpha: .18),
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Text('🕘 版本快照',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: fg)),
            Padding(
              padding: const EdgeInsets.only(top: 3, bottom: 10),
              child: Text(
                  '停止输入 30 秒 / 每 500 字自动留存 · '
                  '${mode == 'replace' ? '恢复默认直接替换当前正文（替换前自动留快照），恢复方式可在记录管理切换' : '恢复=新增一条副本笔记，当前正文不动'}',
                  style: TextStyle(
                      fontSize: 10.5, color: fg.withValues(alpha: .45))),
            ),
            if (snaps.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Text('暂无快照',
                    style: TextStyle(
                        fontSize: 12, color: fg.withValues(alpha: .5))),
              ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (var i = 0; i < snaps.length; i++)
                    _snapRow(bc, snaps[i], i, bg, fg, note, ref,
                        mode: mode,
                        currentBody: currentBody,
                        onReplace: onReplace),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                key: const ValueKey('snap-close'),
                onPressed: () => Navigator.of(bc).pop(),
                style: TextButton.styleFrom(
                  backgroundColor: fg.withValues(alpha: .06),
                  foregroundColor: fg,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('收起', style: TextStyle(fontSize: 13)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _snapRow(BuildContext bc, Map<String, Object?> row, int i, Color bg,
    Color fg, Note? note, WidgetRef ref,
    {required String mode,
    String currentBody = '',
    void Function(String content)? onReplace}) {
  final content = (row['content'] as String?) ?? '';
  final words = content.replaceAll(RegExp(r'\s'), '').length;
  return Container(
    key: ValueKey('snap-row-$i'),
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
        color: fg.withValues(alpha: .05),
        borderRadius: BorderRadius.circular(14)),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  _snapTimeLabel(row['created_at'] as int? ??
                      DateTime.now().millisecondsSinceEpoch),
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: fg)),
              Text('$words 字',
                  style:
                      TextStyle(fontSize: 10, color: fg.withValues(alpha: .5))),
            ],
          ),
        ),
        TextButton(
          key: ValueKey('snap-prev-$i'),
          onPressed: () => _previewSnapshot(bc, content, bg, fg),
          style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF6366F1),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap),
          child: const Text('预览', style: TextStyle(fontSize: 12)),
        ),
        TextButton(
          key: ValueKey('snap-rest-$i'),
          onPressed: () async {
            final dao = ref.read(noteDaoProvider);
            final now = DateTime.now();
            final t = (note?.title ?? '').trim();
            if (mode == 'replace' && note?.id != null && onReplace != null) {
              // 直接替换当前正文：替换前自动留快照，可反悔。
              await dao.snapshot(note!.id!, currentBody);
              onReplace(content);
              ref.invalidate(notesProvider);
              if (!bc.mounted) return;
              Navigator.of(bc).pop();
              AppToast.show(bc, '已恢复 · 当前正文已替换（替换前已留快照）');
              return;
            }
            await dao.save(Note(
                title: '${t.isEmpty ? '未命名笔记' : t}（副本）',
                content: content,
                kind: note?.kind ?? 'plain',
                folder: note?.folder,
                createdAt: now,
                updatedAt: now));
            ref.invalidate(notesProvider);
            if (!bc.mounted) return;
            Navigator.of(bc).pop();
            AppToast.show(bc, '已恢复为一条副本笔记，当前正文不动');
          },
          style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF6366F1),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap),
          child: const Text('恢复', style: TextStyle(fontSize: 12)),
        ),
      ],
    ),
  );
}

Future<void> _previewSnapshot(
    BuildContext bc, String content, Color bg, Color fg) {
  return showModalBottomSheet<void>(
    context: bc,
    backgroundColor: bg,
    isScrollControlled: true,
    builder: (ic) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('快照预览',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: fg)),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                child: SelectableText(
                  content.trim().isEmpty ? '（空）' : content,
                  key: const ValueKey('snap-preview-text'),
                  style: TextStyle(
                      fontSize: 13, height: 1.9, color: fg),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

String _safeName(String s) {
  final cleaned = s
      .replaceAll(RegExp(r'[<>:"/\\|?*\n\r]'), '')
      .trim()
      .clampLength();
  return cleaned.isEmpty ? '未命名笔记' : cleaned;
}

extension on String {
  String clampLength() => length > 40 ? substring(0, 40) : this;
}

/// ⋯ 弹层（V1.29轮2②： 快照并入此处）：快照 / 复制全文 / 导出 MD / 导出 TXT。
Future<void> showExportSheet(
    BuildContext context, String title, String body, Color bg, Color fg,
    {VoidCallback? onSnap}) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: bg,
    builder: (bc) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
            child: Text('笔记选项',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: fg)),
          ),
          if (onSnap != null)
            ListTile(
              key: const ValueKey('exp-snap'),
              title: Text('🕘 快照 · 版本快照·恢复',
                  style: TextStyle(fontSize: 13.5, color: fg)),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () {
                Navigator.of(bc).pop();
                onSnap();
              },
            ),
          ListTile(
            key: const ValueKey('exp-copy'),
            title: Text('📋 复制全文（TXT）',
                style: TextStyle(fontSize: 13.5, color: fg)),
            onTap: () async {
              await Clipboard.setData(
                  ClipboardData(text: '${title.isEmpty ? '未命名笔记' : title}\n\n$body'));
              if (bc.mounted) Navigator.of(bc).pop();
              if (context.mounted) {
                AppToast.show(context, '已复制全文到剪贴板');
              }
            },
          ),
          ListTile(
            key: const ValueKey('exp-md'),
            title: Text('📄 导出 Markdown 文件',
                style: TextStyle(fontSize: 13.5, color: fg)),
            onTap: () async {
              await _writeExport(context, bc, title, body, 'md');
            },
          ),
          ListTile(
            key: const ValueKey('exp-txt'),
            title: Text('📃 导出 TXT 文件',
                style: TextStyle(fontSize: 13.5, color: fg)),
            onTap: () async {
              await _writeExport(context, bc, title, body, 'txt');
            },
          ),
          const SizedBox(height: 6),
        ],
      ),
    ),
  );
}

Future<void> _writeExport(BuildContext pageCtx, BuildContext bc, String title,
    String body, String ext) async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final out = Directory(p.join(dir.path, 'exports'));
    if (!await out.exists()) await out.create(recursive: true);
    final name =
        '${_safeName(title.isEmpty ? '未命名笔记' : title)}.${DateTime.now().millisecondsSinceEpoch}.$ext';
    final text = ext == 'md'
        ? '${title.isEmpty ? '' : '# $title\n\n'}$body\n'
        : '${_safeName(title)}\n\n$body\n';
    await File(p.join(out.path, name)).writeAsString(text);
    if (bc.mounted) Navigator.of(bc).pop();
    if (pageCtx.mounted) {
      AppToast.show(pageCtx, '已导出 $name');
    }
  } catch (_) {
    if (pageCtx.mounted) AppToast.show(pageCtx, '导出失败 · 请重试');
  }
}
