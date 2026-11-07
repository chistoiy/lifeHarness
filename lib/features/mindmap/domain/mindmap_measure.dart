/// 节点标题盒度量（批2 F4-6 多行化）。独立小件：布局域 `mindmap_layout.dart`
/// 保持零 Flutter 依赖（纯 Dart 测试可跑），本文件吃 TextPainter。
///
/// 口径：标题内 `\n` 换行、无行数上限、宽度封顶 [maxWidth]；画布与导出共用
/// 一份（§4.10「同一布局算法生成初始坐标」含度量——度量不一致＝HTML 初始
/// 布局漂移）。树布局纵向间距按本函数**实测高逐节点累加**（引擎 `visit`
/// 已是 `max(minRowH, size.height)`），禁用常量行高——多行节点渲染高 ≠ 单行，
/// 常量行高会让兄弟行叠压。
library;

import 'dart:math' as math;

import 'package:flutter/painting.dart';

import 'mindmap_node_meta.dart' show mmNodeExtraWidth;

/// 批5：标签 chip 的单枚估算宽（原型 9px 字号 ＋ `padding:1px 5px` ＋ 圆角余量）。
/// 中文按全角估——低估会让 chip 压到标题上（原型踩过同类字宽低估的坑）。
double mmTagWidthEstimate(String tag) => tag.length * 10.0 + 12.0;

/// 节点标题盒度量（批2 F4-6 多行化）。独立小件：布局域 `mindmap_layout.dart`
/// 保持零 Flutter 依赖（纯 Dart 测试可跑），本文件吃 TextPainter。
///
/// 口径：标题内 `\n` 换行、无行数上限、宽度封顶 [maxWidth]；画布与导出共用
/// 一份（§4.10「同一布局算法生成初始坐标」含度量——度量不一致＝HTML 初始
/// 布局漂移）。树布局纵向间距按本函数**实测高逐节点累加**（引擎 `visit`
/// 已是 `max(minRowH, size.height)`），禁用常量行高——多行节点渲染高 ≠ 单行，
/// 常量行高会让兄弟行叠压。
///
/// **批5**：[extraWidth] 是任务勾选框 ＋ 图片占位 ＋ 标签 chip 的合计占宽，
/// 由 [mmNodeExtraWidth] 逐节点算（不同节点段数不同）——不在这里猜段数。
Size mmNodeMeasure(
  String title, {
  TextStyle style = const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
  double maxWidth = 280,
  double hPad = 12,
  double vPad = 22,
  double minH = 40,
  double extraWidth = 0,
}) {
  final tp = TextPainter(
    text: TextSpan(text: title.isEmpty ? ' ' : title, style: style),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: math.max(40, maxWidth - hPad * 2 - extraWidth));
  return Size(
    math.min(maxWidth, tp.width + hPad * 2 + extraWidth),
    math.max(minH, tp.height + vPad),
  );
}
