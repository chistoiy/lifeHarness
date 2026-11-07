import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/host/event_bus.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/todo/data/todo_dao.dart';
import 'package:lifeharness/features/todo/domain/todo.dart';
import 'package:lifeharness/features/todo/domain/todo_repository.dart';
import 'package:lifeharness/features/todo/presentation/todo_page.dart';
import 'package:lifeharness/features/todo/presentation/todo_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 交互整改批六 · T3（删除可逆性）常驻用例。
///
/// 拍板①＝待办左滑改**软删进全局回收站**＋带「撤销」的提示条（壳原型
/// `delTaskFromSheet` 早就是「进垃圾箱」口径，本次是把实现对齐回事实源）；
/// 拍板②＝呵护侧疫苗/里程碑删除先二次确认（用例改在
/// `care_vaccine_milestones_test.dart`，本文件用源码守护钉住不许回潮）。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late TodoRepository repo;
  late EventBus bus;
  late SharedPreferences prefs;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    bus = EventBus();
    repo = TodoRepository(TodoDao(db), bus);
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  tearDown(() async {
    await db.close();
    await bus.dispose();
  });

  Widget app() => ProviderScope(
        overrides: [
          todoRepositoryProvider.overrideWithValue(repo),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: const MaterialApp(home: TodoPage()),
      );

  Future<Map<String, Object?>> row(int id) async =>
      (await db.query(DbSchema.tTodos, where: 'id = ?', whereArgs: [id])).single;

  group('1 · 待办左滑＝软删进回收站（可撤销）', () {
    testWidgets('滑掉：行还在库里但 deleted_at 非空，在册列表不再出现', (tester) async {
      await useSurface(tester);
      final t = await repo.add(Todo(title: '买奶粉', quadrant: Quadrant.q3));
      await tester.pumpWidget(app());
      await settle5(tester);
      expect(find.text('买奶粉'), findsOneWidget);

      await tester.drag(find.byKey(ValueKey('dismiss-${t.id}')),
          const Offset(-500, 0));
      expect(await pollText(tester, '已移入回收站'), isTrue,
          reason: '滑删后必须给找回入口（撤销条）');
      expect(find.text('撤销'), findsOneWidget);
      await settle5(tester);

      final r = await row(t.id!);
      expect(r['deleted_at'], isNotNull, reason: '软删＝置 deleted_at，不许真 DELETE');
      expect(find.text('买奶粉'), findsNothing);
    });

    testWidgets('点撤销：deleted_at 清回 NULL，条目原样回在册', (tester) async {
      await useSurface(tester);
      final t = await repo.add(Todo(title: '约体检', quadrant: Quadrant.q2));
      await tester.pumpWidget(app());
      await settle5(tester);

      await tester.drag(find.byKey(ValueKey('dismiss-${t.id}')),
          const Offset(-500, 0));
      expect(await pollText(tester, '已移入回收站'), isTrue);
      // 等进场动画落定再点：SnackBarAction 在滑入过程中不可命中
      await settleFrames(tester);
      final undoBtn = find.descendant(
          of: find.byType(SnackBar), matching: find.text('撤销'));
      expect(undoBtn, findsOneWidget);
      await tester.tap(undoBtn);
      // 撤销＝异步 restore，小步 pump 等它落库（大 pump 会跳过 SnackBar 退场）
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        final r = await row(t.id!);
        if (r['deleted_at'] == null) break;
      }
      expect((await row(t.id!))['deleted_at'], isNull,
          reason: 'restore 只清 deleted_at，象限/截止不动');
      await settle5(tester);
      expect(find.text('约体检'), findsOneWidget);
    });
  });

  group('2 · 源码守护（不许回潮）', () {
    String read(String rel) => File('lib/$rel').readAsStringSync();

    test('待办清单不许再调真删 remove(todo)', () {
      final src = read('features/todo/presentation/widgets/todo_list_view.dart');
      expect(src, isNot(contains('.remove(todo)')),
          reason: '滑删必须走 softRemove（回收站通道现成）');
      expect(src, contains('softRemove(todo)'));
      expect(src, contains('showUndoWith'), reason: '必须给撤销口（messenger 先取）');
    });

    test('疫苗/里程碑删除前必须二次确认', () {
      for (final e in {
        'features/care/presentation/vaccine_page.dart': 'delVaccine',
        'features/care/presentation/milestone_page.dart': 'delMilestone',
      }.entries) {
        final src = read(e.key);
        final at = src.indexOf(e.value);
        expect(at, greaterThan(-1), reason: '${e.key} 找不到 ${e.value}');
        final head = src.substring(src.lastIndexOf('onTap:', at), at);
        expect(head, contains('lhConfirm'),
            reason: '${e.key} 的删除必须在确认之后才执行');
      }
    });

    test('确认版式只有一份实现（日子侧委托公共原语）', () {
      expect(read('features/days/presentation/days_kit.dart'),
          contains('lhConfirm(context, message'), reason: '日子侧必须委托公共原语');
      expect(read('features/days/presentation/days_kit.dart'),
          isNot(contains('showDialog')), reason: '确认版式不许有第二份实现');
      expect(read('shared/widgets/confirm_dialog.dart'),
          contains("ValueKey('d-confirm-ok')"),
          reason: 'key 不拆：既有用例与真机走查锚点沿用日子侧');
    });
  });
}
