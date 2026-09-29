import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../../core/logging/app_log.dart';
import '../../../../core/providers.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../domain/note.dart';
import '../journal_providers.dart';
import '../note_paper.dart';

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

/// ⋯ 笔记选项弹层（V1.29轮9h/9j/9m/9n/9p/9q/9t 汇总 · 原型 sheetNoteKit）：
/// 标题「笔记选项」+统计+分享钮 / 类型三 chip / 字号 / 纸色一体行（预置4点+色条+名）/
/// 聚焦开关 / 行号开关（仅纯文本）/ 文件夹 / 快照。配色跟随当前纸色（9m）。
Future<void> showNoteKitSheet(
  BuildContext context,
  WidgetRef ref, {
  required String kind,
  required double font,
  required String paper,
  required bool focusOn,
  required String folder,
  required String countText,
  required void Function(String kind) onKind,
  required void Function(double font) onFont,
  required void Function(String paper) onPaper,
  required VoidCallback onFocus,
  required void Function(String folder) onFolder,
  required VoidCallback onSnap,
  required VoidCallback onShare,
}) async {
  var sKind = kind;
  var sFont = font;
  var sPaper = paper;
  var sFocus = focusOn;
  var sFolder = folder;
  var sLn = ref.read(settingsControllerProvider).notePlainLineNum;
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (bc) => StatefulBuilder(
      builder: (bc, setSheet) {
        final bg = paperBg(sPaper);
        final fg = paperFg(sPaper);
        Widget row(String label, List<Widget> children,
                {Key? key, VoidCallback? onTap}) =>
            GestureDetector(
              key: key,
              onTap: onTap,
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border:
                      Border.all(color: fg.withValues(alpha: .18)),
                ),
                child: Row(
                  children: [
                    SizedBox(
                        width: 44,
                        child: Text(label,
                            style: TextStyle(
                                fontSize: 12, color: fg.withValues(alpha: .5)))),
                    ...children,
                  ],
                ),
              ),
            );
        Widget chip(String k, String text) {
          final on = sKind == k;
          return GestureDetector(
            key: ValueKey('kit-kind-$k'),
            onTap: () {
              setSheet(() => sKind = k);
              onKind(k);
            },
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: on ? fg.withValues(alpha: .12) : Colors.transparent,
                border: Border.all(
                    color: on ? fg.withValues(alpha: .5) : fg.withValues(alpha: .2)),
              ),
              child: Text(text,
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: on ? FontWeight.w900 : FontWeight.w500,
                      color: on ? fg : fg.withValues(alpha: .6))),
            ),
          );
        }

        return SafeArea(
          child: Container(
            decoration: BoxDecoration(
              color: bg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
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
                // 轮9q：标题去「⋯」前缀 · 统计信息上移至标题右侧；轮9r：分享钮进标题行。
                // 轮10-7：统计+分享贴右缘——统计必须是**非 flex** 子件：
                // Flexible(flex:1) 会与 Expanded 标题平分剩余空间，把钮停在中间。
                Row(
                  children: [
                    Expanded(
                      child: Text('笔记选项',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              color: fg)),
                    ),
                    Text(countText,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11, color: fg.withValues(alpha: .6))),
                    const SizedBox(width: 4),
                    IconButton(
                      key: const ValueKey('kit-share'),
                      tooltip: '分享 / 导出',
                      onPressed: () {
                        Navigator.of(bc).pop();
                        onShare();
                      },
                      visualDensity: VisualDensity.compact,
                      style: IconButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(32, 32)),
                      icon: Icon(Icons.ios_share, size: 19, color: fg),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        // 类型（轮9j 去 emoji · 原型顺序 富文本/纯文本/MD 文档）
                        row('类型', [
                          chip('rich', '富文本'),
                          const SizedBox(width: 6),
                          chip('plain', '纯文本'),
                          const SizedBox(width: 6),
                          chip('md', 'MD 文档'),
                        ]),
                        row('字号', [
                          Expanded(
                            child: Slider(
                              key: const ValueKey('kit-font'),
                              value: sFont,
                              min: 13,
                              max: 19,
                              divisions: 6,
                              activeColor: const Color(0xFF6366F1),
                              inactiveColor: fg.withValues(alpha: .2),
                              onChanged: (v) {
                                setSheet(() => sFont = v);
                                onFont(v);
                              },
                            ),
                          ),
                          SizedBox(
                            width: 44,
                            child: Text('${sFont.round()} px',
                                key: const ValueKey('kit-font-label'),
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: fg.withValues(alpha: .55))),
                          ),
                        ]),
                        // 纸色一体行（轮9n：预置4点+色条+当前名 · 按笔记独立生效）
                        row('纸色', [
                          for (var i = 0; i < notePapers.length; i++)
                            GestureDetector(
                              key: ValueKey('kit-paper-$i'),
                              onTap: () {
                                setSheet(() => sPaper = 'p$i');
                                onPaper('p$i');
                              },
                              child: Container(
                                width: 20,
                                height: 20,
                                margin: const EdgeInsets.only(right: 6),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: notePapers[i].$1,
                                  border: Border.all(
                                      color: sPaper == 'p$i'
                                          ? const Color(0xFF6366F1)
                                          : fg.withValues(alpha: .3),
                                      width: 1.5),
                                ),
                              ),
                            ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: _HueBar(
                              key: const ValueKey('kit-hue'),
                              fg: fg,
                              hue: paperHue(sPaper),
                              custom: sPaper.startsWith('h'),
                              onHue: (h) {
                                final v = 'h${h.round()}';
                                setSheet(() => sPaper = v);
                                onPaper(v);
                              },
                            ),
                          ),
                          const SizedBox(width: 6),
                          SizedBox(
                            width: 40,
                            child: Text(paperName(sPaper),
                                key: const ValueKey('kit-paper-name'),
                                textAlign: TextAlign.right,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 10.5,
                                    color: fg.withValues(alpha: .55))),
                          ),
                        ]),
                        // 聚焦（轮9j补正2：纸面默认开·开关在此·ml-auto 靠右）
                        row('聚焦', [
                          const Spacer(),
                          Switch(
                            key: const ValueKey('kit-focus'),
                            value: sFocus,
                            activeThumbColor: const Color(0xFF6366F1),
                            onChanged: (v) {
                              setSheet(() => sFocus = v);
                              onFocus();
                            },
                          ),
                        ]),
                        // 行号（轮9p：仅纯文本显示本行·默认关·持久化设置位）
                        if (sKind == 'plain')
                          row('行号', [
                            const Spacer(),
                            Switch(
                              key: const ValueKey('kit-ln'),
                              value: sLn,
                              activeThumbColor: const Color(0xFF6366F1),
                              onChanged: (v) async {
                                setSheet(() => sLn = v);
                                await ref
                                    .read(settingsControllerProvider.notifier)
                                    .setNotePlainLineNum(v);
                                if (bc.mounted) {
                                  AppToast.show(bc, v ? '已显示行号' : '已隐藏行号');
                                }
                              },
                            ),
                          ]),
                        // 文件夹（轮9t：分类改口文件夹·未归属=未归类）
                        row('文件夹', [
                          Expanded(
                            child: Text(
                                sFolder.isEmpty
                                    ? '未归类'
                                    : sFolder.split('/').last,
                                textAlign: TextAlign.right,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: fg)),
                          ),
                          Text(' ▾',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: fg.withValues(alpha: .5))),
                        ],
                            key: const ValueKey('kit-folder'),
                            onTap: () async {
                              // 轮10-5：选项=外部文件夹树（note_folders·含空夹），
                              // 而非仅「已有笔记的文件夹」；当前值兜底并入防旧值消失。
                              final tree = await ref
                                  .read(noteFolderListProvider.future);
                              if (!bc.mounted) return;
                              final names = <String>{
                                ...tree.map((f) => f.name),
                                if (sFolder.isNotEmpty) sFolder,
                              };
                              final picked = await showModalBottomSheet<String>(
                                context: bc,
                                backgroundColor: bg,
                                builder: (fc) => SafeArea(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      for (final f in ['未归类', ...names])
                                        ListTile(
                                          key: ValueKey(
                                              'kit-folder-opt-${f == '未归类' ? '' : f}'),
                                          trailing: (f == '未归类'
                                                  ? ''
                                                  : f) ==
                                                  sFolder
                                              ? Icon(Icons.check,
                                                  size: 18, color: fg)
                                              : null,
                                          title: Text(f,
                                              style: TextStyle(
                                                  fontSize: 13.5, color: fg)),
                                          onTap: () => Navigator.of(fc)
                                              .pop(f == '未归类' ? '' : f),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                              if (picked == null || !bc.mounted) return;
                              setSheet(() => sFolder = picked);
                              onFolder(picked);
                            }),
                        // 快照（轮2② 并入此处）
                        row('快照', [
                          Expanded(
                            child: Text('版本快照 · 恢复 ›',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: fg.withValues(alpha: .55))),
                          ),
                        ],
                            key: const ValueKey('kit-snap'),
                            onTap: () {
                              Navigator.of(bc).pop();
                              onSnap();
                            }),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    key: const ValueKey('kit-close'),
                    onPressed: () => Navigator.of(bc).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: fg,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: BorderSide(color: fg.withValues(alpha: .22)),
                      shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.all(Radius.circular(14))),
                    ),
                    child: const Text('收起', style: TextStyle(fontSize: 13)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// 色条（原型 #pwHue 渐变滑条）：点/拖取色相 → hsl(h,60%,88%) 自定义纸色。
class _HueBar extends StatelessWidget {
  const _HueBar(
      {super.key,
      required this.fg,
      required this.hue,
      required this.custom,
      required this.onHue});

  final Color fg;
  final double hue;
  final bool custom;
  final ValueChanged<double> onHue;

  static const _stops = <Color>[
    Color(0xFFF2C6C6), Color(0xFFF2E7C6), Color(0xFFD4F2C6), Color(0xFFC6F2E3),
    Color(0xFFC6D8F2), Color(0xFFE3C6F2), Color(0xFFF2C6C6),
  ];

  void _emit(double dx, double w) => onHue((dx / w).clamp(0, 1) * 359);

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (bc, box) {
        return GestureDetector(
          onTapDown: (e) => _emit(e.localPosition.dx, box.maxWidth),
          onHorizontalDragUpdate: (e) =>
              _emit(e.localPosition.dx.clamp(0, box.maxWidth), box.maxWidth),
          onHorizontalDragStart: (e) =>
              _emit(e.localPosition.dx.clamp(0, box.maxWidth), box.maxWidth),
          child: Container(
            height: 26,
            alignment: Alignment.center,
            child: Container(
              height: 14,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                gradient: const LinearGradient(colors: _stops),
                border: Border.all(color: fg.withValues(alpha: .15)),
              ),
              child: custom
                  ? Align(
                      alignment: Alignment((hue / 359) * 2 - 1, 0),
                      child: Container(
                        width: 16,
                        height: 16,
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: HSLColor.fromAHSL(1, hue, .6, .88).toColor(),
                          border: Border.all(
                              color: const Color(0xFF6366F1), width: 2),
                        ),
                      ),
                    )
                  : null,
            ),
          ),
        );
      });
}

/// 分享弹层（V1.29轮9r · 原型 sheetNoteShare）：导出 TXT/Markdown · 复制全文 ·
/// 以图片形式分享（生成 PNG 卡片存 exports；系统分享面板规划 V1.x）。
Future<void> showNoteShareSheet(
    BuildContext context, String title, String body, Color bg, Color fg) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: bg,
    builder: (bc) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 轮10-8：与笔记选项同款 grabber+标题头（弹层语言统一）。
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              decoration: BoxDecoration(
                  color: fg.withValues(alpha: .18),
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
            child: Text('分享',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w900, color: fg)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                for (final (k, label) in const [
                  ('share-txt', '导出 TXT'),
                  ('share-md', '导出 Markdown'),
                ])
                  _shareRow(bc, context, k, label, fg, () async {
                    await _writeExport(context, bc, title, body,
                        k == 'share-md' ? 'md' : 'txt');
                  }),
                _shareRow(bc, context, 'share-copy', '复制全文', fg, () async {
                  await Clipboard.setData(ClipboardData(
                      text: '${title.isEmpty ? '未命名笔记' : title}\n\n$body'));
                  if (bc.mounted) Navigator.of(bc).pop();
                  if (context.mounted) {
                    AppToast.show(context, '已复制全文到剪贴板');
                  }
                }),
                _shareRow(bc, context, 'share-img', '以图片形式分享', fg, () async {
                  if (bc.mounted) Navigator.of(bc).pop();
                  await _shareAsImage(context, title, body);
                }),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SizedBox(
              width: double.infinity,
              child: TextButton(
                key: const ValueKey('share-close'),
                onPressed: () => Navigator.of(bc).pop(),
                style: TextButton.styleFrom(
                  foregroundColor: fg,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: BorderSide(color: fg.withValues(alpha: .22)),
                  shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(Radius.circular(14))),
                ),
                child: const Text('取消', style: TextStyle(fontSize: 13)),
              ),
            ),
          ),
          const SizedBox(height: 6),
        ],
      ),
    ),
  );
}

Widget _shareRow(BuildContext bc, BuildContext pageCtx, String key, String label,
    Color fg, VoidCallback onTap) {
  return GestureDetector(
    key: ValueKey(key),
    onTap: onTap,
    child: Container(
      // 轮10-8：整行条目=与笔记选项同语言（全宽卡·名称左 · ›右）。
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: fg.withValues(alpha: .18))),
      child: Row(
        children: [
          Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: fg))),
          Text('›',
              style:
                  TextStyle(fontSize: 14, color: fg.withValues(alpha: .4))),
        ],
      ),
    ),
  );
}

/// 以图片形式分享：离屏绘制纸面风笔记卡 → PNG 落 exports 目录。
/// 系统分享面板需 share_plus（本机网络受限未引），规划 V1.x。
Future<void> _shareAsImage(BuildContext context, String title, String body) async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final out = Directory(p.join(dir.path, 'exports'));
    if (!await out.exists()) await out.create(recursive: true);
    final name =
        '${_safeName(title.isEmpty ? '未命名笔记' : title)}.${DateTime.now().millisecondsSinceEpoch}.png';
    final file = File(p.join(out.path, name));
    await file.writeAsBytes(await _noteCardPng(title, body));
    if (context.mounted) {
      AppToast.show(context, '已生成笔记图片卡片 · 存至 exports（系统分享面板规划 V1.x）');
    }
  } catch (err) {
    AppLog.add('笔记图片卡片生成失败：$err', level: LhLevel.error);
    if (context.mounted) AppToast.show(context, '生成图片失败 · 请重试');
  }
}

const _cardW = 720.0;
const _cardBg = Color(0xFFFBF8F1);
const _cardFg = Color(0xFF403A31);

Future<Uint8List> _noteCardPng(String title, String body) async {
  const pad = 48.0;
  final textW = _cardW - pad * 2;
  final t = title.trim();
  final titlePainter = _cardPainter(t.isEmpty ? '未命名笔记' : t,
      size: 40, weight: FontWeight.w900, width: textW);
  var bodyText = body.trim();
  // 卡片最多约 22 行正文，超出截断加省略号。
  bodyText = bodyText.length > 900 ? '${bodyText.substring(0, 900)}…' : bodyText;
  if (bodyText.isEmpty) bodyText = '（空白笔记）';
  var bodyPainter = _cardPainter(bodyText, size: 28, width: textW);
  const maxBodyH = 1400.0;
  if (bodyPainter.height > maxBodyH) {
    var end = bodyText.length;
    while (end > 20) {
      end -= (end / 10).ceil();
      bodyPainter =
          _cardPainter('${bodyText.substring(0, end)}…', size: 28, width: textW);
      if (bodyPainter.height <= maxBodyH) break;
    }
  }
  final h = (pad + titlePainter.height + 24 + bodyPainter.height + pad)
      .ceilToDouble();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..drawRect(Rect.fromLTWH(0, 0, _cardW, h), Paint()..color = _cardBg);
  titlePainter.paint(canvas, Offset(pad, pad));
  bodyPainter
      .paint(canvas, Offset(pad, pad + titlePainter.height + 24));
  final img = await recorder.endRecording().toImage(_cardW.ceil(), h.ceil());
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  return data!.buffer.asUint8List();
}

TextPainter _cardPainter(String text,
    {required double size,
    FontWeight weight = FontWeight.w500,
    required double width}) {
  final tp = TextPainter(
    text: TextSpan(
        text: text,
        style: TextStyle(
            color: _cardFg, fontSize: size, height: 1.8, fontWeight: weight)),
    // package:path 同名导出 TextDirection，显式取 dart:ui 版。
    textDirection: ui.TextDirection.ltr,
  )..layout(maxWidth: width);
  return tp;
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
  } catch (err) {
    AppLog.add('笔记导出失败（$ext）：$err', level: LhLevel.error);
    if (pageCtx.mounted) AppToast.show(pageCtx, '导出失败 · 请重试');
  }
}
