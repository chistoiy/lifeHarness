import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../data/inbox_dao.dart';
import '../domain/inbox_item.dart';

final inboxDaoProvider =
    Provider<InboxDao>((ref) => InboxDao(AppDatabase.instance.db));

/// 未整理条目（新→旧；添加/分流/删除后 invalidate）。
/// `dependencies: [inboxDaoProvider]` 是**测试可换库的前提**：不声明时，
/// 上层的 ProviderScope 覆盖 DAO 会被 riverpod 判成「依赖被覆盖而自己没盖」
/// 直接抛断言（外壳单测注入同库 DAO 时必踩）。
final inboxItemsProvider = FutureProvider<List<InboxItem>>(
    (ref) => ref.watch(inboxDaoProvider).listPending(),
    dependencies: [inboxDaoProvider]);
