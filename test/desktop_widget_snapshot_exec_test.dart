/// 桌面批 3 · `buildSnapshot` **真实执行**守护（2026-10-15 真机崩溃回归）。
///
/// ## 为什么单独一个文件（别删我）
///
/// 真机 21:47 崩在 `buildSnapshot`：`NoSuchMethodError: Class 'AsyncData<List<Todo>>'
/// has no instance getter 'valueOrNull'`。根因是上一轮为了让 `Ref`（挂载点）与
/// `WidgetRef`（设置页）都能传进来，把参数声明成了 `dynamic ref` —— 于是
/// `ref.read(...)` 的静态类型退化为 `dynamic`，`valueOrNull` 这个**扩展方法
/// 根本不再参与解析**，运行时直接抛。
///
/// 当时 `flutter analyze` 全绿、26 例小组件守护也全绿，**两条路都漏了**：
/// - analyze 对 `dynamic` 的成员调用不做任何检查；
/// - 原 widget 测试跑在 `AppDatabase` 未初始化状态，`buildSnapshot` 第一行就
///   `return null`，**那一行代码从来没被执行过**；
/// - 而守护测试是**扫源码文本**（`contains('buildSnapshot(ref)')`），
///   它压根不执行运行时路径。
///
/// 所以本文件的作用就一件事：**让 `ref.read(...).valueOrNull` 那一行被真正跑到**。
/// 做法＝真开一个 ffi 库把 `AppDatabase` 初始化起来（越过那道 early return），
/// 再用 `ProviderContainer` 构造真Provider，逐字段核对快照。
///
/// 回归时把它改回 `dynamic`，本文件必然红（NoSuchMethodError）。
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/app_database.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/platform/desktop_widget.dart';
import 'package:lifeharness/core/providers.dart' show sharedPreferencesProvider;
import 'package:lifeharness/core/settings/settings_repository.dart';
import 'package:lifeharness/shared/linkage/desktop_widget_mounts.dart'
    show buildSnapshot;
import 'package:lifeharness/shared/linkage/stats_providers.dart'
    show Todo, todosProvider;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late ProviderContainer container;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tmp = Directory.systemTemp.createTempSync('lh_snap_exec_');
    // 真初始化：buildSnapshot 第一行的 early return 只有在这里才会被越过。
    await AppDatabase.instance.open(pathOverride: '${tmp.path}/app.db');
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    try {
      await AppDatabase.instance.close();
    } catch (_) {
      // catch-ok：单例可能已被关闭。
    }
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {
      // catch-ok：临时目录清理失败不阻断。
    }
  });

  group('buildSnapshot 真实执行（dynamic 退化回归）', () {
    test('库已初始化时不再提前 return，且真的跑过 valueOrNull 扩展', () {
      // 三个 FutureProvider 都还没首次到达 ⇒ 必走
      //   `if (todos == null && habit == null && ledger == null) return null;`
      // 但注意：它**先**执行了三行 read().valueOrNull ⇒ 只要类型退化成 dynamic
      // 就会在这一步抛 NoSuchMethodError，测试直接红。
      expect(AppDatabase.instance.isInitialized, isTrue);
      final snap = buildSnapshot(container.read);
      expect(snap, isNull, reason: '三源都没到达 ⇒ 无快照（与桌面同口径）');
    });

    test('待办 provider 有值时，出快照且待办数与行池都对得上', () async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 9);
      final overdue = DateTime(now.year, now.month, now.day, 8)
          .subtract(const Duration(days: 1));

      final c2 = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
        ],
      );
      addTearDown(c2.dispose);

      // 先读一次让 AsyncData 就位（FutureProvider 首帧是 AsyncLoading）。
      await c2.read(todosProvider.future);
      // 断言 valueOrNull 扩展在真实 Provider 上可用 —— 这一行就是崩溃点。
      expect(c2.read(todosProvider).valueOrNull, isA<List<Todo>>());

      // 造一条今天到期、一条逾期的待办，走真库。
      final db = AppDatabase.instance.db;
      await db.insert(DbSchema.tTodos, {
        'title': '今天到期',
        'due_at': today.millisecondsSinceEpoch,
        'done': 0,
        'dropped': 0,
        'created_at': 1,
        'updated_at': 1,
      });
      await db.insert(DbSchema.tTodos, {
        'title': '逾期未完',
        'due_at': overdue.millisecondsSinceEpoch,
        'done': 0,
        'dropped': 0,
        'created_at': 2,
        'updated_at': 2,
      });
      c2.invalidate(todosProvider);
      await c2.read(todosProvider.future);

      final snap = buildSnapshot(c2.read);
      expect(snap, isNotNull, reason: '待办源已到达 ⇒ 必须出快照');
      expect(snap!.todoCount, 1, reason: '「今日到期」只数今天那条，逾期不混计');
      expect(snap.todoItems.length, 2, reason: '行池＝今天到期 ＋ 逾期，两条都在');
      expect(
        snap.todoItems.map((e) => e.title).toSet(),
        <String>{'今天到期', '逾期未完'},
      );
      expect(snap.todoItems.first.id, greaterThan(0), reason: '闭环靠 id 回写');
      expect(snap.todoOverflow, 0);
    });

    test('行池上限是 kWidgetTodoRows，且超出部分进 todoOverflow', () async {
      final now = DateTime.now();
      final c3 = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
        ],
      );
      addTearDown(c3.dispose);

      final db = AppDatabase.instance.db;
      for (var i = 0; i < kWidgetTodoRows + 2; i++) {
        await db.insert(DbSchema.tTodos, {
          'title': 'T$i',
          'due_at': DateTime(now.year, now.month, now.day, 7, i)
              .millisecondsSinceEpoch,
          'done': 0,
          'dropped': 0,
          'created_at': i,
          'updated_at': i,
        });
      }
      await c3.read(todosProvider.future);
      final snap = buildSnapshot(c3.read);
      expect(snap, isNotNull);
      expect(snap!.todoItems.length, kWidgetTodoRows);
      expect(snap.todoOverflow, 2, reason: '多出的 2 条用「还有 N 条」表达');
    });

    test('已完成 / 已丢 / 已删的待办都不进行池', () async {
      final now = DateTime.now();
      final due = DateTime(now.year, now.month, now.day, 7).millisecondsSinceEpoch;
      final c4 = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
        ],
      );
      addTearDown(c4.dispose);

      final db = AppDatabase.instance.db;
      await db.insert(DbSchema.tTodos, {
        'title': '已完成',
        'due_at': due,
        'done': 1,
        'dropped': 0,
        'created_at': 1,
        'updated_at': 1,
      });
      await db.insert(DbSchema.tTodos, {
        'title': '已丢弃',
        'due_at': due,
        'done': 0,
        'dropped': 1,
        'created_at': 2,
        'updated_at': 2,
      });
      await db.insert(DbSchema.tTodos, {
        'title': '已删',
        'due_at': due,
        'done': 0,
        'dropped': 0,
        'deleted_at': 1,
        'created_at': 3,
        'updated_at': 3,
      });
      await c4.read(todosProvider.future);
      final snap = buildSnapshot(c4.read);
      expect(snap, isNotNull);
      expect(snap!.todoItems, isEmpty);
      expect(snap.todoOverflow, 0);
    });

    test('隐藏金额开关对三个金额位同时生效（遮蔽口径在真源里算好）', () async {
      final now = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      // 键名取 SettingsRepository 的常量，别手抄（抄错就是「假绿」）。
      await prefs.setBool(
        SettingsRepository.kDeskHideAmountKey,
        true,
      );

      final c5 = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(c5.dispose);
      await c5.read(todosProvider.future);

      final snap = buildSnapshot(c5.read);
      expect(snap, isNotNull);
      expect(snap!.amountCell, '••••');
      expect(snap.monthAmountCell, '••••');
      expect(snap.balanceCell, '••••');
    });

    test('签名保持强类型读取函数（禁改回 dynamic · 扫源码兜底）', () {
      final src =
          File('lib/shared/linkage/desktop_widget_mounts.dart').readAsStringSync();
      expect(src, contains('DesktopWidgetSnapshot? buildSnapshot(WidgetSnapshotRead read)'));
      expect(src, isNot(contains('buildSnapshot(dynamic')));
      expect(src, isNot(contains('avoid_dynamic_calls')));
    });
  });
}