import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../data/diary_template_dao.dart';
import '../data/journal_dao.dart';
import '../data/note_dao.dart';
import '../data/note_folder_dao.dart';
import '../domain/diary_template.dart';
import '../domain/journal_entry.dart';
import '../domain/journal_repository.dart';
import '../domain/note.dart';
import '../domain/note_folder.dart';

final journalRepositoryProvider = Provider<JournalRepository>((ref) {
  return JournalRepository(JournalDao(AppDatabase.instance.db));
});

/// 日记模板（V1.28 真结构：diary_templates + template_sections）。
final diaryTemplateDaoProvider =
    Provider<DiaryTemplateDao>((ref) => DiaryTemplateDao(AppDatabase.instance.db));

final diaryTemplatesProvider = FutureProvider<List<DiaryTemplate>>(
    (ref) => ref.watch(diaryTemplateDaoProvider).list());

/// 笔记 DAO（M0 收集箱分流写入；M1 批1 列表/管理/编辑器接管）。
final noteDaoProvider =
    Provider<NoteDao>((ref) => NoteDao(AppDatabase.instance.db));

/// 笔记列表筛选（V1.29轮6：页内搜索移除·query 恒空由全局搜索承接；
/// folder：''=全部 · '__trash__'=回收站 · 其余=文件夹名；
/// 轮8④ asc=方向翻转·再点当前排序项切换 降⇄升/ A→Z⇄Z→A）。
final noteFilterProvider =
    StateProvider<({String folder, NoteSort sort, bool asc})>(
        (ref) => (folder: '', sort: NoteSort.updated, asc: false));

/// 回收站特殊文件夹值。
const kNoteTrash = '__trash__';

/// 笔记视图（0=列表；2/3/4=卡片每行列数 · 原型 ☰/▦ 循环）。
final noteViewColsProvider = StateProvider<int>((ref) => 0);

/// 批量选择中的笔记 id 集（空=普通模式；长按卡片进入）。
final noteSelProvider = StateProvider<Set<int>>((ref) => const {});

/// 笔记列表（随筛选刷新；保存/置顶/归档/删除后 invalidate）。
final notesProvider = FutureProvider<List<Note>>((ref) async {
  final f = ref.watch(noteFilterProvider);
  final dao = ref.watch(noteDaoProvider);
  if (f.folder == kNoteTrash) return dao.trash();
  return dao.list(
      folder: f.folder.isEmpty ? null : f.folder, sort: f.sort, asc: f.asc);
});

/// 笔记文件夹 chips 行（含去重来源）。
final noteFoldersProvider =
    FutureProvider<List<String>>((ref) => ref.watch(noteDaoProvider).folders());

/// 笔记文件夹树 DAO（V1.29 批A1 · note_folders 多层嵌套）。
final noteFolderDaoProvider =
    Provider<NoteFolderDao>((ref) => NoteFolderDao(AppDatabase.instance.db));

/// 文件夹原始列表（增删改后 invalidate）。
final noteFolderListProvider = FutureProvider<List<NoteFolder>>(
    (ref) => ref.watch(noteFolderDaoProvider).list());

/// 渲染树（含各夹直属笔记数；随笔记与文件夹变化刷新）。
final noteTreeProvider = FutureProvider<List<FolderNode>>((ref) async {
  final all = ref.watch(noteFolderListProvider).valueOrNull ?? const [];
  ref.watch(notesProvider); // 笔记增删/移动后计数刷新
  final counts = await ref.watch(noteDaoProvider).folderCounts();
  return NoteFolderDao.buildTree(all, noteCounts: counts);
});

/// 全部日记（新→旧；保存/回望操作后 invalidate 刷新）。
final journalsProvider = FutureProvider<List<JournalEntry>>(
    (ref) => ref.watch(journalRepositoryProvider).list());

/// 连续记录天数（记录页渐变卡）。
final journalStreakProvider = FutureProvider<int>((ref) {
  ref.watch(journalsProvider);
  return ref.watch(journalRepositoryProvider).streak();
});

/// 记录页筛选（'all' 或标签名）。
final journalFilterProvider = StateProvider<String>((ref) => 'all');

/// 记录页布局（false=列表 true=INS 卡片流）。
final journalInsProvider = StateProvider<bool>((ref) => false);

/// 记录页四段 tab（diary/note/book/media）。
final recordTabProvider = StateProvider<String>((ref) => 'diary');
