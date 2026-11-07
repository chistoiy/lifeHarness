import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/providers.dart' show settingsControllerProvider;
import '../data/diary_template_dao.dart';
import '../data/journal_dao.dart';
import '../data/note_dao.dart';
import '../data/note_folder_dao.dart';
import '../data/tag_dao.dart';
import '../domain/diary_template.dart';
import '../domain/journal_entry.dart';
import '../domain/journal_repository.dart';
import '../domain/note.dart';
import '../domain/note_folder.dart';
import '../domain/tag.dart';

final journalRepositoryProvider = Provider<JournalRepository>((ref) {
  return JournalRepository(JournalDao(AppDatabase.instance.db));
});

/// 标签池 DAO（批2b · 池全局唯一，写操作全在这里）。
final tagDaoProvider =
    Provider<TagDao>((ref) => TagDao(AppDatabase.instance.db));

/// 标签池（含全仓引用计数）。
///
/// 读前先跑一次历史标签懒导入：老库升级到 v50 后 `journal_entries.tags` 里的
/// 名字要靠它进池（幂等，判据见 `TagDao.seedFromJournalTags`）。
/// 放在 provider 而不是迁移 SQL 里：迁移只支持纯语句，解析 JSON 得靠 Dart。
final tagPoolProvider = FutureProvider<List<Tag>>((ref) async {
  final dao = ref.watch(tagDaoProvider);
  await dao.seedFromJournalTags();
  return dao.list();
});

/// 日记侧可用标签（口径③：只列 scopes 含 diary 的）。
///
/// 与 [tagPoolProvider] 分开是给编辑页/筛选用的——它们不该看见只属笔记/时间的标签。
final diaryTagPoolProvider = FutureProvider<List<Tag>>((ref) async {
  final all = await ref.watch(tagPoolProvider.future);
  return [for (final t in all) if (t.appliesTo('diary')) t];
});

/// 日记模板（V1.28 真结构：diary_templates + template_sections）。
final diaryTemplateDaoProvider =
    Provider<DiaryTemplateDao>((ref) => DiaryTemplateDao(AppDatabase.instance.db));

final diaryTemplatesProvider = FutureProvider<List<DiaryTemplate>>(
    (ref) => ref.watch(diaryTemplateDaoProvider).list());

/// 笔记 DAO（M0 收集箱分流写入；M1 批1 列表/管理/编辑器接管）。
final noteDaoProvider =
    Provider<NoteDao>((ref) => NoteDao(AppDatabase.instance.db));

/// 笔记列表筛选（V1.29轮6：folder：''=全部 · 其余=文件夹名；
/// 轮8④ asc=方向翻转·再点当前排序项切换 降⇄升/ A→Z⇄Z→A）。
///
/// 批5③（2026-10-12）：起始值自 [UserSettings] 读（**重启不复位**——原为纯内存
/// StateProvider ⇒ 每次冷启动都回「最后修改↓ / 列表 / 全部」）；改值一律经
/// [saveNoteFilter] 写回设置。直接赋 `noteFilterProvider.notifier.state` 只会改内存，
/// 是本能力的唯一破法，改这三档筛选请只用 helper。
final noteFilterProvider =
    StateProvider<({String folder, NoteSort sort, bool asc})>((ref) {
  final s = ref.read(settingsControllerProvider);
  return (
    folder: s.noteFolder,
    sort: NoteSort.values
        .firstWhere((e) => e.name == s.noteSort, orElse: () => NoteSort.updated),
    asc: s.noteSortAsc,
  );
});

/// 批5③：改「文件夹/排序」并写回设置（树侧与列表侧四个入口统一走它）。
void saveNoteFilter(WidgetRef ref, ({String folder, NoteSort sort, bool asc}) f) {
  ref.read(noteFilterProvider.notifier).state = f;
  ref
      .read(settingsControllerProvider.notifier)
      .setNoteFilter(folder: f.folder, sort: f.sort.name, asc: f.asc);
}

/// 批5⑤：按**来源**筛选（''=全部；'local'=本地导入（local_dir + local_file 两来源合一）；
/// 'export'=导出目录；'open_with'=系统打开）。兑现卸载弹层
/// 「已导入的 N 条笔记保留在库 · 来源标仍可筛」这句承诺——原实现只有文件夹+排序，
/// 没有任何按来源看的入口。
final noteSourceProvider = StateProvider<String>((ref) => '');

/// 批4①：文件夹树的**展开集合**（跨开合保留）。
/// 原为 `_TreeDrawerState` 局部态 ⇒ 面板收起时 `NoteTreeOverlay` 把面板换成
/// `SizedBox.shrink()`、State 被 dispose、展开态全丢（只剩选中项自动展开）；
/// 原型 `ntOpen` 是模块级变量、跨开关保留。提到 provider 后与面板生命周期解耦。
final noteTreeOpenProvider = StateProvider<Set<int>>((ref) => const {});

// V1.60 全局回收站：笔记不再有 `__trash__` 特殊筛选值与页内垃圾箱视图，
// 回收站六类统一进 `/settings/trash`（抽屉入口改道），故本屏只出在册笔记。

/// 笔记视图（0=列表；2/3=卡片每行列数 · 轮9b 循环收为 列表→2→3·瀑布流错落）。
/// 批5③：起始从设置读、改值走 [saveNoteViewCols]（脏值收敛到 0=列表）。
final noteViewColsProvider = StateProvider<int>((ref) {
  final c = ref.read(settingsControllerProvider).noteViewCols;
  return (c == 2 || c == 3) ? c : 0;
});

/// 批5③：改视图档并写回设置。
void saveNoteViewCols(WidgetRef ref, int cols) {
  ref.read(noteViewColsProvider.notifier).state = cols;
  ref.read(settingsControllerProvider.notifier).setNoteViewCols(cols);
}

/// 批量选择中的笔记 id 集（空=普通模式；长按卡片进入）。
final noteSelProvider = StateProvider<Set<int>>((ref) => const {});

/// 笔记列表（随筛选刷新；保存/置顶/归档/删除后 invalidate）。
final notesProvider = FutureProvider<List<Note>>((ref) async {
  final f = ref.watch(noteFilterProvider);
  final src = ref.watch(noteSourceProvider);
  final dao = ref.watch(noteDaoProvider);
  final list = await dao.list(
      folder: f.folder.isEmpty ? null : f.folder, sort: f.sort, asc: f.asc);
  if (src.isEmpty) return list;
  // 来源筛选在内存侧过（DAO.list 无 source 形参）；'local' 覆盖 local_dir + local_file 两来源。
  bool match(String s) => switch (src) {
        'local' => s == 'local_dir' || s == 'local_file',
        _ => s == src,
      };
  return [
    for (final n in list)
      if (match(n.source)) n,
  ];
});

/// 笔记文件夹 chips 行（含去重来源）。
final noteFoldersProvider =
    FutureProvider<List<String>>((ref) => ref.watch(noteDaoProvider).folders());

/// 笔记文件夹树 DAO（V1.29 批A1 · note_folders 多层嵌套）。
final noteFolderDaoProvider =
    Provider<NoteFolderDao>((ref) => NoteFolderDao(AppDatabase.instance.db));

/// 文件夹原始列表（增删改后 invalidate）。
/// V1.67：读值前先做「默认归属兜底」（幂等·零散笔记零写入）——本 provider 是
/// 列表 chips 与树的共同上游，兜底挂这里＝树/弹层/列表任何入口都先归位再出数。
final noteFolderListProvider = FutureProvider<List<NoteFolder>>(
    (ref) async {
  final dao = ref.watch(noteFolderDaoProvider);
  await dao.ensureDefaultOwnership();
  return dao.list();
});

/// 渲染树（含各夹直属笔记数；随笔记与文件夹变化刷新）。
final noteTreeProvider = FutureProvider<List<FolderNode>>((ref) async {
  final all = ref.watch(noteFolderListProvider).valueOrNull ?? const [];
  ref.watch(notesProvider); // 笔记增删/移动后计数刷新
  final counts = await ref.watch(noteDaoProvider).folderCounts();
  return NoteFolderDao.buildTree(all, noteCounts: counts);
});

/// V1.64 批2 N-1c：仍含本地来源笔记的夹名（树上「本地」挂标的自动回落判据）。
final noteLocalFoldersProvider = FutureProvider<Set<String>>(
    (ref) => ref.watch(noteDaoProvider).foldersHoldingLocalNotes());

/// 全部日记（新→旧）。
/// 语义断链批 #26（2026-10-12）：FutureProvider → AsyncNotifier——热路径
/// （点赞/星标/天气/回望计数）改单篇 patch（改哪篇补哪篇），不再整表重拉；
/// 保存/删除/联动等结构性变化仍走 ref.invalidate 全量刷新。
/// 读法兼容：AsyncValue 与 FutureProvider 同形，既有 `.valueOrNull`/`.when` 不动。
class JournalsNotifier extends AsyncNotifier<List<JournalEntry>> {
  @override
  Future<List<JournalEntry>> build() =>
      ref.watch(journalRepositoryProvider).list();

  /// 单篇原位替换：列表未载入/该篇不在库＝丢弃，等下次全量刷新对齐。
  /// 入参应是**页内当前完整对象**（copyWith 出来的，保留 sections），勿传裸 DB 行。
  void patch(JournalEntry e) {
    final cur = state.valueOrNull;
    if (cur == null || e.id == null) return;
    state = AsyncData([
      for (final x in cur)
        if (x.id == e.id) e else x,
    ]);
  }
}

final journalsProvider =
    AsyncNotifierProvider<JournalsNotifier, List<JournalEntry>>(
        JournalsNotifier.new);

/// 连续记录天数（记录页渐变卡）。
final journalStreakProvider = FutureProvider<int>((ref) {
  ref.watch(journalsProvider);
  return ref.watch(journalRepositoryProvider).streak();
});

/// 那年今日（记录页日记段尾卡）。UI/流畅批（2026-10-12）：原在 build 里
/// 现建 future——多选勾选等每次 setState 都重查 DB；提为 provider 后
/// 结果按列表失效缓存（增删日记才重查），setState 不再触发。
final onThisDayProvider = FutureProvider<JournalEntry?>((ref) {
  ref.watch(journalsProvider); // 列表增删后随之刷新
  return ref.watch(journalRepositoryProvider).onThisDayLastYear();
});

/// 记录页筛选（'all' 或标签名）。
/// 语义断链批 #27（2026-10-12）：日记段筛选/INS 布局持久化（笔记批5③ 同族）。
/// 读＝settings 派生（冷启动恢复上次态）；写＝走 SettingsController 落盘
/// （原两 StateProvider 纯内存态，冷启动复位）。
final journalFilterProvider = Provider<String>(
    (ref) => ref.watch(settingsControllerProvider).journalFilter);

/// 日记改版收尾批（2026-10-19）：筛选**标签多选**（AND 语义）。
///
/// 与 [journalFilterProvider]（标记单选）正交并存——两条都命中才算筛出。
/// 旧版本把标签名存在 `journalFilter` 单值里，读侧由 `dfTagsOf` 做只读兼容，
/// 所以这里**只读新键**，不做迁移写盘。
final journalTagsProvider = Provider<List<String>>(
    (ref) => ref.watch(settingsControllerProvider).journalTags);
final journalInsProvider =
    Provider<bool>((ref) => ref.watch(settingsControllerProvider).journalIns);

/// 日记页视图三档（日记改版批1a）：`track` / `list` / `ins`，默认 `list`。
/// 旧 [journalInsProvider] 保留给「关闭 INS 就回列表」的旧调用点；新代码一律读这条。
final journalLayoutProvider = Provider<String>(
    (ref) => ref.watch(settingsControllerProvider).journalLayout);

/// 日记改版批2d（2026-10-19）：筛选时间段（8 档预设键 或 `custom`）。
/// 档位表与判据在 `domain/diary_filter_kit.dart`（`kDiaryRanges` / `diaryInRange`）。
final journalRangeProvider = Provider<String>(
    (ref) => ref.watch(settingsControllerProvider).journalRange);

/// 日记改版批2d：自定义起止（`YYYY-MM-DD`；空串＝该端不设限＝开区间）。
///
/// 合成一条 record 而不是两个 provider：这两键**永远一起用**（判区间要同时看两端），
/// 拆开只会让每个调用方各 watch 两次、漏一处就出「只按起始日筛」的偏。
final journalSpanProvider = Provider<({String from, String to})>((ref) {
  final s = ref.watch(settingsControllerProvider);
  return (from: s.journalFrom, to: s.journalTo);
});

/// 记录页四段 tab（diary/note/book/media）。
final recordTabProvider = StateProvider<String>((ref) => 'diary');
