// AI 能力点本地实调验证 CLI（不进包体；两档流程的「先本地验证」通道）。
//
// 用法（项目根目录）：
//   dart run tools/ai_verify.dart --list
//   dart run tools/ai_verify.dart --all                 # 全部能力点用样例实调
//   dart run tools/ai_verify.dart --task todo.quadrant --var title=明晚交周报
//   dart run tools/ai_verify.dart --all --model deepseek-flash
//
// Key 读取顺序：环境变量 DEEPSEEK_API_KEY → tools/.ai_verify.env（gitignored）。
// 请求走 prompts.json 的 defaults.baseUrl（OpenAI 兼容 /chat/completions）。
import 'dart:convert';
import 'dart:io';

import 'package:lifeharness/core/ai/ai_prompt_pack.dart';
import 'package:lifeharness/core/ai/ai_validate.dart';

Future<void> main(List<String> args) async {
  final root = Directory.current.path;
  final packSrc =
      File('$root/assets/ai_prompts/prompts.json').readAsStringSync();
  final pack = AiPromptPack.decode(packSrc);
  final env = _loadEnv('$root/tools/.ai_verify.env');
  final apiKey =
      Platform.environment['DEEPSEEK_API_KEY'] ?? env['DEEPSEEK_API_KEY'];
  final baseUrl = (argValue(args, '--base') ??
          env['AI_BASE_URL'] ??
          pack.defaultBaseUrl)
      .replaceAll(RegExp(r'/+$'), '');
  final model =
      argValue(args, '--model') ?? env['AI_MODEL'] ?? pack.defaultModel;

  if (args.contains('--list')) {
    for (final t in pack.tasks) {
      stdout.writeln(
          '${t.id.padRight(22)} ${t.module}·${t.name}  [${t.expect.name}]  占位符: ${t.placeholders.join(', ')}');
    }
    return;
  }
  if (apiKey == null || apiKey.trim().isEmpty) {
    stderr.writeln('缺少 Key：设 DEEPSEEK_API_KEY 环境变量或写 tools/.ai_verify.env');
    exitCode = 2;
    return;
  }

  List<AiPromptTask> targets;
  if (args.contains('--all')) {
    targets = pack.tasks.where((t) => t.id != 'tool.verify').toList();
  } else {
    final id = argValue(args, '--task');
    final t = id == null ? null : pack.taskById(id);
    if (t == null) {
      stderr.writeln('未找到能力点：$id（--list 查看全部）');
      exitCode = 2;
      return;
    }
    targets = [t];
  }

  // --var k=v 覆盖样例输入。
  final overrides = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--var' && i + 1 < args.length) {
      final kv = args[++i];
      final eq = kv.indexOf('=');
      if (eq > 0) overrides[kv.substring(0, eq)] = kv.substring(eq + 1);
    }
  }

  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  var pass = 0,
      fail = 0;
  for (final t in targets) {
    final vars = <String, String>{...t.sample, ...overrides};
    final user = renderTemplate(t.user, vars);
    stdout.writeln('── ${t.id}（${t.module}·${t.name}）');
    stdout.writeln('   user: ${_oneLine(user)}');
    try {
      final r = await _chat(client, baseUrl, apiKey, model, t.system, user);
      final content = r.content;
      stdout.writeln(
          '   ✔ ${r.statusMs}ms · tokens ${r.promptTokens}+${r.completionTokens}');
      stdout.writeln('   回复: ${_clip(_oneLine(content), 220)}');
      final err = validateAiOutput(t.id, t.expect, content, vars);
      if (err == null) {
        pass++;
        stdout.writeln('   PASS');
      } else {
        fail++;
        stdout.writeln('   FAIL: $err');
      }
    } catch (e) {
      fail++;
      stdout.writeln('   FAIL: $e');
    }
    stdout.writeln('');
  }
  client.close(force: true);
  stdout.writeln('结果: $pass PASS / $fail FAIL');
  if (fail > 0) exitCode = 1;
}

class _Resp {
  _Resp(this.content, this.statusMs, this.promptTokens, this.completionTokens);
  final String content;
  final int statusMs;
  final int promptTokens;
  final int completionTokens;
}

Future<_Resp> _chat(HttpClient client, String baseUrl, String key, String model,
    String system, String user) async {
  final sw = Stopwatch()..start();
  final req = await client.postUrl(Uri.parse('$baseUrl/chat/completions'));
  req.headers.contentType = ContentType.json;
  req.headers.set('Authorization', 'Bearer $key');
  req.write(jsonEncode({
    'model': model,
    'messages': [
      {'role': 'system', 'content': system},
      {'role': 'user', 'content': user},
    ],
    'temperature': 0.2,
  }));
  final res = await req.close().timeout(const Duration(seconds: 90));
  final body = await res.transform(utf8.decoder).join();
  sw.stop();
  if (res.statusCode != 200) {
    throw StateError('HTTP ${res.statusCode}: ${_clip(body, 200)}');
  }
  final j = jsonDecode(body) as Map<String, dynamic>;
  final choice = (j['choices'] as List?)?.first as Map?;
  final content = (choice?['message']?['content'] as String?)?.trim();
  if (content == null || content.isEmpty) {
    throw StateError('回复为空: ${_clip(body, 200)}');
  }
  final usage = (j['usage'] as Map?) ?? const {};
  return _Resp(content, sw.elapsedMilliseconds,
      usage['prompt_tokens'] as int? ?? 0, usage['completion_tokens'] as int? ?? 0);
}

String? argValue(List<String> args, String flag) {
  final i = args.indexOf(flag);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
}

Map<String, String> _loadEnv(String path) {
  final f = File(path);
  if (!f.existsSync()) return const {};
  return {
    for (final line in f.readAsLinesSync())
      if (line.contains('=') && !line.trimLeft().startsWith('#'))
        line.substring(0, line.indexOf('='))
            .trim(): line.substring(line.indexOf('=') + 1).trim()
  };
}

String _oneLine(String s) => s.replaceAll(RegExp(r'\s+'), ' ');
String _clip(String s, int n) => s.length <= n ? s : '${s.substring(0, n)}…';
