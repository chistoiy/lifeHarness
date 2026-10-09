import 'media_item.dart';

/// 影音单行模型（`media_lists` · 表 v38 已建＝批8b 零迁移）。
///
/// 两条口径在模型层就钉死：
/// - **年度底稿不落行**：成员＝完结档（[MediaItem.doneStates]）取本年按达成日倒序
///   动态求得（工单 §1），所以本类只有手动单，底稿在 UI 侧以合成行出现；
/// - `kind_filter` 存五档类型键（四类＋mix 混合单），单名可改、类型建后不换
///   （换类型＝另一张单，改档不迁移成员）。
class MediaList {
  const MediaList({
    required this.id,
    required this.name,
    required this.kindFilter,
    required this.createdAt,
    this.note,
  });

  final int id;
  final String name;

  /// 五档类型键：movie|series|music|game|mix（混合单存 mix，不存空串）。
  final String kindFilter;
  final int createdAt;
  final String? note;

  /// 五档类型徽标（原型 ML_TYPE 逐字）。
  static const typeLabels = {
    MediaItem.kMovie: '片单',
    MediaItem.kSeries: '剧单',
    MediaItem.kMusic: '歌单',
    MediaItem.kGame: '游戏单',
    'mix': '混合单',
  };

  /// 新建弹层的五档候选序（原型 chips 同序：四类＋混合）。
  static const typeOrder = [
    MediaItem.kMovie,
    MediaItem.kSeries,
    MediaItem.kMusic,
    MediaItem.kGame,
    'mix',
  ];

  String get typeLabel => typeLabels[kindFilter] ?? '混合单';

  bool get isMix => kindFilter == 'mix';

  static MediaList fromRow(Map<String, Object?> m) => MediaList(
    id: (m['id'] as num).toInt(),
    name: m['name'] as String,
    kindFilter: (m['kind_filter'] as String?)?.isEmpty ?? true
        ? 'mix'
        : m['kind_filter'] as String,
    createdAt: (m['created_at'] as num?)?.toInt() ?? 0,
    note: m['note'] as String?,
  );
}
