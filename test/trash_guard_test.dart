import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// V1.60 全局回收站 E 批红线守护（六类纳入党表）：
/// **任何在册读取**都必须带 `deleted_at` 谓词，漏一处就是「删了还在」或「恢复出幽灵」。
///
/// 判定形状（与既有 `todo_trash_guard_test` 同族，但按语句取数，不按单行）：
/// · 命中六张表名的位置，向前找最近的 `db.query( / db.rawQuery( / db.delete( / db.update( / db.insert(`
///   作为语句起点，向后取到该调用的收尾，得到**整条语句**；
/// · 读语句（query/rawQuery）必须出现 `deleted_at`，否则要么列红灯、要么进白名单；
/// · 写语句（insert/update/delete）按主键或整表操作，不要求在册谓词，直接放过；
/// · 白名单条目必须仍然命中，防止「文件改名后守护悄悄空转」。
///
/// 唯一例外说明写在 [whitelist] 里，动到相关取数时同步改这里，别静默绕过。
void main() {
  const libDir = 'lib';

  /// 六类纳入党表（表常量名 + 裸表名两种写法都认）。
  const tables = {
    'tTodos': 'todos',
    'tNotes': 'notes',
    'tHabits': 'habits',
    'tBooks': 'books',
    'tBookQuotes': 'book_quotes',
    'tBookLists': 'book_lists',
  };

  /// 允许「读语句不带 deleted_at」的位置 → 理由（必须仍然成立）。
  const whitelist = <String, String>{
    // 全量取数入口：调用侧按 isDeleted 过滤，回收站与判孤需要看见软删行。
    'features/read/data/read_repository.dart':
        '枢纽 allBooks/bookById/allQuotes 取全量（回收站判孤与派生统计按 isDeleted 自筛）',
    // 回收站自己的取数口：走各模块 DAO，不直碰表名（直碰就该报红，故不列白名单）。
    'features/journal/data/note_dao.dart': 'DAO 内部：trash()/purge 系列按 deleted_at 分流',
    'features/todo/data/todo_dao.dart': 'DAO 内部：trashed()/purgeExpired 系列按 deleted_at 分流',
    'features/habit/data/habit_repository.dart': 'DAO 内部：在册读带谓词，垃圾箱读取反',
    'features/read/data/read_repo_book.dart': '书籍域群：在册与垃圾箱两套谓词都在本文件内',
    'features/read/data/read_repo_quote.dart': '摘录域群：判重/在册/垃圾箱三套谓词都在本文件内',
    'features/read/data/read_repo_list.dart': '书单域群：allLists 在枢纽层已过滤，此处取反谓词',
    'features/read/data/read_repo_import.dart': '导入按 id/整表重写，不读在册集',
    'features/read/data/read_repo_export.dart': '整包备份含垃圾箱行（随到随走口径）',
    'features/read/data/read_repo_dict.dart': '字典计数在 rawQuery 串里已带谓词',
    'features/read/data/xray/xray_dao.dart': 'X-Ray 按书 id 定位与孤儿清理，不按在册集',
    'core/database/schema.dart': '建表 DDL（deleted_at 列定义处）',
    'core/database/schema/core.dart': '迁移 ALTER 语句（加列，不选数据）',
    'core/database/schema/read.dart': '建表与局部唯一索引定义',
    'core/media/media_usage_scanner.dart':
        '图片占用扫描按 notes.id 反查附件引用，与在册/垃圾箱无关（附件行随笔记真删级联回收）',
    'features/goals/data/goals_repository.dart': 'KR 汇聚按表计数，已带谓词（守护防回退）',
  };

  bool isComment(String line) {
    final t = line.trim();
    return t.startsWith('//') || t.startsWith('///') || t.startsWith('*');
  }

  RegExp ref(String constName, String rawName) =>
      RegExp('''(?:$constName|['"]$rawName['"])''');

  /// 命中位置 → (相对路径, 语句文本)。
  List<(String, int, String, bool)> readSites() {
    final out = <(String, int, String, bool)>[];
    for (final f in Directory(libDir)
        .listSync(recursive: true)
        .whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final rel = p.posix.joinAll(p.split(p.relative(f.path, from: libDir)));
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (isComment(line)) continue;
        String? table;
        for (final e in tables.entries) {
          if (ref(e.key, e.value).hasMatch(line)) {
            table = e.key;
            break;
          }
        }
        if (table == null) continue;
        // 向前找语句起点（最多 8 行），再向后收 10 行＝语句体。
        var start = i;
        for (var k = i; k > i - 8 && k >= 0; k--) {
          if (RegExp(r'\b(?:query|rawQuery|delete|update|insert)\(')
              .hasMatch(lines[k])) {
            start = k;
            break;
          }
        }
        final stmt = lines.sublist(start, (i + 10).clamp(0, lines.length)).join('\n');
        final isRead = RegExp(r'\b(?:query|rawQuery)\s*\(').hasMatch(stmt) ||
            RegExp(r'SELECT\b').hasMatch(stmt);
        out.add((rel, start + 1, stmt, isRead));
      }
    }
    return out;
  }

  test('六表在册读取：白名单外一律带 deleted_at 谓词', () {
    final leaked = <String>[];
    for (final (rel, ln, stmt, isRead) in readSites()) {
      if (!isRead) continue;
      if (whitelist.containsKey(rel)) continue;
      if (stmt.contains('deleted_at')) continue;
      leaked.add('$rel:$ln');
    }
    expect(leaked, isEmpty,
        reason: '以下位置直碰六类纳入党表却没有软删谓词（垃圾箱条目会漏进在册读数）：\n'
            '${leaked.join('\n')}\n'
            '补 deleted_at IS NULL，或把理由写进本守护的白名单。');
  });

  test('白名单条目仍然成立（守护不得空转）', () {
    final hitFiles = {for (final (rel, _, _, _) in readSites()) rel};
    final stale = whitelist.keys.where((k) => !hitFiles.contains(k)).toList();
    expect(stale, isEmpty,
        reason: '白名单里的文件已不再直碰这六张表，请删掉该条目：${stale.join(', ')}');
  });

  test('回收站入口位置钉死（2026-10-04 产品「挪放到我的页面，与日志管理同级」）', () {
    final mine = File('lib/features/settings/presentation/settings_page.dart')
        .readAsStringSync();
    final recmg =
        File('lib/features/settings/presentation/recmg_page.dart')
            .readAsStringSync();
    expect(mine.contains("ValueKey('entry-trash')"), isTrue,
        reason: '「我的」页缺同级回收站入口行');
    expect(mine.contains('六类删除内容 · 保留期内可恢复'), isTrue,
        reason: '入口副标题与屏内不一致');
    expect(mine.contains("'/settings/trash'"), isTrue,
        reason: '入口未指向统一屏');
    expect(recmg.contains("'/settings/trash'"), isFalse,
        reason: '记录管理只留「自动清理」档位，设置侧入口不得有两处（原型 p-sub-recmg 同步撤行）');
  });

  test('六类垃圾箱五件套齐备（软删/列表/恢复/彻底删除/到期清理）', () {
    final src = {
      'features/todo/data/todo_dao.dart':
          ['softRemove', 'trashed', 'restore', 'purge', 'purgeExpired'],
      'features/journal/data/note_dao.dart':
          ['softDelete', 'trash', 'restore', 'purge', 'purgeExpired'],
      'features/habit/data/habit_repository.dart': [
        'deleteHabit',
        'trashedHabits',
        'restoreHabit',
        'purgeHabit',
        'purgeExpiredHabits'
      ],
      'features/read/data/read_repo_book.dart': [
        'softDeleteBooks',
        'trashedBooks',
        'restoreBook',
        'purgeBook',
        'purgeExpiredTrashBooks'
      ],
      'features/read/data/read_repo_quote.dart': [
        'softDeleteQuote',
        'trashedQuotes',
        'restoreQuote',
        'purgeQuote',
        'purgeExpiredTrashQuotes'
      ],
      'features/read/data/read_repo_list.dart': [
        'softDeleteList',
        'trashedLists',
        'restoreList',
        'purgeList',
        'purgeExpiredTrashLists'
      ],
    };
    for (final e in src.entries) {
      final text = File(p.join(libDir, e.key)).readAsStringSync();
      for (final m in e.value) {
        expect(text.contains('$m('), isTrue,
            reason: '${e.key} 缺垃圾箱能力出口：$m');
      }
    }
  });

  test('冷启动到期清理必须走六表出口（不得退回仅待办）', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(main.contains('purgeExpiredByTable'), isTrue,
        reason: '启动清理应经 TrashRepository 六表出口，不是单表 purgeExpired');
    final repo = File(p.join(libDir, 'shared/trash/trash_repository.dart'))
        .readAsStringSync();
    for (final m in [
      'purgeExpired(',
      'purgeExpiredHabits(',
      'purgeExpiredTrashBooks(',
      'purgeExpiredTrashQuotes(',
      'purgeExpiredTrashLists('
    ]) {
      expect(repo.contains(m), isTrue, reason: '到期清理漏表：$m');
    }
  });
}
