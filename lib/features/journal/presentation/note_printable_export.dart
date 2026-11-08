/// C08b · 单篇「导出为可打印 HTML」动作（笔记分享弹层 / 日记编辑页共用）。
///
/// 口径：产物是**本地 HTML 文件**（A4 打印样式），PDF 由用户在系统打印面板
/// 「另存为 PDF」得到——所以文案只说「可打印 HTML · 系统打印可另存为 PDF」，
/// 绝不写「已导出 PDF」（零依赖下做不出内嵌中文字体的真 PDF）。
library;

import 'package:flutter/material.dart';

import '../../../core/export/export_save.dart';
import '../../../core/export/printable_html.dart';
import '../../../core/logging/app_log.dart';
import '../../../shared/widgets/ui_kit.dart' show AppToast;

/// 组装 HTML → 走既有 SAF 另存 → 出声。取消（系统选择器返回 null）也出一句，
/// 用户不会「点了没反应」。
Future<void> notePrintableHtmlAction(
  BuildContext context, {
  required String title,
  required String body,
  String subtitle = '',
}) async {
  final safeTitle = title.trim().isEmpty ? '未命名笔记' : title.trim();
  try {
    final html = noteToPrintableHtml(
      title: safeTitle,
      body: body,
      subtitle: subtitle,
    );
    final saved = await savePrintableHtmlAs(title: safeTitle, html: html);
    if (!context.mounted) return;
    AppToast.show(
        context,
        saved == null
            ? '已取消'
            : '已导出 $saved · $kPrintableHtmlExportHint',
        ms: 2600);
  } catch (err) {
    AppLog.add('可打印 HTML 导出失败：$err', level: LhLevel.error);
    if (context.mounted) AppToast.show(context, '导出失败 · 请重试');
  }
}
