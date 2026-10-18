import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/core/theme/app_theme.dart';
import 'package:lifeharness/core/theme/theme_tokens.dart';
import 'package:lifeharness/features/ledger/presentation/ledger_add_page.dart';
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
    test('弹窗分支只是换外壳，表单仍走 _body', () {
      expect(
        addPage.contains('if (widget.dialogMode) return _dialogShell(async);'),
        isTrue,
      );
      final shell = bodyOf(addPage, 'Widget _dialogShell(');
      expect(shell.contains('_body(d)'), isTrue,
          reason: '弹窗必须复用整页那棵表单树');
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

    test('四 tab／键盘／分类行全仓各只有一处（同源即唯一）', () {
      // `        _Keypad(`＝_body 里那一处调用（类声明与构造器不带头缩进）。
      expect(RegExp(r'\n        _Keypad\(').allMatches(addPage).length, 1);
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
      expect(shell.contains('IconButton('), isTrue); // ✕ 关闭
      // 整页形态仍带 AppBar（回归：别为了弹窗把整页外壳也改了）。
      expect(addPage.contains('appBar: AppBar('), isTrue);
    });

    test('高度按内容收（shrinkWrap 只在弹窗形态开）', () {
      expect(addPage.contains('shrinkWrap: widget.dialogMode,'), isTrue);
      expect(addPage.contains('MediaQuery.sizeOf(context).height * 0.88'),
          isTrue);
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
      expect(find.byIcon(Icons.close), findsOneWidget);
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
