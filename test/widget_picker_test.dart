import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/nfc/domain/nfc_card.dart'
    show kNfcRefCare, kNfcRefHabit, nfcCareSubOf, nfcCareSubParse;
import 'package:lifeharness/features/widget/domain/widget_binding.dart';
import 'package:lifeharness/features/widget/presentation/widget_target_picker.dart';
import 'package:lifeharness/shared/linkage/nfc_mounts.dart'
    show nfcBabyOptions, nfcCareKindOptions, nfcCategoryTree, nfcHabitOptions;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 小组件模块 批A · 选择层守护（工单 §1 面板·`test/widget_picker_test.dart`）。
///
/// 三块口径（面板原文）：**五段目标返回三件套**（UI 走通五区→确认拿到
/// `{kind, ref, sub}`）；**写卡分支隔离不泄漏**（新组件零 NFC feature 依赖·
/// 源码扫描钉死）；**同一数据源**（各区选项与 `nfc_mounts` 同库同函数输出
/// 逐项一致）。另加同源守护：与 NFC 侧两处登记（tab 表／ref 常量／care 子
/// 格式）逐字节对齐——NFC 改序/改标签 ⇒ 本文件红，禁悄悄漂移。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  databaseFactory = databaseFactoryFfiNoIsolate;

  group('纯函数：初始目标 → （tab，各区记忆）', () {
    test('无初始目标落 nav 区、全区空记忆', () {
      final (tab, sel) = widgetPickerTabSelOf(null);
      expect(tab, 'nav');
      expect(sel.values.every((v) => v == null), isTrue);
    });

    test('无效目标按未绑定处理（脏数据禁渲染成选中）', () {
      final (tab, _) = widgetPickerTabSelOf(
          const WidgetTarget(kind: 'timer_cat', ref: ''));
      expect(tab, 'nav');
    });

    test('打卡目标 → habit 区、记忆＝习惯名', () {
      final (tab, sel) = widgetPickerTabSelOf(
          const WidgetTarget(kind: 'nav', ref: 'habit', sub: '早起喝水'));
      expect(tab, 'habit');
      expect(sel['habit'], '早起喝水');
    });

    test('呵护目标 → care 区、记忆＝<babyId>/<kindId>', () {
      final (tab, sel) = widgetPickerTabSelOf(
          const WidgetTarget(kind: 'nav', ref: 'care', sub: '3/nurse'));
      expect(tab, 'care');
      expect(sel['care'], '3/nurse');
    });

    test('动作/计时/阅读目标各落本区、记忆＝ref', () {
      final nav = widgetPickerTabSelOf(const WidgetTarget(kind: 'nav', ref: 'ledger'));
      expect(nav.$1, 'nav');
      expect(nav.$2['nav'], 'ledger');
      final cat =
          widgetPickerTabSelOf(const WidgetTarget(kind: 'timer_cat', ref: '7'));
      expect(cat.$1, 'timer_cat');
      expect(cat.$2['timer_cat'], '7');
      final book =
          widgetPickerTabSelOf(const WidgetTarget(kind: 'read_book', ref: 'bk1'));
      expect(book.$1, 'read_book');
      expect(book.$2['read_book'], 'bk1');
    });

    test('care 子参数编解码往返＋脏数据返回 null', () {
      expect(widgetCareSubOf(3, 'nurse'), '3/nurse');
      final p = widgetCareSubParse('3/nurse');
      expect(p!.$1, 3);
      expect(p.$2, 'nurse');
      expect(widgetCareSubParse(null), isNull);
      expect(widgetCareSubParse(''), isNull);
      expect(widgetCareSubParse('3'), isNull);
      expect(widgetCareSubParse('x/nurse'), isNull);
      expect(widgetCareSubParse('3/'), isNull);
    });
  });

  group('同源守护：与 NFC 侧两处登记逐字节对齐（禁悄悄漂移）', () {
    test('五段 tab 序与标签 ≡ nfc_sheets 的 kNfcTargetTabs', () {
      final src =
          File('lib/features/nfc/presentation/nfc_sheets.dart').readAsStringSync();
      final m = RegExp(r'const List<\(String, String\)> kNfcTargetTabs = \[(.*?)\];',
              dotAll: true)
          .firstMatch(src);
      expect(m, isNotNull,
          reason: 'NFC 侧 kNfcTargetTabs 常量不见了——共享选择器的 tab 真源被挪走，'
              '请同步本组件的 kWidgetPickerTabs 并 review 本守护');
      final tuples = RegExp(r"\('([^']+)',\s*'([^']+)'\)")
          .allMatches(m!.group(1)!)
          .map((e) => (e.group(1)!, e.group(2)!))
          .toList();
      expect(kWidgetPickerTabs, tuples,
          reason: 'NFC 五段 tab 序/标签已变而 widget 选择器没跟——两边同一份用户可见结构，'
              '必须同步改（改完把本期望值一起更新）');
    });

    test('ref 常量 ≡ nfc_card 的 kNfcRefHabit/kNfcRefCare', () {
      expect(kWidgetRefHabit, kNfcRefHabit);
      expect(kWidgetRefCare, kNfcRefCare);
    });

    test('care 子格式 ≡ nfcCareSubOf/nfcCareSubParse', () {
      expect(widgetCareSubOf(1, 'sleep'), nfcCareSubOf(1, 'sleep'));
      expect(widgetCareSubParse('2/feed'), nfcCareSubParse('2/feed'));
      expect(widgetCareSubParse('脏'), nfcCareSubParse('脏'));
    });
  });

  group('写卡分支隔离：新组件零 NFC feature 依赖', () {
    test('picker 源码不 import features/nfc、不碰卡片仓库', () {
      final src = File(
              'lib/features/widget/presentation/widget_target_picker.dart')
          .readAsStringSync();
      // 路径判据只扫 import 行（文档注释里提 `features/nfc/**` 是说明，不是依赖）。
      final imports = src
          .split('\n')
          .where((l) => l.trimLeft().startsWith('import '))
          .join('\n');
      expect(imports, isNot(contains("features/nfc/")));
      expect(imports, isNot(contains("../nfc/")));
      // 写卡专属分支（探卡/写入状态机/卡号）一概不进组件：连仓库类名都不许出现。
      expect(src, isNot(contains('NfcRepo')));
      expect(src, isNot(contains('nfc_repo')));
      expect(src, isNot(contains('showNfcEditSheet')));
      expect(src, isNot(contains('bindTagKey')));
    });
  });

  group('选择器 UI（同一数据源 · in-memory 库注入）', () {
    late Database db;
    late int catParentId;
    late int catChildId;
    late int babyId;
    late String firstKindId;

    setUp(() async {
      db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      for (final sql in DbSchema.createStatements) {
        await db.execute(sql);
      }
      // ⚠ 全量 DDL 带 categorySeed（既有种子分类）⇒ 自建分类的 id 不一定是 1/2，
      // 一律插完回查真实 id 再用（禁在用例里写死自增 id）。
      await db.insert(DbSchema.tCategories, {'name': 'wg测试一级', 'sort': 99});
      await db.insert(DbSchema.tCategories,
          {'name': 'wg测试子级', 'parent_id': await _lastInsertId(db), 'sort': 0});
      final cats = await nfcCategoryTree(db);
      final parent = cats.firstWhere((g) => g.name == 'wg测试一级');
      catParentId = parent.id;
      catChildId = parent.children.first.id;
      await db.insert(DbSchema.tBooks, {
        'id': 'bk1',
        'title': '活着',
        'author': '余华',
        'created_at': 0,
        'updated_at': 0
      });
      await db.insert(DbSchema.tBooks, {
        'id': 'bk2',
        'title': '三体',
        'author': '刘慈欣',
        'created_at': 0,
        'updated_at': 0
      });
      await db.insert(DbSchema.tHabits, {
        'id': 'h1',
        'name': '早起喝水',
        'icon': 'run',
        'type': 'pos',
        'cycle': 'day',
        'start_date': '2026-01-01',
        'created_at': 0,
        'updated_at': 0,
      });
      await db.insert(DbSchema.tHabits, {
        'id': 'h2',
        'name': '夜读半小时',
        'icon': 'book',
        'type': 'pos',
        'cycle': 'day',
        'start_date': '2026-01-01',
        'created_at': 0,
        'updated_at': 0,
      });
      await db.insert(DbSchema.tCareBabies, {
        'name': '小宝',
        'birth': '2025-01-01',
        'created_at': 0,
        'updated_at': 0,
      });
      babyId = (await nfcBabyOptions(db)).first.id;
      firstKindId = nfcCareKindOptions().first.id;
    });

    tearDown(() async => db.close());

    testWidgets('打卡区：habit chips 与 nfcHabitOptions 同源·确认返回三件套',
        (tester) async {
      final habits = await nfcHabitOptions(db);
      expect(habits.length, 2);
      await _open(tester, db: db, initialTab: 'habit');
      // 同一数据源：chip 文案逐项等于 linkage 出口同名输出（先断言后确认——
      // 确认即弹层关闭，关了就看不到 chip）。
      expect(find.text('早起喝水'), findsOneWidget);
      expect(find.text('夜读半小时'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('wg-target-habit-h2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('wg-confirm')));
      await tester.pumpAndSettle();
      final target = _lastResult;
      expect(target, isNotNull);
      expect(target!.kind, 'nav');
      expect(target.ref, 'habit');
      expect(target.sub, '夜读半小时');
    });

    testWidgets('widget 模式按钮文案「添加到桌面」（nfc 模式「保存」）',
        (tester) async {
      await _open(tester, db: db, initialTab: 'habit');
      expect(find.widgetWithText(FilledButton, '添加到桌面'), findsOneWidget);
      // 直接换树重开（modal sheet 无返回按钮·pageBack 不适用）。
      await _open(tester, db: db, initialTab: 'habit', mode: WidgetPickerMode.nfc);
      expect(find.widgetWithText(FilledButton, '保存'), findsOneWidget);
    });

    testWidgets('计时分类区：两级 chips·点子级返回 timer_cat 三件套', (tester) async {
      await _open(tester, db: db);
      await tester.tap(find.byKey(const ValueKey('wg-tab-timer_cat')));
      await tester.pumpAndSettle();
      // 先选自建一级（默认选中的是种子分类），子级 chips 才轮到它。
      await tester.tap(find.byKey(ValueKey<String>('wg-target-cat-$catParentId')));
      await tester.pumpAndSettle();
      final target = await _pickConfirm(tester, 'wg-target-cat-$catChildId');
      expect(target, isNotNull);
      expect(target!.kind, 'timer_cat');
      expect(target.ref, '$catChildId');
      expect(target.sub, isNull);
    });

    testWidgets('再点同一子级＝退回父级（与 NFC 弹层同口径）', (tester) async {
      await _open(tester, db: db);
      await tester.tap(find.byKey(const ValueKey('wg-tab-timer_cat')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey<String>('wg-target-cat-$catParentId')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey<String>('wg-target-cat-$catChildId')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey<String>('wg-target-cat-$catChildId')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('wg-confirm')));
      await tester.pumpAndSettle();
      // 收回父级 ⇒ ref＝一级 id。
      expect(_lastResult?.kind, 'timer_cat');
      expect(_lastResult?.ref, '$catParentId');
    });

    testWidgets('阅读书目区：展开下拉选书返回 read_book 三件套', (tester) async {
      await _open(tester, db: db);
      await tester.tap(find.byKey(const ValueKey('wg-tab-read_book')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('wg-book-toggle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('wg-book-bk2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('wg-confirm')));
      await tester.pumpAndSettle();
      expect(_lastResult?.kind, 'read_book');
      expect(_lastResult?.ref, 'bk2');
    });

    testWidgets('快捷动作区：动作 chips 返回 nav 三件套（动作表去打卡）', (tester) async {
      final target = await _openAndPick(tester,
          db: db, tapTab: 'nav', tapKey: 'wg-target-nav-ledger');
      expect(target, isNotNull);
      expect(target!.kind, 'nav');
      expect(target.ref, 'ledger');
      // 打卡已独立成段：动作区不出现「打卡」chip（tab 行的标签不算）。
      expect(find.byKey(const ValueKey('wg-target-nav-habit')), findsNothing);
    });

    testWidgets('呵护宝宝区：宝宝×类型两级·确认返回 nav/care 三件套', (tester) async {
      await _open(tester, db: db);
      await tester.tap(find.byKey(const ValueKey('wg-tab-care')));
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(ValueKey<String>('wg-target-care-baby-$babyId')));
      await tester.pumpAndSettle();
      await tester.tap(
          find.byKey(ValueKey<String>('wg-target-care-kind-$firstKindId')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('wg-confirm')));
      await tester.pumpAndSettle();
      expect(_lastResult?.kind, 'nav');
      expect(_lastResult?.ref, 'care');
      expect(_lastResult?.sub, '$babyId/$firstKindId');
    });

    testWidgets('切区不改变已选（各区各自记住·与 NFC 弹层同口径）', (tester) async {
      await _open(tester, db: db, initialTab: 'habit');
      await tester.tap(find.byKey(const ValueKey('wg-target-habit-h1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('wg-tab-timer_cat')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('wg-tab-habit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('wg-confirm')));
      await tester.pumpAndSettle();
      expect(_lastResult?.ref, 'habit');
      expect(_lastResult?.sub, '早起喝水');
    });

    testWidgets('无习惯条目时确认键置灰（禁把空目标绑到桌面）', (tester) async {
      await db.delete(DbSchema.tHabits);
      await _open(tester, db: db, initialTab: 'habit');
      expect(find.text('还没有习惯条目'), findsOneWidget);
      final btn =
          tester.widget<FilledButton>(find.byKey(const ValueKey('wg-confirm')));
      expect(btn.onPressed, isNull);
    });

    testWidgets('进区即有默认选中（原型 nfcTabTo 同口径）', (tester) async {
      await _open(tester, db: db, initialTab: 'habit');
      // 未点任何 chip 直接确认 ⇒ 落到该区第一条（早起喝水）。
      await tester.tap(find.byKey(const ValueKey('wg-confirm')));
      await tester.pumpAndSettle();
      expect(_lastResult?.sub, '早起喝水');
    });
  });
}

/// 最近一次选择器的返回结果（harness 回写·断言用）。
WidgetTarget? _lastResult;

/// 刚插入行的自增 id（sqflite 的 `rawInsert` 即返回 last_insert_rowid）。
Future<int> _lastInsertId(Database db) async {
  final rows = await db.rawQuery('SELECT last_insert_rowid() AS id');
  return rows.first['id'] as int;
}

/// 起一个自动开选择器的宿主（[UniqueKey] 保证每次 _open 都是新 State·
/// initState 只跑一次，不会叠开两层）。
Future<void> _open(
  WidgetTester tester, {
  required Database db,
  String initialTab = 'nav',
  WidgetTarget? initial,
  WidgetPickerMode mode = WidgetPickerMode.widget,
}) async {
  _lastResult = null;
  await tester.pumpWidget(MaterialApp(
    home: _PickerHarness(
      key: UniqueKey(),
      db: db,
      initialTab: initialTab,
      initial: initial,
      mode: mode,
    ),
  ));
  await tester.pumpAndSettle();
}

/// 打开 → 可选切 tab → 点一枚 chip/书 → 确认，返回选中的目标。
Future<WidgetTarget?> _openAndPick(
  WidgetTester tester, {
  required Database db,
  String? tapTab,
  required String tapKey,
  String initialTab = 'nav',
}) async {
  await _open(tester, db: db, initialTab: initialTab);
  if (tapTab != null) {
    await tester.tap(find.byKey(ValueKey<String>('wg-tab-$tapTab')));
    await tester.pumpAndSettle();
  }
  return _pickConfirm(tester, tapKey);
}

/// 点一枚 chip/书 → 确认，返回选中的目标。
Future<WidgetTarget?> _pickConfirm(WidgetTester tester, String tapKey) async {
  await tester.tap(find.byKey(ValueKey<String>(tapKey)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('wg-confirm')));
  await tester.pumpAndSettle();
  return _lastResult;
}

class _PickerHarness extends StatefulWidget {
  const _PickerHarness({
    super.key,
    required this.db,
    required this.initialTab,
    this.initial,
    this.mode = WidgetPickerMode.widget,
  });

  final Database db;
  final String initialTab;
  final WidgetTarget? initial;
  final WidgetPickerMode mode;

  @override
  State<_PickerHarness> createState() => _PickerHarnessState();
}

class _PickerHarnessState extends State<_PickerHarness> {
  @override
  void initState() {
    super.initState();
    // 首帧后自动开选择器（省一次按钮点击·与调用点行为无涉）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showWidgetTargetPicker(
        context,
        mode: widget.mode,
        initial: widget.initial,
        initialTab: widget.initialTab,
        db: widget.db,
      ).then((t) => _lastResult = t);
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox.shrink());
}
