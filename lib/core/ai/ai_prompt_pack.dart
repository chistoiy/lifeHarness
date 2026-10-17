/// AI 提示词资产包（纯 Dart，无 flutter 依赖：app 与 tools/ai_verify.dart 共用）。
///
/// 事实源：`assets/ai_prompts/prompts.json`。每个能力点 = 一条 [AiPromptTask]，
/// system/user 模板里的 `{{占位符}}` 由调用方数据填充；用户在「提示词管理」页
/// 的覆盖值经 [renderTemplate] 走同一渲染器，改提示词不需要改代码。
library;

import 'dart:convert';

/// 渲染模板：把 `{{name}}` 替换为 vars[name]；缺失的占位符原样保留（可见即可控）。
String renderTemplate(String template, Map<String, String> vars) {
  return template.replaceAllMapped(RegExp(r'\{\{(\w+)\}\}'), (m) {
    final v = vars[m.group(1)];
    return v ?? m.group(0)!;
  });
}

/// 模板声明的占位符名列表（提示词管理页展示可用变量）。
List<String> templatePlaceholders(String template) => RegExp(r'\{\{(\w+)\}\}')
    .allMatches(template)
    .map((m) => m.group(1)!)
    .toList();

/// 一个 AI 能力点的提示词规格。
class AiPromptTask {
  const AiPromptTask({
    required this.id,
    required this.module,
    required this.name,
    required this.system,
    required this.user,
    required this.expect,
    required this.placeholders,
    required this.sample,
  });

  factory AiPromptTask.fromJson(Map<String, dynamic> j) => AiPromptTask(
        id: j['id'] as String,
        module: j['module'] as String? ?? '',
        name: j['name'] as String? ?? '',
        system: j['system'] as String? ?? '',
        user: j['user'] as String? ?? '',
        expect: (j['expect'] as String?) == 'json'
            ? AiExpect.json
            : AiExpect.text,
        placeholders:
            (j['placeholders'] as List?)?.map((e) => e as String).toList() ??
                const [],
        sample: (j['sample'] as Map?)?.map((k, v) => MapEntry('$k', '$v')) ??
            const {},
      );

  final String id;
  final String module;
  final String name;
  final String system;
  final String user;
  final AiExpect expect;
  final List<String> placeholders;
  final Map<String, String> sample;
}

/// 期望的模型输出形态：json=必须可解析为 JSON 对象；text=纯文稿。
enum AiExpect { json, text }

/// 提示词包（prompts.json 全量）。
class AiPromptPack {
  const AiPromptPack({
    required this.version,
    required this.defaultBaseUrl,
    required this.defaultModel,
    required this.tasks,
  });

  factory AiPromptPack.decode(String source) {
    final j = jsonDecode(source) as Map<String, dynamic>;
    final d = (j['defaults'] as Map?)?.cast<String, dynamic>() ?? const {};
    return AiPromptPack(
      version: j['version'] as int? ?? 1,
      defaultBaseUrl: d['baseUrl'] as String? ?? '',
      defaultModel: d['model'] as String? ?? '',
      tasks: (j['tasks'] as List? ?? const [])
          .map((e) => AiPromptTask.fromJson((e as Map).cast<String, dynamic>()))
          .toList(growable: false),
    );
  }

  final int version;
  final String defaultBaseUrl;
  final String defaultModel;
  final List<AiPromptTask> tasks;

  AiPromptTask? taskById(String id) {
    for (final t in tasks) {
      if (t.id == id) return t;
    }
    return null;
  }
}

/// 模型回复 → 期望形态的宽容解析（与 CLI、app 共用一套口径）。
///
/// 剥离 ```json 围栏与前后杂语后取第一个平衡的 `{...}`；失败抛 FormatException。
Map<String, dynamic> decodeJsonObject(String content) {
  var s = content.trim();
  final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```');
  if (fence.hasMatch(s)) s = fence.firstMatch(s)!.group(1)!.trim();
  final start = s.indexOf('{');
  if (start < 0) throw const FormatException('回复中没有 JSON 对象');
  var depth = 0;
  var inStr = false;
  var esc = false;
  for (var i = start; i < s.length; i++) {
    final ch = s[i];
    if (inStr) {
      if (esc) {
        esc = false;
      } else if (ch == r'\') {
        esc = true;
      } else if (ch == '"') {
        inStr = false;
      }
      continue;
    }
    if (ch == '"') {
      inStr = true;
    } else if (ch == '{') {
      depth++;
    } else if (ch == '}') {
      depth--;
      if (depth == 0) {
        final obj = jsonDecode(s.substring(start, i + 1));
        if (obj is Map<String, dynamic>) return obj;
        throw const FormatException('JSON 顶层不是对象');
      }
    }
  }
  throw const FormatException('JSON 花括号不平衡');
}

/// 文本结果清洗（去围栏/首尾空白与包裹引号），用于 text 期望的能力点。
String cleanTextResult(String content) {
  var s = content.trim();
  final fence = RegExp(r'```(?:\w+)?\s*([\s\S]*?)\s*```');
  if (fence.hasMatch(s)) s = fence.firstMatch(s)!.group(1)!.trim();
  if (s.length > 1 && s.startsWith('"') && s.endsWith('"')) {
    s = s.substring(1, s.length - 1);
  }
  return s;
}
