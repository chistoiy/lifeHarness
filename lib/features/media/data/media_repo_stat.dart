import '../../../core/database/schema/media.dart';
import '../domain/media_session.dart';
import 'media_repository.dart';

/// 影音游统计与轨迹的取数口（批7 · 词典 LH-C21／LH-S37）。
extension MediaStatRepo on MediaRepository {
  /// 全库**已结算**会话（日期升序），统计屏与轨迹弹层同吃这一份。
  ///
  /// 两条硬口径：
  /// - 进行中（`ended_at IS NULL`）不入账＝不进统计，也不进逐次柱——
  ///   跑着的墙钟随分钟变，画进热力图会把「还在看」算成已完成；
  /// - **软删条目的会话不出现**：JOIN 在册条目（`deleted_at IS NULL`），
  ///   与 [MediaRepository.rawLive] 那条「在册读取唯一出口」同口径。
  ///   条目进回收站后它的历史仍留在库里（回收站可找回），但架上与统计都不该再看见它。
  Future<List<MediaSession>> closedSessions() async {
    final rows = await db.rawQuery(
      'SELECT s.* FROM $tMediaSessions s '
      'JOIN $tMediaItems i ON i.id = s.item_id '
      'WHERE s.ended_at IS NOT NULL AND i.${MediaRepository.rawLive} '
      'ORDER BY s.started_at ASC',
    );
    return rows.map(MediaSession.fromRow).toList(growable: false);
  }

  /// 单条目已结算会话（日期升序；明细屏的倒序由页面自己排）。
  Future<List<MediaSession>> closedSessionsOfItem(String itemId) async {
    final rows = await db.query(
      tMediaSessions,
      where: 'item_id = ? AND ended_at IS NOT NULL',
      whereArgs: [itemId],
      orderBy: 'started_at ASC',
    );
    return rows.map(MediaSession.fromRow).toList(growable: false);
  }
}
