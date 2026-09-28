import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/providers.dart' show sharedPreferencesProvider;
import 'package:lifeharness/features/read/data/epub_doc.dart';
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:lifeharness/features/read/domain/book.dart';
import 'package:lifeharness/features/read/domain/book_session.dart';
import 'package:lifeharness/features/read/domain/shelf_query.dart';
import 'package:lifeharness/features/read/presentation/read_providers.dart';
import 'package:lifeharness/features/read/presentation/read_settings_page.dart';
import 'package:lifeharness/features/read/presentation/reader_page.dart';

// V1.53.2 轮5.2② · 阅读计时自动结算（DB v27）：
// 退出阅读器自动写起止章节/页/百分比，短会话按 read.brMinSecs 门槛整条丢弃。
// 独立文件防 isolate 污染；FakeAsync 下不注入 docsPath（真文件 IO 会挂）。

EpubPara _p(String t) => EpubPara(kind: EpubParaKind.text, text: t);

const _lorem = '这是分页实测正文素材，默认字号下约两到三行。';

EpubDoc _doc() => EpubDoc(
  format: 'EPUB3',
  title: '结算书',
  author: '甲',
  toc: const [],
  chapters: [
    EpubChapter(
      href: 'c1',
      title: '第一章',
      paras: [
        const EpubPara(
          kind: EpubParaKind.heading,
          text: '第一章',
          headingLevel: 1,
        ),
        ...List.generate(30, (i) => _p('一之$i。$_lorem')),
      ],
    ),
    EpubChapter(
      href: 'c2',
      title: '第二章',
      paras: [
        const EpubPara(
          kind: EpubParaKind.heading,
          text: '第二章',
          headingLevel: 1,
        ),
        ...List.generate(24, (i) => _p('二之$i。$_lorem')),
      ],
    ),
  ],
  imageCount: 0,
  totalChars: 4000,
  images: const {},
);

void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late ReadRepository repo;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = ReadRepository(db);
  });
  tearDown(() => db.close());

  Future<void> step(WidgetTester t, {int ms = 200, int times = 1}) async {
    for (var i = 0; i < times; i++) {
      await t.pump(Duration(milliseconds: ms));
    }
  }

  Widget wrap(Widget home) => ProviderScope(
    overrides: [
      readRepositoryProvider.overrideWithValue(repo),
      sharedPreferencesProvider.overrideWithValue(prefs),
      epubDocLoaderProvider.overrideWithValue((_) async => _doc()),
    ],
    child: MaterialApp(home: home),
  );

  Future<void> addBook(String id) => repo.addBook(
    Book(
      id: id,
      title: '结算书',
      local: true,
      epub: const EpubRef(fmt: 'EPUB3', size: 10, path: 'mem'),
      createdAt: 1,
      updatedAt: 1,
    ),
  );

  group('轮5.2② · 会话门槛（纯函数与仓储）', () {
    test('closeRunning：未达门槛返回 null · 达门槛按 1 分钟起计', () {
      final s = BookSession(bookId: 'g', startedAt: 0);
      expect(closeRunning(s, 29 * 1000, minSecs: 30), isNull);
      final ok = closeRunning(s, 31 * 1000, minSecs: 30)!;
      expect(ok.minutes, 1);
      // 不传门槛＝不设限（工作台/计时页手动结束仍按原语义入账）。
      expect(closeRunning(s, 5 * 1000)?.minutes, 1);
      // 时钟回拨优先：无论如何丢弃。
      expect(closeRunning(BookSession(bookId: 'g', startedAt: 9000), 100), isNull);
    });

    test('startSession(at) 落 from_* · endSession(to) 落 to_*', () async {
      await addBook('s1');
      final ses = await repo.startSession(
        's1',
        at: const BrLoc(page: 12, pct: 20, chapter: '第一章'),
      );
      final run = (await repo.runningSession())!;
      expect(run.fromChapter, '第一章');
      expect(run.fromPage, 12);
      expect(run.fromPct, 20);
      final closed = (await repo.endSession(
        's1',
        to: const BrLoc(page: 40, pct: 66, chapter: '第二章'),
      ))!;
      expect(closed.id, ses.id);
      final row = (await repo.sessionsOf('s1')).single;
      expect(row.toChapter, '第二章');
      expect(row.toPage, 40);
      expect(row.toPct, 66);
    });

    test('stampSessionStart：进页时文档未就绪 → 就绪后补写起始快照', () async {
      await addBook('s2');
      final ses = await repo.startSession('s2');
      await repo.stampSessionStart(
        ses.id!,
        const BrLoc(page: 3, pct: 7.5, chapter: '第一章'),
      );
      final row = (await repo.sessionsOf('s2')).single;
      expect(row.fromChapter, '第一章');
      expect(row.fromPct, 7.5);
    });

    test('未达门槛：endSession 删行不入账（明细里不留痕）', () async {
      await addBook('s3');
      await repo.startSession('s3', at: const BrLoc(page: 1, pct: 1));
      expect(await repo.endSession('s3', minSecs: 3600), isNull);
      expect(await repo.sessionsOf('s3'), isEmpty);
    });
  });

  group('轮5.2② · DB v27 与设置项', () {
    test('v27 迁移步在册 · 新列在建库语句里', () async {
      expect(DbSchema.migrations.containsKey(26), isTrue);
      final cols = (await db.rawQuery('PRAGMA table_info(book_sessions)'))
          .map((r) => '${r['name']}')
          .toList();
      for (final c in [
        'from_chapter',
        'to_chapter',
        'from_pct',
        'to_pct',
      ]) {
        expect(cols, contains(c), reason: c);
      }
    });

    testWidgets('本地阅读器组新增门槛行 · chip 落 read.brMinSecs', (t) async {
      await useSurface(t);
      await t.pumpWidget(wrap(const ReadSettingsPage()));
      await step(t, times: 3);
      await t.tap(find.byKey(const ValueKey('set-tab-5')));
      await step(t, times: 2);
      expect(find.text('短于该时长的阅读不计入'), findsOne);
      // 默认 30 秒（未落键时按默认选中）。
      expect(find.byKey(const ValueKey('set-brMinSecs-60')), findsOne);
      await t.tap(find.byKey(const ValueKey('set-brMinSecs-60')));
      await step(t, times: 2);
      expect(await repo.kv('read.brMinSecs'), '60');
    });
  });

  group('轮5.2② · 阅读器退出自动结算', () {
    Future<void> open(WidgetTester t, String id) async {
      await useSurface(t, const Size(420, 780));
      await addBook(id);
      await t.pumpWidget(wrap(ReaderPage(bookId: id)));
      await step(t, times: 4);
    }

    testWidgets('翻到第二章后退出：会话行自动带起止章节与百分比', (t) async {
      await repo.setKv('read.brMinSecs', '0');
      await open(t, 'q1');
      // 进度滑条拖到后半区（弹层内）→ 落进第二章。
      await t.tapAt(const Offset(210, 645));
      await step(t);
      await t.tap(find.byKey(const ValueKey('brBtnProg')));
      await step(t, ms: 320, times: 2);
      final sr = t.getRect(find.byKey(const ValueKey('brProg')));
      await t.dragFrom(
        Offset(sr.center.dx, sr.center.dy),
        Offset(sr.width * .4, 0),
      );
      await step(t, ms: 300, times: 2);
      await t.tap(find.byKey(const ValueKey('brPpClose')));
      await step(t, ms: 300, times: 2);
      await t.tap(find.byKey(const ValueKey('br-back')));
      await step(t, times: 3);
      final row = (await repo.sessionsOf('q1')).single;
      expect(row.fromChapter, '第一章');
      expect(row.toChapter, '第二章');
      expect(row.fromPct, lessThan(row.toPct!), reason: '起点应在第二章之前');
      expect(row.fromPage, isNotNull);
      expect(row.toPage, greaterThan(row.fromPage!), reason: '页码同步自动填');
      // 进度也随退出写回书籍记录。
      final b = (await repo.bookById('q1'))!;
      expect(b.readPages, greaterThan(0), reason: '退出即按全书页写回进度');
      // 结算提示条：清掉防污染下一条用例。
      await clearToasts(t);
    });

    testWidgets('默认 30 秒门槛：短会话整条丢弃，只更新进度', (t) async {
      await open(t, 'q2');
      await t.tapAt(const Offset(210, 645)); // 唤起 chrome 才有返回钮
      await step(t);
      await t.tap(find.byKey(const ValueKey('br-back')));
      await step(t, times: 3);
      expect(await repo.sessionsOf('q2'), isEmpty);
      // 门槛之外的一切照常：书籍进度仍被保存（原型 brLeave 短会话口径）。
      final b = (await repo.bookById('q2'))!;
      expect(b.lastReadAt, isNotNull, reason: '短会话不记时长，但进度与最后阅读时间仍更新');
      await clearToasts(t);
    });
  });
}
