import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// 架构守护测试（《开发计划书》§2.1 模块解耦规范的可执行化）。
///
/// 规则：
/// R1 `features/<mod>/**` 不得 import 其他 feature（跨模块只经 shared/linkage 或事件总线）。
/// R2 `core/**` 不得 import `features/**`（组合根白名单除外）。
/// R3 feature 的 domain/data 层不得 import 任何 presentation（模型/仓库层纯净，可单测）。
/// R4 `for` 循环的增量子句必须有副作用（防空增量静默死循环，见 2026-09-20 事故）。
/// 违反任何一条即测试失败——新增跨模块依赖必须先过架构评审并更新本白名单。
void main() {
  const libDir = 'lib';
  // 组合根：允许装配各 feature 页面/Provider 的文件。
  const compositionRoots = {
    'core/router/app_router.dart',
  };

  // 文件 → 其 import 解析出的 lib 相对路径列表。
  Map<String, List<String>> collectImports() {
    final result = <String, List<String>>{};
    for (final f in Directory(libDir).listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final rel = p.posix.joinAll(p.split(p.relative(f.path, from: libDir)));
      final imports = <String>[];
      for (final line in f.readAsLinesSync()) {
        final m = RegExp(r"""^import\s+['"]([^'"]+)['"]""").firstMatch(line);
        if (m == null) continue;
        final uri = m.group(1)!;
        if (uri.startsWith('package:lifeharness/')) {
          imports.add(uri.substring('package:lifeharness/'.length));
        } else if (uri.startsWith('dart:') || !uri.contains('.')) {
          continue;
        } else if (!uri.startsWith('package:') && !uri.startsWith('file:')) {
          // 相对 import：解析为 lib 相对路径。
          final resolved = p.normalize(p.join(p.dirname(rel), uri));
          if (resolved.startsWith('../')) continue; // 出了 lib/（外部包）
          imports.add(p.posix.joinAll(p.split(resolved)));
        }
      }
      result[rel] = imports;
    }
    return result;
  }

  final imports = collectImports();

  test('R1 features 不得互相 import（跨模块必须走 shared/linkage）', () {
    final violations = <String>[];
    for (final entry in imports.entries) {
      final mod = entry.key.split('/').first;
      if (!entry.key.startsWith('features/')) continue;
      for (final imp in entry.value) {
        if (!imp.startsWith('features/')) continue;
        final target = imp.split('/').first;
        if (target != mod) {
          violations.add('${entry.key} → features/$target');
        }
      }
    }
    expect(violations, isEmpty,
        reason: 'feature 间直接依赖会互相牵连（改 A 崩 B、测试漏测）。'
            '请经 shared/linkage 聚合服务或事件总线传递。');
  });

  test('R2 core 不得依赖 features（组合根白名单除外）', () {
    final violations = <String>[];
    for (final entry in imports.entries) {
      if (!entry.key.startsWith('core/')) continue;
      if (compositionRoots.contains(entry.key)) continue;
      for (final imp in entry.value) {
        if (imp.startsWith('features/')) {
          violations.add('${entry.key} → $imp');
        }
      }
    }
    expect(violations, isEmpty,
        reason: 'core 是通用底座，反向依赖 feature 会导致其无法独立复用与测试。'
            '跨模块 UI 聚合请放 shared/linkage（如 timer_bar_overlay）。');
  });

  test('R3 feature domain/data 不得依赖 presentation', () {
    final violations = <String>[];
    for (final entry in imports.entries) {
      final seg = entry.key.split('/');
      if (seg.first != 'features' || !['domain', 'data'].contains(seg[1])) continue;
      for (final imp in entry.value) {
        if (imp.contains('/presentation/')) {
          violations.add('${entry.key} → $imp');
        }
      }
    }
    expect(violations, isEmpty,
        reason: 'domain/data 是模块对外稳定层，依赖 UI 层会阻碍仓库级单测与后续插件化。');
  });

  test('R4 for 循环增量子句必须有副作用（防空增量静默死循环）', () {
    /// 去掉字符串字面量/注释，避免把 `for` 出现在文案或注释里误判。
    String strip(String src) {
      final out = StringBuffer();
      var i = 0;
      while (i < src.length) {
        final c = src[i];
        if (c == '/' && i + 1 < src.length && src[i + 1] == '/') {
          while (i < src.length && src[i] != '\n') {
            i++;
          }
          continue;
        }
        if (c == '/' && i + 1 < src.length && src[i + 1] == '*') {
          i += 2;
          while (i + 1 < src.length && !(src[i] == '*' && src[i + 1] == '/')) {
            i++;
          }
          i += 2;
          continue;
        }
        if (c == "'" || c == '"') {
          final triple = src.startsWith(c * 3, i);
          final q = triple ? c * 3 : c;
          i += q.length;
          while (i < src.length) {
            if (src[i] == r'\') {
              i += 2;
              continue;
            }
            if (src.startsWith(q, i)) {
              i += q.length;
              break;
            }
            i++;
          }
          out.write('S'); // 占位，保持结构
          continue;
        }
        out.write(c);
        i++;
      }
      return out.toString();
    }

    /// 取出 `for (...)` 的括号内容（含跨行），返回 [内容, 结束下标]。
    List<Object>? header(String s, int open) {
      var depth = 0;
      for (var i = open; i < s.length; i++) {
        if (s[i] == '(') depth++;
        if (s[i] == ')') {
          depth--;
          if (depth == 0) return [s.substring(open + 1, i), i];
        }
      }
      return null;
    }

    final violations = <String>[];
    for (final f in Directory(libDir).listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final rel = p.posix.joinAll(p.split(p.relative(f.path, from: libDir)));
      final src = strip(f.readAsStringSync());
      for (final m in RegExp(r'\bfor\s*\(').allMatches(src)) {
        final open = src.indexOf('(', m.start);
        final h = header(src, open);
        if (h == null) continue;
        final head = h[0] as String;
        final parts = <String>[];
        var depth = 0;
        var start = 0;
        for (var i = 0; i < head.length; i++) {
          final c = head[i];
          if (c == '(' || c == '[' || c == '{') depth++;
          if (c == ')' || c == ']' || c == '}') depth--;
          if (c == ';' && depth == 0) {
            parts.add(head.substring(start, i));
            start = i + 1;
          }
        }
        parts.add(head.substring(start));
        if (parts.length != 3) continue; // for-in / for (;;)
        final inc = parts[2].trim();
        if (inc.isEmpty) continue;
        // 裸标识符或数字字面量 = 无副作用 = 条件永远不变 → 死循环。
        if (RegExp(r'^[A-Za-z_$][\w$]*$').hasMatch(inc) ||
            RegExp(r'^[0-9]+$').hasMatch(inc)) {
          final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
          violations.add('$rel:$line  `for (...; ...; $inc )`');
        }
      }
    }
    expect(violations, isEmpty,
        reason: 'for 的增量子句若是裸变量/字面量（如把 `h++` 写成 `h`）就没有副作用，'
            '条件恒真 → 同帧同步死循环：单核 100%、列表无界增长直至 OOM，'
            '且不让出事件循环所以 --timeout 也杀不掉。'
            '请写 `i++` / `i += n`，构建列表优先用 List.generate。');
  });

  test('守护自身有效性：确认真实扫到了文件', () {
    expect(imports.length, greaterThan(20));
    expect(imports.keys.where((k) => k.startsWith('features/')).length,
        greaterThan(10));
  });
}
