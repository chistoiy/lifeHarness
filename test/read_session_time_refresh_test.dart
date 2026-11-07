import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/calendar/data/time_block_dao.dart';
import 'package:lifeharness/features/calendar/domain/time_block.dart';
import 'package:lifeharness/features/calendar/presentation/calendar_providers.dart';
import 'package:lifeharness/features/read/presentation/read_actions.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 6075 真机测出缺陷：阅读侧结算/编辑/删除落的 L4 时间块是 repo 层直写库，
/// 时间模块的 dayBlocks/monthBlockDays 不 invalidate 不会重取（此前只有冷启动才见新块）。
/// 本文件＝行为钉（不刷看不见／刷了看得见）＋源码守护（防八处写点漏接）。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  group('refreshTimeAfterSession · 行为', () {
    late Database db;
    late TimeBlockDao dao;
    late ProviderContainer c;
    final day = DateTime(2026, 10, 6);

    setUp(() async {
      db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
      for (final sql in DbSchema.createStatements) {
        await db.execute(sql);
      }
      dao = TimeBlockDao(db);
      c = ProviderContainer(
        overrides: [timeBlockDaoProvider.overrideWithValue(dao)],
      );
    });
    tearDown(() async {
      c.dispose();
      await db.close();
    });

    test('不刷新看不见新块·刷新后看得见', () async {
      await dao.insert(TimeBlock(
          day: day, startMin: 60, endMin: 90, catName: '工作'));
      expect((await c.read(dayBlocksProvider(day).future)).length, 1);
      // 模拟阅读结算 _syncTxn 的直写库（绕过任何 provider）
      await db.insert(DbSchema.tTimeBlocks, {
        'day': day.millisecondsSinceEpoch,
        'start_min': 120,
        'end_min': 150,
        'category': '阅读',
        'note': '《测试书》',
        'source': 'mark',
        'cat_id': DbSchema.catReadingId,
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });
      // 这条红了＝provider 本身会重取，缺陷另有成因（当前真机证明它不重取）
      expect((await c.read(dayBlocksProvider(day).future)).length, 1);
      refreshTimeAfterSession(
          c, [day.add(const Duration(hours: 2)).millisecondsSinceEpoch]);
      expect((await c.read(dayBlocksProvider(day).future)).length, 2);
    });

    test('空时刻不炸·同日多时刻归一', () async {
      refreshTimeAfterSession(c, [null]);
      final ms = day.millisecondsSinceEpoch;
      refreshTimeAfterSession(c, [ms, ms + 1000, ms + 2000]);
      expect(await c.read(dayBlocksProvider(day).future), isEmpty);
    });
  });

  test('源码守护：阅读侧每个写点都接了刷新（定义 1＋调用 7）', () {
    // 文件 → 最少出现次数（read_actions 含定义行与 readTimerTap 调用）
    const floors = {
      'lib/features/read/presentation/read_actions.dart': 2,
      'lib/features/read/presentation/reader/reader_page.dart': 2,
      'lib/features/read/presentation/stats/read_timer_page.dart': 1,
      'lib/features/read/presentation/stats/read_log_page.dart': 4,
    };
    for (final e in floors.entries) {
      final src = File(e.key).readAsStringSync();
      final n = 'refreshTimeAfterSession('.allMatches(src).length;
      expect(n, greaterThanOrEqualTo(e.value),
          reason: '${e.key} 出现 $n < ${e.value}，写点漏接时间侧刷新');
    }
  });
}
