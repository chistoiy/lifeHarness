import 'dart:convert';

/// 影音游条目（`media_items` 表 · 计划 §2.1 · 四类＝电影/剧集/音乐/游戏，综艺并入剧集）。
///
/// 四条口径在模型层就钉死，不在 UI 侧补：
/// - [id] 是 **TEXT**（外部 id 归一后直接当主键，批1 建表已定）；
/// - [state] 一列四义，合法取值按 [kind] 查 [kMediaStates]（同一列四类各读各的）；
/// - [progressWay] 决定进度怎么算：`movie=pct|min`·`series=ep`·`music=loops`·
///   `game=mainpct|playthrough|achv`；终点写在 [progressTo]（按 way 解释的数字串）；
/// - 游戏**只有 [kWayMainPct] 才画进度条**——竞技网游没有通关%（§三 三类记录模型纠正口径：
///   「进度按作品是否有剧情决定，不以网游门控」，落到字段层就是 progress_way 是否为剧情档）；
/// - 软删 [deletedAt]：在册读取一律带 `deleted_at IS NULL`（仓储层唯一出口，UI 不许自己拼裸查）。
class MediaItem {
  const MediaItem({
    this.id = '',
    required this.kind,
    required this.title,
    this.subtitle,
    this.creator = '未知',
    this.creatorRole,
    this.publisher,
    this.publisherRole,
    this.releaseYear,
    this.country,
    this.language,
    this.coverPath,
    this.colorIdx = 0,
    required this.state,
    this.rating = 0,
    this.myRating = 0,
    this.durationMin = 0,
    this.seasonsCount = 0,
    this.episodesTotal = 0,
    this.tracksCount = 0,
    this.playthroughs = 0,
    this.mainPct = 0,
    this.sidePct = 0,
    this.achPct = 0,
    this.completed = false,
    required this.progressWay,
    this.progressFrom,
    this.progressTo,
    this.source,
    this.grp,
    this.externalIds = const {},
    this.tags = const [],
    this.startedAt,
    this.endedAt,
    this.lastActivityAt,
    this.intro,
    this.note,
    this.finalNote,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    /// 音乐「循环次数」由会话条数派生（表里不存列，与 book 聚合口径一致；
    /// 仓储取数时回填，未回填时 null＝卡面按 0 读）。
    this.listenLoops,
  });

  // ---- 取值域（与批1 `schema/media.dart` 的 mediaKinds、计划 §2.1 注释同源）----
  static const kMovie = 'movie';
  static const kSeries = 'series';
  static const kMusic = 'music';
  static const kGame = 'game';

  /// 进度方式（§2.1 progress_way 列注释的四套口径）。
  static const kWayPct = 'pct';
  static const kWayMin = 'min';
  static const kWayEp = 'ep';
  static const kWayLoops = 'loops';
  static const kWayMainPct = 'mainpct';
  static const kWayPlaythrough = 'playthrough';
  static const kWayAchv = 'achv';

  static const kinds = [kMovie, kSeries, kMusic, kGame];

  /// 分区（state）按 kind 四套（原型 MSTATE_MAP 逐字对齐；综艺归剧集＝§九.5）。
  static const states = {
    kMovie: ['未看', '在看', '看完', '搁置'],
    kSeries: ['未看', '在追', '追完', '弃剧', '搁置'],
    kMusic: ['未听', '在听', '循环中', '搁置'],
    kGame: ['未玩', '在玩', '通关', '搁置'],
  };

  /// 每个 kind 的进度方式候选（录入弹层据此出字段，不是同一张表单换标题）。
  static const ways = {
    kMovie: [kWayPct, kWayMin],
    kSeries: [kWayEp],
    kMusic: [kWayLoops],
    kGame: [kWayMainPct, kWayPlaythrough, kWayAchv],
  };

  /// 全部状态筛选 chip（影音架「全部分区」按语义归并成四档，原型 mStateCls 同口径）。
  static const stateGroups = <(String, List<String>)>[
    ('未看', ['未看', '想看', '未听', '未玩']),
    ('在看/追/玩', ['在看', '在追', '在玩', '在听', '循环中']),
    ('看完/追完/通关', ['看完', '追完', '通关']),
    ('搁置', ['搁置', '弃剧']),
  ];

  /// 角色与占位文案（原型 mSetAddKind / 顶栏 placeholders 的人话口径）。
  static const creatorRoleLabel = {
    kMovie: '导演',
    kSeries: '主创',
    kMusic: '艺人',
    kGame: '工作室',
  };
  static const publisherRoleLabel = {
    kMovie: '制片',
    kSeries: '电视台/流媒体',
    kMusic: '唱片公司',
    kGame: '发行商',
  };

  static String labelOf(String kind) => switch (kind) {
    kMovie => '电影',
    kSeries => '剧集',
    kMusic => '音乐',
    kGame => '游戏',
    _ => kind,
  };

  /// 该 kind 的默认分区（新条目落点：电影「未看」…游戏「未玩」）。
  static String initialState(String kind) => (states[kind] ?? states[kMovie]!).first;

  /// 该 kind 的默认进度方式（音乐没有百分比口径；游戏默认剧情进度）。
  static String defaultWay(String kind) => (ways[kind] ?? ways[kMovie]!).first;

  final String id;
  final String kind;
  final String title;
  final String? subtitle;
  final String creator;
  final String? creatorRole;
  final String? publisher;
  final String? publisherRole;
  final int? releaseYear;
  final String? country;
  final String? language;

  /// 本地上传封面（§九.3：只做本地上传，不拉第三方 API）。
  final String? coverPath;

  /// 无封面时的色板下标（与书籍侧 BS_COV 同构机制）。
  final int colorIdx;
  final String state;
  final double rating;
  final double myRating;
  final int durationMin;
  final int seasonsCount;
  final int episodesTotal;
  final int tracksCount;
  final int playthroughs;
  final int mainPct;
  final int sidePct;
  final int achPct;
  final bool completed;
  final String progressWay;
  final String? progressFrom;
  final String? progressTo;
  final String? source;
  final String? grp;
  final Map<String, String> externalIds;
  final List<String> tags;
  final int? startedAt;
  final int? endedAt;
  final int? lastActivityAt;
  final String? intro;
  final String? note;
  final String? finalNote;
  final int createdAt;
  final int updatedAt;
  final int? deletedAt;

  bool get trashed => deletedAt != null;

  /// 色板下标越界回绕（同 book.paletteIdx 口径）。
  int get paletteIdx {
    const n = 8; // kMdsCov 组数（widgets/media_card.dart 唯一来源）
    final i = colorIdx % n;
    return i < 0 ? i + n : i;
  }

  /// 进度百分比（原型 mProg 同判）：null＝该条目没有进度语义，卡底不画条。
  int? get progressPercent {
    switch (kind) {
      case kMovie:
        if (state == '未看' || state == '想看') return 0;
        if (state == '看完') return 100;
        // min 档只有时间点没有百分比口径 → 不画条（不编数）。
        return progressWay == kWayPct
            ? (int.tryParse(progressTo ?? '') ?? 0).clamp(0, 100)
            : null;
      case kSeries:
        if (state == '未看') return 0;
        if (state == '追完') return 100;
        if (episodesTotal <= 0) return null;
        final cur = int.tryParse(progressTo ?? '') ?? 0;
        return (cur * 100 / episodesTotal).round().clamp(0, 100);
      case kGame:
        if (progressWay != kWayMainPct) return null; // 无剧情进度＝不画条
        if (state == '未玩') return 0;
        if (state == '通关') return 100;
        return mainPct.clamp(0, 100);
      default:
        return null; // 音乐＝循环次数，不是百分比
    }
  }

  /// 卡底进度条着色（原型 mProgCls：完结档 done / 搁置弃剧 give / 其余默认 accent）。
  String get progressTone => switch (state) {
    '看完' || '追完' || '通关' => 'done',
    '搁置' || '弃剧' => 'give',
    _ => '',
  };

  /// 分区徽标语义档（st-w 待看 / st-i 在场 / st-d 完结 / st-s 搁置）。
  String get stateTone => switch (state) {
    '在看' || '在追' || '在玩' || '在听' || '循环中' => 'i',
    '看完' || '追完' || '通关' => 'd',
    '搁置' || '弃剧' => 's',
    _ => 'w',
  };

  /// 卡面副行（列表视图 meta，原型 list 分支逐类四套文案）。
  String get metaLine {
    switch (kind) {
      case kMovie:
        return [
          if (releaseYear != null && releaseYear! > 0) '$releaseYear',
          if (durationMin > 0) '${durationMin}min',
          if (creator.isNotEmpty) creator,
        ].join(' · ');
      case kSeries:
        return '共 $seasonsCount 季·$episodesTotal 集 · 看到 ${progressTo ?? 0} 集';
      case kMusic:
        return '$tracksCount 曲 · 循环 ${listenLoops ?? 0} 次';
      case kGame:
        return '周目 $playthroughs · 主线 $mainPct% · ${publisher ?? creator}';
      default:
        return creator;
    }
  }

  /// 音乐「循环次数」＝会话条数（表里不存列，与 book 聚合口径一致；
  /// 仓储取数时回填，未回填时 null＝卡面按 0 读）。
  final int? listenLoops;


  /// 编辑保存的合并口径：表单能改的字段用新值，**表单没露出去的字段照旧**
  /// （评分/简介/各家外部 id/起止与活动时刻/创建时间/软删标记）。
  /// [old] 为 null（理论不会发生）＝原样返回自己。
  MediaItem mergedOnto(MediaItem? old) {
    if (old == null) return this;
    return MediaItem(
      id: id.isEmpty ? old.id : id,
      kind: kind,
      title: title,
      subtitle: subtitle ?? old.subtitle,
      creator: creator,
      creatorRole: creatorRole ?? old.creatorRole,
      publisher: publisher,
      publisherRole: publisherRole ?? old.publisherRole,
      releaseYear: releaseYear,
      country: old.country,
      language: old.language,
      coverPath: old.coverPath,
      colorIdx: old.colorIdx,
      state: state,
      rating: old.rating,
      myRating: old.myRating,
      durationMin: durationMin,
      seasonsCount: seasonsCount,
      episodesTotal: episodesTotal,
      tracksCount: tracksCount,
      playthroughs: playthroughs,
      mainPct: mainPct,
      sidePct: old.sidePct,
      achPct: old.achPct,
      completed: old.completed,
      progressWay: progressWay,
      progressFrom: old.progressFrom,
      progressTo: progressTo,
      source: source ?? old.source,
      grp: grp ?? old.grp,
      externalIds: old.externalIds,
      tags: old.tags,
      startedAt: old.startedAt,
      endedAt: old.endedAt,
      lastActivityAt: old.lastActivityAt,
      intro: old.intro,
      note: old.note,
      finalNote: old.finalNote,
      createdAt: old.createdAt,
      updatedAt: updatedAt,
      deletedAt: old.deletedAt,
      listenLoops: old.listenLoops,
    );
  }

  MediaItem copyWith({
    String? title,
    String? state,
    String? progressWay,
    String? progressTo,
    String? progressFrom,
    int? mainPct,
    int? playthroughs,
    List<String>? tags,
    String? grp,
    bool? completed,
    int? updatedAt,
    int? deletedAt,
    int? listenLoops,
  }) {
    return MediaItem(
      id: id,
      kind: kind,
      title: title ?? this.title,
      subtitle: subtitle,
      creator: creator,
      creatorRole: creatorRole,
      publisher: publisher,
      publisherRole: publisherRole,
      releaseYear: releaseYear,
      country: country,
      language: language,
      coverPath: coverPath,
      colorIdx: colorIdx,
      state: state ?? this.state,
      rating: rating,
      myRating: myRating,
      durationMin: durationMin,
      seasonsCount: seasonsCount,
      episodesTotal: episodesTotal,
      tracksCount: tracksCount,
      playthroughs: playthroughs ?? this.playthroughs,
      mainPct: mainPct ?? this.mainPct,
      sidePct: sidePct,
      achPct: achPct,
      completed: completed ?? this.completed,
      progressWay: progressWay ?? this.progressWay,
      progressFrom: progressFrom ?? this.progressFrom,
      progressTo: progressTo ?? this.progressTo,
      source: source,
      grp: grp ?? this.grp,
      externalIds: externalIds,
      tags: tags ?? this.tags,
      startedAt: startedAt,
      endedAt: endedAt,
      lastActivityAt: lastActivityAt,
      intro: intro,
      note: note,
      finalNote: finalNote,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      listenLoops: listenLoops ?? this.listenLoops,
    );
  }

  static MediaItem fromMap(Map<String, Object?> m) {
    final tagsRaw = (m['tags'] as String?) ?? '';
    final extRaw = (m['external_ids'] as String?) ?? '';
    Map<String, String> ext = const {};
    if (extRaw.isNotEmpty) {
      try {
        final d = jsonDecode(extRaw);
        if (d is Map) {
          ext = {for (final e in d.entries) '${e.key}': '${e.value}'};
        }
      } on FormatException {
        // catch-ok: 脏 external_ids 列按「无外部 id」处理，一条坏 JSON 不许炸掉整张影音架（无网络、无副作用）。
        ext = const {};
      }
    }
    return MediaItem(
      id: '${m['id']}',
      kind: '${m['kind']}',
      title: '${m['title']}',
      subtitle: m['subtitle'] as String?,
      creator: '${m['creator'] ?? '未知'}',
      creatorRole: m['creator_role'] as String?,
      publisher: m['publisher'] as String?,
      publisherRole: m['publisher_role'] as String?,
      releaseYear: (m['release_year'] as num?)?.toInt(),
      country: m['country'] as String?,
      language: m['language'] as String?,
      coverPath: m['cover_path'] as String?,
      colorIdx: (m['color_idx'] as num?)?.toInt() ?? 0,
      state: '${m['state']}',
      rating: (m['rating'] as num?)?.toDouble() ?? 0,
      myRating: (m['my_rating'] as num?)?.toDouble() ?? 0,
      durationMin: (m['duration_min'] as num?)?.toInt() ?? 0,
      seasonsCount: (m['seasons_count'] as num?)?.toInt() ?? 0,
      episodesTotal: (m['episodes_total'] as num?)?.toInt() ?? 0,
      tracksCount: (m['tracks_count'] as num?)?.toInt() ?? 0,
      playthroughs: (m['playthroughs'] as num?)?.toInt() ?? 0,
      mainPct: (m['main_pct'] as num?)?.toInt() ?? 0,
      sidePct: (m['side_pct'] as num?)?.toInt() ?? 0,
      achPct: (m['ach_pct'] as num?)?.toInt() ?? 0,
      completed: (m['completed'] as num?)?.toInt() == 1,
      progressWay: '${m['progress_way'] ?? MediaItem.kWayPct}',
      progressFrom: m['progress_from'] as String?,
      progressTo: m['progress_to'] as String?,
      source: m['source'] as String?,
      grp: m['grp'] as String?,
      externalIds: ext,
      tags: tagsRaw.split(',').where((s) => s.trim().isNotEmpty).toList(),
      startedAt: (m['started_at'] as num?)?.toInt(),
      endedAt: (m['ended_at'] as num?)?.toInt(),
      lastActivityAt: (m['last_activity_at'] as num?)?.toInt(),
      intro: m['intro'] as String?,
      note: m['note'] as String?,
      finalNote: m['final_note'] as String?,
      createdAt: (m['created_at'] as num?)?.toInt() ?? 0,
      updatedAt: (m['updated_at'] as num?)?.toInt() ?? 0,
      deletedAt: (m['deleted_at'] as num?)?.toInt(),
    );
  }

  Map<String, Object?> toMap() => {
    if (id.isNotEmpty) 'id': id,
    'kind': kind,
    'title': title,
    'subtitle': subtitle,
    'creator': creator,
    'creator_role': creatorRole,
    'publisher': publisher,
    'publisher_role': publisherRole,
    'release_year': releaseYear,
    'release_date': null,
    'country': country,
    'language': language,
    'cover_path': coverPath,
    'color_idx': colorIdx,
    'state': state,
    'rating': rating,
    'my_rating': myRating,
    'duration_min': durationMin,
    'seasons_count': seasonsCount,
    'episodes_total': episodesTotal,
    'tracks_count': tracksCount,
    'playthroughs': playthroughs,
    'main_pct': mainPct,
    'side_pct': sidePct,
    'ach_pct': achPct,
    'completed': completed ? 1 : 0,
    'progress_way': progressWay,
    'progress_from': progressFrom,
    'progress_to': progressTo,
    'source': source,
    'grp': grp,
    'external_ids': externalIds.isEmpty ? null : jsonEncode(externalIds),
    'tags': tags.join(','),
    'started_at': startedAt,
    'ended_at': endedAt,
    'last_activity_at': lastActivityAt,
    'intro': intro,
    'note': note,
    'final_note': finalNote,
    'created_at': createdAt,
    'updated_at': updatedAt,
    'deleted_at': deletedAt,
  };
}
