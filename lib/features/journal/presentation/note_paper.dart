import 'package:flutter/material.dart';

/// 纸色（原型 PW_PAPERS · V1.29轮9n）：米纸 / 纯白 / 护眼绿 / 深夜。
const notePapers = <(Color, Color)>[
  (Color(0xFFFBF8F1), Color(0xFF403A31)),
  (Color(0xFFFFFFFF), Color(0xFF334155)),
  (Color(0xFFEDF3EA), Color(0xFF37412F)),
  (Color(0xFF1E1D1B), Color(0xFFCFC9BD)),
];

const notePaperNames = ['米纸', '纯白', '护眼绿', '深夜'];

/// 自定义色条前景（原型 pwSetPaperHue 固定 #403a31）。
const noteCustomFg = Color(0xFF403A31);

/// 笔记纸色编码（DB v9 · notes.paper · 按笔记独立生效）：
/// 空 = 默认（米纸）· `p<i>` = 预置第 i 项 · `h<hue>` = 色条自定义 hsl(hue,60%,88%)。
Color paperBg(String paper) {
  final (r, g) = paperParts(paper);
  return r ?? notePapers.first.$1;
}

Color paperFg(String paper) {
  final (r, g) = paperParts(paper);
  return g ?? notePapers.first.$2;
}

/// 纸色名（原型 pwPaperName：预置显示名称，自定义显示「自定义」）。
String paperName(String paper) {
  final m = RegExp(r'^p(\d)$').firstMatch(paper);
  if (m == null) return paper.isEmpty ? notePaperNames.first : '自定义';
  final i = int.parse(m.group(1)!);
  return i < notePaperNames.length ? notePaperNames[i] : '自定义';
}

/// 色条 hue（0-359）；预置/未设置时回落到米纸色相 40（原型滑块默认值）。
double paperHue(String paper) {
  final m = RegExp(r'^h(\d+(?:\.\d+)?)$').firstMatch(paper);
  return m == null ? 40 : double.parse(m.group(1)!);
}

(Color?, Color?) paperParts(String paper) {
  final preset = RegExp(r'^p(\d)$').firstMatch(paper);
  if (preset != null) {
    final i = int.parse(preset.group(1)!);
    if (i >= 0 && i < notePapers.length) return (notePapers[i].$1, notePapers[i].$2);
    return (null, null);
  }
  final hue = RegExp(r'^h(\d+(?:\.\d+)?)$').firstMatch(paper);
  if (hue != null) {
    final c = HSLColor.fromAHSL(1, double.parse(hue.group(1)!) % 360, .6, .88)
        .toColor();
    return (c, noteCustomFg);
  }
  return (null, null);
}
