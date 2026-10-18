import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/core/theme/app_theme.dart';
import 'package:lifeharness/core/theme/theme_tokens.dart';
import 'package:lifeharness/features/ledger/domain/ledger_models.dart';
import 'package:lifeharness/features/ledger/presentation/ledger_add_page.dart';
import 'package:lifeharness/features/ledger/presentation/ledger_providers.dart'
    show LedgerData, ledgerDataProvider;
import 'package:lifeharness/shared/linkage/desktop_widget_mounts.dart'
    show ledgerWidgetCells;
import 'package:shared_preferences/shared_preferences.dart';

/// 小组件批A · **记一笔弹窗**（工单 §7.1 · 拍板件 §五 首选路②）守护。
///
/// 这一刀的全部风险都在「两套 UI 会漂」与「独立引擎推快照推空别域」两件事上，
/// 所以逐条钉死：
///
/// ① 表单同源——弹窗**只有容器**，四 tab／分类行／子类 chips／键盘仍走 `_body`；
/// ② 容器差异只允许两处——无 AppBar、按内容收高（`shrinkWrap`）；
/// ③ 关闭出口——弹窗形态收 Activity（`SystemNavigator.pop`），不 `context.go`；
/// ④ 入口点——`@pragma('vm:entry-point')` 保命（release 树摇后全仓无静态引用）；
/// ⑤ 只推记账三键——整包下发会把待办卡／打卡卡推成空（批A 同一坑）；
/// ⑥ 三键口径唯一——`ledgerWidgetCells` 一处算，整包与弹窗共用。
void main() {
  String read(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

  final addPage = read('lib/features/ledger/presentation/ledger_add_page.dart');
  final mainDart = read('lib/main.dart');
  final quickMounts = read('lib/shared/linkage/widget_quick_add_mounts.dart');
  final widgetMounts = read('lib/shared/linkage/desktop_widget_mounts.dart');
  final platform = read('lib/core/platform/desktop_widget.dart');

  /// 抽函数体。[close]＝闭合行（类内方法两格缩进、顶层零格、object 内成员四格）。
  ///
  /// ⚠ 不能只找 `\n}`：类内方法的闭合是 `\n  }`，而 `\n}` 会一路吃到文件里
  /// 下一个顶层闭合，把后面整段代码都算进「函数体」（本测试首跑即栽在这）。
  String bodyOf(String src, String signature,
      {String close = '\n  }\n'}) {
    final s = src.replaceAll('\r\n', '\n');
    final i = s.indexOf(signature);
    expect(i, greaterThanOrEqualTo(0), reason: '找不到 $signature');
    final rest = s.substring(i);
    final j = rest.indexOf(close);
    expect(j, greaterThanOrEqualTo(0), reason: '$signature 函数体未闭合');
    return rest.substring(0, j + close.length);
  }

  group('① 表单同源（弹窗不另造一套）', () {
    test('弹窗分支只是换外壳，字段段仍走 _formSections', () {
      expect(
        addPage.contains('if (widget.dialogMode) return _dialogShell(async);'),
        isTrue,
      );
      final shell = bodyOf(addPage, 'Widget _dialogShell(');
      expect(shell.contains('_dialogBody(d)'), isTrue,
          reason: '弹窗必须复用整页那棵表单树（只是密度与 chrome 不同）');
      // 弹窗外壳里不许出现分类/键盘的自建实现（出现即意味着复制了一份）。
      for (final banned in [
        '        _Keypad(',
        '_AcctCard(',
        'LedgerTxn.kExpense',
        '_expenseIncomeBody(',
        'transferBody(',
        'debtBody(',
      ]) {
        expect(shell.contains(banned), isFalse, reason: '弹窗外壳内出现 $banned');
      }
    });

    test('弹窗正文＝可滚字段区＋钉底键盘，字段段与整页同一个函数', () {
      final body = bodyOf(addPage, 'Widget _dialogBody(');
      expect(body.contains('_formSections(d, compact: true)'), isTrue);
      expect(body.contains('_Keypad('), isTrue, reason: '键盘钉底不进滚动区');
      expect(body.contains('SingleChildScrollView('), isTrue);
      // 整页与弹窗都从同一个 `_formSections` 出字段（禁第二套）。
      final page = bodyOf(addPage, 'Widget _body(');
      expect(page.contains('..._formSections(d),'), isTrue);
    });

    test('四 tab／键盘／分类行全仓各只有一处（同源即唯一）', () {
      // `_Keypad(` 两处调用＝整页与弹窗各一次（实现只有 `class _Keypad` 一处）。
      expect(RegExp(r'\n        _Keypad\(').allMatches(addPage).length, 2);
      expect(RegExp(r'class _Keypad extends StatelessWidget').allMatches(addPage).length, 1);
      expect(
        RegExp(RegExp.escape("(LedgerTxn.kExpense, '支出')"))
            .allMatches(addPage)
            .length,
        1,
      );
      expect(
        RegExp(r'\n  List<Widget> _expenseIncomeBody\(').allMatches(addPage).length,
        1,
      );
    });
  });

  group('② 容器差异只允许两处', () {
    test('弹窗形态无 AppBar；整页形态保留', () {
      final shell = bodyOf(addPage, 'Widget _dialogShell(');
      expect(shell.contains('AppBar('), isFalse);
      expect(shell.contains("'记一笔'"), isTrue);
      expect(shell.contains("'✕'"), isTrue); // ✕ 关闭（原型 26dp 圆形）
      // 整页形态仍带 AppBar（回归：别为了弹窗把整页外壳也改了）。
      expect(addPage.contains('appBar: AppBar('), isTrue);
    });

    test('高度按内容收（卡片上限 322×72% 屏高，禁撑成全屏页）', () {
      // 2026-10-18 真机二次报障「记一笔是拉长版的」：上一版上限 88% 屏高＋整页
      // 九枚 meta chips／付款账户／图片附件全在 ⇒ 视觉等同全屏页。
      final shell = bodyOf(addPage, 'Widget _dialogShell(');
      expect(shell.contains('maxWidth: 322'), isTrue, reason: '原型卡片宽 ≤322');
      expect(shell.contains('* 0.72'), isTrue, reason: '安全闸 72% 屏高');
      expect(shell.contains('* 0.88'), isFalse, reason: '88% 会顶到状态栏');
      expect(shell.contains('mainAxisSize: MainAxisSize.min'), isTrue,
          reason: '按内容收高');
    });

    test('页面专属 chrome 不进弹窗（否则必然撑回整页）', () {
      final sections = bodyOf(addPage, 'List<Widget> _formSections(');
      // 三处都挂 compact 闸：付款账户行、meta chips 区、图片附件（备注分支）。
      expect(sections.contains('if (!compact && !isTr && !isDbt)'), isTrue);
      expect(sections.contains('if (!compact && !isDbt) ...['), isTrue);
      expect(sections.contains('if (compact)'), isTrue, reason: '备注两形态');
    });
  });

  group('③ 关闭出口', () {
    test('弹窗形态收 Activity，不走路由', () {
      final leave = bodyOf(addPage, 'void _leave()');
      expect(leave.contains('SystemNavigator.pop()'), isTrue);
      expect(leave.contains("context.go('/ledger')"), isTrue); // 整页分支保留
      // 保存路径的两处离开都改走 _leave（否则弹窗里 context.go 必崩）。
      expect(RegExp(r'if \(mounted\) _leave\(\);').allMatches(addPage).length, 2);
      expect(addPage.contains("if (mounted) context.go('/ledger');"), isFalse);
    });
  });

  group('④ 入口点', () {
    test('widgetQuickAddMain 带 pragma 并接到装配函数', () {
      expect(
        mainDart
            .contains("@pragma('vm:entry-point')\nvoid widgetQuickAddMain()"),
        isTrue,
        reason: '缺 pragma ⇒ release 树摇后点小组件没反应',
      );
      final entry = bodyOf(mainDart, 'void widgetQuickAddMain()', close: '\n}\n');
      expect(entry.contains('runWidgetQuickAddApp()'), isTrue);
    });

    test('弹窗根跟随系统深浅、主题与整页同源', () {
      expect(quickMounts.contains('themeMode: ThemeMode.system'), isTrue);
      expect(quickMounts.contains('ref.watch(lightThemeProvider)'), isTrue);
      expect(quickMounts.contains('ref.watch(darkThemeProvider)'), isTrue);
      expect(quickMounts.contains('dialogMode: true'), isTrue);
    });

    test('初始化只三件事（prefs / 开库 / 主题令牌）', () {
      final boot =
          bodyOf(quickMounts, 'Future<void> runWidgetQuickAddApp()', close: '\n}\n');
      expect(boot.contains('SharedPreferences.getInstance()'), isTrue);
      expect(boot.contains('AppDatabase.instance.open()'), isTrue);
      expect(boot.contains('ThemeRepository().loadAll()'), isTrue);
      // 禁跑 main() 的其余初始化（提醒重排/迁移/备份）。
      for (final banned in [
        'NotificationService',
        'BackupService',
        'MediaHashMigrator',
      ]) {
        expect(boot.contains(banned), isFalse, reason: '弹窗引擎跑了 $banned');
      }
    });

    test('首行 ensureInitialized（真机报障「点记一笔没反应」根因）', () {
      // 自定义入口点没有框架替它建 binding；第一句 prefs 就走平台通道 ⇒
      // binding 未初始化时抛异常，runApp 根本执行不到，宿主是透明对话框主题
      // ⇒ 用户看到的是「窗口起来了但一个字都没画」＝完全没反应。
      final boot =
          bodyOf(quickMounts, 'Future<void> runWidgetQuickAddApp()', close: '\n}\n');
      final iBind = boot.indexOf('WidgetsFlutterBinding.ensureInitialized()');
      final iPrefs = boot.indexOf('SharedPreferences.getInstance()');
      expect(iBind, greaterThan(-1), reason: '缺 ensureInitialized ⇒ 弹窗永远白屏');
      expect(iBind, lessThan(iPrefs),
          reason: 'binding 必须建在任何插件调用之前');
    });
  });

  group('⑤ 只推记账三键（禁整包）', () {
    test('弹窗引擎不调整包下发', () {
      expect(quickMounts.contains('pushDesktopWidgetSnapshot('), isFalse,
          reason: '整包会把待办/习惯推成空值');
      expect(quickMounts.contains('pushWidgetLedgerSnapshot('), isTrue);
    });

    test('三键下发只重绘消费它们的两枚', () {
      final fn = bodyOf(platform, 'Future<void> pushWidgetLedgerSnapshot(',
          close: '\n}\n');
      for (final key in ['amountCell', 'monthAmountCell', 'balanceCell']) {
        expect(fn.contains('LhWidgetKeys.$key'), isTrue, reason: '缺 $key');
      }
      expect(fn.contains('LhWidgetNames.ledgerOverview'), isTrue);
      expect(fn.contains('LhWidgetNames.quickRecord'), isTrue);
      for (final other in [
        'LhWidgetNames.todoList',
        'LhWidgetNames.habitCheck',
        'LhWidgetNames.todayOverview',
      ]) {
        expect(fn.contains(other), isFalse, reason: '不该重绘 $other');
      }
    });
  });

  group('⑥ 三键口径唯一', () {
    test('空域/隐藏金额两档（口径入口）', () {
      final now = DateTime(2026, 10, 18, 9);
      final empty = ledgerWidgetCells(null, now, hideAmount: false);
      expect(empty.amount, '--');
      expect(empty.month, '--');
      expect(empty.balance, '--');
      final masked = ledgerWidgetCells(null, now, hideAmount: true);
      expect(masked.amount, '••••');
      expect(masked.month, '••••');
      expect(masked.balance, '••••');
    });

    test('整包与弹窗共用一处计算（mStat 只在口径函数里）', () {
      final snap = bodyOf(widgetMounts, 'DesktopWidgetSnapshot? buildSnapshot(',
          close: '\n}\n');
      expect(snap.contains('mStat('), isFalse,
          reason: '整包自己再算一遍 ⇒ 两套算法必然漂移');
      expect(snap.contains('ledgerWidgetCells('), isTrue);
      final cells = bodyOf(
        widgetMounts,
        '({String amount, String month, String balance}) ledgerWidgetCells(',
        close: '\n}\n',
      );
      expect(cells.contains('mStat('), isTrue);
      expect(quickMounts.contains('ledgerWidgetCells('), isTrue);
    });
  });

  group('⑦ 渲染形态（无 AppBar／有标题）', () {
    testWidgets('dialogMode 渲染出「记一笔」头部且无 AppBar', (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          child: MaterialApp(
            theme: AppTheme.build(ThemeTokens.defaults, isDark: false),
            home: const Scaffold(body: LedgerAddPage(dialogMode: true)),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(AppBar), findsNothing);
      expect(find.text('记一笔'), findsOneWidget);
      // 关闭键＝原型 26dp 圆形 ✕（不是 Material 的 close 图标）。
      expect(find.text('✕'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsNothing);
    });

    testWidgets('弹窗＝紧凑卡片：四 tab／分类行／键盘在，页面 chrome 全不在', (tester) async {
      // 2026-10-18 真机二次报障「记一笔是拉长版的页面，跟高保真不一样」：
      // 上一版把整页表单塞进 88% 屏高的壳，付款账户/九枚 meta chips/图片附件全在，
      // 高度顶满 ⇒ 观感就是全屏页。这条用例钉住「弹窗该长什么样」。
      tester.view.physicalSize = const Size(1200, 2670); // 400×890dp @3x
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            ledgerDataProvider.overrideWith((ref) async => _fakeLedger()),
          ],
          child: MaterialApp(
            theme: AppTheme.build(ThemeTokens.defaults, isDark: false),
            home: const Scaffold(
              body: Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: LedgerAddPage(dialogMode: true),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // ① 四类型 tab ＋ 键盘（保存跨两行）都在。
      for (final t in ['支出', '收入', '转账', '借贷', '保存', '再记', '备注…']) {
        expect(find.text(t), findsWidgets, reason: '弹窗缺「$t」');
      }
      // ② 分类行（大类名）＋ 子类 chips 轨在。
      expect(find.text('餐饮'), findsWidgets); // 分类行 ＋ chips 首枚
      expect(find.text('早餐'), findsWidgets);
      // ③ 页面专属 chrome 一枚都不许出现（出现即撑回整页）。
      for (final gone in ['付款账户', '无退款', '非报销', '计入收支和预算', '无标签', '无商家']) {
        expect(find.text(gone), findsNothing, reason: '弹窗里不该有「$gone」');
      }
      expect(find.byIcon(Icons.image_outlined), findsNothing);

      // ④ 尺寸：卡片 ≤322 宽、高度按内容收（远低于 72% 安全闸）。
      final card = tester.getSize(find.byKey(const ValueKey('ledger-add-card')));
      expect(card.width, lessThanOrEqualTo(322.0));
      expect(card.height, lessThan(890 * 0.72),
          reason: '撑到上限就是全屏页观感（本次报障）');
      // 内容量决定高度：支出形态约 380–460dp，给一档宽区间防漂。
      expect(card.height, lessThan(560.0));
    });

    testWidgets('弹窗按内容收高：换到借贷形态高度不同（不是固定整页）',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 2670);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            ledgerDataProvider.overrideWith((ref) async => _fakeLedger()),
          ],
          child: MaterialApp(
            theme: AppTheme.build(ThemeTokens.defaults, isDark: false),
            home: const Scaffold(
              body: Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: LedgerAddPage(dialogMode: true),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final h0 = tester
          .getSize(find.byKey(const ValueKey('ledger-add-card')))
          .height;
      await tester.tap(find.text('借贷'));
      await tester.pumpAndSettle();
      // 借贷形态有 dseg＋对方输入＋金额行（比支出形态少 chips 轨）⇒ 高度应变化，
      // 但仍在安全闸内；关键断言是「不是固定撑满」。
      final h1 = tester
          .getSize(find.byKey(const ValueKey('ledger-add-card')))
          .height;
      expect(h1, lessThan(890 * 0.72));
      expect(find.text('借出 · 别人欠我'), findsOneWidget);
      expect(find.text('对方（如：老王）'), findsOneWidget);
      expect((h1 - h0).abs(), greaterThan(0.0),
          reason: '两种形态同高 ⇒ 说明高度是写死的整页，不是按内容收');
    });
  });

  group('⑧ 原生侧（弹窗 Activity ＋ 4×1 三区）', () {
    const kt = 'android/app/src/main/kotlin/com/lifeharness/lifeharness';
    final quick = read('$kt/QuickRecordWidget.kt');
    final activity = read('$kt/QuickAddActivity.kt');
    final support = read('$kt/LhWidgetSupport.kt');
    final quickLayout = read('android/app/src/main/res/layout/lh_widget_quick.xml');
    final manifest = read('android/app/src/main/AndroidManifest.xml');
    final styles = read('android/app/src/main/res/values/styles.xml');

    test('4×1 三区：两个读数位 + 两条分隔线（ImageView 不用裸 View）', () {
      for (final id in ['lh_wg_amount', 'lh_wg_balance']) {
        expect(quickLayout.contains('@+id/$id'), isTrue, reason: '缺 $id');
      }
      expect(quickLayout.contains('@string/lh_widget_label_today_cost'), isTrue);
      expect(
        quickLayout.contains('@string/lh_widget_label_month_balance'),
        isTrue,
      );
      // RemoteViews 白名单：裸 <View> 会 InflateException（8150 装机实锤）。
      // 只认「行首元素」——布局注释里提到「裸 <View>」不算违规。
      expect(RegExp(r'\n\s*<View\b').hasMatch(quickLayout), isFalse);
      // 分隔线＝ImageView + 色值（两区之间各一条）。
      expect(RegExp(r'@color/lh_wg_div').allMatches(quickLayout).length, 2);
    });

    test('4×1 点击改走弹窗，不再起 App', () {
      expect(quick.contains('LhWidget.quickAddIntent('), isTrue);
      expect(quick.contains('SEG_LEDGER_ADD'), isFalse,
          reason: '仍走 lh://ledger/add ⇒ 又变成「打开 App」');
      expect(quick.contains('R.id.lh_wg_balance'), isTrue);
    });

    test('quickAddIntent 直起 Activity、不派发 scheme', () {
      final fn = bodyOf(support, 'fun quickAddIntent(', close: '\n    }\n');
      expect(fn.contains('QuickAddActivity::class.java'), isTrue);
      expect(fn.contains('lhScheme'), isFalse, reason: '弹窗不该再走 scheme 派发');
      expect(fn.contains('FLAG_IMMUTABLE'), isTrue);
    });

    test('Activity 入口点与 Dart 侧同名（跨语言同源）', () {
      expect(activity.contains('const val ENTRYPOINT = "widgetQuickAddMain"'),
          isTrue);
      expect(
        mainDart.contains('void widgetQuickAddMain()'),
        isTrue,
        reason: '两侧入口点名必须逐字一致',
      );
      expect(activity.contains('getDartEntrypointFunctionName'), isTrue);
    });

    test('Manifest：不进最近任务、不归并主任务、不导出', () {
      final m = RegExp(
        r'<activity\s+android:name="\.QuickAddActivity"[\s\S]*?/>',
      ).firstMatch(manifest);
      expect(m, isNotNull, reason: 'QuickAddActivity 未注册');
      final block = m!.group(0)!;
      for (final attr in [
        'android:excludeFromRecents="true"',
        'android:noHistory="true"',
        'android:exported="false"',
        'android:launchMode="singleTask"',
        'android:windowSoftInputMode="adjustResize"',
      ]) {
        expect(block.contains(attr), isTrue, reason: '缺 $attr');
      }
      // 独立 affinity 且非空（空串撞桌面批3 守卫，且会把主任务拉前台）。
      final aff = RegExp(r'android:taskAffinity="([^"]*)"').firstMatch(block);
      expect(aff, isNotNull);
      expect(aff!.group(1)!.isNotEmpty, isTrue);
    });

    test('主题：全屏非浮动（软键盘才顶得动）＋ 透明底', () {
      expect(styles.contains('name="QuickAddTheme"'), isTrue);
      final st = RegExp(
        r'<style name="QuickAddTheme"[\s\S]*?</style>',
      ).firstMatch(styles)!
          .group(0)!;
      expect(st.contains('android:windowIsFloating">false'), isTrue,
          reason: '浮动窗口的 adjustResize 不生效，软键盘会盖住保存键');
      expect(st.contains('@android:color/transparent'), isTrue);
      expect(st.contains('adjustResize'), isTrue);
    });
  });
}

/// 弹窗渲染用例的最小账本夹具（只喂渲染要读的字段：分类树/账户/偏好开关）。
///
/// 为什么不连真库：`LedgerData` 走 sqflite，在 Windows 测试环境会卡住（本仓
/// 既有约定：一律用注入缝）；这里只要「分类行＋chips 轨＋账户」能画出来。
LedgerData _fakeLedger() => LedgerData(
      books: const [LedgerBook(id: 1, name: '日常')],
      curBook: const LedgerBook(id: 1, name: '日常'),
      accounts: const [
        LedgerAccount(id: 1, type: 'cash', name: '现金'),
        LedgerAccount(id: 2, type: 'debit', name: '储蓄卡'),
      ],
      cats: const [
        LedgerCat(id: 101, kind: 'expense', name: '餐饮', icon: 'food', color: '#fb7185'),
        LedgerCat(id: 102, kind: 'expense', parentId: 101, name: '早餐'),
        LedgerCat(id: 103, kind: 'expense', parentId: 101, name: '午餐'),
        LedgerCat(id: 201, kind: 'income', name: '工资', icon: 'salary', color: '#10b981'),
      ],
      favs: const [],
      txns: const [],
      budget: LedgerBudget(),
      month: '2026-10',
      hideAmounts: false,
      defAcctId: 1,
      afterSave: 'stay',
      confirmDel: false,
      monthStart: 1,
      whoDef: '自己',
      quickCats: const [],
      heroBig: '',
      heroSlots: const [],
      whos: const [],
      tagGroups: const [],
      merchants: const [],
      txnCounts: const {},
      dueRecurN: 0,
    );
