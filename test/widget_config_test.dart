import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/platform/desktop_widget.dart' show LhWidgetNames;
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/settings/presentation/desktop_settings_page.dart';
import 'package:lifeharness/features/widget/data/widget_binding_store.dart';
import 'package:lifeharness/features/widget/domain/widget_binding.dart';
import 'package:lifeharness/features/widget/presentation/widget_target_picker.dart'
    show widgetTargetLabel;
import 'package:lifeharness/shared/linkage/widget_bind_mounts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 小组件模块 批A · 配置页守护（工单 §2 配置页层 ·「先选后落」）。
///
/// 五块：
/// ① **预选绑定的编解码与有效期**（纯函数·脏值不猜、过期作废）；
/// ② **交接位不进实例清单**（`loadAll` 必须跳过 `…pending`，否则配置页会把它
///    当成一枚真实实例列出来）；
/// ③ **人话标签**（设置页只拿得到标签，拿不到目标模型——R1）；
/// ④ **流程四步 ①~③**（真链路·内存库注入）：开选择器（打卡段预开）→ 取消不落盘／
///    选中即落预选并请系统 pin；
/// ⑤ **设置页接线**（假流程注入）：两个入口都通到同一流程、取消不提示、选中给提示。
///
/// ⚠ 不在测试里初始化 `AppDatabase`：它走 sqflite 全局工厂，在 Windows 测试环境
/// 会卡住（实测 2 分钟超时无输出）——故一律用 picker 既有的 `db:` 注入缝。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  databaseFactory = databaseFactoryFfiNoIsolate;

  const habitTarget = WidgetTarget(kind: 'nav', ref: 'habit', sub: '早起喝水');

  group('预选绑定（域层纯函数）', () {
    test('五段编码往返：目标与时间戳原样回来', () {
      const p = WidgetPendingBind(
          widgetKind: kWidgetKindHabit, target: habitTarget, atMs: 1730000000000);
      final back = WidgetPendingBind.decode(p.encode());
      expect(back, isNotNull);
      expect(back!.widgetKind, kWidgetKindHabit);
      expect(back.target, habitTarget);
      expect(back.atMs, 1730000000000);
      // 五段：种类 + kind + ref + sub + 时间戳（分隔符与目标同族）。
      expect(p.encode().split(kWidgetBindFieldSep).length, 5);
    });

    test('sub 为空也往返（无二级参数的目标）', () {
      const p = WidgetPendingBind(
        widgetKind: kWidgetKindHabit,
        target: WidgetTarget(kind: 'timer_cat', ref: '7'),
        atMs: 1,
      );
      final back = WidgetPendingBind.decode(p.encode());
      expect(back!.target.kind, 'timer_cat');
      expect(back.target.ref, '7');
      expect(back.target.sub, isNull);
    });

    test('脏值一律 null（段数/种类/时间戳/目标任一不合格）', () {
      expect(WidgetPendingBind.decode(null), isNull);
      expect(WidgetPendingBind.decode(''), isNull);
      // 段数不足
      expect(WidgetPendingBind.decode('habit${kWidgetBindFieldSep}nav'), isNull);
      // 种类空
      expect(WidgetPendingBind.decode(_pending(['', 'nav', 'habit', '早起', '1'])),
          isNull);
      // 目标 kind 不在已知集合
      expect(
          WidgetPendingBind.decode(
              _pending(['habit', 'zzz', 'habit', '早起', '1'])),
          isNull);
      // 目标 ref 空
      expect(
          WidgetPendingBind.decode(_pending(['habit', 'nav', '', '早起', '1'])),
          isNull);
      // 时间戳非法/非正
      expect(
          WidgetPendingBind.decode(
              _pending(['habit', 'nav', 'habit', '早起', 'x'])),
          isNull);
      expect(
          WidgetPendingBind.decode(
              _pending(['habit', 'nav', 'habit', '早起', '0'])),
          isNull);
    });

    test('有效期：TTL 内有效·超时作废·未来时间戳不永久有效', () {
      const at = 1730000000000;
      const p = WidgetPendingBind(
          widgetKind: kWidgetKindHabit, target: habitTarget, atMs: at);
      expect(p.isFreshAt(at), isTrue);
      expect(p.isFreshAt(at + kWidgetBindPendingTtlMs), isTrue);
      expect(p.isFreshAt(at + kWidgetBindPendingTtlMs + 1), isFalse);
      // 时钟回拨容忍窗口内仍算新鲜（同机单调递增·只为吃掉脏值）。
      expect(p.isFreshAt(at - kWidgetBindPendingSkewMs), isTrue);
      expect(p.isFreshAt(at - kWidgetBindPendingSkewMs - 1), isFalse);
    });
  });

  group('交接位（store）', () {
    late SharedPreferences prefs;
    late WidgetBindingStore store;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      prefs = await SharedPreferences.getInstance();
      store = WidgetBindingStore(prefs);
    });

    test('落预选 → 同种类可取；种类不匹配取不到', () async {
      await store.setPendingTarget(kWidgetKindHabit, habitTarget, nowMs: 1000);
      final p = store.pendingBindFor(kWidgetKindHabit, nowMs: 1000);
      expect(p, isNotNull);
      expect(p!.target, habitTarget);
      // 别的枚来问：拿不到（防「取消后随手拖出别的枚被误吃」）。
      expect(store.pendingBindFor('todo', nowMs: 1000), isNull);
      // 原始记录不判过期（排障用）。
      expect(store.pendingBind, isNotNull);
    });

    test('过期即视为无预选', () async {
      await store.setPendingTarget(kWidgetKindHabit, habitTarget, nowMs: 1000);
      expect(
          store.pendingBindFor(kWidgetKindHabit,
              nowMs: 1000 + kWidgetBindPendingTtlMs + 1),
          isNull);
    });

    test('目标无效不落盘（半成品状态禁写）', () async {
      await store.setPendingTarget(kWidgetKindHabit,
          const WidgetTarget(kind: 'nav', ref: ''), nowMs: 1000);
      expect(store.pendingBind, isNull);
      expect(prefs.getString(kWidgetBindPendingKey), isNull);
    });

    test('clearPendingBind 清干净', () async {
      await store.setPendingTarget(kWidgetKindHabit, habitTarget, nowMs: 1000);
      await store.clearPendingBind();
      expect(store.pendingBind, isNull);
    });

    test('预选键不进实例清单（loadAll 跳过 pending/default）', () async {
      await store.setPendingTarget(kWidgetKindHabit, habitTarget, nowMs: 1000);
      await store.bind(7, habitTarget);
      await store.setGlobalDefault(habitTarget);
      final all = store.loadAll();
      expect(all.keys, <int>[7]);
      expect(all[7]!.target, habitTarget);
    });
  });

  group('人话标签（设置页只拿得到这一层）', () {
    test('打卡带习惯名·快捷动作取动作标签·其余只给大类', () {
      expect(widgetTargetLabel(habitTarget), '打卡 · 早起喝水');
      expect(widgetTargetLabel(const WidgetTarget(kind: 'nav', ref: 'ledger')),
          '快捷动作 · 记一笔');
      // 呵护的二级参数是 <babyId>/<kindId> 机器码，不上屏。
      expect(
          widgetTargetLabel(
              const WidgetTarget(kind: 'nav', ref: 'care', sub: '3/nurse')),
          '呵护宝宝');
      expect(widgetTargetLabel(const WidgetTarget(kind: 'timer_cat', ref: '7')),
          '计时分类');
      expect(
          widgetTargetLabel(const WidgetTarget(kind: 'read_book', ref: 'bk1')),
          '阅读书目');
    });
  });

  group('流程四步 ①~③（真链路·内存库注入）', () {
    late Database db;
    late SharedPreferences prefs;
    late List<String> pinCalls;
    late List<String> redrawCalls;

    setUp(() async {
      db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      for (final sql in DbSchema.createStatements) {
        await db.execute(sql);
      }
      for (final (id, name) in <(String, String)>[
        ('h1', '早起喝水'),
        ('h2', '夜读半小时'),
      ]) {
        await db.insert(DbSchema.tHabits, {
          'id': id,
          'name': name,
          'icon': 'run',
          'type': 'pos',
          'cycle': 'day',
          'start_date': '2026-01-01',
          'created_at': 0,
          'updated_at': 0,
        });
      }
      SharedPreferences.setMockInitialValues(<String, Object>{});
      prefs = await SharedPreferences.getInstance();
      pinCalls = <String>[];
      redrawCalls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('lh/desktop'),
              (call) async {
        if (call.method == 'pinWidget') {
          pinCalls.add(
              (call.arguments as Map<Object?, Object?>)['widget']! as String);
          return true;
        }
        if (call.method == 'syncShortcuts') return 0;
        return null;
      });
      // 2026-10-18：流程尾部会「推一把重绘」（真机报障：MIUI 不跑配置页 ⇒
      // 选了不生效，选完当场重绘一次让桌面立刻显示所选习惯）。这条通道在
      // 测试绑定里必须有桩，否则那次调用会悬着不返回，整个流程走不完。
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('home_widget'),
              (call) async {
        if (call.method == 'updateWidget') {
          redrawCalls
              .add((call.arguments as Map<Object?, Object?>)['android'] as String);
          return true;
        }
        return null;
      });
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('lh/desktop'), null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('home_widget'), null);
      await db.close();
    });

    testWidgets('选择器开在打卡段（步②预开）·按钮随 widget 模式变「添加到桌面」',
        (tester) async {
      await _pumpFlow(tester, prefs: prefs, db: db);
      await tester.tap(find.byKey(const ValueKey('flow')));
      await tester.pumpAndSettle();
      // 不点 tab 就有习惯 chip ＝ 打卡段预开。
      expect(find.text('早起喝水'), findsOneWidget);
      expect(find.text('夜读半小时'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '添加到桌面'), findsOneWidget);
      expect(find.text('点击后做什么'), findsOneWidget);
    });

    testWidgets('取消 ⇒ 不落预选、不调 pin（原型步③「取消则不落桌面」）',
        (tester) async {
      await _pumpFlow(tester, prefs: prefs, db: db);
      await tester.tap(find.byKey(const ValueKey('flow')));
      await tester.pumpAndSettle();
      // 点遮罩区收起弹层（modal sheet 无返回按钮）。
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(prefs.getString(kWidgetBindPendingKey), isNull);
      expect(pinCalls, isEmpty);
      expect(find.text('已选'), findsNothing);
    });

    testWidgets('选中习惯 ⇒ 落预选（打卡目标）＋只请 pin 打卡枚＋回人话标签',
        (tester) async {
      await _pumpFlow(tester, prefs: prefs, db: db);
      await tester.tap(find.byKey(const ValueKey('flow')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('wg-target-habit-h2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('wg-confirm')));
      await tester.pumpAndSettle();
      // 2026-10-18：流程尾部多了「落默认绑定 + 推一把重绘」两次异步（真机报障修），
      // 提示文案的 setState 落在上一轮 settle 之后 ⇒ 再 settle 一次才画出来。
      await tester.pumpAndSettle();

      // ② 预选落盘：种类＝打卡枚，目标＝nav/habit/夜读半小时。
      final staged = WidgetBindingStore(prefs).pendingBind;
      expect(staged, isNotNull);
      expect(staged!.widgetKind, kWidgetKindHabit);
      expect(staged.target.kind, 'nav');
      expect(staged.target.ref, 'habit');
      expect(staged.target.sub, '夜读半小时');
      // ③ 只请 pin 打卡这一枚（不是四枚读数型里的任何一枚）。
      expect(pinCalls, <String>[kWidgetKindHabit]);
      // ③b 兜底：默认绑定也落一份（MIUI 不跑配置页时实例靠它显示所选习惯），
      //     并当场推一把重绘（已在桌面的未绑定枚不会自己醒）。
      expect(WidgetBindingStore(prefs).globalDefault?.sub, '夜读半小时');
      expect(redrawCalls, <String>[LhWidgetNames.habitCheck]);
      // 流程回的是人话标签（设置页直接拿去提示）。
      expect(find.text('打卡 · 夜读半小时'), findsOneWidget);
    });
  });

  group('设置页接线（假流程注入·不读库）', () {
    late List<String?> flowResults;
    late int calls;

    setUp(() {
      flowResults = <String?>[];
      calls = 0;
    });

    Future<void> pumpPage(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      tester.view.physicalSize = const Size(1200, 2800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          home: DesktopSettingsPage(
            addWidgetFlow: (_, _) async {
              calls++;
              return flowResults.isEmpty ? null : flowResults.removeAt(0);
            },
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('卡片有「添加小组件」与「打卡-单习惯（2×2）」两个入口', (tester) async {
      await pumpPage(tester);
      expect(find.byKey(const ValueKey('wg-add-widget')), findsOneWidget);
      expect(find.text('添加小组件'), findsOneWidget);
      expect(find.text('打卡-单习惯（2×2）'), findsOneWidget);
      expect(find.byKey(const ValueKey('wg-pin-habit')), findsOneWidget);
    });

    testWidgets('两个入口都通到同一流程；选中给提示、取消不提示', (tester) async {
      await pumpPage(tester);
      // ① 头部入口：流程返回标签 ⇒ 提示带标签。
      flowResults = <String?>['打卡 · 早起喝水'];
      await tester.tap(find.byKey(const ValueKey('wg-add-widget')));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.textContaining('已选「打卡 · 早起喝水」'), findsOneWidget);
      // ② 行内「添加」：流程返回 null（取消）⇒ 不再提示。
      // 先把上一条提示等过去（SnackBar 1.6s 自消，不等会误判成「又弹了一条」）。
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.textContaining('已选「'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('wg-pin-habit')));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.textContaining('已选「'), findsNothing);
    });
  });
}

/// 五段拼接（分隔符是控制字符，逐段插值会被 lint 追着咬，且拼接处看不出段界）。
String _pending(List<String> fields) => fields.join(kWidgetBindFieldSep);

/// 只放一个按钮的宿主页：点它就跑一次真流程（选择器要 BuildContext 与 Navigator）。
class _FlowHarness extends StatefulWidget {
  const _FlowHarness({required this.prefs, required this.db});

  final SharedPreferences prefs;
  final Database db;

  @override
  State<_FlowHarness> createState() => _FlowHarnessState();
}

class _FlowHarnessState extends State<_FlowHarness> {
  String? _label;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              key: const ValueKey('flow'),
              onPressed: () async {
                final l = await addHabitWidgetFromSettings(context, widget.prefs,
                    db: widget.db);
                if (mounted) setState(() => _label = l);
              },
              child: const Text('添加小组件'),
            ),
            if (_label != null) Text(_label!),
          ],
        ),
      ),
    );
  }
}

Future<void> _pumpFlow(
  WidgetTester tester, {
  required SharedPreferences prefs,
  required Database db,
}) async {
  await tester.pumpWidget(MaterialApp(home: _FlowHarness(prefs: prefs, db: db)));
  await tester.pumpAndSettle();
}
