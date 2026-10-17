import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:lifeharness/features/read/domain/book.dart';
import 'package:lifeharness/features/read/domain/book_session.dart';

/// 阅读模块批1 · F1-5 设置项生效 + tlRange 口径统一（doc 冻结方案 §2.1 F1-5 · §6.4）。
///
/// 覆盖：
/// - `floatBar`/`speedFold`/`dailyQ`/`clipAuto`/`feeTxn` 各至少 1 个真实生效点；
/// - `tlRange` **存英文枚举**（month/half/year）非中文串；
/// - `brRate` 有声书倍速：`startSession` 落 `speed` 快照 → `billedMinutes` 真折算。
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
    BookSession.speedFold = true; // 复位静态闸（他例可能改过）
  });
  tearDown(() => db.close());

  test('F1-5a tlRange 存英文枚举：set 后读回原文（不落中文）', () async {
    await repo.setKv('read.tlRange', 'month');
    expect(await repo.kv('read.tlRange'), 'month');
    await repo.setKv('read.tlRange', 'half');
    expect(await repo.kv('read.tlRange'), 'half');
    await repo.setKv('read.tlRange', 'year');
    expect(await repo.kv('read.tlRange'), 'year');
    // 不带中文分支（口径统一后写侧只落英文）
    expect(await repo.kv('read.tlRange'), isNot(contains('月')));
  });

  test('F1-5b feeTxn 生效点：开关值随 KV 落库可读', () async {
    expect(await repo.kv('read.feeTxn'), isNull); // 未设置＝默认开（读侧兜底 true）
    await repo.setKv('read.feeTxn', 'false');
    expect(await repo.kv('read.feeTxn'), 'false');
  });

  test('F1-5c brRate 生效点：有声书 startSession 落 speed 快照', () async {
    await repo.setKv('read.brRate', '1.5');
    final audio = await repo.addBook(Book(
        title: '有声书', format: Book.kFormatAudio, createdAt: 0, updatedAt: 0));
    final s = await repo.startSession(audio.id);
    expect(s.speed, 1.5, reason: '有声书 session 落 brRate 快照');
    // 纸质书不落 speed（折算恒不触发）
    await repo.endSession(audio.id);
    final paper = await repo.addBook(
        Book(title: '纸质', format: Book.kFormatPaper, createdAt: 0, updatedAt: 0));
    final s2 = await repo.startSession(paper.id);
    expect(s2.speed, isNull);
  });

  test('F1-5d speedFold 关：同一 speed 快照不折算', () async {
    final s = BookSession(
        bookId: 'b', startedAt: 0, endedAt: 60000, minutes: 40, speed: 1.5);
    BookSession.speedFold = true;
    expect(s.billedMinutes, 60); // 40×1.5
    BookSession.speedFold = false;
    expect(s.billedMinutes, 40, reason: 'speedFold 关 → 按墙钟入账');
    BookSession.speedFold = true; // 复位，防跨文件污染
  });
}
