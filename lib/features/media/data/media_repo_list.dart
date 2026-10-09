import '../../../core/database/schema/media.dart';
import '../domain/media_item.dart';
import '../domain/media_list.dart';

import 'media_repository.dart';

/// 影音单读写口（批8b · 工单 §3：两表 v38 已建，本批**零迁移**）。
///
/// 三条硬口径：
/// - 成员序＝`media_list_items.pos`（0 起连续），重排/移出/加入一律整段重写
///   （单量级＝几十条，一次事务删插比逐行挪 pos 少一类半序脏态）；
/// - 成员读出口只给**在册**条目（软删行随 join 消失，删条目不脏单）；
/// - 年度底稿零写口——[yearDraftItems] 纯查询，库里永远没有它的行。
extension MediaListRepo on MediaRepository {
  /// 手动单全行（列序＝建单序；底稿不在其中＝UI 侧合成置顶）。
  Future<List<MediaList>> listRows() async {
    final rows = await db.query(tMediaLists, orderBy: 'id ASC');
    return rows.map(MediaList.fromRow).toList(growable: false);
  }

  /// 建单（五档类型键落 `kind_filter`，混合单存 'mix'），返回新 id。
  Future<int> createList(String name, String typeKey) => db.insert(tMediaLists, {
    'name': name,
    'kind_filter': typeKey,
    'cover_style': 'desk',
    'created_at': DateTime.now().millisecondsSinceEpoch,
  });

  /// 就地改名（底稿没有这条口：它不落行，名字＝年份拼出来的）。
  Future<int> renameList(int id, String name) => db.update(
    tMediaLists,
    {'name': name},
    where: 'id = ?',
    whereArgs: [id],
  );

  /// 单成员（pos 升序 × 在册过滤＝列表现算与详情面同一出口）。
  Future<List<MediaItem>> listMemberItems(int listId) async {
    final rows = await db.rawQuery(
      'SELECT i.* FROM $tMediaListItems li '
      'JOIN $tMediaItems i ON i.id = li.item_id '
      'WHERE li.list_id = ? AND i.${MediaRepository.rawLive} ORDER BY li.pos ASC',
      [listId],
    );
    return rows.map(MediaItem.fromMap).toList(growable: false);
  }

  /// 整段重写成员序（加入＝尾插后写回；移出/拖拽＝改列后写回）。
  Future<void> setMembers(int listId, List<String> ids) => db.transaction((txn) async {
    await txn.delete(tMediaListItems, where: 'list_id = ?', whereArgs: [listId]);
    for (var i = 0; i < ids.length; i++) {
      await txn.insert(tMediaListItems, {'list_id': listId, 'item_id': ids[i], 'pos': i});
    }
  });

  /// 该条目当前在哪些手动单里（动作面「移入影音单」的勾选态）。
  Future<List<int>> listsHolding(String itemId) async {
    final rows = await db.query(
      tMediaListItems,
      columns: ['list_id'],
      where: 'item_id = ?',
      whereArgs: [itemId],
    );
    return rows.map((r) => (r['list_id'] as num).toInt()).toList(growable: false);
  }

  /// 年度底稿成员＝完结档 ∧ 达成日在本自然年，按达成日倒序（同日按 id 稳定）。
  ///
  /// 窗口从 [now] 现算自然年界（与阅读侧同法），**不跨年顺延**：去年完结的
  /// 归去年底稿（＝当时的本年窗口），今年列表里永远只有今年达成的。
  Future<List<MediaItem>> yearDraftItems(DateTime now) async {
    final yStart = DateTime(now.year).millisecondsSinceEpoch;
    final yEnd = DateTime(now.year + 1).millisecondsSinceEpoch;
    final rows = await db.query(
      tMediaItems,
      where: '${MediaRepository.rawLive} AND state IN (${MediaItem.doneStates.map((_) => '?').join(',')}) '
          'AND ended_at IS NOT NULL AND ended_at >= ? AND ended_at < ?',
      whereArgs: [...MediaItem.doneStates, yStart, yEnd],
      orderBy: 'ended_at DESC, id ASC',
    );
    return rows.map(MediaItem.fromMap).toList(growable: false);
  }
}
