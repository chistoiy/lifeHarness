import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/host/event_bus.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/todo/data/todo_dao.dart';
import 'package:lifeharness/features/todo/domain/todo.dart';
import 'package:lifeharness/features/todo/domain/todo_repository.dart';
import 'package:lifeharness/features/todo/presentation/todo_page.dart';
import 'package:lifeharness/features/todo/presentation/todo_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// T9 防重入用例专用：把插入钉慢，制造「写入进行中」那一帧
/// （真 IO 在 FakeAsync 下的完成时机不可预测，慢仓才稳）。
class _SlowTodoRepo extends TodoRepository {
  _SlowTodoRepo(super.dao, super.bus);

  @override
  Future<Todo> add(Todo t) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return super.add(t);
  }
}

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
    // 清单视图监听 settingsControllerProvider（临期升紧急开关），需 prefs 桩
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  tearDown(() async {
    await db.close();
    await bus.dispose();
  });

  Widget app({TodoRepository? data}) => ProviderScope(
        overrides: [
          todoRepositoryProvider.overrideWithValue(data ?? repo),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: const MaterialApp(home: TodoPage()),
      );

  testWidgets('引导式两问 100% 落象限：重要+紧急 → Q1（原型单表单式）', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add).last); // FAB → 类型二选一（T4）
    await tester.pumpAndSettle();
    expect(find.text('普通待办'), findsOneWidget);
    expect(find.text('番茄计时'), findsOneWidget);
    await tester.tap(find.text('普通待办'));
    await tester.pumpAndSettle();
    expect(find.text('新建待办'), findsOneWidget);
    expect(find.text('引导式判象限（推荐）'), findsOneWidget);

    // 两张问卡各点一次 = 是
    await tester.tap(find.text('这件事重要吗？'));
    await tester.pump();
    await tester.tap(find.text('这件事紧急吗？'));
    await tester.pump();
    expect(find.text('是 ✓'), findsNWidgets(2));

    await tester.enterText(find.byType(TextField).first, '救火任务');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final saved = await repo.list();
    expect(saved.single.title, '救火任务');
    expect(saved.single.quadrant, Quadrant.q1);
    expect(find.text('已保存到「重要且紧急」象限 ✓'), findsOneWidget);
  });

  testWidgets('T9 批三：空标题就地报错（不挂提示条）＋保存连点只落一条',
      (tester) async {
    final slow = _SlowTodoRepo(TodoDao(db), bus); // 写入钉慢才测得到「进行中」
    await tester.pumpWidget(app(data: slow));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add).last); // FAB → 类型二选一
    await tester.pumpAndSettle();
    await tester.tap(find.text('普通待办'));
    await tester.pumpAndSettle();
    expect(find.text('新建待办'), findsOneWidget);

    // 空标题点保存：错误挂字段旁，弹层内不借道页面提示条
    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(
        tester
            .widget<TextField>(find.byType(TextField).first)
            .decoration!
            .errorText,
        '请先输入任务标题');
    expect(find.byType(SnackBar), findsNothing);

    // 报错行使输入框变高，点对 TextField 中心会落到错误行上，
    // 所以对着可编辑区（EditableText）聚焦再输入。
    await tester.enterText(
        find.descendant(
            of: find.byType(TextField).first,
            matching: find.byType(EditableText)),
        '一条任务');
    await tester.pump();
    expect(find.text('请先输入任务标题'), findsNothing); // 输入即撤错

    // 连点两次：第一次逐条 await 未完时，第二次不许再写一遍
    await tester.ensureVisible(find.text('保存'));
    await tester.tap(find.text('保存'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('新建待办'), findsOneWidget); // 还在写＝弹层没关
    await tester.tap(find.text('保存'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    final saved = await repo.list();
    expect(saved, hasLength(1));
    expect(saved.single.title, '一条任务');
  });

  testWidgets('勾选完成 → L2 联动 toast，任务划线保留', (tester) async {
    final t = await repo.add(Todo(title: '待办A', quadrant: Quadrant.q2));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    // 原型 .chk 圆形勾选（key='chk-<id>'）
    await tester.tap(find.byKey(ValueKey('chk-${t.id}')));
    await tester.pumpAndSettle();

    final saved = await repo.list();
    expect(saved.single.done, isTrue);
    expect(find.text('完成 ✓ 已计入今日小结（联动 L2）'), findsOneWidget);
    expect(find.text('待办A'), findsOneWidget); // 全部筛选下沉底保留
  });

  testWidgets('四象限视图：提示条/格内计数/逾期图标', (tester) async {
    final now = DateTime.now();
    await repo.add(Todo(title: '逾期任务', quadrant: Quadrant.q1, dueAt: now.subtract(const Duration(days: 1))));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('⏰ 1'), findsOneWidget); // AppBar 角标

    await tester.tap(find.byKey(const ValueKey('btn-view-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('💡 长按卡片可拖到其他象限'), findsNothing); // T8 已移除
    expect(find.text('重要且紧急'), findsOneWidget);
    expect(find.text('立即做 · 1 待办'), findsOneWidget);
    expect(find.text('逾期任务'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    // T11：象限卡片=方框＋标题
    expect(find.byKey(ValueKey('qchk-1')), findsOneWidget);
  });

  testWidgets('详情弹层改判象限并持久化（原型 sheetTask q-move 即点即存）',
      (tester) async {
    final t = await repo.add(Todo(title: '改判任务', quadrant: Quadrant.q4));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('改判任务'));
    await tester.pumpAndSettle();
    // 原型 q-move 四短钮：立即做/计划做/委托/淘汰
    expect(find.text('委托'), findsOneWidget);
    expect(find.text('淘汰'), findsOneWidget);

    await tester.tap(find.text('委托'));
    await tester.pumpAndSettle();

    final list = await repo.list();
    expect(list.first.quadrant, Quadrant.q3);
    expect(t.id, isNotNull);
    expect(find.text('已改判为「紧急不重要」（拖拽同样可用）'), findsOneWidget);
  });

  testWidgets('V1.27 T3 详情→编辑：复用表单回填并覆盖保存', (tester) async {
    final t = await repo.add(Todo(
        title: '原始标题',
        quadrant: Quadrant.q2,
        tag: '收集箱',
        dueAt: DateTime.now().add(const Duration(days: 2))));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    // 点条目 → 详情弹层 → ✏️ 编辑
    await tester.tap(find.text('原始标题'));
    await tester.pumpAndSettle();
    expect(find.text('✏️ 编辑'), findsOneWidget);
    await tester.tap(find.text('✏️ 编辑'));
    await tester.pumpAndSettle();

    expect(find.text('编辑待办'), findsOneWidget);
    // 标题回填（表单输入框初值；列表页同款文本在弹层后仍可见）
    expect(tester.widget<TextField>(find.byType(TextField).first).controller?.text,
        '原始标题');
    // 不重答两问直接改标题保存 → 象限/标签保持不变
    await tester.enterText(find.byType(TextField).first, '改后标题');
    await tester.tap(find.text('保存修改'));
    await tester.pumpAndSettle();

    final saved = await repo.list();
    expect(saved.single.title, '改后标题');
    expect(saved.single.quadrant, Quadrant.q2);
    expect(saved.single.tag, '收集箱');
    expect(saved.single.id, t.id); // 覆盖原条目而非新增
    expect(find.text('修改已保存 ✓'), findsOneWidget);
  });

  testWidgets('V1.27 T4 番茄钟路径：类型卡+进度条快捷点渲染', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add).last); // FAB → 二选一
    await tester.pumpAndSettle();
    await tester.tap(find.text('番茄计时'));
    await tester.pumpAndSettle();

    expect(find.text('番茄计时'), findsOneWidget);
    expect(find.text('倒计时'), findsOneWidget);
    // 切倒计时 → 进度条 + 快捷点（5/15/30/45）出现
    await tester.tap(find.text('倒计时'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pomo-min')), findsOneWidget);
    expect(find.byKey(const ValueKey('pomo-quick-30')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pomo-quick-30')));
    await tester.pump();
    expect(find.text('30 分钟'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '专注任务');
    await tester.ensureVisible(find.text('保存'));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final saved = await repo.list();
    expect(saved.single.pomoMode, 'down');
    expect(saved.single.pomoMin, 30);
  });

  testWidgets('V1.27 追加：象限格内＋添加 → 预置两问+落点预览·可改·保存直达象限',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('btn-view-toggle')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('+ 添加').first); // Q1「重要且紧急」格
    await tester.pumpAndSettle();
    expect(find.text('新建待办'), findsOneWidget);
    // 预置直观可见：两卡均「是 ✓」+ 落点预览
    expect(find.text('是 ✓'), findsNWidgets(2));
    expect(find.text('保存后进入「重要且紧急」象限'), findsOneWidget);

    // 手动改「重要=否」→ 落点即时跟随
    await tester.tap(find.text('这件事重要吗？'));
    await tester.pump();
    expect(find.text('保存后进入「紧急不重要」象限'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '象限预置任务');
    await tester.ensureVisible(find.text('保存'));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final saved = await repo.list();
    expect(saved.single.title, '象限预置任务');
    expect(saved.single.quadrant, Quadrant.q3);
  });
}
