/// AI 输出结构校验（纯 Dart）：CLI tools/ai_verify.dart 与 app AiService
/// 共用同一口径，保证「本地验证通过 = 端上解析同规则可过」。
library;

import 'ai_prompt_pack.dart';

/// 校验模型回复是否满足能力点的期望形态；通过返回 null，否则返回失败原因。
String? validateAiOutput(
    String taskId, AiExpect expect, String content, Map<String, String> vars) {
  return expect == AiExpect.json
      ? _validateJson(taskId, content, vars)
      : _validateText(taskId, content);
}

String? _validateJson(String taskId, String content, Map<String, String> vars) {
  Map<String, dynamic> o;
  try {
    o = decodeJsonObject(content);
  } on FormatException catch (e) {
    return e.message;
  }
  switch (taskId) {
    case 'todo.quadrant':
      final q = o['quadrant'];
      if (q is! int || q < 1 || q > 4) return 'quadrant 非 1~4: $q';
      if (o['reason'] is! String) return '缺 reason';
    case 'todo.nl_parse':
      if (o['title'] is! String || (o['title'] as String).isEmpty) {
        return '缺 title';
      }
      final q = o['quadrant'];
      if (q != null && q is! int) return 'quadrant 类型错: $q';
      final d = o['dueDate'];
      if (d != null &&
          d is! String &&
          !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch('$d')) {
        return 'dueDate 非日期: $d';
      }
    case 'todo.subtask':
      final s = o['subtasks'];
      if (s is! List || s.length < 2 || s.any((e) => e is! String)) {
        return 'subtasks 非 2+ 条字符串数组: $s';
      }
    case 'inbox.triage':
      final tgt = o['target'];
      if (!{'todo', 'journal', 'note', 'quote'}.contains(tgt)) {
        return 'target 非法: $tgt';
      }
    case 'read.toc':
      final cs = o['chapters'];
      // 空数组是**合法**产出：read.toc 系统提示词明确要求「该书确实未知时返回空
      // chapters，不要编造」（红线：AI 不造目录）。旧写法把空数组判成结构错，
      // 真机表现为《两宋之变》这类书目点「AI 补全」直接报「chapters 结构错: []」。
      // 「没有可用章节」由调用方给友好回执并拒绝覆盖既有目录，不在此处报错。
      if (cs is! List || cs.any((e) => e is! Map || e['title'] is! String)) {
        return 'chapters 结构错: ${_clip('$cs', 120)}';
      }
      // 上限按实书放宽：69 节的书（真机样本）曾撞旧上限 40 被整条判失败。
      if (cs.length > 120) return '章节过多: ${cs.length}';
    case 'read.quote_insight':
      if (o['insight'] is! String || (o['insight'] as String).isEmpty) {
        return '缺 insight';
      }
      if (o['tags'] != null && o['tags'] is! List) return 'tags 非数组';
    case 'ledger.categorize':
      final items = o['items'];
      final wantLines = (vars['items'] ?? '')
          .split('\n')
          .where((e) => e.trim().isNotEmpty)
          .length;
      if (items is! List || items.length != wantLines) {
        return 'items 条数 ${items is List ? items.length : '?'} ≠ 输入 $wantLines';
      }
      final cats = (vars['cats'] ?? '')
          .split(RegExp('[,，]'))
          .map((e) => e.trim())
          .toSet();
      for (final e in items) {
        if (e is! Map || !cats.contains('${e['category']}')) {
          return '分类越界: ${_clip('$e', 80)}';
        }
      }
  }
  return null;
}

String? _validateText(String taskId, String content) {
  final s = cleanTextResult(content);
  if (taskId == 'tool.verify') {
    // 连通性验证：拿到非空回复即通过（样例要求回复四个字）。
    return s.isEmpty ? '空回复' : null;
  }
  if (s.length < 15) return '文本过短: ${_clip(s, 60)}';
  if (taskId == 'care.cycle_insight' && !s.contains('不构成医学诊断')) {
    return '缺医疗免责句';
  }
  return null;
}

String _clip(String s, int n) => s.length <= n ? s : '${s.substring(0, n)}…';
