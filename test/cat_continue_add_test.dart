import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/calendar/data/category_dao.dart';
import 'package:lifeharness/features/calendar/domain/category.dart';
import 'package:lifeharness/features/calendar/presentation/category_page.dart';
import 'package:lifeharness/features/calendar/presentation/calendar_providers.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// F4-2（时间模块批2 · 冻结口径）分类页「继续添加」：
/// ① 「继续添加」保存后**留在本页且表单清空**，可连续添加；
/// ② 「保 存」保存后关闭弹层（原型 caSave(keep=0)）；
/// ③ 编辑态「保存修改」不出现继续添加钮、保存后照常关闭。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late CategoryDao dao;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    dao = CategoryDao(db);
    await dao.insert(const Category(name: '甲组', sort: 1));
    await dao.insert(Category(name: '开会', parentId: 1, sort: 1));
  });
  tearDown(() async => db.close());

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        categoryDaoProvider.overrideWithValue(dao),
      ],
      child: const MaterialApp(home: CategoryPage()),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> openAddSheet(WidgetTester tester) async {
    await tester.tap(find.byTooltip('添加分类'));
    await tester.pumpAndSettle();
  }

  testWidgets('继续添加：保存后留本页＋名称清空，可连续添加', (tester) async {
    await pumpPage(tester);
    await openAddSheet(tester);

    final nameField = find.byType(TextField);
    expect(nameField, findsOneWidget);

    await tester.enterText(nameField, '购物');
    await tester.tap(find.byKey(const ValueKey('cat-continue-add')));
    await tester.pumpAndSettle();

    // 弹层仍在（未 pop），名称已清空，添加态双钮还在。
    expect(find.byKey(const ValueKey('cat-continue-add')), findsOneWidget);
    expect(find.text('保 存'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);
    // 落库生效（继续添加后立即可见/同源）。
    expect((await dao.list()).map((c) => c.name), contains('购物'));

    // 连续添加第二条。
    await tester.enterText(find.byType(TextField), '通勤');
    await tester.tap(find.byKey(const ValueKey('cat-continue-add')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cat-continue-add')), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);
    final names = (await dao.list()).map((c) => c.name).toList();
    expect(names, containsAll(['购物', '通勤']));
  });

  testWidgets('保 存：保存后关闭弹层（不触发继续）', (tester) async {
    await pumpPage(tester);
    await openAddSheet(tester);

    await tester.enterText(find.byType(TextField), '运动');
    await tester.tap(find.text('保 存'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing, reason: '保存后弹层应关闭');
    expect((await dao.list()).map((c) => c.name), contains('运动'));
  });

  testWidgets('编辑态：只有「保存修改」，无继续添加钮，保存后关闭', (tester) async {
    await pumpPage(tester);
    // 点次级行进编辑弹层（同名 Text 可能两处命中，钉首枚可点行）。
    await tester.tap(find.text('开会').first);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('cat-continue-add')), findsNothing);
    expect(find.text('保存修改'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '例会');
    await tester.tap(find.text('保存修改'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing, reason: '保存修改后弹层应关闭');
    expect((await dao.list()).map((c) => c.name), contains('例会'));
  });
}
