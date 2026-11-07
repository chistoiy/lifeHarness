import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:lifeharness/features/read/domain/book.dart';
import 'package:lifeharness/features/read/domain/book_session.dart';
import 'package:lifeharness/features/read/domain/shelf_query.dart';

/// 阅读模块批1 · F1-1 计时时长真实落库（doc 冻结方案 §2.1 F1-1 · §6.4）。
///
/// 口径（「先快照秒数再停表」）：
/// - 结束计时＝先用 `runningSession()` 快照在跑会话，再 `_close` 落 `minutes`；
///   读数（toast/进度表单 timerMinutes）取的就是这一次快照的 `closeRunning` 结果，
///   与落库同源；
/// - `minutes = (elapsed/60000).ceil()`：不足 1 分钟算 1 分钟（≥1），
///   故「先停表再算」与「先快照再停」在读数上都应等于真实耗时。
void main() {
  sqfliteFfiInit();

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

  test('F1-1a closeRunning：不足 1 分钟算 1 分钟 · 真实耗时 ceil', () {
    // 快照法：startedAt 与 nowMs 差 90s → ceil(1.5) = 2 分钟
    final s = BookSession(bookId: 'b', startedAt: 0);
    final closed = closeRunning(s, 90000);
    expect(closed, isNotNull);
    expect(closed!.minutes, 2, reason: '90s → ceil = 2 分钟（≥1 且真实）');
    // 10 秒 → 1 分钟（下限 1，不落 0）
    expect(closeRunning(BookSession(bookId: 'b', startedAt: 0), 10000)!.minutes, 1);
    // 回拨（nowMs < startedAt）→ 丢弃
    expect(closeRunning(BookSession(bookId: 'b', startedAt: 9000), 100), isNull);
  });

  test('F1-1b endSession 落库 minutes 与快照读数一致', () async {
    final b = await repo.addBook(
        Book(title: '计时书', createdAt: 0, updatedAt: 0));
    final started = DateTime.now().subtract(const Duration(minutes: 3, seconds: 20));
    // 直接落一条在跑会话（started_at 回拨 3m20s）
    final id = await db.insert(
      DbSchema.tBookSessions,
      BookSession(bookId: b.id, startedAt: started.millisecondsSinceEpoch).toRow(),
    );
    final closed = await repo.endSession(b.id);
    expect(closed, isNotNull);
    expect(closed!.id, id);
    // 3m20s → ceil = 4 分钟；落库读数＝快照读数
    expect(closed.minutes, 4);
    final row = (await db.query(DbSchema.tBookSessions,
            where: 'id = ?', whereArgs: [id]))
        .single;
    expect(row['minutes'], 4, reason: '落库 minutes 与快照读数同源');
    expect(row['ended_at'], isNotNull);
  });

  test('F1-1c 无在跑会话时 endSession 返回 null（读数不伪造）', () async {
    final b = await repo.addBook(
        Book(title: '空书', createdAt: 0, updatedAt: 0));
    expect(await repo.endSession(b.id), isNull);
  });

  test('F1-1d billedMinutes 落库口径：有声倍速折算（初始 1.0 不折）', () {
    // speed=1.0 → 折算后＝原值（不缩水）
    final s1 = BookSession(
        bookId: 'b', startedAt: 0, endedAt: 60000, minutes: 30, speed: 1.0);
    expect(s1.billedMinutes, 30);
    // 无 speed（纸质/电子书）→ 原样
    final s2 = BookSession(bookId: 'b', startedAt: 0, endedAt: 60000, minutes: 30);
    expect(s2.billedMinutes, 30);
  });
}
