import '../../../core/database/schema/media.dart';
import '../domain/media_item.dart';
import 'media_repository.dart';

/// 影音资料字典（`media_dict` · 原型 `m-mgr` 五类实体＝来源/分组/创作者/发行/标签）。
///
/// 三条硬口径：
/// - **在册口径同仓储唯一出口**（引用计数只数 `deleted_at IS NULL` 的条目，
///   软删行不算「仍在用」，也不阻碍改名——改名按人话范围联动）；
/// - 字典是「名册」不是「外键」：条目侧存的是名字文本，所以**改名要联动条目列**，
///   删除要先过引用守卫（有在用条目＝不许删，原型 §四「删除前引用守卫」）；
/// - 新条目录入时创作者/发行方/来源**自动登记**（`INSERT OR IGNORE` 幂等，
///   撞 `(kind,name)` 唯一索引即视为已在册）。
extension MediaDictRepo on MediaRepository {
  /// 五类 tab → 字典 kind 名（与批1 预置的 `source` 同族命名）。
  static const dictKinds = <String, String>{
    'source': 'source',
    'grp': 'group',
    'creator': 'creator',
    'pub': 'publisher',
    'tags': 'tag',
  };

  /// 字典 kind → 条目侧存名字的列（tag 走逗号列 LIKE，另算）。
  static const _itemColumn = <String, String>{
    'source': 'source',
    'group': 'grp',
    'creator': 'creator',
    'publisher': 'publisher',
  };

  /// 五类清单（名册 ∪ 条目实际值——字典没登记过但条目在用的名字也要看得见）：
  /// 每行＝名字＋在册条目引用数，按引用数倒序、同名并列按字典 sort。
  Future<List<({String name, int refCount})>> dictRows(String dictKind) async {
    final names = <String>{};
    final dict = await db.query(
      tMediaDict,
      columns: ['name'],
      where: 'kind = ?',
      whereArgs: [dictKind],
      orderBy: 'sort ASC, id ASC',
    );
    for (final r in dict) {
      names.add('${r['name']}');
    }
    final col = _itemColumn[dictKind];
    if (col != null) {
      final used = await db.rawQuery(
        'SELECT DISTINCT $col AS n FROM $tMediaItems '
        "WHERE $_liveItem AND $col IS NOT NULL AND $col <> ''",
      );
      for (final r in used) {
        final v = '${r['n']}';
        // 「未知」＝建条目时没填主创的占位值，不进管理器（否则清单全是噪声）
        if (v.isNotEmpty && v != '未知') names.add(v);
      }
    } else if (dictKind == 'tag') {
      final used = await db.rawQuery(
        'SELECT tags AS n FROM $tMediaItems '
        "WHERE $_liveItem AND tags IS NOT NULL AND tags <> ''",
      );
      for (final r in used) {
        for (final t in '${r['n']}'.split(',')) {
          final v = t.trim();
          if (v.isNotEmpty && v != '未知') names.add(v);
        }
      }
    }
    final out = <({String name, int refCount})>[];
    for (final n in names) {
      out.add((name: n, refCount: await refCountOf(dictKind, n)));
    }
    out.sort((a, b) {
      final byRef = b.refCount.compareTo(a.refCount);
      return byRef != 0 ? byRef : a.name.compareTo(b.name);
    });
    return out;
  }

  static const String _liveItem = 'deleted_at IS NULL';

  /// 该名字的在册条目引用数（tag 吃逗号列，值带逗号必须转义）。
  Future<int> refCountOf(String dictKind, String name) async {
    final col = _itemColumn[dictKind];
    if (col != null) {
      final rows = await db.rawQuery(
        'SELECT COUNT(*) AS n FROM $tMediaItems '
        'WHERE $_liveItem AND $col = ?',
        [name],
      );
      return (rows.first['n'] as num?)?.toInt() ?? 0;
    }
    final rows = await db.rawQuery(
      "SELECT COUNT(*) AS n FROM $tMediaItems "
      "WHERE $_liveItem AND (',' || REPLACE(tags, ' ', '') || ',') "
      "LIKE ?",
      ['%,${name.replaceAll(',', '')},%'],
    );
    return (rows.first['n'] as num?)?.toInt() ?? 0;
  }

  /// 反查同值条目（跨 kind：管理器点行＝架面按关键词落点，口径与芯片反查一致）。
  Future<List<String>> itemIdsOf(String dictKind, String name) async {
    final col = _itemColumn[dictKind];
    final rows = col != null
        ? await db.rawQuery(
            'SELECT id FROM $tMediaItems WHERE $_liveItem AND $col = ? '
            'ORDER BY COALESCE(last_activity_at, created_at) DESC',
            [name],
          )
        : await db.rawQuery(
            "SELECT id FROM $tMediaItems WHERE $_liveItem AND "
            "(',' || REPLACE(tags, ' ', '') || ',') LIKE ? "
            'ORDER BY COALESCE(last_activity_at, created_at) DESC',
            ['%,${name.replaceAll(',', '')},%'],
          );
    return rows.map((r) => '${r['id']}').toList();
  }

  /// 登记一个名字（幂等：撞 `(kind,name)` 唯一索引即视为已在册）；返回是否新建。
  Future<bool> ensureDict(String dictKind, String name) async {
    final v = name.trim();
    if (v.isEmpty || v == '未知') return false;
    final hit = await db.query(
      tMediaDict,
      columns: ['id'],
      where: 'kind = ? AND name = ?',
      whereArgs: [dictKind, v],
      limit: 1,
    );
    if (hit.isNotEmpty) return false;
    await db.rawInsert(
      'INSERT OR IGNORE INTO $tMediaDict(kind,name,sort) '
      'SELECT ?, ?, COALESCE(MAX(sort),0)+1 FROM $tMediaDict WHERE kind = ?',
      [dictKind, v, dictKind],
    );
    return true;
  }

  /// 改名：字典行 + 条目侧列同场联动（标签走逗号列逐条重写）。
  /// 返回被联动的条目数；字典没这条记录也算改名成功（名册可以缺，条目不能失联）。
  Future<int> renameDict(String dictKind, String from, String to) async {
    final t = to.trim();
    if (t.isEmpty || t == from) return 0;
    await db.transaction((txn) async {
      // 目标名已在册＝改名变合并：旧行直接删，不 UPDATE（撞 (kind,name) 唯一索引会炸整笔事务）。
      final hit = await txn.rawQuery(
        'SELECT id FROM $tMediaDict WHERE kind = ? AND name = ? LIMIT 1',
        [dictKind, t],
      );
      if (hit.isEmpty) {
        await txn.rawUpdate(
          'UPDATE $tMediaDict SET name = ? WHERE kind = ? AND name = ?',
          [t, dictKind, from],
        );
      }
      await txn.rawDelete(
        'DELETE FROM $tMediaDict WHERE kind = ? AND name = ?',
        [dictKind, from],
      );
      final col = _itemColumn[dictKind];
      if (col != null) {
        await txn.rawUpdate(
          'UPDATE $tMediaItems SET $col = ?, updated_at = ? '
          'WHERE $_liveItem AND $col = ?',
          [t, DateTime.now().millisecondsSinceEpoch, from],
        );
      } else {
        final rows = await txn.rawQuery(
          "SELECT id, tags FROM $tMediaItems WHERE $_liveItem "
          "AND (',' || REPLACE(tags, ' ', '') || ',') LIKE ?",
          ['%,${from.replaceAll(',', '')},%'],
        );
        for (final r in rows) {
          final parts = '${r['tags']}'
              .split(',')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .map((s) => s == from ? t : s)
              // 改名撞已有标签＝去重，不留下两条同名
              .toList();
          final uniq = <String>{...parts}.join(',');
          await txn.update(
            tMediaItems,
            {
              'tags': uniq,
              'updated_at': DateTime.now().millisecondsSinceEpoch,
            },
            where: 'id = ?',
            whereArgs: [r['id']],
          );
        }
      }
    });
    return refCountOf(dictKind, t);
  }

  /// 删除字典项（**引用守卫**）：仍有在册条目在用＝返回 false 不动库；
  /// 名册里根本没有这个名字＝同样返回 false（不谎报「已删除」）；
  /// 只有真空闲且真在名册里的名字才摘得掉（条目侧本来就没存 id，无需清理）。
  Future<bool> deleteDict(String dictKind, String name) async {
    if (await refCountOf(dictKind, name) > 0) return false;
    final n = await db.delete(
      tMediaDict,
      where: 'kind = ? AND name = ?',
      whereArgs: [dictKind, name],
    );
    return n > 0;
  }

  /// 新条目落库后的名册自动登记（计划 §五 批2「创作者/发行方自动入库」）：
  /// 三个名字各归各类，空值与「未知」不进名册（不污染管理器清单）。
  Future<void> registerItemNames(MediaItem item) async {
    await ensureDict('creator', item.creator);
    await ensureDict('publisher', item.publisher ?? '');
    await ensureDict('source', item.source ?? '');
    await ensureDict('group', item.grp ?? '');
    for (final t in item.tags) {
      await ensureDict('tag', t);
    }
  }
}
