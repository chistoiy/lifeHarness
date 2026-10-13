import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:lifeharness/features/read/domain/book.dart';

/// 阅读模块批1 · F1-6 统计去伪随机 + F1-7 钻取联动与真读数
/// （doc 冻结方案 §2.1 F1-6/F1-7 · §6.4）。
///
/// F1-6：统计取数链 0 处伪随机（`Random`/LCG/取模造数）——源码守护。
/// F1-7：统计读数全部取真（今日分钟/自然日列表直接从落库会话现算）。
void main() {
  sqfliteFfiInit();

  group('F1-6 统计取数链无伪随机（源码守护）', () {
    test('F1-6a 统计相关源文件不含 Random/LCG 造数', () {
      // 统计取数与呈现链（读数来源），逐个扫「伪随机」关键词。
      const files = [
        'lib/features/read/presentation/stats/read_stat_page.dart',
        'lib/features/read/presentation/stats/read_stat_widgets.dart',
        'lib/features/read/presentation/stats/read_stat_heat_card.dart',
      ];
      final banned = RegExp(r'\bRandom\b|\bLCG\b|nextInt|nextDouble');
      for (final f in files) {
        final src = File(f).readAsStringSync();
        for (final (i, line) in src.split('\n').indexed) {
          final t = line.trim();
          if (t.startsWith('//')) continue; // 注释不算
          expect(banned.hasMatch(t), isFalse,
              reason: '$f:${i + 1} 命中伪随机（统计去伪随机＝F1-6）：$t');
        }
      }
    });
  });

  group('F1-7 统计真读数（现算自落库会话）', () {
    late Database db;
    late ReadRepository repo;

    setUp(() async {
      db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
      for (final sql in DbSchema.createStatements) {
        await db.execute(sql);
      }
      repo = ReadRepository(db);
    });
    tearDown(() => db.close());

    test('F1-7a minutesOnDay 现算：今日会话分钟之和', () async {
      final b = await repo.addBook(
          Book(title: '书', createdAt: 0, updatedAt: 0));
      final today = DateTime.now();
      await repo.addManualSession(bookId: b.id, day: today, minutes: 25);
      await repo.addManualSession(bookId: b.id, day: today, minutes: 35);
      // 昨天入账不入今日
      await repo.addManualSession(
          bookId: b.id, day: today.subtract(const Duration(days: 1)), minutes: 99);
      expect(await repo.minutesOnDay(today), 60,
          reason: '今日＝25+35=60，昨天 99 不计入');
    });

    test('F1-7b readingDays 现算：只含有入账的自然日', () async {
      final b = await repo.addBook(
          Book(title: '书', createdAt: 0, updatedAt: 0));
      final d1 = DateTime(2026, 10, 12);
      final d2 = DateTime(2026, 10, 13);
      await repo.addManualSession(bookId: b.id, day: d1, minutes: 10);
      await repo.addManualSession(bookId: b.id, day: d2, minutes: 20);
      final days = await repo.readingDays();
      expect(days, hasLength(2));
      expect(days.first.isAfter(days.last) || days.first == days.last, isTrue,
          reason: '倒序');
    });

    test('F1-7c minutesThisWeek 现算：本周一起算', () async {
      final b = await repo.addBook(
          Book(title: '书', createdAt: 0, updatedAt: 0));
      final now = DateTime.now();
      await repo.addManualSession(bookId: b.id, day: now, minutes: 15);
      expect(await repo.minutesThisWeek(), greaterThanOrEqualTo(15));
    });
  });
}
