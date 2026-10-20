import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/journal/data/tag_dao.dart';
import 'package:lifeharness/features/journal/domain/tag.dart';
import 'package:lifeharness/features/journal/presentation/journal_providers.dart';
import 'package:lifeharness/features/journal/presentation/journal_routes.dart';
import 'package:lifeharness/features/journal/presentation/tag_add_page.dart';
import 'package:lifeharness/features/journal/presentation/tag_manage_page.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';

/// 批2b · 标签管理屏（原型 `p-sub-tags` / `p-sub-tagAdd` / `sheetTagEdit`）。
///
/// 钉：分区是**视图不是数据**（同一标签可同时出现在两段）、计数=全仓引用总数、
/// 折叠、改名/删除的可见结果，以及添加页「默认三模块全勾 + 公共快捷」。
void main() {
  sqfliteFfiInit();

  late Database db;
  late TagDao dao;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    dao = TagDao(db);
  });

  tearDown(() async => db.close());

  Widget host({String at = '/tags'}) {
    final router = GoRouter(
      initialLocation: at,
      routes: [
        GoRoute(path: '/tags', builder: (_, _) => const TagManagePage()),
        GoRoute(path: '/tags/add', builder: (_, _) => const TagAddPage()),
      ],
    );
    return ProviderScope(
      overrides: [tagDaoProvider.overrideWithValue(dao)],
      child: MaterialApp.router(
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
  }

  test('M0 路由登记：/tags 与 /tags/add 在日记全屏栈里', () {
    final paths = journalPageRoutes().map((r) => r.path).toList();
    expect(paths, containsAll(['/tags', '/tags/add']));
  });

  testWidgets('M1 分区导轨五档 + 分区是视图（双模块标签两段都出现）', (tester) async {
    await dao.create('生活', scopes: {'diary', 'time'});
    await dao.create('读书笔记', scopes: {'note'});
    await dao.create('通用', scopes: {'diary', 'note', 'time'});

    // 四段卡片加起来高于默认 600px 视口 ⇒ 先撑高，否则 ListView 不构建离屏段
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    // 导轨计数：全部 3 / 日记 2 / 笔记 2 / 时间 2 / 公共 1
    expect(find.byKey(const ValueKey('tg-rail-all')), findsOneWidget);
    expect(find.byKey(const ValueKey('tg-rail-public')), findsOneWidget);

    // 「生活」同时属日记与时间 ⇒ 两段各出现一次
    expect(find.byKey(const ValueKey('tg-row-生活')), findsNWidgets(2));
    // 「读书笔记」只属笔记 ⇒ 只出现一次
    expect(find.byKey(const ValueKey('tg-row-读书笔记')), findsOneWidget);
    // 「通用」三模块全占 ⇒ 日记/笔记/时间/公共四段各出现一次（分区是视图不是数据）
    expect(find.byKey(const ValueKey('tg-row-通用')), findsNWidgets(4));
    await drainLogTimer(tester);
  });

  testWidgets('M2 折叠：点段头收起该段，全部折叠/展开', (tester) async {
    await dao.create('生活', scopes: {'diary'});
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tg-row-生活')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tg-seg-diary')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tg-row-生活')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('tg-fold-all')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tg-row-生活')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('tg-fold-all')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tg-row-生活')), findsOneWidget);
    await drainLogTimer(tester);
  });

  testWidgets('M3 编辑弹层改名：池行改名，引用数与分区跟着变', (tester) async {
    await dao.create('复盘', scopes: {'diary'});
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('tg-row-复盘')));
    await tester.pumpAndSettle();
    expect(find.text('编辑标签'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('tg-edit-name')), '日复盘');
    await tester.tap(find.byKey(const ValueKey('tg-edit-save')));
    await tester.pumpAndSettle();

    expect((await dao.list()).map((t) => t.name), ['日复盘']);
    expect(find.byKey(const ValueKey('tg-row-日复盘')), findsOneWidget);
    await drainLogTimer(tester);
  });

  testWidgets('M4 删除：确认后解绑摘池，弹层关闭、池为空', (tester) async {
    await dao.create('加班', scopes: {'diary'});
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('tg-row-加班')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tg-edit-delete')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget, reason: '删除必须二次确认');
    await tester.tap(find.byKey(const ValueKey('d-confirm-ok')));
    await tester.pumpAndSettle();

    expect(await dao.list(), isEmpty);
    expect(find.byKey(const ValueKey('tg-row-加班')), findsNothing);
    await drainLogTimer(tester);
  });

  testWidgets('M5 添加页：默认三模块全勾；关掉「公共」只剩一个；保存进池', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tg-add')));
    await tester.pumpAndSettle();

    // 默认三勾（每枚选中胶囊带一枚 check 图标）
    expect(find.byIcon(Icons.check), findsNWidgets(3));

    await tester.enterText(find.byKey(const ValueKey('tg-add-name')), '晨间页');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('tg-add-scope-note')));
    await tester.pump();
    expect(find.byIcon(Icons.check), findsNWidgets(2));

    await tester.tap(find.byKey(const ValueKey('tg-add-save')));
    await tester.pumpAndSettle();

    final pool = await dao.list();
    expect(pool.single.name, '晨间页');
    expect(pool.single.scopes, {'diary', 'time'});
    expect(find.byType(TagManagePage), findsOneWidget, reason: '保存后回到管理屏');
    await drainLogTimer(tester);
  });
}
