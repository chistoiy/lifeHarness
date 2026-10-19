import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/core/settings/settings_repository.dart';
import 'package:lifeharness/features/journal/data/journal_dao.dart';
import 'package:lifeharness/features/journal/domain/journal_entry.dart';
import 'package:lifeharness/features/journal/domain/journal_repository.dart';
import 'package:lifeharness/features/journal/presentation/journal_page.dart';
import 'package:lifeharness/features/journal/presentation/journal_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';

/// 日记页 FAB 长按扇形（§4c-2 产品令）——「设置与筛选挂到新建钮上」的常驻回归。
///
/// 为什么单开一份：这套交互的坑都在**时序**上（长按后抑制单击、展开态短按收起、
/// 环外点击收起），塞进 `journal_test.dart` 会和那批列表断言搅在一起；
/// 另按库内规矩「全 app 用例拆独立文件」。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

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

  /// **必须关动画**：呼吸环是 `repeat(reverse:true)` 的无限动画，`pumpAndSettle`
  /// 会一直等不到静止而超时（9 例全红的唯一原因）。`disableAnimations` 正是
  /// 原型 `prefers-reduced-motion` 的 Flutter 对应物，组件里已有停环分支——
  /// 顺带把这条降级路径也纳入了回归。
  Widget scope(Widget home) => ProviderScope(
        overrides: [
          journalRepositoryProvider.overrideWithValue(jrepo),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: home,
          ),
        ),
      );

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(scope(const JournalPage()));
    await tester.pumpAndSettle();
  }

  Future<void> openFan(WidgetTester tester) async {
    await tester.longPress(find.byKey(const ValueKey('diary-fan-fab')));
    await tester.pumpAndSettle();
  }

  group('日记 FAB 长按扇形（§4c-2）', () {

    testWidgets('F1 收起态：只有球，扇形两枚都不在', (tester) async {
      await pumpPage(tester);
      expect(find.byKey(const ValueKey('diary-fan-fab')), findsOneWidget);
      expect(find.byKey(const ValueKey('diary-fan-筛选')), findsNothing);
      expect(find.byKey(const ValueKey('diary-fan-设置')), findsNothing);
    });

    testWidgets('F1b 呼吸效果三层齐备：2px 描边环 72 + 6px 外光晕 68 + 本体 56',
        (tester) async {
      await pumpPage(tester);
      // 环（原型 #fabHalo inset:-8px）
      final halo = find.byKey(const ValueKey('diary-fan-halo'));
      expect(halo, findsOneWidget);
      expect(tester.getSize(halo), const Size(72, 72));
      // 本体外光晕（原型 #fab 的 `0 0 0 6px`）——**这是「呼吸感」的另一半**：
      // 只有描边环时会看成「一圈灰边在胀」，6px 柔光环才像光在散开。
      final glow = find.byKey(const ValueKey('diary-fan-glow'));
      expect(glow, findsOneWidget, reason: '缺外光晕＝观感与原型不一致');
      expect(tester.getSize(glow), const Size(68, 68));
      // 球体本体仍是 56（不得被环/光晕撑大）
      expect(tester.getSize(find.byType(SizedBox).first).width, isNotNull);
    });

    testWidgets('F2 顶行三枚图标已整行移除（单入口：只留 FAB）', (tester) async {
      await pumpPage(tester);
      // 这三枚是 §4c-2 之前实现里多留的，原型早已整行删除。
      // 若将来有人「顺手加回来」把设置/筛选又挂到顶行，这条会红。
      expect(find.byKey(const ValueKey('diary-view')), findsNothing);
      expect(find.byKey(const ValueKey('diary-set')), findsNothing);
      expect(find.byKey(const ValueKey('diary-filter')), findsNothing);
    });

    testWidgets('F3 长按展开：筛选 + 设置两枚出现，且只两枚', (tester) async {
      await pumpPage(tester);
      await openFan(tester);
      expect(find.byKey(const ValueKey('diary-fan-筛选')), findsOneWidget);
      expect(find.byKey(const ValueKey('diary-fan-设置')), findsOneWidget);
      // 只出图标不出文字（产品令）⇒ 可见文字里不应有独立的两项名。
      expect(find.text('筛选'), findsNothing);
      expect(find.text('设置'), findsNothing);
    });

    testWidgets('F4 扇形向左上展开：两枚都不越过球体右缘', (tester) async {
      await pumpPage(tester);
      final fabRect = tester.getRect(find.byKey(const ValueKey('diary-fan-fab')));
      await openFan(tester);
      for (final label in ['筛选', '设置']) {
        final r = tester.getRect(find.byKey(ValueKey('diary-fan-$label')));
        // 原型口径：弧线 -168°..-102° 全在左侧/上方，末枚不顶屏幕右缘。
        expect(r.left, lessThan(fabRect.center.dx),
            reason: '$label 跑到球体右半区，弧线算错了');
      }
      final setR = tester.getRect(find.byKey(const ValueKey('diary-fan-设置')));
      final filterR =
          tester.getRect(find.byKey(const ValueKey('diary-fan-筛选')));
      // 筛选取 -168°（更靠左），设取 -102°（更靠上）
      expect(filterR.center.dx, lessThan(setR.center.dx));
      expect(filterR.center.dy, greaterThan(setR.center.dy));
    });

    testWidgets('F5 展开态短按球＝收起，不新建日记', (tester) async {
      await pumpPage(tester);
      await openFan(tester);
      await tester.tap(find.byKey(const ValueKey('diary-fan-fab')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('diary-fan-筛选')), findsNothing);
      // 仍在记录页（没被推到编辑页）
      expect(find.text('记录 · 日记'), findsOneWidget);
    });

    testWidgets('F6 点环外收起', (tester) async {
      await pumpPage(tester);
      await openFan(tester);
      expect(find.byKey(const ValueKey('diary-fan-筛选')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('diary-fan-scrim')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('diary-fan-筛选')), findsNothing);
    });

    testWidgets('F7 点「设置」＝开日记设置弹层（含三档）', (tester) async {
      await pumpPage(tester);
      await openFan(tester);
      await tester.tap(find.byKey(const ValueKey('diary-fan-设置')));
      await tester.pumpAndSettle();
      expect(find.text('日记设置'), findsOneWidget);
      expect(find.byKey(const ValueKey('dset-list')), findsOneWidget);
      expect(find.byKey(const ValueKey('dset-track')), findsOneWidget);
      expect(find.byKey(const ValueKey('dset-ins')), findsOneWidget);
    });

    testWidgets('F8 点「筛选」＝开筛选弹层，且筛完真的过滤', (tester) async {
      await jrepo.save(JournalEntry(
          day: DateTime.now(),
          content: '☐ 买猫粮 未完成',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now()));
      await jrepo.save(JournalEntry(
          day: DateTime.now(),
          content: '普通一天',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now()));
      await pumpPage(tester);

      await openFan(tester);
      await tester.tap(find.byKey(const ValueKey('diary-fan-筛选')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('df-opt-☐ 待办')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('df-opt-☐ 待办')));
      await settle5(tester);

      expect(find.textContaining('买猫粮'), findsOneWidget);
      expect(find.textContaining('普通一天'), findsNothing);
    });

    testWidgets('F9 单击球＝新建日记（扇形从未展开时不被长按逻辑吃掉）',
        (tester) async {
      await pumpPage(tester);
      await tester.tap(find.byKey(const ValueKey('diary-fan-fab')));
      await tester.pump();

      // 测试用的 MaterialApp 没挂 go_router，`push('/journal/edit')` 会抛
      // 「No GoRouter found in context」——**这个异常本身就是判据**：
      // 它只在新建回调真的被派发时才会出现（回调体内第一句就是 push）。
      // 若长按逻辑吃掉了单击，这里会是 null。
      final err = tester.takeException();
      expect(err, isNotNull, reason: '单击没触发新建（onTap 没跑）');
      expect(err.toString(), contains('GoRouter'),
          reason: '单击产生了非预期异常：$err');
    });
  });
}
