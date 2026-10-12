/// 导出弹层（原型 `sheetMm-export`）与执行体（批2 F4-5 ＋ 批5 解禁 `.xmind`）。
///
/// 格式五枚原型形态保留：HTML/md/opml/png 可选，`.xmind` **批5 起解禁**
///（**只出不进**，不提供导入）。两开关＝正文（**默认关**，§4.10 隐私硬口径·
/// 变异刀1 钉点）＋横向预设（落法 C，仅 HTML 生效；PNG 与 `.xmind` 时两开关
/// 处置灰——前者是像素、后者只带结构与批5 三段）。
///
/// 执行通道：md/opml/HTML/xmind 写临时文件 → `safSaveAs` 系统另存（零新增原生
/// 通道）；PNG 由画布页离屏绘制快照注入（`pngSnapshot`），本文件不碰画布细节。
library;

import 'dart:io';
import 'dart:ui' as ui show Canvas, PictureRecorder;
import 'dart:math' as math;
import 'dart:typed_data';


import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/logging/app_log.dart';
import '../../../core/platform/saf.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../domain/mindmap_export.dart';
import '../domain/mindmap_layout.dart';
import '../domain/mindmap_layout_preset.dart';
import '../domain/mindmap_measure.dart';
import '../../../shared/export/png_encode.dart';
import '../domain/mindmap_models.dart';
import '../domain/mindmap_style.dart';
import 'mindmap_painter.dart';

/// 导出选项（弹层返回值）。
class MmExportChoice {
  const MmExportChoice({
    required this.format,
    required this.includeBody,
    required this.landscape,
  });

  final String format; // 'html' | 'md' | 'opml' | 'png'
  final bool includeBody;
  final bool landscape;
}

/// 导出弹层。返回 null＝取消。
Future<MmExportChoice?> showMmExportSheet(BuildContext context) {
  return showModalBottomSheet<MmExportChoice>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (bc) => const _MmExportSheet(),
  );
}

class _MmExportSheet extends StatefulWidget {
  const _MmExportSheet();

  @override
  State<_MmExportSheet> createState() => _MmExportSheetState();
}

class _MmExportSheetState extends State<_MmExportSheet> {
  String _fmt = 'html';
  bool _body = false; // 默认关——§4.10：禁止「默认带正文」形态
  bool _landscape = false;

  static const _formats = [
    ('html', 'HTML（可看可折叠可跳转）', Icons.code_outlined),
    ('md', 'Markdown 大纲', Icons.format_list_bulleted),
    ('opml', 'OPML 大纲', Icons.account_tree_outlined),
    ('png', 'PNG 图片', Icons.image_outlined),
    // 批5 F4-9 解禁：原型第五枚一直是可点的（`.xmind` 只出不进）。
    ('xmind', '.xmind（只出不进）', Icons.extension_outlined),
  ];

  /// PNG 与 `.xmind` 都**不含「挂载正文」语义**（前者是像素、后者只带结构
  /// 与批5 三段），两开关对它们置灰——与原型 `mmRenderExportSpec` 的
  /// `hasBodyOpt` 同款口径。
  bool get _isPng => _fmt == 'png';
  bool get _isXmind => _fmt == 'xmind';
  bool get _noBodySemantics => _isPng || _isXmind;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        key: const ValueKey('mm-export-sheet'),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('导出',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            for (final (key, label, icon) in _formats)
              ListTile(
                key: ValueKey('mm-export-fmt-$key'),
                dense: true,
                leading: Icon(icon, size: 20),
                title: Text(label, style: const TextStyle(fontSize: 13.5)),
                trailing:
                    _fmt == key ? Icon(Icons.check, size: 18, color: cs.primary) : null,
                onTap: () => setState(() => _fmt = key),
              ),
            ListTile(
              key: const ValueKey('mm-export-fmt-xmind-help'),
              dense: true,
              enabled: false,
              leading: Icon(Icons.extension_outlined,
                  size: 20, color: cs.onSurfaceVariant.withValues(alpha: .45)),
              title: Text('.xmind 只出不进：XMind 可打开，本应用不提供导入',
                  style: TextStyle(
                      fontSize: 11.5,
                      color: cs.onSurfaceVariant.withValues(alpha: .7))),
            ),
            const Divider(height: 16),
            // PNG 是画布像素快照，.xmind 只带结构 ⇒ 两开关置灰
            SwitchListTile(
              key: const ValueKey('mm-export-body-sw'),
              dense: true,
              value: _body && !_noBodySemantics,
              onChanged: _noBodySemantics
                  ? null
                  : (v) => setState(() => _body = v),
              title: const Text('带挂载笔记正文',
                  style: TextStyle(fontSize: 13.5)),
              subtitle: Text(
                _noBodySemantics ? '该格式不含笔记正文' : '默认只导笔记标题；开启后正文随文件带出',
                style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
              ),
            ),
            SwitchListTile(
              key: const ValueKey('mm-export-landscape-sw'),
              dense: true,
              value: _landscape && !_isPng,
              onChanged:
                  _isPng ? null : (v) => setState(() => _landscape = v),
              title: const Text('横向布局预设',
                  style: TextStyle(fontSize: 13.5)),
              subtitle: Text(
                _isPng ? 'PNG 不适用' : 'HTML 文件自带横向比例，浏览器打开即横向',
                style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              key: const ValueKey('mm-export-go'),
              onPressed: () => Navigator.pop(
                context,
                MmExportChoice(
                  format: _fmt,
                  includeBody: _body && !_noBodySemantics,
                  landscape: _landscape && !_isPng,
                ),
              ),
              child: const Text('导出'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 导出执行体（画布页/列表页共用）。
/// · HTML：本文件内现跑 [TreeLayoutEngine]（TextPainter 现量宽）＝与 App
///   同一布局算法生成初始坐标（§4.10）；显示标题/挂载快照经回调取（linkage，
///   **正文只在 includeBody 时读取**——默认关＝连读都不读）。
/// · PNG：[pngSnapshot] 由画布页注入（离屏绘制当前图全内容；null＝画布外
///   不可用，选 PNG 时提示「请从画布导出」）。
Future<void> mmRunExport(
  BuildContext context, {
  required String mapTitle,
  required List<MindmapNode> rows,
  required Future<String?> Function(MindmapNode n) noteTitleOf,
  required Future<String?> Function(MindmapNode n) noteBodyOf,
  required Future<Uint8List?> Function() pngSnapshot,

  /// 批4：HTML 初始坐标跟当前布局预设（导出即所见；null ＝纵向树默认）。
  /// 列表页发起导出时传 null＝用默认纵向树（该页无画布局语境）。
  MmLayoutPreset? preset,
}) async {
  final choice = await showMmExportSheet(context);
  if (choice == null || !context.mounted) return;
  try {
    final tmp = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final base = p.join(tmp.path, 'mindmap-$stamp');
    String? savedName;
    switch (choice.format) {
      case 'png':
        final bytes = await pngSnapshot();
        if (bytes == null || bytes.isEmpty) {
          if (context.mounted) AppToast.show(context, '请从画布发起 PNG 导出');
          return;
        }
        final f = File('$base.png')..writeAsBytesSync(bytes);
        savedName = await safSaveAs(f.path);
      case 'md':
        final f = File('$base.md')
          ..writeAsStringSync(mmExportMarkdown(rows));
        savedName = await safSaveAs(f.path);
      case 'opml':
        final f = File('$base.opml')
          ..writeAsStringSync(mmExportOpml(mapTitle, rows));
        savedName = await safSaveAs(f.path);
      case 'xmind':
        // 批5 F4-9：**只出不进**——产出 zip 字节落临时文件后走同一条
        // `safSaveAs`（零新增原生通道，与 md/opml/html 同款）。
        final f = File('$base.xmind')
          ..writeAsBytesSync(mmExportXmindBytes(mapTitle: mapTitle, rows: rows));
        savedName = await safSaveAs(f.path);
      case 'html':
        // 挂载快照预取（async 出口 → 先收齐再组装）。
        final titles = <int, String?>{};
        final bodies = <int, String?>{};
        for (final n in rows) {
          if (n.id == null || n.noteId == null) continue;
          titles[n.id!] = await noteTitleOf(n);
          if (choice.includeBody) bodies[n.id!] = await noteBodyOf(n);
        }
        final html = _buildHtml(
          mapTitle: mapTitle,
          rows: rows,
          noteTitles: titles,
          noteBodies: bodies,
          landscape: choice.landscape,
          preset: preset ?? MmLayoutPreset.defaults,
        );
        final f = File('$base.html')..writeAsStringSync(html);
        savedName = await safSaveAs(f.path);
      default:
        return;
    }
    if (context.mounted) {
      AppToast.show(context, savedName == null ? '已取消' : '已导出为 $savedName');
    }
  } catch (err) {
    AppLog.add('导图导出失败：$err', level: LhLevel.error);
    if (context.mounted) AppToast.show(context, '导出失败 · 请重试');
  }
}

/// PNG 离屏快照（画布页薄封装调这里）：整图（含视口外）scale=1，
/// pan 平移内容到原点＋边距；令牌与屏上 painter 同源（导出即所见主题）。
/// 返回 null＝无可绘内容（空图）。
Future<Uint8List?> mmCanvasPngSnapshot({
  required List<MindmapNode> nodes,
  required MmLayoutResult? layout,
  required Rect bounds,
  required String Function(MindmapNode n) displayTitleOf,
  required double Function(MindmapNode n) dxOf,
  required double Function(MindmapNode n) dyOf,
  required ColorScheme cs,
  MmStyle? style,
}) async {
  if (layout == null || nodes.isEmpty || bounds == Rect.zero) return null;
  const margin = 24.0;
  final size = Size(bounds.width + margin * 2, bounds.height + margin * 2);
  final recorder = ui.PictureRecorder();
  // 批3 样式层：与屏上 painter 同一个工厂解析（导出＝所见，不各算一套）。
  MmCanvasPainter(
    nodes: nodes,
    layout: layout,
    scale: 1,
    pan: -bounds.topLeft + const Offset(margin, margin),
    selectedId: null,
    nodeTitles: {for (final n in nodes) if (n.id != null) n.id!: displayTitleOf(n)},
    mountedIds: {for (final n in nodes) if (n.noteId != null) n.id!},
    dxs: {for (final n in nodes) if (n.id != null) n.id!: dxOf(n)},
    dys: {for (final n in nodes) if (n.id != null) n.id!: dyOf(n)},
    style: MmPaintStyle.of(style, cs),
  ).paint(ui.Canvas(recorder), size);
  return encodeOffscreenPng(recorder, size.width, size.height);
}

/// 导出 HTML 组装：按**当前布局预设**跑引擎＋显示标题合成（挂载笔记标题
/// 优先，失效回落节点标题——与画布显示口径一致）。
///
/// 批4：预设经 [MmLayoutPreset.engine] 挑引擎，**初始坐标＝屏上所见**；
/// 连线画法随 `layout.edgeKind` 写进 HTML（横向/放射布局在导出文件里也走
/// 中心直线，不会套阶梯公式斜穿节点）。
String _buildHtml({
  required String mapTitle,
  required List<MindmapNode> rows,
  required Map<int, String?> noteTitles,
  required Map<int, String?> noteBodies,
  required bool landscape,
  required MmLayoutPreset preset,
}) {
  // 度量与画布同源：按**合成后显示标题**（挂载笔记标题优先）量宽。
  final layout = mmLayoutOf(
    preset,
    rows,
    measure: (n) => mmNodeMeasure(noteTitles[n.id] ?? n.title),
  );
  var boundsW = 0.0;
  var boundsH = 0.0;
  final exportNodes = <MmExportNode>[];
  for (final n in rows) {
    if (n.id == null || !layout.baseline.containsKey(n.id)) continue;
    final b = layout.baseline[n.id]!;
    final s = layout.sizes[n.id] ?? const Size(120, 36);
    boundsW = math.max(boundsW, b.dx + s.width);
    boundsH = math.max(boundsH, b.dy + s.height);
    final nt = noteTitles[n.id!];
    final hasTitle = nt != null && nt.isNotEmpty;
    exportNodes.add(MmExportNode(
      id: n.id!,
      parentId: n.parentId,
      displayTitle: hasTitle ? nt : n.title,
      note: n.note.isEmpty ? null : n.note,
      noteTitle: hasTitle ? nt : null,
      noteBody: noteBodies[n.id!],
      folded: n.folded,
    ));
  }
  return mmExportHtml(
    mapTitle: mapTitle,
    nodes: exportNodes,
    baseline: layout.baseline,
    sizes: layout.sizes,
    boundsWidth: boundsW,
    boundsHeight: boundsH,
    landscapePreset: landscape,
    edgeKind: layout.edgeKind,
    exportedAt: DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()),
  );
}
