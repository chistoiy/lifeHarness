import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/providers.dart' show sharedPreferencesProvider;
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:lifeharness/features/read/presentation/read_providers.dart';
import 'package:lifeharness/features/read/presentation/read_sheets.dart'
    show kReadToastDuration, showBooklistFormSheet;
import 'package:lifeharness/features/read/presentation/shelf/book_form_page.dart';

/// 阅读模块批2 · 反馈层常驻用例（F2-13 toast 层级 / F2-15 防重入）。
///
/// 规格＝`docs/handoff/阅读模块-冻结版开发方案-20261013.md` §2.3，
/// 用例清单＝`docs/handoff/交棒话术-20261014-阅读模块批2交付链与状态层.md` §0.3。
///
/// 口径：`readToast` 走**根 Overlay 直挂**（单例浮层 · 锚点键 `read-toast` ·
/// 驻留 [kReadToastDuration]＝2200ms，逐字对齐原型 `toast()`），不再走页面级
/// `ScaffoldMessenger`——故断言一律「非 SnackBar ＋ 不在弹层子树里」。
/// 摘除走 `Timer`（非帧驱动），`pumpAndSettle` 不会把它推掉；本文件仍以小步
/// `pump` 控制时间，收尾用 [drainToast] 走完窗口。
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

  Widget boot(Widget home) => ProviderScope(
        overrides: [
          readRepositoryProvider.overrideWithValue(repo),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: MaterialApp(home: home),
      );

  /// 推帧但**不推时间**到驻留窗口之外（toast 存活期内）。
  Future<void> tick(WidgetTester tester, [int ms = 120]) =>
      tester.pump(Duration(milliseconds: ms));

  /// 走完驻留窗口让提示条自移除，避免 OverlayEntry 跨用例残留。
  Future<void> drainToast(WidgetTester tester) =>
      tester.pump(kReadToastDuration + const Duration(milliseconds: 200));

  testWidgets('F2-13 弹层内触发的 toast 挂根 Overlay：可见 · 非 SnackBar · 不在弹层子树里',
      (tester) async {
    await tester.pumpWidget(boot(const _SheetHost()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open-sheet')));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget, reason: '弹层已开');

    // 弹层内点「保存」：书单名为空 → **弹层内**触发 readToast。
    await tester.tap(find.byKey(const ValueKey('blf-save')));
    await tick(tester);

    expect(find.text('给书单起个名字'), findsOneWidget,
        reason: 'F2-13：弹层内 toast 必须可见（不被遮罩吞）');
    expect(find.byType(SnackBar), findsNothing,
        reason: 'F2-13：不再借道页面级 ScaffoldMessenger（SnackBar 会挂在弹层之下）');
    expect(
      find.descendant(
          of: find.byType(BottomSheet), matching: find.text('给书单起个名字')),
      findsNothing,
      reason: 'F2-13：toast 挂在根 Overlay（弹层之上），不在弹层子树里',
    );
    // 弹层还开着——toast 没把弹层顶掉。
    expect(find.byType(BottomSheet), findsOneWidget);

    await drainToast(tester);
    expect(find.text('给书单起个名字'), findsNothing, reason: '2.2s 后自移除');
  });

  testWidgets('F2-15 书单表单：连点保存只落一次写', (tester) async {
    await tester.pumpWidget(boot(const _SheetHost()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open-sheet')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('blf-name')), '2026 想读');
    await tester.pump();

    // 同一帧内连点两下：第一下置 `_busy`，第二下被门挡回。
    await tester.tap(find.byKey(const ValueKey('blf-save')));
    await tester.tap(find.byKey(const ValueKey('blf-save')));
    await tester.pump();
    final btn = tester
        .widget<FilledButton>(find.byKey(const ValueKey('blf-save')));
    expect(btn.onPressed, isNull, reason: 'F2-15：保存中置灰点不动（连点第二下空转）');

    await settle5(tester);
    expect((await repo.allLists()).length, 1, reason: '连点只落一次写');
    await drainToast(tester);
  });

  testWidgets('F2-15 书籍表单：保存中置灰点不动，连点只落一本', (tester) async {
    await tester.pumpWidget(boot(const BookFormPage()));
    await tester.pumpAndSettle();
    await useSurface(tester, const Size(800, 4000));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('bf-title')), '万历十五年');
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('bf-save')));
    await tester.tap(find.byKey(const ValueKey('bf-save')));
    await tester.pump();
    final btn =
        tester.widget<TextButton>(find.byKey(const ValueKey('bf-save')));
    expect(btn.onPressed, isNull, reason: 'F2-15：保存中置灰点不动');

    await settle5(tester);
    final books = await repo.allBooks();
    expect(books.length, 1, reason: '连点只落一次写');
    expect(books.single.title, '万历十五年');
    await drainToast(tester);
  });
}

/// 只做一件事：给「开书单弹层」一个可点的宿主（弹层是 F2-13/F2-15 的载体）。
class _SheetHost extends ConsumerWidget {
  const _SheetHost();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        body: Center(
          child: FilledButton(
            key: const ValueKey('open-sheet'),
            onPressed: () => showBooklistFormSheet(context, ref),
            child: const Text('开书单弹层'),
          ),
        ),
      );
}
