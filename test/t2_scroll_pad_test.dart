import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lifeharness/app.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/core/theme/theme_repository.dart';
import 'package:lifeharness/features/todo/domain/todo.dart';
import 'package:lifeharness/features/todo/presentation/todo_providers.dart';
import 'package:lifeharness/shared/widgets/scroll_pad.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

// T2-B（交互整改批一）·切栏滚动垫常驻回归。
// 机制层：本地 ShellRoute 真换路由（router.go 销毁重建子路由，与壳切栏同构）
// 三对照——无垫=0（缺陷基线）、PageStorageKey 结果如实钉、ScrollPad>0。
// 实弹层：全 app 待办枚滚半屏→切今天→切回，滚动位与视图档保留
// （本文件唯一全 app 用例——同 isolate 多全 app 会互相污染挂死）。
// 注：ReorderableListView 3.38 内部为 Sliver 实现，找滚动体一律 byType(Scrollable)。

class _LongList extends StatelessWidget {
  const _LongList({this.keyOverride});

  final Key? keyOverride;

  @override
  Widget build(BuildContext context) => ListView(
        key: keyOverride,
        children: [
          for (var i = 0; i < 80; i++)
            SizedBox(height: 60, child: Center(child: Text('item-$i'))),
        ],
      );
}

// 注意：Scrollable 由 ListView/ReorderableListView **内部向下构建**，
// 取滚动位必须用 descendant（ancestor 恒空）。
double _offset(WidgetTester t) => t
    .state<ScrollableState>(find
        .descendant(
            of: find.byType(ListView), matching: find.byType(Scrollable))
        .first)
    .position
    .pixels;

Future<void> _scroll(WidgetTester t) async {
  await t.drag(find.byType(ListView), const Offset(0, -1200));
  await t.pumpAndSettle();
}

/// 本地壳：/a 长列表页 ⇄ /b 空页，go() 换路由＝子路由销毁重建（切栏同构）。
class _ShellHarness {
  _ShellHarness(this.pageA, {ProviderContainer? container})
      : router = GoRouter(
            initialLocation: '/a',
            routes: [
              ShellRoute(
                builder: (context, state, child) => child,
                routes: [
                  GoRoute(path: '/a', builder: (_, __) => pageA),
                  GoRoute(
                      path: '/b',
                      builder: (_, __) =>
                          const Scaffold(body: SizedBox.shrink())),
                ],
              ),
            ]) {
    if (container != null) {
      app = UncontrolledProviderScope(
          container: container, child: MaterialApp.router(routerConfig: router));
    } else {
      app = MaterialApp.router(routerConfig: router);
    }
  }

  final Widget pageA;
  final GoRouter router;
  late final Widget app;

  Future<void> swap(WidgetTester t) async {
    router.go('/b');
    await t.pumpAndSettle();
    router.go('/a');
    await t.pumpAndSettle();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('机制对照（ShellRoute 真换路由）', () {
    testWidgets('无垫：切栏回来滚动位=0（缺陷基线）', (tester) async {
      await useSurface(tester, const Size(390, 844));
      final h = _ShellHarness(const _LongList());
      addTearDown(h.router.dispose);
      await tester.pumpWidget(h.app);
      await tester.pumpAndSettle();
      await _scroll(tester);
      expect(_offset(tester), greaterThan(0));
      await h.swap(tester);
      expect(_offset(tester), 0, reason: '路由销毁重建即回零——这就是要修的现象');
    });

    testWidgets('PageStorageKey 跨不了路由（桶随旧路由销毁）', (tester) async {
      await useSurface(tester, const Size(390, 844));
      final h = _ShellHarness(
          const _LongList(keyOverride: PageStorageKey('probe')));
      addTearDown(h.router.dispose);
      await tester.pumpWidget(h.app);
      await tester.pumpAndSettle();
      await _scroll(tester);
      expect(_offset(tester), greaterThan(0));
      await h.swap(tester);
      expect(_offset(tester), 0,
          reason: 'PageStorageBucket 挂在 ModalRoute 上随旧路由销毁——'
              '故落地改用常驻 provider 垫（施工图口径修正见工单落地记录）');
    });

    testWidgets('ScrollPad：换路由回来 initialScrollOffset 垫回原位', (tester) async {
      await useSurface(tester, const Size(390, 844));
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final h = _ShellHarness(
          const ScrollPad(id: 'probe', child: _LongList()),
          container: container);
      addTearDown(h.router.dispose);
      await tester.pumpWidget(h.app);
      await tester.pumpAndSettle();
      await _scroll(tester);
      final saved = container.read(scrollPadProvider('probe'));
      expect(saved, greaterThan(0), reason: '滚动即写常驻槽位');
      await h.swap(tester);
      expect(_offset(tester), greaterThan(0), reason: '切栏回来仍在原位');
      expect(_offset(tester), closeTo(saved, 1.0));
    });
  });

  // 全 app 唯一用例。视口取宽是为避开仪表盘 hero 存量横向溢出（390 宽下 39px，
  // 非本批产物，观察项随批登记）。
  testWidgets('T2-B 实弹：待办枚滚半屏→切今天→切回，滚动位与视图档保留',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final registry = await const ThemeRepository().loadAll();
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      themeRegistryProvider.overrideWithValue(registry),
      todosProvider.overrideWith(
          (ref) => List.generate(80, (i) => Todo(id: i, title: 'T$i'))),
      overdueCountProvider.overrideWith((ref) => 0),
    ]);
    addTearDown(container.dispose);
    await useSurface(tester, const Size(480, 1280));
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: const LifeHarnessApp()));
    await settleFrames(tester);

    // 进待办枚（底栏文案唯一命中）。
    await tester.tap(find.text('待办').last);
    await settleFrames(tester);
    expect(find.text('T0'), findsOneWidget);

    // 滚过半屏（3.38 的 ReorderableListView 内部是 Sliver，取它内部 Scrollable）。
    final todoScroll = find.descendant(
        of: find.byType(ReorderableListView),
        matching: find.byType(Scrollable));
    await tester.drag(todoScroll, const Offset(0, -1400));
    await settleFrames(tester);
    final saved = container.read(scrollPadProvider('todo-list'));
    expect(saved, greaterThan(0), reason: '滚动即写常驻槽位');

    // 切今天 → 切回待办：位置垫回。
    await tester.tap(find.text('今天').last);
    await settleFrames(tester);
    await tester.tap(find.text('待办').last);
    await settleFrames(tester);
    final back = tester
        .state<ScrollableState>(todoScroll.first)
        .position
        .pixels;
    expect(back, greaterThan(0), reason: '切栏回来不再回零');
    expect(back, closeTo(saved, 1.0));

    // 视图档（清单⇄四象限）常驻存活：切栏往返不丢。
    await tester.tap(find.byKey(const ValueKey('btn-view-toggle')));
    await settleFrames(tester);
    await tester.tap(find.text('今天').last);
    await settleFrames(tester);
    await tester.tap(find.text('待办').last);
    await settleFrames(tester);
    expect(container.read(todoViewModeProvider), isTrue,
        reason: '象限档切栏存活（常驻 provider 口径）');
  });
}
