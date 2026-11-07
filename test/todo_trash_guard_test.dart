import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// V1.57 E 批红线守护（待办垃圾箱）：todos 同表混放软删条目后，
/// **任何**在册读取都必须带 `deleted_at IS NULL`，漏一处就是「删掉的待办还在提醒/还计数」。
///
/// 口径：
/// · 唯一合法出口 = `TodoDao`（其内部谓词由下面第二条用例钉死）；
/// · DAO 之外直碰表名的文件进白名单（建表/迁移/纯 insert），白名单条目失效同样报红
///   ——防止「某文件改名后守护悄悄空转」；
/// · 其余命中行必须含 `deleted_at IS NULL`，否则列进红灯清单。
void main() {
  const libDir = 'lib';

  /// 表名/常量命中模式（`DbSchema.tTodos` / `$tTodos` / 裸 `'todos'` 三种写法都算）。
  final tableRef = RegExp(r'''tTodos|'todos'|"todos"''');

  /// 白名单：文件 → 允许直碰表名的理由（必须仍成立，否则用例尾部的失效检查报红）。
  const whitelist = <String, String>{
    'features/todo/data/todo_dao.dart': '唯一 DAO：谓词在本文件内统一出口',
    'core/database/schema.dart': '建表 DDL（deleted_at 列定义处）',
    'core/database/schema/core.dart': '迁移 ALTER 语句（加列，不选数据）',
    'features/read/data/read_repo_quote.dart': '仅 insert 生成引用待办，不读在册集',
    // 他批遗留红灯归位（批2a 六类回归跑出，肇事提交＝B-4 `8eee214`，全量基线当时未重跑）：
    // 这里是「表名 → 人话标签」的展示映射与逐表 COUNT(*)（存储口径，软删行也占空间），
    // 不读在册集；真正取数在 rawQuery('... FROM "$name"') 的动态表名上，本守护按行扫不到。
    'core/backup/db_overview.dart':
        'B-4 数据库概览：表→模块词条映射＋按表数行（含软删行的存储口径），不读在册集',
  };

  bool isComment(String line) {
    final t = line.trim();
    return t.startsWith('//') || t.startsWith('///') || t.startsWith('*');
  }

  /// 清单 D-2：原本 `hits()` 被两条断言各调一次＝同一棵 lib 树递归扫两遍。
  /// 改成先一次遍历收全「命中行」，两条断言各自过滤——扫描次数 2→1，判定结果不变。
  final hitLines = <(String, int, String)>[];
  List<(String, int, String)> allHits() {
    if (hitLines.isNotEmpty) return hitLines;
    for (final f in Directory(libDir).listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final rel = p.posix.joinAll(p.split(p.relative(f.path, from: libDir)));
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (isComment(line)) continue;
        if (!tableRef.hasMatch(line)) continue;
        hitLines.add((rel, i + 1, line));
      }
    }
    return hitLines;
  }

  List<String> hits(bool Function(String rel, String line) pred) => [
        for (final (rel, ln, line) in allHits())
          if (pred(rel, line)) '$rel:$ln  ${line.trim()}',
      ];

  test('todos 表裸查询：白名单外一律必须带 deleted_at IS NULL', () {
    final leaked = hits(
      (rel, line) =>
          !whitelist.containsKey(rel) && !line.contains('deleted_at IS NULL'),
    );
    expect(
        leaked,
        isEmpty,
        reason: '以下位置直碰 todos 表却没有软删谓词（垃圾箱条目会漏进在册读数）：\n'
            '${leaked.join('\n')}\n'
            '改走 TodoDao 统一出口，或在本行查询里补 deleted_at IS NULL。');
  });

  test('白名单条目仍然成立（守护不得空转）', () {
    final stillHit = hits((rel, _) => whitelist.containsKey(rel)).map((h) => h.split(':').first).toSet();
    final stale = whitelist.keys.where((k) => !stillHit.contains(k)).toList();
    expect(stale, isEmpty,
        reason: '白名单里的文件已不再直碰 todos 表，请删掉该条目：${stale.join(', ')}');
  });

  test('DAO 内部：在册读取带谓词 · 垃圾箱五件套齐备', () {
    final src = File(p.join(libDir, 'features/todo/data/todo_dao.dart')).readAsStringSync();
    // list() / countOverdue() 是在册读数的两个出口，都必须过滤软删行。
    final listBody = src.substring(src.indexOf('Future<List<Todo>> list()'),
        src.indexOf('Future<int> _maxSort()'));
    expect(listBody.contains('deleted_at IS NULL'), isTrue,
        reason: 'list() 未过滤垃圾箱条目');
    final overdue = src.substring(src.indexOf('Future<int> countOverdue()'));
    expect(overdue.contains('deleted_at IS NULL'), isTrue,
        reason: 'countOverdue() 未过滤垃圾箱条目');
    for (final m in ['softRemove', 'trashed', 'restore', 'purge', 'purgeExpired']) {
      expect(src.contains('Future<') && src.contains('$m('), isTrue,
          reason: 'DAO 缺垃圾箱能力出口：$m');
    }
    // trashed() 取反谓词：只回垃圾箱里的条目。
    expect(src.contains("where: 'deleted_at IS NOT NULL'"), isTrue,
        reason: 'trashed() 应以 deleted_at IS NOT NULL 为谓词');
  });
}
