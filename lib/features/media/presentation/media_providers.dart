import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/app_log.dart';

import '../../../core/database/app_database.dart';
import '../data/media_cover.dart';
import '../data/media_repo_dict.dart';
import '../data/media_repo_goal.dart';
import '../data/media_repo_list.dart';
import '../data/media_repo_note.dart';
import '../data/media_repo_session.dart';
import '../data/media_repo_stat.dart';
import '../data/media_repository.dart';
import '../domain/media_goal.dart';
import '../domain/media_item.dart';
import '../domain/media_list.dart';
import '../domain/media_note.dart';
import '../domain/media_session.dart';
import '../domain/media_stats.dart';
import '../domain/media_summary.dart';

/// 影音游模块 providers（批2 · 影音架）。
///
/// 写库后统一 `mediaTickProvider.state++` 触发重取（与 readTickProvider 同法）。

final mediaRepositoryProvider = Provider<MediaRepository>(
  (ref) => MediaRepository(AppDatabase.instance.db),
);

final mediaTickProvider = StateProvider<int>((ref) => 0);

/// 封面取图口（批6）：生产＝[mdsPickAndStoreCover]（选图 → 平台侧按长边 480·JPEG .82 降采样
/// → 解码自证 → 落媒体根 → 返回路径；取消/读不出各有交代）。
/// 测试注入固定返回值＝弹层只验自己的状态机（选上/移除/失败不落值），
/// 取图与落盘的真身由 `test/media_cover_test.dart` 直接对真实现下判
/// （widget 测试里真插件通道与异步文件 I/O 在 FakeAsync 下永不返回，同 `healthExportDirProvider` 定式）。
final mediaCoverPickProvider = Provider<MdsCoverPick>(
  (ref) => (src) => mdsPickAndStoreCover(source: src),
);

/// 影音架视图：桌面 / 脊 / 列表（原型 mCurView，偏好属 §七 media.defaultView）。
final mediaViewProvider = StateProvider<String>((ref) => 'desk');

/// 类型 chip（all|movie|series|music|game）。
final mediaKindProvider = StateProvider<String>((ref) => 'all');

/// 分区 chip（all ＋ 该 kind 的分区名；all 类型下吃四档语义归并）。
final mediaStateProvider = StateProvider<String>((ref) => 'all');

/// 关键词（片名/原名/主创/发行/标签，原型 mFilter 同范围）。
final mediaQueryProvider = StateProvider<String>((ref) => '');

/// 影音架在册条目（筛选与排序的唯一取数面；deleted 行永不进来）。
final mediaItemsProvider = FutureProvider<List<MediaItem>>((ref) {
  ref.watch(mediaTickProvider);
  final kind = ref.watch(mediaKindProvider);
  return ref
      .watch(mediaRepositoryProvider)
      .items(
        kind: kind,
        stateGroup: ref.watch(mediaStateProvider),
        query: ref.watch(mediaQueryProvider),
        sort: ref.watch(mediaSortProvider),
      );
});

/// 类型 chip 角标计数（与架面同源，不受关键词影响＝在册总量口径）。
final mediaKindCountsProvider = FutureProvider<Map<String, int>>((ref) {
  ref.watch(mediaTickProvider);
  return ref.watch(mediaRepositoryProvider).kindCounts();
});

/// 桌面俯瞰 · 最近四条（记录页影音游 tab 用）。
final mediaRecentProvider = FutureProvider<List<MediaItem>>((ref) {
  ref.watch(mediaTickProvider);
  return ref.watch(mediaRepositoryProvider).recentPerKind();
});

/// 排序键（§七 media.sortDefault＝recent）。
final mediaSortProvider = StateProvider<String>((ref) => 'recent');

/// settings 表 `media.*` 键通用取值（计划 §七：KV 存 settings 表，不散落 SharedPreferences）。
final mediaKvProvider =
    FutureProvider.family<String, (String key, String def)>((ref, arg) async {
  ref.watch(mediaTickProvider);
  final raw = await ref.watch(mediaRepositoryProvider).kv(arg.$1);
  return raw ?? arg.$2;
});

/// 计时形态（§七 media.timerUI＝capsule；full＝起停直接进沉浸页）。
final mediaTimerUIProvider = FutureProvider<String>(
  (ref) => ref.watch(mediaKvProvider(('media.timerUI', 'capsule')).future),
);

/// 悬浮计时条开关（media.floatBar，默认开）。
final mediaFloatBarProvider = FutureProvider<bool>(
  (ref) async =>
      (await ref.watch(mediaKvProvider(('media.floatBar', 'true')).future)) ==
      'true',
);

/// 结束计时即弹记进度（media.autoAsk，默认开）。
final mediaAutoAskProvider = FutureProvider<bool>(
  (ref) async =>
      (await ref.watch(mediaKvProvider(('media.autoAsk', 'true')).future)) ==
      'true',
);

/// 影音悬浮条可见＝有在跑会话 × floatBar 开（与 read 侧 readTimerBarVisibleProvider 同法）。
/// 两路读数都按「取不到＝不显示」的 AsyncValue 口径走，不硬断言非空。
final mediaTimerBarVisibleProvider = Provider<bool>((ref) {
  // floatBar 默认开＝装载中也按开处理，读数落地后再校正。
  final floatOn = ref.watch(mediaFloatBarProvider).valueOrNull ?? true;
  final running = ref.watch(mediaRunningSessionProvider).valueOrNull;
  return floatOn && running != null;
});

/// 全库单活的影音会话（杀进程重开延续靠这条库内读数，不存内存态）。
final mediaRunningSessionProvider = FutureProvider<MediaSession?>((ref) {
  ref.watch(mediaTickProvider);
  return ref.watch(mediaRepositoryProvider).runningSession();
});

/// 详情/计时页条目取数（软删行＝null＝屏走「已不在架」空态）。
final mediaItemDetailProvider = FutureProvider.family<MediaItem?, String>((
  ref,
  id,
) {
  ref.watch(mediaTickProvider);
  return ref.watch(mediaRepositoryProvider).itemById(id);
});

/// 条目「一页总结」（final_note JSON 三键；空＝MediaSummary()，UI 侧出虚线属 A3）。
final mediaSummaryProvider = FutureProvider.family<MediaSummary, String>((
  ref,
  id,
) {
  ref.watch(mediaTickProvider);
  return ref.watch(mediaRepositoryProvider).summaryOf(id);
});

/// 单条目会话明细（倒序；进行中那条置顶由页面处理）。
final mediaSessionsProvider = FutureProvider.family<List<MediaSession>, String>((
  ref,
  id,
) {
  ref.watch(mediaTickProvider);
  return ref.watch(mediaRepositoryProvider).sessionsOf(id);
});

/// 单条目累计入账分钟（详情统计行）。
final mediaMinutesProvider = FutureProvider.family<int, String>((ref, id) {
  ref.watch(mediaTickProvider);
  return ref.watch(mediaRepositoryProvider).minutesOfItem(id);
});

/// 管理器当前类（原型 mMgrTab＝src/grp/creator/pub/tags）。
final mediaDictTabProvider = StateProvider<String>((ref) => 'source');

/// 一类名册清单（名册 ∪ 条目实际值＋引用数；写库后随 mediaTick 重取）。
final mediaDictRowsProvider =
    FutureProvider.family<List<({String name, int refCount})>, String>((
  ref,
  tab,
) {
  ref.watch(mediaTickProvider);
  return ref.watch(mediaRepositoryProvider).dictRows(
    MediaDictRepo.dictKinds[tab] ?? tab,
  );
});

// ==================== 影音笔记库＋复习（批5 UI） ====================

/// 笔记库六路筛选的唯一状态（类型／kind／条目／标星／标签／关键词）。
///
/// 用 record 而不是六枚 StateProvider：**family 键要整体换**，六枚各 watch 会让
/// 「改一路就重建整段查询」与「漏 watch 一路＝读数来自旧快照」两类坑同时存在。
/// 拍板①＝屏面只留筛选钮＋摘要行，六组条件都在筛选面板里改，「应用筛选」一次性落。
typedef MediaNoteFilter = ({
  String? type,
  String? kind,
  String? itemId,
  String? tag,
  bool starred,
  String query,
});

const MediaNoteFilter kMediaNoteFilterAll = (
  type: null,
  kind: null,
  itemId: null,
  tag: null,
  starred: false,
  query: '',
);

final mediaNoteFilterProvider = StateProvider<MediaNoteFilter>(
    (ref) => kMediaNoteFilterAll);

/// 六路筛选各自的「换一路、其余原样」构造（record 没有 `copyWith`，
/// 而面板里「选回全部／不限」＝**显式清成 null**，用 `?? 原值` 那种写法清不掉，
/// 所以每路一个整份重建的小函数，别在 UI 里手拼六次字段）。
MediaNoteFilter nfType(MediaNoteFilter f, String? v) =>
    (type: v, kind: f.kind, itemId: f.itemId, tag: f.tag, starred: f.starred, query: f.query);

MediaNoteFilter nfKind(MediaNoteFilter f, String? v) =>
    (type: f.type, kind: v, itemId: f.itemId, tag: f.tag, starred: f.starred, query: f.query);

MediaNoteFilter nfItem(MediaNoteFilter f, String? v) =>
    (type: f.type, kind: f.kind, itemId: v, tag: f.tag, starred: f.starred, query: f.query);

MediaNoteFilter nfTag(MediaNoteFilter f, String? v) =>
    (type: f.type, kind: f.kind, itemId: f.itemId, tag: v, starred: f.starred, query: f.query);

MediaNoteFilter nfStarred(MediaNoteFilter f, bool v) =>
    (type: f.type, kind: f.kind, itemId: f.itemId, tag: f.tag, starred: v, query: f.query);

MediaNoteFilter nfQuery(MediaNoteFilter f, String v) =>
    (type: f.type, kind: f.kind, itemId: f.itemId, tag: f.tag, starred: f.starred, query: v);

/// 四视图档（卡片／行／按条目／截图墙）；**拍板②＝默认「按条目」**。
final mediaNoteViewProvider = StateProvider<String>((ref) => 'byitem');

/// 在册条目全量（笔记条目的标题与条目选择页共用）。
///
/// 不吃架面那三枚筛选（kind/state/query）：笔记库的「条目 chips」与表单的「选条目」
/// 都要看全库，跟着架面筛选走会让「这条笔记的条目名」在某些架面状态下取不到。
final mediaAllItemsProvider = FutureProvider<List<MediaItem>>((ref) {
  ref.watch(mediaTickProvider);
  return ref.watch(mediaRepositoryProvider).items();
});

/// 笔记列表（六路筛选的唯一出口；四视图都画这一份，计数天然一致＝工单 §1.1 的构造性保证）。
final mediaNotesProvider = FutureProvider<List<MediaNote>>((ref) {
  ref.watch(mediaTickProvider);
  final f = ref.watch(mediaNoteFilterProvider);
  return ref.watch(mediaRepositoryProvider).notes(
        noteType: f.type,
        kind: f.kind,
        itemId: f.itemId,
        tag: f.tag,
        query: f.query,
        starredOnly: f.starred,
      );
});

/// 条目 chips 的档位来源（只列有笔记的条目，**不吃 itemId 自身**——仓储侧已钉）。
final mediaNoteFacetProvider = FutureProvider<List<({String itemId, int count})>>((ref) {
  ref.watch(mediaTickProvider);
  final f = ref.watch(mediaNoteFilterProvider);
  return ref.watch(mediaRepositoryProvider).noteItemFacet(
        kind: f.kind,
        noteType: f.type,
        tag: f.tag,
        query: f.query,
        starredOnly: f.starred,
      );
});

/// 标签 chips 来源（在册行 tag 去重）。
final mediaNoteTagsProvider = FutureProvider<List<String>>((ref) {
  ref.watch(mediaTickProvider);
  return ref.watch(mediaRepositoryProvider).noteTags();
});

/// 复习角标读数＝**吃同一份筛选**的到期队列长度（工单 §1.2：队列来源＝筛过的笔记）。
final mediaDueCountProvider = FutureProvider<int>((ref) {
  ref.watch(mediaTickProvider);
  final f = ref.watch(mediaNoteFilterProvider);
  return ref.watch(mediaRepositoryProvider).dueReviewCount(
        noteType: f.type,
        kind: f.kind,
        itemId: f.itemId,
        tag: f.tag,
        query: f.query,
        starredOnly: f.starred,
      );
});

/// 在册笔记总数（**不受筛选影响**）：空态两档分话术用——
/// 0 条＝「还没有影音笔记」，非 0 但当前筛选空＝「当前筛选没有笔记」。
final mediaNoteTotalProvider = FutureProvider<int>((ref) {
  ref.watch(mediaTickProvider);
  return ref.watch(mediaRepositoryProvider).noteCount();
});

/// 某条目的在册笔记（详情页名场面时间线）。
final mediaItemNotesProvider = FutureProvider.family<List<MediaNote>, String>((ref, id) {
  ref.watch(mediaTickProvider);
  return ref.watch(mediaRepositoryProvider).notesOfItem(id);
});

// ==================== 统计屏与条目轨迹（批7 UI · LH-C21／LH-S37） ====================

/// 倍速折算开关（§七 `media.speedFold`）：**默认为真实耗时**。
///
/// 计划 §七 表里那行「默认 true」写在 §九.1 定案之前，已过期——批4 拍板＝账本吃真实、
/// 折算只在读侧算，所以统计屏顶部那两枚 chip（真实时长／折算时长）就是这枚设置的可见表达，
/// 切换当场写回，别处不散存第二份态。
final mediaSpeedFoldProvider = FutureProvider<bool>((ref) async {
  ref.watch(mediaTickProvider);
  return (await ref.watch(mediaKvProvider(('media.speedFold', 'false')).future)) == 'true';
});

/// 四行筛选条的唯一状态（年／月／度量／构成；**口径不在这份里**，见 [mediaStatProvider]）。
final mdsStatFilterProvider = StateProvider<MdsStatFilter>(
    (ref) => const MdsStatFilter());

/// 全库已结算会话（统计屏八块的原料；进行中那条不入账＝不进统计）。
final mediaClosedSessionsProvider = FutureProvider<List<MediaSession>>((ref) {
  ref.watch(mediaTickProvider);
  return ref.watch(mediaRepositoryProvider).closedSessions();
});

/// 统计屏八块读数的唯一出口。
///
/// [MdsStatFilter.fold] 在这里**由设置注入**，不让筛选态与设置各存一份口径：
/// chip 的选中态读 [mediaSpeedFoldProvider]，点 chip 只写 KV＋失效重取，
/// 屏上所有读数因此永远同源（刀1 摘掉算面里的折算分支时，页面不需要改一行就会红）。
final mediaStatProvider = FutureProvider<MdsStatRead>((ref) async {
  final f = ref.watch(mdsStatFilterProvider);
  final fold = ref.watch(mediaSpeedFoldProvider).valueOrNull ?? false;
  final sessions = await ref.watch(mediaClosedSessionsProvider.future);
  final items = await ref.watch(mediaAllItemsProvider.future);
  return mdsComputeStat(
    sessions: sessions,
    items: items,
    filter: f.copyWith(fold: fold),
    now: DateTime.now(),
  );
});

/// 单条目已结算会话（轨迹弹层逐次柱与里程碑；日期升序）。
final mediaTrackSessionsProvider = FutureProvider.family<List<MediaSession>, String>((
  ref,
  id,
) {
  ref.watch(mediaTickProvider);
  return ref.watch(mediaRepositoryProvider).closedSessionsOfItem(id);
});

// ==================== 目标屏＋设置生效面（批8a · LH-C22／LH-C23） ====================

/// 目标屏一行的视图模型（定义＋落库目标＋现算读数；goal=null＝未设出虚线）。
typedef MediaGoalRow = ({
  ({String k, String label, String unit, String per}) def,
  MediaGoal? goal,
  num read,
});

/// `media_goals` 全行（未设＝无行）。
final mediaGoalsProvider = FutureProvider<List<MediaGoal>>((ref) {
  ref.watch(mediaTickProvider);
  return ref.watch(mediaRepositoryProvider).goalRows();
});

/// 六路达成读数（**恒吃真实耗时**＝账本 §九.1；折算 chip 不参与，LH-C22 铁口径②）。
final mediaGoalReadsProvider = FutureProvider<Map<String, num>>((ref) async {
  final sessions = await ref.watch(mediaClosedSessionsProvider.future);
  final items = await ref.watch(mediaAllItemsProvider.future);
  final now = DateTime.now();
  final sceneN = await ref
      .watch(mediaRepositoryProvider)
      .sceneNotesBetween(DateTime(now.year, now.month), DateTime(now.year, now.month + 1));
  return mdsComputeGoalReads(
    sessions: sessions,
    items: items,
    sceneNotesThisMonth: sceneN,
    now: now,
  );
});

/// 目标屏六行的唯一出口（行序＝kMdsGoalDefs 固定序；与统计屏目标块同源）。
final mediaGoalRowsProvider = FutureProvider<List<MediaGoalRow>>((ref) async {
  final goals = await ref.watch(mediaGoalsProvider.future);
  final reads = await ref.watch(mediaGoalReadsProvider.future);
  return [
    for (final d in kMdsGoalDefs)
      (
        def: d,
        goal: goals.where((g) => g.metric == d.k).firstOrNull,
        read: reads[d.k] ?? 0,
      ),
  ];
});

/// settings KV 通用**读侧带回落**：表缺席/读失败一律回落默认（老测试库不建 settings 表
/// 也不炸；计划 §九.2 的回落口径，读写都只走 settings 表 KV＝LH-C23 铁口径④）。
Future<String> mediaKvSafe(MediaRepository repo, String key, String def) async {
  try {
    return await repo.kv(key) ?? def;
  } catch (e) {
    AppLog.add('影音 KV 读取失败（回落默认 $key）：$e', src: '数据库');
    return def;
  }
}

/// 默认视图（media.defaultView＝desk）。进架入口在点「影音架」时吃进 mediaViewProvider。
final mediaDefaultViewProvider = FutureProvider<String>((ref) async {
  ref.watch(mediaTickProvider);
  return mediaKvSafe(
      ref.watch(mediaRepositoryProvider), 'media.defaultView', 'desk');
});

/// 默认排序（media.sortDefault＝recent；六档键在进架口映射进架面排序）。
final mediaSortDefaultProvider = FutureProvider<String>((ref) async {
  ref.watch(mediaTickProvider);
  return mediaKvSafe(
      ref.watch(mediaRepositoryProvider), 'media.sortDefault', 'recent');
});

/// 桌面列数（media.wallCols＝2，原型 MSET 同档；进架网格内联轨道吃这一份）。
final mediaWallColsProvider = FutureProvider<int>((ref) async {
  ref.watch(mediaTickProvider);
  return int.tryParse(await mediaKvSafe(
              ref.watch(mediaRepositoryProvider), 'media.wallCols', '2')) ??
          2;
});

/// 新增插入位（media.newPos＝head|tail；录入弹层保存时读，tail＝created_at 取全库最小-1）。
final mediaNewPosProvider = FutureProvider<String>((ref) async {
  ref.watch(mediaTickProvider);
  return mediaKvSafe(ref.watch(mediaRepositoryProvider), 'media.newPos', 'head');
});

/// 笔记弹层「默认带时间点」（media.autoPos＝true）。
final mediaAutoPosProvider = FutureProvider<bool>((ref) async =>
    (await mediaKvSafe(
            ref.watch(mediaRepositoryProvider), 'media.autoPos', 'true')) ==
        'true');

/// 笔记弹层「剪贴板识别」＝粘贴钮显隐（media.clipAuto＝true）。
final mediaClipAutoProvider = FutureProvider<bool>((ref) async =>
    (await mediaKvSafe(
            ref.watch(mediaRepositoryProvider), 'media.clipAuto', 'true')) ==
        'true');

/// 晚间补记提醒（media.dailyQ＝true）：今日无已结算会话才在工作台出提示行（应用内＝§0.4）。
final mediaDailyQHintProvider = FutureProvider<bool>((ref) async {
  ref.watch(mediaTickProvider);
  final repo = ref.watch(mediaRepositoryProvider);
  if ((await mediaKvSafe(repo, 'media.dailyQ', 'true')) != 'true') return false;
  final now = DateTime.now();
  return !(await repo.hasSessionOnDay(DateTime(now.year, now.month, now.day)));
});

/// 影音单一次装载的三面读数（批8b）：手动单行 × 各单成员 × 年度底稿。
///
/// 打包成一个 provider 而不是 family 逐单取：列表面每枚瓦片都要「n 条 · x.x h」，
/// 逐单异步各取各的会让瓦片计数错峰跳；一 tick 一次全取＝整屏同帧。
class MediaListsBundle {
  const MediaListsBundle({
    required this.lists,
    required this.members,
    required this.year,
  });

  final List<MediaList> lists;

  /// listId → 成员条目（pos 序 × 在册过滤）。
  final Map<int, List<MediaItem>> members;

  /// 年度底稿成员（完结档本年 · 达成日倒序 · 零落行）。
  final List<MediaItem> year;

  List<MediaItem> of(MediaList row) => members[row.id] ?? const [];

  /// 底稿合成行（名字＝年份拼出来；id 用 -1 占位，路由侧一律走 'auto' 串）。
  MediaList get yearRow => MediaList(
        id: -1,
        name: '${DateTime.now().year} 影音',
        kindFilter: 'mix',
        createdAt: 0,
      );
}

final mediaListsBundleProvider = FutureProvider<MediaListsBundle>((ref) async {
  ref.watch(mediaTickProvider);
  final repo = ref.watch(mediaRepositoryProvider);
  final lists = await repo.listRows();
  final members = <int, List<MediaItem>>{};
  for (final l in lists) {
    members[l.id] = await repo.listMemberItems(l.id);
  }
  return MediaListsBundle(
    lists: lists,
    members: members,
    year: await repo.yearDraftItems(DateTime.now()),
  );
});

/// 全量在册条目（影音单「添加条目」候选专用）：与 [mediaItemsProvider] 分家，
/// 后者吃架面 kind/分区/关键词筛选态——选择面候选不能被别的屏的筛选态污染。
final mediaAllLiveItemsProvider = FutureProvider<List<MediaItem>>((ref) {
  ref.watch(mediaTickProvider);
  return ref
      .watch(mediaRepositoryProvider)
      .items(kind: 'all', stateGroup: 'all', query: '', sort: 'recent');
});
