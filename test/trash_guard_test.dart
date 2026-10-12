import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/shared/trash/trash_models.dart';
import 'package:lifeharness/shared/trash/trash_specs.dart';
import 'package:path/path.dart' as p;

/// V1.60 全局回收站 E 批红线守护（各类纳入党表 · V1.61 起含物品共七表）：
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

  /// 纳入党表（表常量名 + 裸表名两种写法都认）。
  const tables = {
    'tTodos': 'todos',
    'tNotes': 'notes',
    'tHabits': 'habits',
    'tBooks': 'books',
    'tBookQuotes': 'book_quotes',
    'tBookLists': 'book_lists',
    'tItemProfiles': 'item_profiles',
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
    // 迁移 34 的 X-Ray 孤儿清理：子查询里的 books 刻意**含**垃圾箱软删书，
    // 这样派生数据能随书恢复回来（源码注释原话「垃圾箱软删书的 md5 仍在 books 表 → 保留」）。
    'core/database/schema/xray.dart':
        '迁移 34 孤儿清理：按 md5 判存在，刻意含软删书以保派生数据可恢复',
    'core/media/media_usage_scanner.dart':
        '图片占用扫描按 notes.id 反查附件引用，与在册/垃圾箱无关（附件行随笔记真删级联回收）',
    'features/goals/data/goals_repository.dart': 'KR 汇聚按表计数，已带谓词（守护防回退）',
    // 物品线：主读 `loadAll` 的谓词由下面「物品主读谓词正钉」单独钉死；此处进白名单
    // 只为放过**刻意含回收站档案**的那条存在性检查——升级建档候选要排除「已产过档」的流水，
    // 档案在回收站期间这个事实依然成立，若按在册过滤会让同一笔流水再建一份档。
    'features/items/data/items_repository.dart':
        'DAO 内部：loadAll 带在册谓词（另有正钉）；垃圾箱读反谓词；候选流水的存在性检查刻意含软删档案',
  };

  bool isComment(String line) {
    final t = line.trim();
    return t.startsWith('//') || t.startsWith('///') || t.startsWith('*');
  }

  RegExp ref(String constName, String rawName) => RegExp(
      // 三种写法都要认：常量名、带引号的裸表名、**SQL 字符串里的裸表名**
      // （`FROM todos WHERE ...`）。第三种是变异刀5 抓出的漏网口——
      // 只认前两种时，把谓词从这类语句里摘掉守护不会红。
      '''(?:$constName|['"]$rawName['"]|\\b(?:FROM|UPDATE|INTO|JOIN)\\s+$rawName\\b)''');

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
        reason: '以下位置直碰纳入党表却没有软删谓词（垃圾箱条目会漏进在册读数）：\n'
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
    expect(mine.contains('九类删除内容 · 保留期内可恢复'), isTrue,
        reason: '入口副标题与屏内不一致（思维导图批1 导图入册后为九类）');
    expect(mine.contains("'/settings/trash'"), isTrue,
        reason: '入口未指向统一屏');
    expect(recmg.contains("'/settings/trash'"), isFalse,
        reason: '记录管理只留「自动清理」档位，设置侧入口不得有两处（原型 p-sub-recmg 同步撤行）');
  });

  test('各类垃圾箱五件套齐备（软删/列表/恢复/彻底删除/到期清理）', () {
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
      'features/items/data/items_repository.dart': [
        'softDeleteItem',
        'trashedItems',
        'restoreItem',
        'purgeItem',
        'purgeExpiredItems'
      ],
      // 思维导图批1（2026-10-12）·导图第九类：五件套同口径钉死。
      'features/mindmap/data/mindmap_dao.dart': [
        'trashMap',
        'trashed',
        'restoreMap',
        'purgeMap',
        'purgeExpired'
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

  test('冷启动到期清理必须走注册表逐类出口（不得退回仅待办）', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(main.contains('purgeExpiredByTable'), isTrue,
        reason: '启动清理应经 TrashRepository 逐类出口，不是单表 purgeExpired');
    // V1.61 起逐类出口登记在注册表里，不再写死在 repository。
    final specs =
        File(p.join(libDir, 'shared/trash/trash_specs.dart')).readAsStringSync();
    for (final m in [
      'purgeExpired(',
      'purgeExpiredHabits(',
      'purgeExpiredTrashBooks(',
      'purgeExpiredTrashQuotes(',
      'purgeExpiredTrashLists('
    ]) {
      expect(specs.contains(m), isTrue, reason: '到期清理漏表：$m');
    }
    // 编排处必须遍历注册表，而不是自己再列一遍表（防两处清单分叉）。
    final repo = File(p.join(libDir, 'shared/trash/trash_repository.dart'))
        .readAsStringSync();
    expect(repo.contains('trashPurgeExpired('), isTrue,
        reason: 'repository 的到期清理应委托注册表出口 trashPurgeExpired');
  });

  test('物品主读必须带在册谓词（白名单是文件级，主路径单独钉死）', () {
    final repo = File(p.join(libDir, 'features/items/data/items_repository.dart'))
        .readAsStringSync();
    // 断代码行原文，不断注释：loadAll 取档案的那条 query 必须带 deleted_at IS NULL。
    expect(
        repo.contains("where: 'deleted_at IS NULL', orderBy: 'billing DESC, id ASC'"),
        isTrue,
        reason: '物品列表/统计/每日成本共用 loadAll——漏谓词＝回收站里的档案还在计费');
    // 彻底删除不得顺手删记账流水（拍板②）：purgeItem 里不许出现流水表写入。
    // 作用域＝purgeItem 到它的下一个成员声明为止（按顺序扫，别圈进别的方法）。
    final start = repo.indexOf('Future<void> purgeItem');
    final next = [
      for (final i in [
        repo.indexOf('Future<', start + 1),
      ])
        if (i > start) i
    ];
    expect(next, isNotEmpty, reason: 'purgeItem 之后应还有别的成员声明，作用域取法要改');
    final purge = repo.substring(start, next.reduce((a, b) => a < b ? a : b));
    expect(purge.contains('tLedgerTxns'), isFalse,
        reason: '物品彻底删除只清档案与两张子表，记账流水保留（V1.61 拍板②）');
  });

  // ================= V1.61 登记式接口：抽掉编译期护栏，这里补回硬闸 =================

  test('每个回收站类别都在注册表登记一次且仅一次', () {
    final kinds = trashKindSpecs.map((s) => s.kind).toList();
    final dup = kinds
        .where((k) => kinds.where((o) => o == k).length > 1)
        .toSet()
        .toList();
    expect(dup, isEmpty, reason: '同一类登记了多次（读源/恢复会跑两遍）：$dup');
    final missing = TrashKind.values.where((k) => !kinds.contains(k)).toList();
    final extra = kinds.where((k) => !TrashKind.values.contains(k)).toList();
    expect(missing, isEmpty,
        reason: '新增类别漏登记＝回收站看不见它、恢复与到期清理都不会碰它：$missing');
    expect(extra, isEmpty, reason: '注册表里有枚举已不存在的类别：$extra');
    expect(trashKindSpecs.length, TrashKind.values.length,
        reason: '登记项数量与类别数不等，逐条查重复或漏项');
  });

  test('到期清理顺序＝书籍先于划线书摘与书单（防刚置孤的行本轮即被清走）', () {
    final idx = <TrashKind, int>{
      for (var i = 0; i < trashKindSpecs.length; i++)
        trashKindSpecs[i].kind: i
    };
    expect(idx[TrashKind.book]!, lessThan(idx[TrashKind.quote]!),
        reason: '书行必须先清，否则其摘录在同一轮里被当过期清走而无人判孤');
    expect(idx[TrashKind.book]!, lessThan(idx[TrashKind.list]!),
        reason: '书行必须先于书单（书单成员含书，顺序倒了会留下指向空档案的成员行）');
    // 顺序是**登记顺序**说了算，消费侧不得自己重排（否则上面的断言就成了摆设）。
    final specsSrc =
        File(p.join(libDir, 'shared/trash/trash_specs.dart')).readAsStringSync();
    expect(specsSrc.contains('for (final s in trashKindSpecs)'), isTrue,
        reason: '到期清理应直接遍历注册表顺序');
    for (final reorder in [
      'trashKindSpecs.reversed',
      'trashKindSpecs.toList()..sort',
      '.sorted('
    ]) {
      expect(specsSrc.contains(reorder), isFalse,
          reason: '消费侧出现重排（$reorder）＝登记顺序的语义被绕开');
    }
  });

  test('回收站分派处不得再按类别分支（注册表是唯一接线点）', () {
    for (final rel in [
      'shared/trash/trash_repository.dart',
      'shared/trash/trash_providers.dart',
    ]) {
      final lines = File(p.join(libDir, rel)).readAsLinesSync();
      final offenders = <String>[];
      for (var i = 0; i < lines.length; i++) {
        final t = lines[i].trim();
        if (t.startsWith('//') || t.startsWith('///')) continue; // 注释不算证据
        if (t.contains('switch (') || t.contains('switch(') ||
            t.contains('case TrashKind.')) {
          offenders.add('$rel:${i + 1}  $t');
        }
      }
      expect(offenders, isEmpty,
          reason: '分派处出现按类别分支，绕开了注册表（加一类就会漏这里）：\n'
              '${offenders.join('\n')}');
    }
  });

  test('每类登记项自带写信号与刷新分组（阅读线共用一路 tick 不重复刷）', () {
    for (final s in trashKindSpecs) {
      expect(s.signals, isNotEmpty,
          reason: '${s.kind.name} 没声明源模块写信号＝回收站进屏不重取的老坑会复发');
    }
    final readGroup =
        trashKindSpecs.where((s) => s.refreshGroup == 'read').map((s) => s.kind).toSet();
    expect(readGroup,
        containsAll(<TrashKind>{TrashKind.book, TrashKind.quote, TrashKind.list}),
        reason: '书·划线·书单应归同一刷新组（共用 readTick，一次动作只刷一遍）');
    expect(trashSourceSignals.length,
        trashSourceSignals.toSet().length,
        reason: '监听信号去重后才接，重复 listen 会让回收站一次变化重取多次');
  });
}
