import 'package:sqflite/sqflite.dart';

import '../../core/database/app_database.dart';
import '../../core/database/schema.dart';

/// NFC 卡片 ⇄ 时间/阅读 挂载出口（批1 · 冻结档 §6.1 · 守 R1）。
///
/// `features/nfc/**` **禁止 import 任何 `features/calendar/**`、`features/read/**`**
/// （架构守护 `architecture_test` R1）；跨模块读数据统一经本文件的函数出口，
/// 与 `mindmap_mounts` / `read_mounts` 同惯例。
///
/// **批1 只提供两个读取转发口**（目标选择器的「计时分类」「阅读书目」两区块要的数据）；
/// 两个 toggle 转发口（`nfcToggleTimer`／`nfcToggleRead`）属**批2 触发链**，
/// 届时按 C32「内部自取 ref/host、不接受外部传 context」实现，先例＝`sys_pill_sync.dart:102`。

/// 一个可绑定的计时分类（C41：`timer.cat` 与 `read.book` **逐字节同构**——
/// 都只存 id、名字实时查；卡片表**不存目标名**，B23 同名分类按 id 区分）。
class NfcCategoryOption {
  const NfcCategoryOption({
    required this.id,
    required this.name,
    required this.path,
    this.parentId,
  });

  final int id;
  final String name;

  /// 父级路径（B23：多级分类显示「工作 › 开会」以免歧义；一级为空）。
  final String path;

  final int? parentId;
}

/// 时间分类列表（目标选择器「计时分类」区块）。
///
/// 口径：一次读 `categories` 全表后在内存拼路径（`parent_id` 只一级，
/// 但按任意深度拼更稳）；排序照 `CategoryDao.list()` 同款
/// （一级在前 → `sort` → `id`）。
Future<List<NfcCategoryOption>> nfcCategoryOptions([Database? db]) async {
  final d = db ?? AppDatabase.instance.db;
  final rows = await d.query(DbSchema.tCategories,
      orderBy: 'parent_id IS NOT NULL, sort ASC, id ASC');
  final byId = <int, Map<String, Object?>>{
    for (final r in rows) r['id'] as int: r,
  };
  String pathOf(int id) {
    final row = byId[id];
    if (row == null) return '';
    final self = (row['name'] as String? ?? '').trim();
    final parentId = row['parent_id'] as int?;
    if (parentId == null || !byId.containsKey(parentId)) return self;
    final parent = pathOf(parentId);
    return parent.isEmpty ? self : '$parent › $self';
  }

  final out = <NfcCategoryOption>[];
  for (final r in rows) {
    final id = r['id'] as int;
    final self = (r['name'] as String? ?? '').trim();
    out.add(NfcCategoryOption(
      id: id,
      name: self,
      path: pathOf(id),
      parentId: r['parent_id'] as int?,
    ));
  }
  return out;
}

/// 一个可绑定的书架书目（`read.book`）。
class NfcBookOption {
  const NfcBookOption({required this.id, required this.title, required this.author});

  final String id;
  final String title;
  final String author;
}

/// 书架书目列表（目标选择器「阅读书目」区块）。
///
/// 口径：取在册书（`deleted_at IS NULL`，B24：书移出书架视图但仍在库 ⇒ 视同目标有效，
/// 这里只过滤真删除，不按书架视图筛选）。
Future<List<NfcBookOption>> nfcBookOptions([Database? db]) async {
  final d = db ?? AppDatabase.instance.db;
  final rows = await d.query(
    DbSchema.tBooks,
    columns: ['id', 'title', 'author'],
    where: 'deleted_at IS NULL',
    orderBy: 'title COLLATE NOCASE ASC',
  );
  return [
    for (final r in rows)
      NfcBookOption(
        id: r['id'] as String? ?? '',
        title: (r['title'] as String? ?? '').trim().isEmpty
            ? '未命名'
            : (r['title'] as String? ?? '').trim(),
        author: (r['author'] as String? ?? '').trim(),
      ),
  ];
}

/// 某分类是否仍在册（触发链的「目标已失效」判据 · C24/B9）。
Future<bool> nfcCategoryExists(int catId, [Database? db]) async {
  final d = db ?? AppDatabase.instance.db;
  final rows = await d.query(DbSchema.tCategories,
      columns: ['id'], where: 'id = ?', whereArgs: [catId], limit: 1);
  return rows.isNotEmpty;
}

/// 某书是否仍在册（C24/B9/B24）。
///
/// ⚠ **必须带 `deleted_at IS NULL`**：书删除进回收站是**软删**，行还在表里。
/// 只按 id 查存在性会把「已进回收站的书」判成有效目标 ⇒ 贴卡时走
/// `startSession` 才失败，表现为贴了没反应而不是「绑的书已经不在了」。
/// 恢复备份把 `deleted_at` 搬回来后本判定自动回到 true，无需额外处理。
Future<bool> nfcBookExists(String bookId, [Database? db]) async {
  final d = db ?? AppDatabase.instance.db;
  final rows = await d.query(
    DbSchema.tBooks,
    columns: ['id'],
    where: 'id = ? AND deleted_at IS NULL',
    whereArgs: [bookId],
    limit: 1,
  );
  return rows.isNotEmpty;
}

/// 卡片张数（「我的」入口行右侧计数用 · F1-6）。
///
/// 与管理屏列表**同源读数**（同一张表的 COUNT）——入口写的数和进去看到的数
/// 必须一致，两处各算一套迟早漂。
///
/// ⚠ 测试/无库环境（widget 全 app 用例）走 `AppDatabase.instance.db` 会抛
/// `MissingPluginException`；调用方须自行降级（catch-ok），**本函数不吞异常**
/// （吞掉就等于给「读不到」和「真的是 0」两种语义同一条路）。
Future<int> nfcCardCount([Database? db]) async {
  final d = db ?? AppDatabase.instance.db;
  final rows = await d.rawQuery('SELECT COUNT(*) FROM ${DbSchema.tNfcCards}');
  return Sqflite.firstIntValue(rows) ?? 0;
}