// 真机反馈轮4⑥（工单 交棒话术-20261004-真机反馈轮4批）：阅读页不在前台必须暂停计时。
// 钉三件事：① 退后台＝当前会话段就地封口（ended_at 落库，不再随时钟长）；
// ② 回前台＝为同一本书另开一段（段与段之间的那段时间不入账）；
// ③ 退出阅读器只结算前台段——两段都在库里，且没有「跨后台的整块时长」。
// 独立文件防 isolate 污染；门槛设 0 秒（默认 30 秒会把短段整条删掉＝看不见落库行）。
@TestOn('windows')
library;


import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/logging/app_log.dart';
import 'package:lifeharness/core/providers.dart' show sharedPreferencesProvider;
import 'package:lifeharness/features/read/data/epub_doc.dart';
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:lifeharness/features/read/domain/book.dart';
import 'package:lifeharness/features/read/presentation/read_providers.dart';
import 'package:lifeharness/features/read/presentation/reader/reader_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';

EpubDoc _doc() => EpubDoc(
  format: 'EPUB3',
  title: '计时书',
  author: '甲',
  toc: const [],
  chapters: [
    EpubChapter(href: 'c1', title: '第一章', paras: [
      for (var i = 0; i < 8; i++)
        EpubPara(kind: EpubParaKind.text, text: '第$i段正文素材，够长就能分页。'),
    ]),
  ],
  imageCount: 0,
  totalChars: 200,
);

void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(Database, ReadRepository)> open(WidgetTester t, String id) async {
    AppLog.reset();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    addTearDown(db.close);
    final repo = ReadRepository(db);
    await repo.addBook(Book(
      id: id,
      title: '计时书',
      local: true,
      epub: const EpubRef(fmt: 'EPUB3', size: 10, path: 'mem'),
      createdAt: 1,
      updatedAt: 1,
    ));
    await repo.setKv('read.brMinSecs', '0'); // 短段也入账，才看得见封口行
    await useSurface(t, const Size(420, 780));
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          readRepositoryProvider.overrideWithValue(repo),
          sharedPreferencesProvider.overrideWithValue(prefs),
          epubDocLoaderProvider.overrideWithValue((_) async => _doc()),
        ],
        child: MaterialApp(home: ReaderPage(bookId: id)),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }
    return (db, repo);
  }

  Future<List<Map<String, Object?>>> rows(Database db, String id) => db.query(
    DbSchema.tBookSessions,
    where: 'book_id = ?',
    whereArgs: [id],
    orderBy: 'started_at ASC',
  );

  testWidgets('进页开一段·退后台封口·回前台另开一段（后台时长不入账）', (t) async {
    final id = 'bg1';
    final (db, repo) = await open(t, id);

    // ① 前台在跑：恰好一段未封口
    final running0 = await repo.runningSession();
    expect(running0, isNotNull, reason: '进阅读页应自动挂起计时');
    expect(running0!.bookId, id);

    // ② 退后台：当前段封口（ended_at 落库），不再有未结束段
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await t.pump(const Duration(milliseconds: 250));
    expect(await repo.runningSession(), isNull, reason: '后台还在计时＝本条要红');
    var rs = await rows(db, id);
    expect(rs, hasLength(1));
    expect(rs.first['ended_at'], isNotNull);

    // ③ 回前台：为同一本书另开一段（新行未结束）
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pump(const Duration(milliseconds: 250));
    final running1 = await repo.runningSession();
    expect(running1, isNotNull, reason: '回前台没续上计时');
    expect(running1!.bookId, id);
    rs = await rows(db, id);
    expect(rs, hasLength(2), reason: '后台前后应各成一段，不是一条跨后台的长段');

    // ④ 再退一次后台＝再封一段：每次挂起都留一条已结束行，绝不允许「跨后台的长段」
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await t.pump(const Duration(milliseconds: 250));
    expect(await repo.runningSession(), isNull, reason: '第二次退后台没封口');
    rs = await rows(db, id);
    final closed = rs.where((r) => r['ended_at'] != null).toList();
    expect(closed, hasLength(2), reason: '两段前台阅读各自入账');
    expect(
      rs.where((r) => r['ended_at'] == null),
      isEmpty,
      reason: '挂起态不该留在跑的会话（此刻＝2 段已封口·0 段在跑）',
    );
    // 时长只按前台段累加：跨后台那段时间不落进任何一行
    expect(closed.every((r) => (r['ended_at'] as int) >= (r['started_at'] as int)), isTrue);

    await settle5(t);
  });
}
