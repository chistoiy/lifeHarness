import 'dart:math';

import 'package:sqflite/sqflite.dart';

import '../../../core/database/schema.dart';
import '../../../core/database/schema/nfc.dart' show NfcTargetKind;
import '../domain/nfc_card.dart';

/// NFC 卡片仓库（批1 · F1-2）。
///
/// 三条口径写在方法层，改动前先读：
/// · **标签只存编号**（C1）⇒ 本表是名称/目标的唯一真源，标签可随时重写而数据不动；
/// · **卡片不进回收站**（C7）⇒ [delete] 是真 DELETE，误删靠重绑恢复；
/// · **进备份包**（C8）⇒ 恢复走**按 id UPSERT**（B18），不产生第二行。
class NfcRepo {
  NfcRepo(this.db);

  final Database db;

  static const String _t = DbSchema.tNfcCards;

  // ==================== 读 ====================

  /// 列全表，按创建时间倒序（新卡在前；管理屏列表序）。
  Future<List<NfcCard>> listAll() async {
    final rows = await db.query(_t, orderBy: 'created_at DESC');
    return [for (final r in rows) NfcCard.fromRow(r)];
  }

  /// 按 id 取（贴卡触发的查表入口 · B35：调用方**必须先过**
  /// [isValidNfcCardId]，非法 id 静默丢弃不得回显）。
  Future<NfcCard?> byId(String id) async {
    final rows = await db.query(_t, where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return NfcCard.fromRow(rows.first);
  }

  /// 按 `tag_key` 取（写卡后回查 / UID 轨用）。
  Future<NfcCard?> byTagKey(String tagKey) async {
    final rows =
        await db.query(_t, where: 'tag_key = ?', whereArgs: [tagKey], limit: 1);
    if (rows.isEmpty) return null;
    return NfcCard.fromRow(rows.first);
  }

  Future<int> count() async =>
      Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM $_t')) ?? 0;

  // ==================== 写 ====================

  /// 建卡。**id 由本方法生成**（C33：12 位 base62＋`Random.secure()`），
  /// 调用方不传 id ⇒ 杜绝外部指定（可枚举/可注入）。
  ///
  /// 主键撞号（62^12 ≈ 3.2×10^21，概率可忽略）时**重生成一次**，仍撞则抛——
  /// **绝不静默覆盖别人的卡**。
  Future<NfcCard> create({
    required String name,
    required String targetKind,
    String? targetRef,
    String? tagKey,
    String? tagKind,
    int? nowMs,
  }) async {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    for (var attempt = 0; attempt < 2; attempt++) {
      final id = generateNfcCardId();
      final card = NfcCard(
        id: id,
        name: name,
        targetKind: targetKind,
        targetRef: targetRef,
        tagKey: tagKey,
        tagKind: tagKind,
        createdAt: now,
      );
      try {
        await db.insert(_t, card.toRow(),
            conflictAlgorithm: ConflictAlgorithm.abort);
        return card;
      } on DatabaseException catch (e) {
        final isPkConflict = e.isUniqueConstraintError() ||
            e.toString().contains('UNIQUE constraint failed: $_t.id');
        if (!isPkConflict || attempt == 1) rethrow;
      }
    }
    throw StateError('nfc_cards 主键连续两次撞号（不可达路径，仅为类型收敛）');
  }

  /// 改名 / 换目标（C3：改数据**不重写标签** ⇒ 本方法不碰 `written_at`）。
  Future<void> update(String id, {String? name, String? targetKind, String? targetRef}) async {
    final sets = <String, Object?>{};
    if (name != null) sets['name'] = name;
    if (targetKind != null) sets['target_kind'] = targetKind;
    if (targetRef != null) sets['target_ref'] = targetRef;
    if (sets.isEmpty) return;
    await db.update(_t, sets, where: 'id = ?', whereArgs: [id]);
  }

  /// 删卡（C7：**不进回收站**，真 DELETE）。原标签变「未绑定」，可重绑（见 B8）。
  Future<void> delete(String id) async {
    await db.delete(_t, where: 'id = ?', whereArgs: [id]);
  }

  /// 记一次使用：`use_count+1`、`last_used_at=now`（计数**只在此一处累加**，
  /// 触发链禁旁路直写——否则去抖窗口内的被吞触发也会计次，B16）。
  Future<void> markUsed(String id, {int? nowMs}) async {
    await db.rawUpdate(
      'UPDATE $_t SET use_count = use_count + 1, last_used_at = ? WHERE id = ?',
      [nowMs ?? DateTime.now().millisecondsSinceEpoch, id],
    );
  }

  /// 置**已写入**态（C31：写卡成功后写 now；换卡覆盖写入覆盖 now）。
  Future<void> markWritten(
    String id, {
    required String tagKey,
    required String tagKind,
    int? nowMs,
  }) async {
    await db.update(
      _t,
      {
        'written_at': nowMs ?? DateTime.now().millisecondsSinceEpoch,
        'tag_key': tagKey,
        'tag_kind': tagKind,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 换标签：把 `tag_key` 指到新卡（B29：UID 卡升级写 NDEF 后**旧 UID 行不留双份**，
  /// `tag_kind` 升为 `ndef` 并换 key）。
  Future<void> rebindTag(String id, {required String tagKey, required String tagKind}) {
    return db.update(
      _t,
      {'tag_key': tagKey, 'tag_kind': tagKind},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 恢复备份用：**按 id UPSERT**（B18：后到覆盖，不产生第二行）。
  ///
  /// `tag_key` 撞车走 UPSERT（B28）⇒ SQLite 的 UNIQUE 冲突下 `CONFLICT(id)`
  /// 不覆盖 `tag_key`，故先按 `tag_key` 查：命中**别的**卡则把旧行的 `tag_key` 清空，
  /// 再 upsert 本行（"最近绑定的那张为准"）。
  Future<void> upsertFromBackup(Map<String, Object?> row) async {
    final card = NfcCard.fromRow(row);
    final incomingKey = card.tagKey;
    if (incomingKey != null && incomingKey.isNotEmpty) {
      final byKey = await byTagKey(incomingKey);
      if (byKey != null && byKey.id != card.id) {
        await db.update(_t, {'tag_key': null, 'tag_kind': null},
            where: 'id = ?', whereArgs: [byKey.id]);
      }
    }
    await db.insert(
      _t,
      card.toRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}

/// 生成 12 位 base62 随机 `id`（C33）。
///
/// **禁 uuid／时间戳／自增**：uuid 长度不可控会让冻结档 §5.7 的容量核算当场失真；
/// 时间戳与自增可枚举、能泄露创建顺序（C33 理由逐字）。
/// 用 [Random.secure] 而非 `Random()`——后者可由种子回推，同机可枚举出历史 id。
String generateNfcCardId() {
  const chars = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
  final rnd = Random.secure();
  final buf = StringBuffer();
  for (var i = 0; i < kNfcIdLen; i++) {
    buf.write(chars[rnd.nextInt(chars.length)]);
  }
  final id = buf.toString();
  // 域层保持零 Flutter 依赖，故不用 debugAssert；此处直接抛（生成侧不可能失败，
  // 一旦失败说明 chars 表被改坏，属开发期硬错）。
  if (!isValidNfcCardId(id)) {
    throw StateError('生成的 NFC id 不合规（chars 表被改坏）：$id');
  }
  return id;
}

/// 目标四类的**校验**（§2.0 目标表唯一定义源）。
///
/// 未知 `target_kind` 一律拒（C35 口径的同源精神：外部输入不认识的类别不许进库）。
bool isKnownNfcTargetKind(String kind) => NfcTargetKind.all.contains(kind);