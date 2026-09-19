import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// 架构守护测试（《开发计划书》§2.1 模块解耦规范的可执行化）。
///
/// 规则：
/// R1 `features/<mod>/**` 不得 import 其他 feature（跨模块只经 shared/linkage 或事件总线）。
/// R2 `core/**` 不得 import `features/**`（组合根白名单除外）。
/// R3 feature 的 domain/data 层不得 import 任何 presentation（模型/仓库层纯净，可单测）。
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

  test('守护自身有效性：确认真实扫到了文件', () {
    expect(imports.length, greaterThan(20));
    expect(imports.keys.where((k) => k.startsWith('features/')).length,
        greaterThan(10));
  });
}
