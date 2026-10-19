import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/journal/data/journal_dao.dart';
import 'package:lifeharness/features/journal/domain/diary_filter_kit.dart';
import 'package:lifeharness/features/journal/domain/journal_entry.dart';
import 'package:lifeharness/features/journal/domain/journal_repository.dart';
import 'package:lifeharness/features/journal/presentation/journal_page.dart';
import 'package:lifeharness/features/journal/presentation/journal_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';

/// 日记改版批2c · 筛选弹层「标签段超一行折叠」（产品令 §4h 第 1/2 条）。
///
/// 这一批真正容易回归的不是画法，而是**判据**：原型在这件事上实错三次——
/// 折叠态是「定高一行 + 裁掉溢出」，被裁掉的胶囊在布局阶段就被排除，
/// 于是「先裁再量」永远量到 `scrollHeight == clientHeight`，恒判「不超一行」；
/// 反过来「先解折叠再量」，容器当场变两行，判据又没了。
/// 定案＝**容器宽度判据**（逐枚累加胶囊宽 + 间距），本文件先在纯逻辑里钉住它，
/// 再用「裁剪层在不在 + 高度是不是 32」验渲染面。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  group('标签折叠纯逻辑（宽度判据）', () {
    // 一枚 2 字标签在 13px 字下约 26px 文字宽 ⇒ 胶囊约 72px
    double chip(double textW) => dfChipWidth(textW);

    test('G1 一行装得下＝不折叠（按钮不出现）', () {
      final widths = List.filled(3, chip(26));
      // 3 枚 × 72 + 2 × 8 = 232
      expect(dfChipLines(widths, 400), 1);
      expect(dfTagsOverflow(widths, 400), isFalse);
      // 恰好装得下（不留余量）也判一行：`>` 而非 `>=`
      expect(dfTagsOverflow(widths, 232), isFalse);
      // 差 1px 就折行
      expect(dfTagsOverflow(widths, 231), isTrue);
    });

    test('G2 超一行＝折叠，行数按贪心累加', () {
      final widths = List.filled(8, chip(26)); // 8 × 72 + 7 × 8 = 632
      expect(dfChipLines(widths, 400), 2);
      expect(dfTagsOverflow(widths, 400), isTrue);
      expect(dfChipLines(widths, 232), 3); // 232/80 ≈ 2.9 枚一行 ⇒ 3 行
    });

    test('G3 空池＝零行、不折叠；未测到宽度按一行（绝不无中生有地折叠）', () {
      expect(dfChipLines(const [], 400), 0);
      expect(dfTagsOverflow(const [], 400), isFalse);
      expect(dfChipLines([chip(26), chip(26)], 0), 1);
      expect(dfTagsOverflow([chip(26), chip(26)], 0), isFalse);
    });

    test('G4 展开按钮报的是**全量**数，不是被裁掉的枚数', () {
      expect(dfMoreLabel(open: false, total: 12), '展开全部 (12)');
      expect(dfMoreLabel(open: true, total: 12), '收起');
    });

    test('G5 命中判定：固定键 / 裸标签 / 历史带 # 标签都要认', () {
      final e = JournalEntry(
        day: DateTime(2026, 10, 19),
        content: '正文\n☐ 买牛奶',
        tags: const ['复盘', '阅读'],
        createdAt: DateTime(2026, 10, 19, 9),
        updatedAt: DateTime(2026, 10, 19, 9),
      );
      expect(diaryHit(e, 'all'), isTrue);
      expect(diaryHit(e, 'todo'), isTrue);
      expect(diaryHit(e, 'starred'), isFalse);
      expect(diaryHit(e, '复盘'), isTrue);
      // 历史筛选值带 `#`（原型曾按名字精确等于 `'#复盘'` 比池内裸名 ⇒ 恒 0 篇）
      expect(diaryHit(e, '#复盘'), isTrue);
      expect(diaryHit(e, '没这个标签'), isFalse);
      expect(diaryHit(e, '☐ 买牛奶'), isFalse); // 待办文字不是标签
    });
  });

  late Database db;
  late JournalRepository jrepo;
  late SharedPreferences prefs;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    jrepo = JournalRepository(JournalDao(db));
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  tearDown(() async => db.close());

  Widget scope(Widget home) => ProviderScope(
        overrides: [
          journalRepositoryProvider.overrideWithValue(jrepo),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: MaterialApp(
          home: MediaQuery(
            // 必须关动画：FAB 呼吸环是无限动画，`pumpAndSettle` 会等不到静止。
            data: const MediaQueryData(disableAnimations: true),
            child: home,
          ),
        ),
      );

  /// 造 n 篇各带一枚标签的日记（标签名 4 字＝胶囊更宽，容易逼出一行装不下）。
  Future<List<String>> seedTags(int n) async {
    final names = <String>[];
    for (var i = 0; i < n; i++) {
      final name = '标签${String.fromCharCode(0x4E00 + i)}${String.fromCharCode(0x4E10 + i)}';
      names.add(name);
      await jrepo.save(JournalEntry(
        day: DateTime.now().subtract(Duration(days: i)),
        content: '第 $i 天 #$name',
        tags: [name],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
    }
    return names;
  }

  Future<void> openFilterSheet(WidgetTester tester) async {
    await tester.pumpWidget(scope(const JournalPage()));
    await tester.pumpAndSettle();
    // §4c-2 之后筛选只剩 FAB 长按扇形一条路
    await tester.longPress(find.byKey(const ValueKey('diary-fan-fab')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('diary-fan-筛选')));
    await tester.pumpAndSettle();
  }

  String countText(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const ValueKey('df-count'))).data!;

  group('标签段折叠（渲染面）', () {
    testWidgets('W1 标签超一行：折叠成一行（裁剪层高 32）+ 末尾「展开全部 (N)」',
        (tester) async {
      final names = await seedTags(10);
      await openFilterSheet(tester);

      // 折叠＝裁剪层在树里，且高度严格一行
      final clip = find.byKey(const ValueKey('df-tag-clip'));
      expect(clip, findsOneWidget);
      expect(tester.getSize(clip).height, kDfChipH);

      // 按钮文案报全量，不是「被裁掉几枚」
      expect(find.text('展开全部 (10)'), findsOneWidget);

      // 被裁掉的标签还在树里（不是删了），但**点不到**——这正是折叠的判据
      expect(find.byKey(ValueKey('df-tag-${names.last}')), findsOneWidget);
      expect(find.byKey(ValueKey('df-tag-${names.last}')).hitTestable(),
          findsNothing);
      // 第一枚始终可点
      expect(find.byKey(ValueKey('df-tag-${names.first}')).hitTestable(),
          findsOneWidget);
    });

    testWidgets('W2 点「展开全部」：全量可见、按钮变「收起」、不再裁剪',
        (tester) async {
      final names = await seedTags(10);
      await openFilterSheet(tester);

      await tester.tap(find.byKey(const ValueKey('df-more')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('df-tag-clip')), findsNothing);
      expect(find.text('收起'), findsOneWidget);
      // 最后一枚现在真的要得着
      expect(find.byKey(ValueKey('df-tag-${names.last}')).hitTestable(),
          findsOneWidget);
    });

    testWidgets('W3 再点「收起」：回到一行折叠', (tester) async {
      await seedTags(10);
      await openFilterSheet(tester);

      await tester.tap(find.byKey(const ValueKey('df-more')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('df-more')));
      await tester.pumpAndSettle();

      expect(tester.getSize(find.byKey(const ValueKey('df-tag-clip'))).height,
          kDfChipH);
      expect(find.text('展开全部 (10)'), findsOneWidget);
    });

    testWidgets('W4 只有两枚标签：不出按钮、也不裁剪（按钮不占位）',
        (tester) async {
      await seedTags(2);
      await openFilterSheet(tester);

      expect(find.byKey(const ValueKey('df-tag-clip')), findsNothing);
      expect(find.byKey(const ValueKey('df-more')), findsNothing);
      expect(find.textContaining('展开全部'), findsNothing);
    });

    testWidgets('W5 展开态切「标记」后保持展开（口径②：展开过就一直展开）',
        (tester) async {
      await seedTags(10);
      await openFilterSheet(tester);
      await tester.tap(find.byKey(const ValueKey('df-more')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('df-mark-todo')));
      await tester.pumpAndSettle();

      expect(find.text('收起'), findsOneWidget);
      expect(find.byKey(const ValueKey('df-tag-clip')), findsNothing);
    });

    testWidgets('W6 选中标签即生效：实时计数跟着变，弹层不关', (tester) async {
      final names = await seedTags(10);
      await openFilterSheet(tester);

      expect(countText(tester), '筛出 10 篇');
      await tester.tap(find.byKey(ValueKey('df-tag-${names.first}')));
      await tester.pumpAndSettle();
      expect(countText(tester), '筛出 1 篇');
      // 弹层没关，且选中态回显（再点一次＝取消，回全部）
      expect(find.byKey(const ValueKey('df-sheet')), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('df-tag-${names.first}')));
      await tester.pumpAndSettle();
      expect(countText(tester), '筛出 10 篇');
    });

    testWidgets('W7 重置：标记回全部、标签清空、计数回满', (tester) async {
      final names = await seedTags(10);
      await openFilterSheet(tester);
      await tester.tap(find.byKey(const ValueKey('df-mark-todo')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('df-tag-${names.first}')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('df-reset')));
      await tester.pumpAndSettle();
      expect(countText(tester), '筛出 10 篇');
    });

    testWidgets('W8 池为空：给一行提示，不渲染空段也不出按钮', (tester) async {
      await jrepo.save(JournalEntry(
        day: DateTime.now(),
        content: '没有标签的一篇',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
      await openFilterSheet(tester);

      expect(find.textContaining('还没有标签'), findsOneWidget);
      expect(find.byKey(const ValueKey('df-more')), findsNothing);
      expect(find.text('筛出 1 篇'), findsOneWidget);
    });
  });
}
