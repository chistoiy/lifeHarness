import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/journal/data/journal_dao.dart';
import 'package:lifeharness/features/journal/domain/journal_repository.dart';
import 'package:lifeharness/features/journal/presentation/journal_page.dart';
import 'package:lifeharness/features/journal/presentation/journal_providers.dart';
import 'package:lifeharness/features/journal/presentation/widgets/diary_filter_sheet.dart';
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

    testWidgets('K1 八档折行且不出现一列：同排 ≥3 枚、单枚不许占满整行、首屏看得见「全部」',
        (tester) async {
      phone(tester);
      await openSheet(tester);

      final keys = [for (final k in pillKeys) 'df-range-$k'];
      final l = layout(tester, keys);

      // 八档一枚不落（折叠/裁切不在这一组）
      for (final k in keys) {
        expect(find.byKey(ValueKey(k)), findsOneWidget);
      }
      // 一列回潮（`Container(alignment)` 在 Wrap 里被撑满）时每排只有 1 枚 ⇒ 必红。
      // 测试环境是等宽方块字体（中文按 1em，比真机宽约 35%），真机 4+4＝2 排、
      // 这里 3 排；上界锁 3 排、且要求同排 ≥3 枚，两个方向都能卡住。
      expect(l.maxPerRow, greaterThanOrEqualTo(3),
          reason: '每枚独占一行＝Container(alignment) 被 Align 撑满');
      expect(l.rows, lessThanOrEqualTo(3), reason: '排数 ${l.rows}');
      // 单枚宽度上界：撑满整行时＝360dp
      expect(l.widest, lessThan(240), reason: '最宽一枚 ${l.widest}dp');
      // 「全部」在最前且**首屏就能点**（单行横滑那版首屏看不到它，真机实测过）
      expect(find.byKey(const ValueKey('df-range-all')).hitTestable(),
          findsOneWidget);
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

    testWidgets('K4 选中某档只换配色，不改变折行结构', (tester) async {
      phone(tester);
      await openSheet(tester);

      final keys = [for (final k in pillKeys) 'df-range-$k'];
      final before = layout(tester, keys);
      await tester.tap(find.byKey(const ValueKey('df-range-90d')));
      await tester.pumpAndSettle();
      final after = layout(tester, keys);

      expect(after.rows, before.rows);
      expect(after.maxPerRow, before.maxPerRow);
      // 选中态是 w600 会略宽，但不该宽到把结构挤乱
      expect(after.widest - before.widest, lessThan(12));
    });

    testWidgets('K5 末档「近两年」折行后直接可点，切档生效', (tester) async {
      phone(tester);
      await openSheet(tester);

      final last = find.byKey(const ValueKey('df-range-2y'));
      expect(last, findsOneWidget);
      // 折行排布下它落在第 2~3 排，仍在首屏内、无需横滑
      expect(last.hitTestable(), findsOneWidget);

      await tester.tap(last);
      await tester.pumpAndSettle();
      expect(
          tester.widget<Text>(find.byKey(const ValueKey('df-count'))).data,
          contains('近两年'));
    });

    testWidgets('K6 定高容器里文字必须真居中（量字形盒，不是量被撑满的渲染盒）',
        (tester) async {
      phone(tester);
      await openSheet(tester);

      /// 一枚定高容器（胶囊/按钮/日期框）里那段文字的实际高度与中心偏移。
      ///
      /// ⚠ 坑：`tester.getRect(find.byType(Text))` 量到的是**渲染盒**。定高容器把子级
      /// 约束成 tight height 时，盒子本身就是 34 高，中心永远等于容器中心 —— 于是
      /// 「字形被顶在 34 高的盒子顶端」这种错法量不出来（第一版 K6 就是这么假绿的）。
      /// 判据必须是**文字自己的高度**：自然行高（约 18）＝某处替它做了垂直居中；
      /// 等于 34＝被拉满，字形顶对齐。
      ({double h, double off}) measure(String key) {
        final box = tester.getRect(find.byKey(ValueKey(key)));
        // 认 `Text` 而不是 `RichText`：日期框里还有一枚 `Icon`，它内部同样是 RichText，
        // 直接找 RichText 会命中两个（`Bad state: Too many elements`）。
        final tf = find.descendant(
            of: find.byKey(ValueKey(key)), matching: find.byType(Text));
        final para = tester.renderObject<RenderParagraph>(tf);
        final text = tester.getRect(tf);
        return (h: para.size.height, off: (text.center.dy - box.center.dy).abs());
      }

      for (final k in [
        'df-range-all',
        'df-range-7d',
        'df-range-30d',
        'df-from',
        'df-to',
        'df-apply'
      ]) {
        final m = measure(k);
        expect(m.h, lessThan(30),
            reason: '$k 的文字高 ${m.h}dp ≈ 容器高（被拉满＝字形顶对齐，看着不居中）');
        expect(m.off, lessThanOrEqualTo(1), reason: '$k 文字中心偏 ${m.off}dp');
      }
    });

    testWidgets('K7 起止框＝虚线＋「年 / 月 / 日」占位＋日历图标；应用＝实心主色、禁用降透明',
        (tester) async {
      phone(tester);
      await openSheet(tester);

      // 占位文案照原生 date input 的浏览器默认（原型是 <input type="date">）
      expect(find.text('年 / 月 / 日'), findsNWidgets(2));
      // 未填时两枚都是虚线框（painter 挂在常驻键上；进 custom 档才转实线主色）
      for (final k in ['df-from-dash', 'df-to-dash']) {
        final cp = tester.widget<CustomPaint>(find.byKey(ValueKey(k)));
        expect(cp.painter, isA<DashRRectPainter>(), reason: '$k 应为虚线描边');
      }
      // 日历图标各一枚（原型浏览器默认给的）
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('df-from')),
              matching: find.byIcon(Icons.calendar_today_outlined)),
          findsOneWidget);

      // 「应用」＝实心主色底（不是描边），不可用时整枚 45% 透明
      final box = tester.widget<Container>(find.descendant(
          of: find.byKey(const ValueKey('df-apply')),
          matching: find.byType(Container)));
      final deco = box.decoration! as BoxDecoration;
      expect(deco.border, isNull, reason: '应用是实心按钮，不该有描边');
      expect(deco.color, isNotNull);
      final op = tester.widget<Opacity>(find.ancestor(
          of: find.byKey(const ValueKey('df-apply')),
          matching: find.byType(Opacity)).first);
      expect(op.opacity, .45, reason: '两端全空＝不可应用');

      // 框本身可点：唤起系统日期选择器（默认选中今天，直接确认）
      await tester.tap(find.byKey(const ValueKey('df-from')));
      await tester.pumpAndSettle();
      expect(find.text('确定'), findsOneWidget, reason: '起止框应能唤起日期选择器');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      // 填好一端后：占位换成日期文本、应用不再降透明
      expect(find.text('年 / 月 / 日'), findsOneWidget); // 只剩另一端
      final op2 = tester.widget<Opacity>(find.ancestor(
          of: find.byKey(const ValueKey('df-apply')),
          matching: find.byType(Opacity)).first);
      expect(op2.opacity, 1, reason: '一端已填＝开区间，可应用');
    });
  });
}
