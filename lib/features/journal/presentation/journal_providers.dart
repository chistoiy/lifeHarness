import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../data/journal_dao.dart';
import '../domain/journal_entry.dart';
import '../domain/journal_repository.dart';

final journalRepositoryProvider = Provider<JournalRepository>((ref) {
  return JournalRepository(JournalDao(AppDatabase.instance.db));
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
