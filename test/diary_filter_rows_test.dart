import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/journal/data/journal_dao.dart';
import 'package:lifeharness/features/journal/domain/journal_repository.dart';
import 'package:lifeharness/features/journal/presentation/journal_page.dart';
import 'package:lifeharness/features/journal/presentation/journal_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 日记批2d-2 · 筛选弹层「时间段必须单行横滑，不许折行/一列」（真机 6195 回归）。
///
/// 两层病灶：
/// ① **约束**——`Container(alignment:)` 会包一层 `Align`，而 `Align` 在**有限**宽度下
///    撑满父级；时间段胶囊外层曾是 `Wrap`（`maxWidth` 有限＝360dp），于是每枚都被撑成
///    整行宽 —— 8 枚＝8 行，弹层 460→670dp，观感就成了「一列选项」。同文件的 `_chip`
///    （标记/标签）没写 `alignment`，所以那两组一直是对的。
/// ② **口径**——原型设计注释写「时间段改为**紧凑单行**＋自定义起止」，但原型实现是
///    `flex flex-wrap`、400px 下实测 2 排（4+4）；照抄实现就照抄了矛盾。产品点名
///    「为什么要做成多行」⇒ 按**注释口径**落单行横滑。
///
/// 这条以前抓不到，是因为既有用例只断言高度（`kDfChipH` / 裁剪层在不在），
/// 一列、一排、两排的高度都能对上。本文件改断言**同排枚数**与**单枚宽度上界**。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  const pillKeys = ['all', '7d', '30d', '90d', 'year', 'month', '1y', '2y'];

  late Database db;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async => db.close());

  Future<void> openSheet(WidgetTester tester) async {
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        journalRepositoryProvider.overrideWithValue(JournalRepository(JournalDao(db))),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: MaterialApp(
        home: const MediaQuery(
          // FAB 呼吸环是无限动画，`pumpAndSettle` 会等不到静止。
          data: MediaQueryData(disableAnimations: true),
          child: JournalPage(),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.longPress(find.byKey(const ValueKey('diary-fan-fab')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('diary-fan-筛选')));
    await tester.pumpAndSettle();
  }

  /// 把一组 key 的 top 折叠成「排数 / 每排枚数 / 最宽一枚」。
  ({int rows, int maxPerRow, double widest}) layout(
      WidgetTester tester, List<String> keys) {
    final perTop = <int, int>{};
    var widest = 0.0;
    for (final k in keys) {
      final r = tester.getRect(find.byKey(ValueKey(k)));
      perTop[r.top.round()] = (perTop[r.top.round()] ?? 0) + 1;
      if (r.width > widest) widest = r.width;
    }
    final maxPer = perTop.values.reduce((a, b) => a > b ? a : b);
    return (rows: perTop.length, maxPerRow: maxPer, widest: widest);
  }

  group('时间段胶囊排版（400dp 等效真机宽）', () {
    void phone(WidgetTester tester) {
      tester.view.physicalSize = const Size(400 * 3, 890 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
    }

    testWidgets('K1 八档严格单行：同一 top、单枚不许占满整行', (tester) async {
      phone(tester);
      await openSheet(tester);

      final keys = [for (final k in pillKeys) 'df-range-$k'];
      final l = layout(tester, keys);

      // 八档一枚不落（折叠/裁切不在这一组）
      for (final k in keys) {
        expect(find.byKey(ValueKey(k)), findsOneWidget);
      }
      // 核心判据：**恰好一排**、且这一排装了全部 8 枚。
      // 一列回潮（`Container(alignment)` 撑满）或折行（改回 `Wrap`）时此断言必红。
      expect(l.rows, 1, reason: '排数 ${l.rows}（口径＝单行横滑）');
      expect(l.maxPerRow, pillKeys.length);
      // 单枚宽度上界：撑满整行时＝360dp
      expect(l.widest, lessThan(240), reason: '最宽一枚 ${l.widest}dp');
    });

    testWidgets('K2 弹层高度回到原型档（一列时会被顶到 670dp）', (tester) async {
      phone(tester);
      await openSheet(tester);

      final h = tester.getSize(find.byKey(const ValueKey('df-sheet'))).height;
      expect(h, lessThan(620), reason: '弹层高 $h');
    });

    testWidgets('K3 标记/标签两组同口径：每组至少同排 2 枚（防照抄出同一坑）',
        (tester) async {
      phone(tester);
      await openSheet(tester);

      final marks = [
        for (final k in ['all', 'starred', 'liked', 'todo']) 'df-mark-$k'
      ];
      final l = layout(tester, marks);
      expect(l.maxPerRow, greaterThanOrEqualTo(2));
      expect(l.widest, lessThan(240));
    });

    testWidgets('K4 选中某档只换配色，不改变单行结构', (tester) async {
      phone(tester);
      await openSheet(tester);

      final keys = [for (final k in pillKeys) 'df-range-$k'];
      final before = layout(tester, keys);
      await tester.tap(find.byKey(const ValueKey('df-range-90d')));
      await tester.pumpAndSettle();
      final after = layout(tester, keys);

      expect(after.rows, 1);
      expect(after.maxPerRow, before.maxPerRow);
      // 选中态是 w600 会略宽，但行内横滑排布下不该把结构挤乱
      expect(after.widest - before.widest, lessThan(12));
    });

    testWidgets('K5 横滑：最末档初始在屏外，左滑后可见可点', (tester) async {
      phone(tester);
      await openSheet(tester);

      final last = find.byKey(const ValueKey('df-range-2y'));
      expect(last, findsOneWidget); // 在树里
      expect(last.hitTestable(), findsNothing); // 但被裁在屏外

      // 左滑＝看右边（手势方向：内容往左走）
      await tester.drag(
          find.byKey(const ValueKey('df-range-scroll')), const Offset(-400, 0));
      await tester.pumpAndSettle();

      expect(last.hitTestable(), findsOneWidget);
      // 滑到最右后点它，真的能切档
      await tester.tap(last);
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('df-count')))
              .data,
          contains('近两年'));
    });
  });
}
