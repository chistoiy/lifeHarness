import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/providers.dart' show sharedPreferencesProvider;
import 'package:lifeharness/features/read/data/epub_cache.dart';
import 'package:lifeharness/features/read/data/epub_doc.dart';
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:lifeharness/features/read/domain/book.dart';
import 'package:lifeharness/features/read/presentation/read_providers.dart';
import 'package:lifeharness/features/read/presentation/reader/reader_page.dart';

// 二期批5 · F5-3（滚动模式真实位置）＋ F5-6（手动/自动翻页同一动效）。
// 独立文件防 isolate 污染。
//
// 旧行为的三处错位（这批要钉死的）：
//  ① 切到滚动模式＝列表顶端或按段数×行高瞎估 → 不是当前页；
//  ② 滚完不写回 → 退出/切章仍按旧 `_pos` 记进度；
//  ③ 手动翻页 `jumpTo` 硬跳，自动翻页才有动画 → 同一动作两种手感。

EpubPara _p(String t) => EpubPara(kind: EpubParaKind.text, text: t);

const _filler =
    '这是一段用于滚动定位实测的中文正文，长度足够在默认字号下占据两到三行，'
    '重复若干次即可稳定地把整章撑到好几屏。';

/// 12 章 × 9 段：每段带唯一标记 `C{章}P{段}`，便于断言「回到同一段」。
EpubDoc _doc() => EpubDoc(
  format: 'EPUB3',
  title: '滚动书',
  author: '甲',
  toc: const [],
  chapters: [
    for (var c = 0; c < 12; c++)
      EpubChapter(
        href: 'c$c',
        title: '第${c + 1}章',
        paras: [
          EpubPara(
            kind: EpubParaKind.heading,
            text: '第${c + 1}章',
            headingLevel: 1,
          ),
          for (var i = 1; i <= 9; i++) _p('C${c}P$i。$_filler'),
        ],
      ),
  ],
  imageCount: 0,
  totalChars: 12 * 9 * _filler.length,
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
    await repo.addBook(
      Book(
        id: 's1',
        title: '滚动书',
        local: true,
        epub: const EpubRef(fmt: 'EPUB3', size: 10, path: 'mem'),
        createdAt: 1,
        updatedAt: 1,
      ),
    );
  });
  tearDown(() => db.close());

  Future<void> step(WidgetTester t, {int ms = 200, int times = 1}) async {
    for (var i = 0; i < times; i++) {
      await t.pump(Duration(milliseconds: ms));
    }
  }

  Future<void> mount(WidgetTester t, {double h = 780}) async {
    await useSurface(t, Size(420, h));
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          readRepositoryProvider.overrideWithValue(repo),
          sharedPreferencesProvider.overrideWithValue(prefs),
          epubDocLoaderProvider.overrideWithValue((_) async => _doc()),
          epubPreloadProvider.overrideWith((_) => EpubPreloadService(repo)),
        ],
        child: const MaterialApp(home: ReaderPage(bookId: 's1')),
      ),
    );
    await step(t, times: 4);
  }

  /// 开书 → 唤起 chrome → 更多弹层 → 切滚动模式。
  Future<void> toScroll(WidgetTester t, {double h = 780}) async {
    await t.tapAt(Offset(210, h * .83));
    await step(t);
    await t.tap(find.byKey(const ValueKey('brBtnMore')));
    await step(t, ms: 320, times: 3);
    await t.tap(find.byKey(const ValueKey('brMode-scroll')));
    // 定位是「帧后逐轮校正」：多给几帧让它收敛。
    await step(t, ms: 120, times: 10);
  }

  double offsetOf(WidgetTester t) {
    final lv = t.widget<ListView>(find.byKey(const ValueKey('br-scroll')));
    return lv.controller!.offset;
  }

  Map<String, dynamic> posOf(String raw) =>
      jsonDecode(raw) as Map<String, dynamic>;

  group('F5-3 · 滚动模式定位与写回', () {
    testWidgets('切到滚动模式落到当前页的真实位置（不是列表顶端）', (t) async {
      await mount(t);
      // 翻两页（右侧 16% 热区＝下一页）。
      for (var i = 0; i < 2; i++) {
        await t.tapAt(Offset(390, 400));
        await step(t, ms: 320, times: 2);
      }
      await toScroll(t);
      expect(find.byKey(const ValueKey('br-scroll')), findsOne);
      expect(
        offsetOf(t),
        greaterThan(0),
        reason: '第 3 页切过来仍停在偏移 0＝切模式定位没生效（旧行为）',
      );
      // 写回的锚点必须与屏幕顶部那一段一致。
      final pos = posOf((await repo.kv('reader.pos.s1'))!);
      final pi = pos['pi'] as int?;
      expect(pi, isNotNull, reason: '滚动模式必须记到段（只记页回不到同一段）');
      final hit = find.textContaining('C0P$pi。');
      expect(hit, findsOneWidget, reason: '锚点段应当就在屏幕上');
      final r = t.getRect(hit);
      expect(r.top, lessThan(120), reason: '锚点段应当是「可见首段」（贴顶部）');
    });

    testWidgets('滚动后写回真实位置，退出重进回到同一段', (t) async {
      await mount(t);
      await toScroll(t);
      final start = posOf((await repo.kv('reader.pos.s1'))!);
      final startCi = start['ci'] as int, startPi = start['pi'] as int? ?? 0;
      // 滚到章中段（三次拖动，每次 500）。
      for (var i = 0; i < 3; i++) {
        await t.drag(find.byKey(const ValueKey('br-scroll')), const Offset(0, -500));
        await step(t, ms: 120, times: 3);
      }
      // 500ms 节流：pump 过窗口才落 KV。
      await step(t, ms: 600, times: 2);

      final pos = posOf((await repo.kv('reader.pos.s1'))!);
      final ci = pos['ci'] as int;
      final pi = pos['pi'] as int;
      final moved = ci > startCi || (ci == startCi && pi > startPi);
      expect(moved, isTrue, reason: '滚过三屏后锚点必须前移（旧值 $startCi/$startPi）');

      // 重进（新挂载同一页）：滚动模式是全局配置，应回到同一段。
      await t.pumpWidget(const SizedBox());
      await step(t);
      await mount(t);
      await step(t, ms: 120, times: 12);
      expect(find.byKey(const ValueKey('br-scroll')), findsOne);
      final hit = find.textContaining('C${ci}P$pi。');
      expect(hit, findsOneWidget, reason: '重进必须回到同一段（锚点丢＝回到章首）');
      final r = t.getRect(hit);
      expect(r.top, lessThan(120), reason: '回来的那一段要贴顶');
    });

    testWidgets('切回翻页模式按锚点换算页码（进度跟着真实位置走）', (t) async {
      await mount(t);
      await toScroll(t);
      for (var i = 0; i < 3; i++) {
        await t.drag(find.byKey(const ValueKey('br-scroll')), const Offset(0, -500));
        await step(t, ms: 120, times: 3);
      }
      await step(t, ms: 600, times: 2);
      final scrolled = posOf((await repo.kv('reader.pos.s1'))!);

      // 切回翻页
      await t.tapAt(Offset(210, 700));
      await step(t);
      await t.tap(find.byKey(const ValueKey('brBtnMore')));
      await step(t, ms: 320, times: 3);
      await t.tap(find.byKey(const ValueKey('brMode-page')));
      await step(t, ms: 320, times: 4);

      final back = posOf((await repo.kv('reader.pos.s1'))!);
      expect(back['ci'], scrolled['ci'], reason: '切回来不许丢章');
      expect(find.byKey(const ValueKey('br-scroll')), findsNothing);
      // 翻页侧应落在「含锚点段」的那一页上（旧行为＝拿旧 _pos 写回更早的页）。
      final ci = scrolled['ci'] as int;
      final pi = scrolled['pi'] as int;
      expect(
        find.textContaining('C${ci}P$pi。'),
        findsOneWidget,
        reason: '切回翻页后当前页不含锚点段＝页码没按真实位置换算',
      );
    });
  });

  group('F5-6 · 滚动模式翻页手感统一', () {
    testWidgets('手动翻页走动画（不再一帧硬跳到位）', (t) async {
      await mount(t);
      await toScroll(t);
      final before = offsetOf(t);

      await t.tapAt(Offset(390, 400)); // 右侧热区＝下一屏
      await t.pump(); // 动画起步
      await t.pump(const Duration(milliseconds: 80));
      final mid = offsetOf(t);
      await step(t, ms: 400, times: 2);
      final end = offsetOf(t);

      expect(end, greaterThan(before), reason: '手动翻页要真的往下走一屏');
      expect(
        mid,
        greaterThan(before),
        reason: '中间帧没动＝直接 jumpTo 硬跳（与自动翻页两套手感）',
      );
      expect(
        mid,
        lessThan(end),
        reason: '中间帧已到终点＝没有动画（硬跳）',
      );
    });
  });
}
