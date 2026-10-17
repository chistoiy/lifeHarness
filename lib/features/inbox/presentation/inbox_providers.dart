import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../data/inbox_dao.dart';
import '../domain/inbox_item.dart';

final inboxDaoProvider =
    Provider<InboxDao>((ref) => InboxDao(AppDatabase.instance.db));

/// 未整理条目（新→旧；添加/分流/删除后 invalidate）。
final inboxItemsProvider = FutureProvider<List<InboxItem>>(
    (ref) => ref.watch(inboxDaoProvider).listPending());
