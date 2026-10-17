import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// X-Ray 四表直碰守护（需求 V1.54 · 批1d 红线）
///
/// 照 E 批 `todo_trash_guard_test.dart` 的先例：**扫源码**而不是靠运行时数据——
/// 「只许 DAO 直碰表」这种约定，一旦有人 copy 一句 SQL 就静默失守，跑多少用例都测不出来。
///
/// 三条判定：
/// 1. 白名单外，`lib/**` 里不许出现四表的表名（常量 `tXray*` 或字面量 `'xray_...'`）；
/// 2. `books.md5` 列的读写也只许 DAO（md5 是 X-Ray 的归属键，别处绕过去就会与索引脱钩）；
/// 3. 白名单本身要自检：登记的文件若已不再直碰，就是**失效白名单**——它会掩护下一个抄 SQL 的人。
void main() {
  const libDir = 'lib';
  const tables = ['xray_task', 'xray_entity', 'xray_mention', 'xray_userdict'];

  // 白名单：文件 → 允许直碰的理由（失效即红）
  //   注意：**调度器不在名单里**——它只能经 XrayDao 说话，直碰表就该红。
  const whitelist = <String, String>{
    'features/read/data/xray/xray_dao.dart': '四表唯一出口',
    'core/database/schema/xray.dart': '建表 DDL 与迁移（表名定义处）',
    'core/database/schema.dart': 'G5 中枢转发（只转发不查询）',
    // 生命周期批（`333a22f`·轮7 拍板 F1/a-b 分类）的两处有意直碰，补登记归因：
    'core/backup/backup_service.dart':
        'kRegenerableExcluded 排除表名清单（只列名零 SQL·恢复后按 schema 建空表）',
    'features/read/data/read_repo_book.dart':
        'purgeBook 连带清 a 类派生数据 + md5 孤行判定（xray_lifecycle_test 钉死）',
    // B-4 数据库概览：人话词表以表名字面量为键（纯展示词条，零 SQL），
    // 与 db_overview_guard_test 的全覆盖/防残留守护配套。
    'core/backup/db_overview.dart': 'B-4 人话表名词条（不执行 SQL）',
  };

  // 判定式由 `tables` 现拼：以后加第五张表若忘了登记这里，守护会照旧漏网——
  // 反过来，表名列表就是唯一事实源，不存在「正则和清单两张皮」。
  final tableRe = RegExp(
      'tXray[A-Z]|\\b(${tables.join('|')})\\b');
  final hits = <(String, int, String)>[];
  for (final f in Directory(libDir).listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('.dart')) continue;
    final rel = f.path.replaceAll('\\', '/').replaceFirst('lib/', '');
    final lines = f.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final raw = lines[i];
      final line = raw.trim();
      if (line.startsWith('//') || line.startsWith('///')) continue;
      // 只认「引用了四表」的形状：tXray* 常量或 xray_* 字面表名。
      // （别再加「行里含引号」这类前置条件——上一版就是这么把中枢的转发行整批漏掉的，
      //  而漏网不会报错，只会让守护假装在工作。）
      if (tableRe.hasMatch(line)) {
        hits.add((rel, i + 1, line));
      }
    }
  }

  test('四表只许 DAO 出口：白名单外一律红', () {
    final leaked = [
      for (final (rel, ln, line) in hits)
        if (!whitelist.containsKey(rel) && !rel.startsWith('core/database/'))
          '$rel:$ln  $line',
    ];
    expect(leaked, isEmpty,
        reason: 'X-Ray 四表要在别处用，请给 XrayDao 加方法；'
            'copy SQL 会让「同 MD5 共享索引」的归属键散落各处（§13）。');
  });

  test('白名单不失效：登记的每个文件必须仍在直碰', () {
    final stale = <String>[];
    for (final rel in whitelist.keys) {
      final path = 'lib/$rel';
      if (!File(path).existsSync()) {
        stale.add('$rel（文件已不存在·登记掩护空气）');
        continue;
      }
      if (!hits.any((h) => h.$1 == rel)) {
        stale.add('$rel（已不再直碰四表·该删登记）');
      }
    }
    expect(stale, isEmpty,
        reason: '失效白名单比漏网更阴：它让守护看起来还在工作。');
  });

  test('守护自证：确实扫到了出口文件，不然大片空转', () {
    expect(hits, isNotEmpty, reason: '一条都没扫到＝正则或路径坏了，本守护等于没跑');
    final files = hits.map((h) => h.$1).toSet();
    expect(files, contains('features/read/data/xray/xray_dao.dart'),
        reason: 'DAO 至少要被扫到；扫不到说明出口漂移了');
    expect(files.length, lessThanOrEqualTo(whitelist.length),
        reason: '命中文件数超过白名单，必有未登记处直碰了表');
  });

  test('books.md5 的列读写收口在 DAO（归属键不许散落）', () {
    final offenders = <String>[];
    for (final f in Directory(libDir).listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final rel = f.path.replaceAll('\\', '/').replaceFirst('lib/', '');
      if (rel == 'features/read/data/xray/xray_dao.dart') continue;
      if (rel.startsWith('core/database/')) continue;
      // 生命周期批（333a22f）拍板口径：purgeBook 的「同 md5 是否仍有他书引用」
      // 孤行判定归 books 仓储（XrayDao 不拥有 books 表），md5 在此是入参不是散落查询。
      if (rel == 'features/read/data/read_repo_book.dart') continue;
      final lines = f.readAsLinesSync()
        ..removeWhere((l) => l.trim().startsWith('//'));
      // 判定用「包含」而不是「正则形状」：形状正则容易写成漏网版（我上一版就是），
      // 包含式的误报会立刻显形，漏报则不会——守护要选后者那种失败方式。
      if (lines.any((l) => l.contains("'md5'") || l.contains('"md5"'))) {
        offenders.add(rel);
      }
    }
    expect(offenders, isEmpty,
        reason: '要读同指纹架位请调 XrayDao.bookIdsWithMd5()，别自己拼 md5 查询'
            '（§13 归属键散落就会与索引脱钩）');
  });
}
