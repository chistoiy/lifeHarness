/// 笔记摘要清洗（卡片 / 列表 / 搜索结果共用一枚纯函数）。
///
/// 背景（批7 A1 · 2026-11-08 · 评估件 A1）：三个视图的卡片摘要此前直接吐正文前 40 字，
/// 于是真机截图里出现 `## **开篇总纲**`、`# 就这些奖学金`、`- 天子命…` 这类裸标记。
/// 症结不是「不会渲染」——编辑器预览态排版是精致的，而是**摘要没走清洗链路**。
///
/// 修法＝复用既有链路而不是照抄第三方给的五行正则（那段漏 `- ` 列表符、不处理附件占位、
/// `**(.+?)**` 跨行不安全）：行内标记统一交给 `note_outline.dart` 的 [stripNoteInlineMd]，
/// 保证「摘要」与「导图节点标题」两处读法一致；富文本→纯文本仍走 `Note.richToPlain`
/// （由调用方传 [displayBody]，本件不重复展开 Delta JSON）。
library;

import 'note_outline.dart' show stripNoteInlineMd;

/// 摘要字数上限（沿用既有 `Note.preview` 的 40 字口径，列表与卡片同一读数）。
const int kNotePreviewMax = 40;

/// 空正文占位（与既有行为一致）。
const String kNotePreviewBlank = '（空白笔记）';

final RegExp _fenceRe = RegExp(r'```[\s\S]*?```|~~~[\s\S]*?~~~');
final RegExp _imgRe = RegExp(r'!\[([^\]]*)\]\([^)]*\)');
final RegExp _linkRe = RegExp(r'\[([^\]]*)\]\([^)]*\)');
final RegExp _headingRe = RegExp(r'^\s*#{1,6}\s*');
final RegExp _quoteRe = RegExp(r'^\s*>\s?');
final RegExp _bulletRe = RegExp(r'^\s*(?:[-*+]|\d+[.)])\s+');
final RegExp _taskRe = RegExp(r'^\[[ xX]\]\s*');
final RegExp _ruleRe = RegExp(r'^\s*(?:-{3,}|\*{3,}|_{3,})\s*$');
/// 表格对齐行（`| --- | :---: |`）：只由竖线/短横/冒号组成，属结构不是内容。
final RegExp _tableSepRe = RegExp(r'^[\s|:-]*-[\s|:-]*$');
final RegExp _wsRe = RegExp(r'\s+');

/// 把一段正文压成一句可读摘要。
///
/// [body] 传「面向展示的正文」：纯文本原样、富文本传 `Note.displayBody`
/// （已是 `richToPlain` 结果、`![alt](path)` 已转 alt）。
/// [title] 用于去掉「首行标题＝笔记标题」的重复（真机样本里卡片会连读两遍同一句）。
String notePreviewText(String body,
    {String title = '', int max = kNotePreviewMax}) {
  var s = body.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  // 围栏代码块整块跳过：代码行不是摘要；留空串会在后续压空白时并掉。
  s = s.replaceAll(_fenceRe, ' ');
  // 图片语法留 alt，无 alt 交「图片」（与 richToPlain 的嵌入占位同词）。
  s = s.replaceAllMapped(
      _imgRe, (m) => (m[1] ?? '').trim().isEmpty ? '图片' : m[1]!.trim());
  // 链接只留可读文字。
  s = s.replaceAllMapped(_linkRe, (m) => m[1] ?? '');

  final lines = <String>[];
  var firstIsHeading = false;
  for (final raw in s.split('\n')) {
    if (_ruleRe.hasMatch(raw)) continue; // 分割线
    if (_tableSepRe.hasMatch(raw)) continue; // 表格对齐行
    final isHeading = _headingRe.hasMatch(raw);
    var l = raw.replaceFirst(_headingRe, '');
    l = l.replaceFirst(_quoteRe, ''); // 引用符
    l = l.replaceFirst(_bulletRe, ''); // 列表符（含有序 `1.` / `1)`）
    l = l.replaceFirst(_taskRe, ''); // 待办勾选框 `[ ]` / `[x]`
    if (l.contains('|')) l = l.replaceAll('|', ' '); // 表格竖线
    l = stripNoteInlineMd(l); // 强调符 / 行内代码 / 残留行首 #
    final t = l.trim();
    if (t.isEmpty) continue;
    if (lines.isEmpty) firstIsHeading = isHeading;
    lines.add(t);
  }

  // 首行是标题且与笔记标题同文：去掉，避免卡片「标题＋摘要」重复同一句。
  final tt = title.trim();
  if (firstIsHeading && tt.isNotEmpty && lines.isNotEmpty && lines.first == tt) {
    lines.removeAt(0);
  }

  final joined = lines.join(' ').replaceAll(_wsRe, ' ').trim();
  if (joined.isEmpty) return kNotePreviewBlank;
  final runes = joined.runes.toList();
  if (runes.length <= max) return joined;
  return '${String.fromCharCodes(runes.take(max))}…';
}
