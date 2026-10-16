import 'package:sqflite/sqflite.dart';

import '../../core/database/app_database.dart';
import '../../core/database/schema.dart';
import '../../core/database/schema/nfc.dart' show NfcTargetKind;
import '../../features/nfc/domain/nfc_card.dart';
import 'habit_mounts.dart';
import 'maternity_mounts.dart';

/// NFC 卡片 ⇄ 时间/阅读/习惯/母婴 挂载出口（批1 · 冻结档 §6.1 · 守 R1；批1b 扩四口）。
///
/// `features/nfc/**` **禁止 import 任何 `features/calendar/**`、`features/read/**`、
/// `features/habit/**`、`features/care/**`**（架构守护 `architecture_test` R1）；
/// 跨模块读数据统一经本文件的函数出口，与 `mindmap_mounts` / `read_mounts` 同惯例。
///
/// **批1 只提供两个读取转发口**（目标选择器的「计时分类」「阅读书目」两区块要的数据）；
/// 两个 toggle 转发口（`nfcToggleTimer`／`nfcToggleRead`）属**批2 触发链**，
/// 届时按 C32「内部自取 ref/host、不接受外部传 context」实现，先例＝`sys_pill_sync.dart:102`。
/// 批1b 补：分类两级结构／习惯条目／宝宝档案／记录类型／批量目标解析。

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

// ==================== 批1b 新增出口 ====================
//
// 口径（工单 §3）：五段横向大类里，「计时分类」要两级选择结构、「打卡」走习惯
// 模块出口、「呵护宝宝」走母婴模块出口（新建 `maternity_mounts.dart`）。
// 失效判定（目标被删后列表标「已失效」）同步扩到这两类新目标。

/// 一个一级分类及其子级（「计时分类」两级选择用 · 批1b §3-1）。
///
/// 与 [nfcCategoryOptions] 的扁平带路径列表并存：扁平口给「只读回显/一次性列表」，
/// 本口给「先选一级再联动子级」的两级选择器。排序仍沿用
/// `parent_id IS NOT NULL, sort ASC, id ASC`（一级在前·同级按 sort/id）。
class NfcCategoryGroup {
  const NfcCategoryGroup({
    required this.id,
    required this.name,
    required this.children,
  });

  final int id;
  final String name;
  final List<NfcCategoryOption> children;
}

/// 分类两级结构（一级 → 子级）。
///
/// 边界：`parent_id` 指向的行不存在（脏数据/父级已被删）时，本行按**一级**收
/// （不能让它既不是一级也不是任何人的子级＝从选择器里凭空消失）。
Future<List<NfcCategoryGroup>> nfcCategoryTree([Database? db]) async {
  final flat = await nfcCategoryOptions(db);
  final ids = {for (final c in flat) c.id};
  final groups = <NfcCategoryGroup>[];
  final indexOf = <int, int>{};
  for (final c in flat) {
    final pid = c.parentId;
    if (pid != null && ids.contains(pid)) continue; // 子级：稍后挂到父级下
    indexOf[c.id] = groups.length;
    groups.add(NfcCategoryGroup(
        id: c.id, name: c.name, children: <NfcCategoryOption>[]));
  }
  for (final c in flat) {
    final pid = c.parentId;
    if (pid == null || !ids.contains(pid)) continue;
    final gi = indexOf[pid];
    if (gi == null) continue; // 父级本身也是子级（三级以上）⇒ 顶层已收，不重复挂
    groups[gi].children.add(c);
  }
  return groups;
}

/// 一个可绑定的习惯条目（「打卡」目标选择器用 · 批1b §3-2）。
class NfcHabitOption {
  const NfcHabitOption({required this.id, required this.name});

  final String id;

  /// **已剥离装饰符**的名字（零 emoji 硬要求）；也是写进 `target_sub` 的同一个串
  /// （显示、存储、失效比对三处同源）。
  final String name;
}

/// 习惯条目列表（同源习惯模块 · 经 `habit_mounts.dart`，**不直连习惯表**）。
///
/// 口径：取未删除习惯（含归档——归档≠删除，归档习惯仍可被卡绑定）；
/// 名字一律过 [nfcHabitDisplayName]（剥装饰符，剥空回落原名）。
Future<List<NfcHabitOption>> nfcHabitOptions([Database? db]) async {
  final rows = await habitOptionList(db);
  return [
    for (final h in rows)
      NfcHabitOption(id: h.id, name: nfcHabitDisplayName(h.name)),
  ];
}

/// 某习惯条目是否还在（按**剥离后**的名字比对 · 批1b §3-4）。
///
/// 与 [nfcHabitOptions] 的写入口径同源：卡里存的就是剥离后的名字，
/// 比对前同样剥离 ⇒ 不会出现「选得上却判失效」。
Future<bool> nfcHabitExists(String? habitName, [Database? db]) async {
  final want = nfcStripEmoji(habitName ?? '');
  if (want.isEmpty) return false;
  final rows = await habitOptionList(db);
  for (final h in rows) {
    if (nfcHabitDisplayName(h.name) == want) return true;
  }
  return false;
}

/// 一个可绑定的宝宝档案（「呵护宝宝」一级 · 批1b §3-3）。
class NfcBabyOption {
  const NfcBabyOption({required this.id, required this.name});

  final int id;
  final String name;
}

/// 一个可绑定的记录类型（「呵护宝宝」二级 · 批1b §3-3）。
class NfcCareKindOption {
  const NfcCareKindOption({required this.id, required this.name});

  final String id;
  final String name;
}

/// 宝宝档案列表（同源母婴模块 · 经 `maternity_mounts.dart`）。
Future<List<NfcBabyOption>> nfcBabyOptions([Database? db]) async {
  final rows = await maternityBabyOptions(db);
  return [for (final b in rows) NfcBabyOption(id: b.id, name: b.name)];
}

/// 记录类型列表（同源母婴模块内置记录类型）。
List<NfcCareKindOption> nfcCareKindOptions() => [
      for (final k in maternityCareKindOptions())
        NfcCareKindOption(id: k.id, name: k.name),
    ];

/// 宝宝＋记录类型是否都还在（`<babyId>/<kindId>` · 批1b §3-4）。
Future<bool> nfcBabyCareExists(String? targetSub, [Database? db]) async {
  final parsed = nfcCareSubParse(targetSub);
  if (parsed == null) return false;
  if (!maternityCareKindExists(parsed.$2)) return false;
  return maternityBabyExists(parsed.$1, db);
}

/// 一张卡的目标解析结果（列表左节点与目标摘要用 · 批1b §5）。
class NfcTargetState {
  const NfcTargetState({this.name, required this.alive});

  /// 目标具体名（分类名／书名／宝宝·类型／习惯名）；查不到时为 null。
  final String? name;

  /// 目标是否仍有效（C24/B9：被删/被清空＝失效，列表标「已失效」）。
  final bool alive;
}

/// **批量**解析一组卡的目标名与有效性（一次读三张表，别在列表里逐行查库）。
///
/// 返回 map：cardId → [NfcTargetState]；标签全文由域层
/// [nfcTargetLabelOf] 用 `name` 拼（口径唯一来源在域层，不在本文件）。
Future<Map<String, NfcTargetState>> nfcTargetStates(
  Iterable<NfcCard> cards, [
  Database? db,
]) async {
  final list = cards.toList();
  final out = <String, NfcTargetState>{};
  if (list.isEmpty) return out;
  final d = db ?? AppDatabase.instance.db;

  Future<Map<String, String>> namesOf(String table, String idCol, String nameCol,
      {String? where, List<Object?>? args}) async {
    final rows = await d.query(table,
        columns: [idCol, nameCol], where: where, whereArgs: args);
    return {
      for (final r in rows)
        '${r[idCol]}': (r[nameCol] as String? ?? '').trim(),
    };
  }

  final catIds = <int>{};
  final bookIds = <String>{};
  final babyIds = <int>{};
  final wantHabit = list.any((c) => c.isHabitTarget);
  for (final c in list) {
    if (c.isHabitTarget || c.isCareTarget) {
      if (c.isCareTarget) {
        final p = nfcCareSubParse(c.targetSub);
        if (p != null) babyIds.add(p.$1);
      }
      continue;
    }
    switch (c.targetKind) {
      case NfcTargetKind.timerCat:
        final id = int.tryParse(c.targetRef ?? '');
        if (id != null) catIds.add(id);
      case NfcTargetKind.readBook:
        if ((c.targetRef ?? '').isNotEmpty) bookIds.add(c.targetRef!);
      default:
        break;
    }
  }

  final catNames = <String, String>{};
  for (final id in catIds) {
    final rows = await d.query(DbSchema.tCategories,
        columns: ['name'], where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isNotEmpty) {
      catNames['$id'] = (rows.first['name'] as String? ?? '').trim();
    }
  }
  final bookNames = bookIds.isEmpty
      ? const <String, String>{}
      : await namesOf(DbSchema.tBooks, 'id', 'title',
          where: 'deleted_at IS NULL'); // 软删＝失效（同 nfcBookExists 口径）
  final babyNames = babyIds.isEmpty
      ? const <String, String>{}
      : await namesOf(DbSchema.tCareBabies, 'id', 'name');

  final habitNames = wantHabit
      ? {for (final h in await habitOptionList(db)) h.id: h.name}
      : const <String, String>{};

  for (final c in list) {
    if (c.isHabitTarget) {
      final want = nfcStripEmoji(c.targetSub ?? '');
      var alive = false;
      if (want.isNotEmpty) {
        for (final raw in habitNames.values) {
          if (nfcHabitDisplayName(raw) == want) {
            alive = true;
            break;
          }
        }
      }
      out[c.id] = NfcTargetState(name: c.targetSub, alive: alive);
      continue;
    }
    if (c.isCareTarget) {
      final p = nfcCareSubParse(c.targetSub);
      if (p == null) {
        out[c.id] = const NfcTargetState(alive: false);
        continue;
      }
      final baby = babyNames['${p.$1}'];
      final kind = maternityCareKindName(p.$2);
      final alive = baby != null && kind != null;
      out[c.id] = NfcTargetState(
        name: alive ? '$baby · $kind' : null,
        alive: alive,
      );
      continue;
    }
    switch (c.targetKind) {
      case NfcTargetKind.timerCat:
        final name = catNames[c.targetRef ?? ''];
        out[c.id] = NfcTargetState(name: name, alive: name != null);
      case NfcTargetKind.readBook:
        final name = bookNames[c.targetRef ?? ''];
        out[c.id] = NfcTargetState(name: name, alive: name != null);
      default:
        final label = navActionLabelOf(c.targetRef);
        out[c.id] = NfcTargetState(name: label, alive: label != null);
    }
  }
  return out;
}

/// 单卡版（弹层「卡片信息」形态的目标摘要用）。
Future<NfcTargetState> nfcTargetStateOf(NfcCard card, [Database? db]) async {
  final m = await nfcTargetStates([card], db);
  return m[card.id] ?? const NfcTargetState(alive: false);
}