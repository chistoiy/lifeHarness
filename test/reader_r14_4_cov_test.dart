import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/providers.dart' show sharedPreferencesProvider;
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:lifeharness/features/read/domain/book.dart';
import 'package:lifeharness/features/read/presentation/read_providers.dart';
import 'package:lifeharness/features/read/presentation/read_settings_page.dart';
import 'package:lifeharness/features/read/presentation/widgets/bs_cover.dart';

// R14-4 · 无封面书卡三档回落（原型 2026-09-30 拍板、逐屏确认过门）：
// A=EPUB 正文首图（默认，带「正文首图」角标）· B=书脊色块＋书名首字 ·
// C=纯文字卡（书名居中＋作者）。有真实封面永远直出。
// 独立文件；夹具 PNG 用 createTempSync 同步造（FakeAsync 禁真实异步 I/O）。

/// 1×1 透明 PNG（python 自检过 CRC；合法图，解码不会报错）。
final _png1x1 = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGNgAAIAAAUA'
  'AXpeqz8AAAAASUVORK5CYII=',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Database db;
  late ReadRepository repo;
  late SharedPreferences prefs;
  late Directory tmp;
  late String pngPath;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = ReadRepository(db);
    tmp = Directory.systemTemp.createTempSync('lh_r144');
    pngPath = (File(p.join(tmp.path, 'fi.png'))..writeAsBytesSync(_png1x1))
        .path;
  });
  tearDown(() async {
    await db.close();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Book bk(
    String id, {
    bool local = false,
    String title = '思考，快与慢',
    String author = '丹尼尔·卡尼曼',
    String? fi,
    String? cover,
  }) => Book(
    id: id,
    title: title,
    author: author,
    local: local,
    firstImgPath: fi,
    coverPath: cover,
    createdAt: 1,
    updatedAt: 1,
  );

  List<Override> ov() => [
    readRepositoryProvider.overrideWithValue(repo),
    sharedPreferencesProvider.overrideWithValue(prefs),
  ];

  Future<void> step(WidgetTester t) async {
    for (var i = 0; i < 3; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  test('bsFallbackModeFromKv：按首字符识别，其余回落 A', () {
    expect(bsFallbackModeFromKv(null), BsFallbackMode.aFirstImg);
    expect(bsFallbackModeFromKv(''), BsFallbackMode.aFirstImg);
    expect(bsFallbackModeFromKv('A 正文首图'), BsFallbackMode.aFirstImg);
    expect(bsFallbackModeFromKv('B 书脊色块'), BsFallbackMode.bSpineInitial);
    expect(bsFallbackModeFromKv('C 纯文字卡'), BsFallbackMode.cPureText);
    expect(bsFallbackModeFromKv('X 未知'), BsFallbackMode.aFirstImg);
  });

  group('三档渲染（显式档位）', () {
    testWidgets('A 档：本地书有正文首图→铺图＋「正文首图」角标；无首图则无', (t) async {
      await t.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Center(
              child: BsCover(
                book: bk('a1', local: true, fi: pngPath),
                fallbackMode: BsFallbackMode.aFirstImg,
              ),
            ),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('cov-fi-tag')), findsOne);
      expect(find.text('正文首图'), findsOne);
      expect(find.byKey(const ValueKey('cov-b-char')), findsNothing);
      expect(find.byKey(const ValueKey('cov-c-title')), findsNothing);

      await t.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Center(
              child: BsCover(
                book: bk('a2', local: true),
                fallbackMode: BsFallbackMode.aFirstImg,
              ),
            ),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('cov-fi-tag')), findsNothing);
    });

    testWidgets('B 档：书脊色块＋书名首字；本地正文首图被忽略', (t) async {
      await t.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Center(
              child: BsCover(
                book: bk('b1', local: true, fi: pngPath, title: '思考，快与慢'),
                fallbackMode: BsFallbackMode.bSpineInitial,
              ),
            ),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('cov-fi-tag')), findsNothing);
      expect(
        t.widget<Text>(find.byKey(const ValueKey('cov-b-char'))).data,
        '思',
      );
      expect(find.byKey(const ValueKey('cov-c-title')), findsNothing);
    });

    testWidgets('C 档：纯文字卡（书名＋作者，无角标无首字）', (t) async {
      await t.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Center(
              child: BsCover(
                book: bk('c1', title: '原子习惯', author: '詹姆斯·克利尔'),
                fallbackMode: BsFallbackMode.cPureText,
              ),
            ),
          ),
        ),
      );
      expect(
        t.widget<Text>(find.byKey(const ValueKey('cov-c-title'))).data,
        '原子习惯',
      );
      expect(find.text('詹姆斯·克利尔'), findsOne);
      expect(find.byKey(const ValueKey('cov-b-char')), findsNothing);
      expect(find.byKey(const ValueKey('cov-fi-tag')), findsNothing);
    });

    testWidgets('真实封面优先：任何档位都不覆盖有封面的书', (t) async {
      await t.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Center(
              child: BsCover(
                book: bk('r1', local: true, cover: pngPath, fi: pngPath),
                fallbackMode: BsFallbackMode.bSpineInitial,
              ),
            ),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('cov-b-char')), findsNothing);
      expect(find.byKey(const ValueKey('cov-fi-tag')), findsNothing);
      expect(find.byKey(const ValueKey('cov-c-title')), findsNothing);
    });

    testWidgets('小尺寸缩略图（列表行 36×52）三档均不溢出', (t) async {
      for (final m in BsFallbackMode.values) {
        await t.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Center(
                child: BsCover(
                  book: bk('s-$m', local: true, fi: pngPath, title: '思考，快与慢'),
                  fallbackMode: m,
                  width: 36,
                  height: 52,
                  radius: 7,
                  showAuthor: false,
                  badgeSize: 7,
                ),
              ),
            ),
          ),
        );
        expect(t.takeException(), isNull, reason: '档位 $m 小尺寸溢出');
      }
    });
  });

  group('设置驱动（KV→广播→渲染）', () {
    testWidgets('默认 A：未设置时本地书首图直出', (t) async {
      await t.pumpWidget(
        ProviderScope(
          overrides: ov(),
          child: MaterialApp(
            home: Center(
              child: BsCover(book: bk('k1', local: true, fi: pngPath)),
            ),
          ),
        ),
      );
      await step(t);
      expect(find.byKey(const ValueKey('cov-fi-tag')), findsOne);
    });

    testWidgets('KV=B 并 readTick 广播：同实例重取后切 B 档', (t) async {
      final container = ProviderContainer(overrides: ov());
      addTearDown(container.dispose);
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Center(
              child: BsCover(
                book: bk('k2', local: true, fi: pngPath, title: '思考，快与慢'),
              ),
            ),
          ),
        ),
      );
      await step(t);
      expect(find.byKey(const ValueKey('cov-b-char')), findsNothing); // 默认 A
      await repo.setKv('read.covFallback', 'B 书脊色块');
      container.read(readTickProvider.notifier).state++;
      await step(t);
      expect(
        t.widget<Text>(find.byKey(const ValueKey('cov-b-char'))).data,
        '思',
      );
      expect(find.byKey(const ValueKey('cov-fi-tag')), findsNothing);
    });

    testWidgets('设置行：无封面书卡 chips 落库 read.covFallback', (t) async {
      await useSurface(t);
      await t.pumpWidget(
        ProviderScope(
          overrides: ov(),
          child: const MaterialApp(home: ReadSettingsPage()),
        ),
      );
      await step(t);
      expect(find.byKey(const ValueKey('set-covFallback')), findsOne);
      expect(
        find.text('EPUB 无内嵌封面时的回落档 · 默认 A · 可在书架同屏预览对比'),
        findsOne,
      );
      await t.ensureVisible(
        find.byKey(const ValueKey('set-covFallback-C 纯文字卡')),
      );
      await t.tap(find.byKey(const ValueKey('set-covFallback-C 纯文字卡')));
      await step(t);
      expect(await repo.kv('read.covFallback'), 'C 纯文字卡');
      await clearToasts(t); // 落键提示条退场
      await settleLogTimer(t);
    });
  });
}
