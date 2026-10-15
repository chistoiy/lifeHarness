import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/platform/desktop_widget.dart';

/// 桌面批2 · 小组件快照桥守护（冻结档 §2.2 F2-1~F2-3 / §4.4 / §5.6 / C5 / C8）。
///
/// 覆盖五类：
/// ① 快照字段白名单（＝批1 钉死的 `todo_count`/`habit_done`/`habit_total`/`amount_cell`
///    ＋有无数值标记；批3 加 `todo_items`/`todo_more`/`month_amount_cell`/`balance_cell`；
///    **呵护类读数一律不进** · C8）；
/// ② 桥调用形态（`home_widget` 通道：逐键 `saveWidgetData` ＋四枚 `updateWidget`）；
/// ③ 跨语言口径（原生 Kotlin 必须用同一批键/类名/偏好文件与键前缀·F2-4 禁两套）；
/// ④ 原生资源在位（四枚 provider 元数据/布局/色档/Manifest 声明）；
/// ⑤ 批3 增量：待办行编码两侧一致、闭环写入路径的 C5 窄例外边界、配置弹窗卡片化。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const nativeRoot =
      'android/app/src/main';
  const kt = 'android/app/src/main/kotlin/com/lifeharness/lifeharness';

  group('快照字段白名单（C8）', () {
    test('字段名与批1 冻结口径逐字一致', () {
      expect(LhWidgetKeys.todoCount, 'todo_count');
      expect(LhWidgetKeys.habitDone, 'habit_done');
      expect(LhWidgetKeys.habitTotal, 'habit_total');
      expect(LhWidgetKeys.amountCell, 'amount_cell');
      expect(LhWidgetKeys.all,
          containsAll(<String>['todo_count', 'habit_done', 'habit_total', 'amount_cell']));
    });

    test('呵护读数不进快照（C8：隐藏敏感时也不写——本批干脆不列入白名单）', () {
      for (final f in LhWidgetKeys.all) {
        expect(f.startsWith('care_'), isFalse, reason: '呵护类读数禁进快照：$f');
      }
    });

    test('toData 只下白名单键，且无快照时不下真值（B6）', () {
      const snap = DesktopWidgetSnapshot(
        todoCount: 3,
        habitDone: 4,
        habitTotal: 6,
        amountCell: '1,286',
      );
      final d = snap.toData();
      expect(d.keys.toSet(), LhWidgetKeys.all.toSet());
      expect(d[LhWidgetKeys.todoCount], '3');
      expect(d[LhWidgetKeys.habitTotal], '6');
      expect(d[LhWidgetKeys.amountCell], '1,286');
      expect(d[LhWidgetKeys.hasSnapshot], 'true');

      const empty = DesktopWidgetSnapshot(
        todoCount: 0,
        habitDone: 0,
        habitTotal: 0,
        amountCell: kWidgetPlaceholder,
        hasSnapshot: false,
      );
      expect(empty.toData()[LhWidgetKeys.todoCount], '',
          reason: '无快照不写真值（0 会被 widget 读成真读数）');
      expect(empty.toData()[LhWidgetKeys.hasSnapshot], 'false');
    });
  });

  group('桥调用形态（home_widget · C5）', () {
    late List<MethodCall> calls;

    setUp(() {
      calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('home_widget'), (c) async {
        calls.add(c);
        return c.method == 'saveWidgetData' ? true : null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('home_widget'), null);
    });

    test('逐键下发快照 + 触发四枚小组件重绘', () async {
      await pushDesktopWidgetSnapshot(const DesktopWidgetSnapshot(
        todoCount: 3,
        habitDone: 4,
        habitTotal: 6,
        amountCell: '••••',
      ));

      final saved = <String, Object?>{};
      final updated = <String>[];
      for (final c in calls) {
        final a = c.arguments as Map;
        if (c.method == 'saveWidgetData') saved[a['id'] as String] = a['data'];
        if (c.method == 'updateWidget') updated.add(a['android'] as String);
      }
      expect(saved.keys.toSet(), LhWidgetKeys.all.toSet());
      expect(saved[LhWidgetKeys.amountCell], '••••', reason: '遮蔽结果原样下发');
      expect(updated, <String>[
        LhWidgetNames.todayOverview,
        LhWidgetNames.quickRecord,
        LhWidgetNames.todoList,
        LhWidgetNames.ledgerOverview,
      ]);
    });

    test('桥不可用（无通道）时静默降级，不抛', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('home_widget'), null);
      await expectLater(
        pushDesktopWidgetSnapshot(const DesktopWidgetSnapshot(
          todoCount: 0,
          habitDone: 0,
          habitTotal: 0,
          amountCell: kWidgetPlaceholder,
        )),
        completes,
      );
    });
  });

  group('跨语言口径（原生必须同源 · C5/C8/F2-4）', () {
    final support = File('$kt/LhWidgetSupport.kt').readAsStringSync();

    test('快照值类型跨语言一致：扁平 String ⇒ 原生禁直读 getBoolean', () {
      // 真机 6145 实锤：`DesktopWidgetSnapshot.toData()` 按 §6.4 扁平字符串口径
      // 走 `saveWidgetData<String>`，`has_snapshot` 落盘是 **String**；
      // 原生若 `p.getBoolean(KEY_HAS_SNAPSHOT, …)` 会抛
      // `ClassCastException: String cannot be cast to Boolean` ⇒ Provider 抛异常
      // ⇒ 两枚小组件全挂、桌面点按毫无反应。此处钉死「禁直读 getBoolean」。
      final data = const DesktopWidgetSnapshot(
        todoCount: 3,
        habitDone: 1,
        habitTotal: 4,
        amountCell: '1,286',
      ).toData();
      for (final e in data.entries) {
        expect(e.value, isA<String>(),
            reason: '${e.key} 走扁平字符串下发（原生侧须按 String 解析）');
      }
      expect(data[LhWidgetKeys.hasSnapshot], 'true');

      expect(support, isNot(contains('getBoolean(KEY_HAS_SNAPSHOT')),
          reason: 'has_snapshot 落盘是 String，直读 getBoolean 必崩（真机 6145 实锤）');
      expect(support, contains('fun flag('),
          reason: '须有类型兼容的布尔读取出口（String/Boolean/Int 都容忍且不抛）');
      expect(support, contains('fun hasSnapshot('));
    });

    test('桌面点击意图必带 CLEAR_TOP：禁让 taskAffinity="" 另起新任务', () {
      // 真机 8146 实锤：点小组件 → 退出后 MIUI 最近任务出现**两张** LifeHarness 卡片。
      // 机理：`taskAffinity=""`（M0 骨架设的）＋ `FLAG_ACTIVITY_NEW_TASK` ⇒ 系统找不到
      // 同 affinity 的已有任务 ⇒ 另起新任务；`singleTop` 只在任务内复用，跨任务无效。
      // 修法＝桌面入口补 CLEAR_TOP（不动 launchMode/taskAffinity：批1 工单依赖 singleTop）。
      //
      // ⚠ 这是**整类 bug**：后续每枚桌面入口（待办闭环、记账 2×2、任何新小组件）都必须
      //   走 `LhWidget.clickIntent`，禁自己拼 Intent 绕过。
      final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      // ⚠ 8147 实锤：只加 CLEAR_TOP **不够**。实测 recents 积出三个 lifeharness 任务
      //（#9287/#9286/#9276），`A=` 全是隐式 `I=` —— MainActivity 的空 taskAffinity 让
      // app 任务不归属任何 affinity，系统找不到可归并的任务 ⇒ 每次从桌面进都新建一个。
      // 产品定案修根因：**去掉 MainActivity 的空 taskAffinity**（回归默认＝包名），
      // 所有入口归并同一任务；launchMode="singleTop" 一字未动，批1 热启动语义不变。
      final mainActivity = RegExp(
        r'android:name="\.MainActivity".*?/>',
        dotAll: true,
      ).firstMatch(manifest)?.group(0) ?? '';
      expect(mainActivity, isNot(contains('android:taskAffinity=""')),
          reason: 'MainActivity 禁再带空 taskAffinity：无 affinity 可归并 ⇒ 每次桌面进都新建任务');
      expect(mainActivity, contains('android:launchMode="singleTop"'),
          reason: 'singleTop 热启动语义须保留（桌面批1 工单依赖）');
      // 配置页是例外：它**要**独立任务（否则跟主任务一起进最近任务），但同样禁空串。
      expect(manifest, contains('android:taskAffinity="com.lifeharness.lifeharness.widgetconfig"'),
          reason: '配置页用带包名前缀的独立 affinity（独立但合法）');
      // 全清单扫**标签**而非全文：注释里会出现该字面量（来由说明），不能算命中。
      for (final tag in RegExp(r'<activity[\s\S]*?>').allMatches(manifest)) {
        expect(tag.group(0), isNot(contains('android:taskAffinity=""')),
            reason: 'activity 标签禁空 taskAffinity：${tag.group(0)}');
      }

      expect(support, contains('fun clickIntent('),
          reason: '桌面点击意图唯一出口，后续小组件须走此处');
      expect(support, contains('FLAG_ACTIVITY_CLEAR_TOP'),
          reason: '缺 CLEAR_TOP ⇒ 桌面入口另起任务 ⇒ 最近任务出现重复卡片');
      // 唯一出口必须仍复用 lhLaunchIntent（禁第二套构造 · C15）。
      expect(support, contains('lhLaunchIntent(context'));
    });

    test('添加小组件走「每张卡直连」：App 侧禁再有自拼选择框（2026-10-15 产品改口）', () {
      // 用户原话：那个弹窗「太丑」（其实是**我们自己**没做样式的 AlertDialog，
      // 不是系统框），且「勾选与否不是添加到桌面的意思…不还是不直观吗」。
      // 改法＝删掉 App 侧中间选择框，设置页每张卡自带「添加到桌面」，点哪枚发哪枚。
      final actRaw = File('$kt/MainActivity.kt').readAsStringSync();
      // ⚠ 剥 Kotlin 注释再判：本文件注释里写着「原先用 AlertDialog」的来由，
      // 不剥就会自指红（本仓同族坑第 N 次）。
      final act = actRaw
          .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
          .replaceAll(RegExp(r'//[^\n]*'), '');
      expect(act, isNot(contains('AlertDialog')),
          reason: 'App 自拼的选择框已退役，禁再引入 AlertDialog');
      expect(act, isNot(contains('showWidgetChooser')),
          reason: '选择框入口应已删除');
      expect(act, isNot(contains('"addWidget"')),
          reason: '旧通道名应已删除');
      // 原生：按 id 直达 provider（四枚都要有分支）。
      expect(act, contains('"pinWidget" ->'));
      for (final id in <String>['overview', 'quick', 'todo', 'ledger']) {
        expect(act, contains('"$id" ->'), reason: 'pinWidgetById 缺分支 $id');
      }

      // Dart 桥：通道名与参数名两侧同源。
      final dart =
          File('lib/core/platform/desktop_shortcuts.dart').readAsStringSync();
      expect(dart, contains("'pinWidget'"));
      expect(dart, contains("'widget': widgetId"));
      expect(dart, isNot(contains('addDesktopWidget')),
          reason: '旧的全局入口应已删除');

      // 设置页：四张卡各带 pinId；右上角全局按钮已退役。
      final page = File(
              'lib/features/settings/presentation/desktop_settings_page.dart')
          .readAsStringSync();
      for (final id in <String>['overview', 'quick', 'todo', 'ledger']) {
        expect(page, contains("pinId: '$id'"), reason: '缺卡片 pinId：$id');
      }
      expect(page, contains("'widget-pin-\$pinId'"),
          reason: '每卡按钮的 key 前缀须与「铺到桌面」的 pin-<id> 区分开（撞键会点错东西）');
    });

    test('四枚元数据：开尺寸调节 + 不写 configure（添加时不许弹配置页）', () {
      // 8147 装机反馈：长按菜单缺「尺寸调节」，与用户参照的成熟小组件不一致。
      // 2026-10-15 产品令：**不写 `android:configure`** —— 它会让「从系统添加小组件」
      // 先弹一次配置页，多一步打扰；而配置页管的开关（四枚总开关 + 隐藏金额）
      // App 设置页里全都有，能力不缺。代价＝长按菜单不再有系统自动生成的「编辑」项
      // （那是 configure 的副产物，和弹窗绑死，只能二选一）。
      for (final f in <String>[
        'lh_widget_overview_info',
        'lh_widget_quick_info',
        'lh_widget_todo_info',
        'lh_widget_ledger_info',
      ]) {
        final raw = File('android/app/src/main/res/xml/$f.xml').readAsStringSync();
        // ⚠ 先剥 XML 注释再判：注释里写着「不写 android:configure」的来由，
        // 不剥就会自指红（本仓同族坑第 N 次，凡「禁某字符串」的守护都要剥注释）。
        final x = raw.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');
        expect(x, isNot(contains('android:configure')),
            reason: '$f 写了 configure 就会在添加时弹配置页（2026-10-15 产品令禁）');
      }
      for (final f in <String>[
        'lh_widget_overview_info',
        'lh_widget_quick_info',
      ]) {
        final x = File('android/app/src/main/res/xml/$f.xml').readAsStringSync();
        expect(x, contains('android:resizeMode="horizontal'),
            reason: '$f 须开横向尺寸调节（禁 none，否则长按菜单没有「尺寸调节」）');
        expect(x, isNot(contains('android:resizeMode="none"')),
            reason: '$f 的 resizeMode 禁回退 none');
      }
      // 4:1 只开横向、锁纵向——纵向拉高会把左右分栏拉成怪形。
      final quick =
          File('android/app/src/main/res/xml/lh_widget_quick_info.xml').readAsStringSync();
      expect(quick, contains('android:resizeMode="horizontal"'),
          reason: '4×1 须是纯 horizontal');
      expect(quick, isNot(contains('android:resizeMode="horizontal|vertical"')),
          reason: '4×1 禁开纵向调节（纵向一动就废）');
      expect(quick, isNot(contains('android:resizeMode="vertical"')),
          reason: '4×1 禁开纵向调节（纵向一动就废）');
      // 2×2 两向皆可。
      final ov =
          File('android/app/src/main/res/xml/lh_widget_overview_info.xml').readAsStringSync();
      expect(ov, contains('horizontal|vertical'), reason: '2×2 两向皆可调节');
    });

    test('快照键与 Dart 逐字一致', () {
      expect(support, contains('"todo_count"'));
      expect(support, contains('"habit_done"'));
      expect(support, contains('"habit_total"'));
      expect(support, contains('"amount_cell"'));
      expect(support, contains('"has_snapshot"'));
    });

    test('小组件类名与 Dart 逐字一致（home_widget 按包名.类名解析）', () {
      for (final n in <String>[
        LhWidgetNames.todayOverview,
        LhWidgetNames.quickRecord,
        LhWidgetNames.todoList,
        LhWidgetNames.ledgerOverview,
      ]) {
        expect(support, contains('"$n"'));
        expect(File('$kt/$n.kt').existsSync(), isTrue, reason: '$n 类文件缺失');
      }
    });

    test('快照新增四个键两侧同源（批3 · 待办行与两个记账读数）', () {
      for (final k in <String>[
        LhWidgetKeys.todoItems,
        LhWidgetKeys.todoMore,
        LhWidgetKeys.monthAmountCell,
        LhWidgetKeys.balanceCell,
      ]) {
        expect(LhWidgetKeys.all, contains(k), reason: '不在白名单里 ⇒ 禁下发：$k');
        expect(support, contains('"$k"'),
            reason: '原生缺常量（值须与 Dart 同名）：$k');
      }
    });

    test('待办行编码两侧逐字一致（分隔符错一位 ⇒ 桌面标题整列错位）', () {
      // Dart 用字符字面量 '\u001e' / '\u001f'，原生用 '\u001e' / '\u001f'。
      expect(kTodoItemSep, '\u001e');
      expect(kTodoFieldSep, '\u001f');
      expect(support, contains(r"'\u001e'"), reason: '原生条目分隔符与 Dart 不一致');
      expect(support, contains(r"'\u001f'"), reason: '原生字段分隔符与 Dart 不一致');
      // 行数上限禁两处各写一个数字（布局只预留三行，多了会被裁掉却看不出来）。
      expect(kWidgetTodoRows, 3);
      expect(support, contains('const val TODO_ROWS = 3'));
    });

    test('待办编码：字段序 id/done/title，控制字符被剔除（禁破坏分隔符）', () {
      final out = encodeWidgetTodoItems(const <WidgetTodoItem>[
        WidgetTodoItem(id: 7, done: false, title: '买\u001e牛奶'),
        WidgetTodoItem(id: 9, done: true, title: '  写周报  '),
      ]);
      final rows = out.split(kTodoItemSep);
      expect(rows.length, 2);
      expect(rows.first.split(kTodoFieldSep), <String>['7', '0', '买 牛奶']);
      // 标题两端空白被 trim（桌面行不需要），done 位是 '1'。
      expect(rows[1].split(kTodoFieldSep), <String>['9', '1', '写周报']);
      // maxRows 裁剪，且溢出条数另计。
      final capped = encodeWidgetTodoItems(List<WidgetTodoItem>.generate(
        5,
        (i) => WidgetTodoItem(id: i, done: false, title: 't$i'),
      ));
      expect(capped.split(kTodoItemSep).length, kWidgetTodoRows);
    });

    test('待办闭环窄例外：C5 只禁「读」，写入路径禁出现 SELECT', () {
      final recv = File('$kt/TodoActionReceiver.kt').readAsStringSync();
      expect(recv, contains('TodoActionReceiver'));
      // 勾圈必须是广播（不开 App 就闭环），且禁导出（否则任意 app 能改我们的库）。
      expect(support, contains('fun toggleIntent'));
      expect(support, contains('TodoActionReceiver::class.java'));
      final manifest = File('$nativeRoot/AndroidManifest.xml').readAsStringSync();
      final tag = RegExp(r'<receiver[^>]*\.TodoActionReceiver[^>]*>', dotAll: true)
          .firstMatch(manifest)
          ?.group(0) ??
          '';
      expect(tag, contains('android:exported="false"'),
          reason: '闭环 receiver 禁导出：$tag');
      // 只写不读：出现查询即越C5。⚠ 先剥注释再判——否则本文件自己的说明文字会自指红。
      final code = recv
          .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
          .replaceAll(RegExp(r'//.*'), '')
          .toUpperCase();
      expect(code, isNot(contains('SELECT')));
      expect(code, isNot(contains('QUERY')));
      expect(code, isNot(contains('RAWQUERY')));
      expect(code, contains('UPDATE TODOS'));
      // 必须有失败兜底（队列入队），否则桌面上「点了没反应」且无从追查。
      expect(recv, contains('enqueuePending'));
      expect(recv, contains('goAsync()'));
      expect(recv, contains(r'WHERE id = ? AND done = 0'),
          reason: '闭环必须是幂等单条写，且不得误改已完成项');
    });

    test('补写队列键两侧同源（App 侧排空 + 原生侧入队）', () {
      final repo = File('lib/core/settings/settings_repository.dart').readAsStringSync();
      for (final key in <String>[
        'desktop.widget_todo_list',
        'desktop.widget_ledger',
        'desktop.widget_pending_toggles',
      ]) {
        expect(support, contains(key), reason: '原生缺键：$key');
        expect(repo, contains("'$key'"), reason: 'Dart 缺键：$key');
      }
      // 库文件名两侧逐字一致（补写要开同一个库文件）。
      expect(File('$kt/TodoActionReceiver.kt').readAsStringSync(),
          contains('const val DB_NAME = "lifeharness.db"'));
      expect(File('lib/core/database/schema.dart').readAsStringSync(),
          contains("fileName = 'lifeharness.db'"));
    });

    test('记账 2×2 三行读数：文案与实现同序，且结余保号', () {
      final strs = File('$nativeRoot/res/values/strings.xml').readAsStringSync();
      expect(strs, contains('本月支出'));
      expect(strs, contains('本月结余'));
      // 三行读数 id 必须在布局里齐备（漏一个 ⇒ 那行永远占位）。
      final layout = File('$nativeRoot/res/layout/lh_widget_ledger.xml').readAsStringSync();
      for (final id in <String>['lh_wg_today', 'lh_wg_month', 'lh_wg_balance']) {
        expect(layout, contains('@+id/$id'), reason: '布局缺读数位：$id');
      }
      // 负结余显示为 -¥1,286（不是 ¥-1,286）。
      expect(support, contains('startsWith("-")'));
      expect(widgetBalanceCell(-1286, hideAmount: false), '-1,286');
      expect(widgetBalanceCell(1286, hideAmount: false), '1,286');
      expect(widgetBalanceCell(-1286, hideAmount: true), '••••');
    });

    test('隐私遮蔽覆盖全部三个金额位（不止今日支出）', () {
      final snap = DesktopWidgetSnapshot(
        todoCount: 1,
        habitDone: 1,
        habitTotal: 2,
        amountCell: '1,286',
        monthAmountCell: '••••',
        balanceCell: '••••',
      );
      final data = snap.toData();
      // 遮蔽位不带货币符号（原生遇 •••• 不加 ¥）。
      expect(data[LhWidgetKeys.monthAmountCell], '••••');
      expect(data[LhWidgetKeys.balanceCell], '••••');
      expect(data.keys.toSet(), LhWidgetKeys.all.toSet(),
          reason: '下发键集必须与白名单完全一致（多一个键＝多一处泄露面）');
    });

    test('配置弹窗已重做为卡片体系（禁退回系统默认表单）', () {
      final layout = File('$nativeRoot/res/layout/lh_widget_config.xml').readAsStringSync();
      expect(layout, contains('@drawable/lh_cfg_card'), reason: '缺卡片底');
      // 勾选框必须自绘（系统 Material 方块＝用户说的「太丑」）。
      expect(layout, contains('@drawable/lh_cfg_check'));
      expect(layout, isNot(contains('@android:drawable/checkbox')));
      // 四行总开关全列：禁再按 provider 隐藏（用户会以为本枚不受这设置管）。
      for (final id in <String>[
        'lh_cfg_summary',
        'lh_cfg_quick',
        'lh_cfg_todo_list',
        'lh_cfg_ledger',
        'lh_cfg_hide_amount',
      ]) {
        expect(layout, contains('@+id/$id'), reason: '配置页缺开关行：$id');
      }
      final cfg = File('$kt/WidgetConfigActivity.kt').readAsStringSync();
      expect(cfg, isNot(contains('View.GONE')),
          reason: '禁再按 provider 藏行（语义骗人）');
      // 关掉也要真从桌面消失，否则是死开关的第三种形态。
      expect(cfg, contains('LhWidget.applyEnabledFlags'));
      // 深浅两档配置页色值齐备。
      for (final f in <String>[
        'res/values/colors.xml',
        'res/values-night/colors.xml',
      ]) {
        final c = File('$nativeRoot/$f').readAsStringSync();
        expect(c, contains('lh_cfg_bg'), reason: '$f 缺弹窗底色');
        expect(c, contains('lh_cfg_card_bg'), reason: '$f 缺弹窗卡片色');
      }
    });

    test('配置 Activity 写 Flutter 同一份偏好（F2-4 禁两套）', () {
      // 文件＝Flutter legacy SharedPreferences 文件名；键另加 Dart 的 `flutter.` 前缀。
      expect(support, contains('"FlutterSharedPreferences"'));
      expect(support, contains(r'"flutter."'));
      final cfg = File('$kt/WidgetConfigActivity.kt').readAsStringSync();
      for (final key in <String>[
        'desktop.widget_summary',
        'desktop.widget_quick',
        'desktop.hide_amount',
      ]) {
        expect(support, contains(key), reason: '原生缺键：$key');
        expect(File('lib/core/settings/settings_repository.dart').readAsStringSync(),
            contains("'$key'"),
            reason: 'Dart SettingsRepository 与原生键不同源：$key');
      }
      expect(cfg, contains('LhWidget.PREF_'), reason: '配置页必须复用同一批键常量');
      expect(cfg, contains('RESULT_OK'));
    });

    test('点击意图走 C15 唯一出口（禁第二套构造）', () {
      expect(support, contains('lhLaunchIntent('));
      expect(support, isNot(contains('Intent(Intent.ACTION_VIEW')));
      // 两枚小组件点击目标必须落在白名单段内（禁散落 scheme 字面量）。
      expect(support, contains('"today"'));
      expect(support, contains('"ledger/add"'));
      final main =
          File('$kt/MainActivity.kt').readAsStringSync();
      expect(main, contains('internal fun lhLaunchIntent('));
    });
  });

  group('原生资源在位（§5.6 / §6.2）', () {
    test('两枚 provider 的布局与元数据齐备', () {
      for (final f in <String>[
        'res/layout/lh_widget_overview.xml',
        'res/layout/lh_widget_quick.xml',
        'res/xml/lh_widget_overview_info.xml',
        'res/xml/lh_widget_quick_info.xml',
        'res/values/colors.xml',
        'res/values-night/colors.xml',
        'res/drawable/lh_wg_card.xml',
        'res/drawable/lh_wg_progress.xml',
      ]) {
        expect(File('$nativeRoot/$f').existsSync(), isTrue, reason: '$f 缺文件');
      }
    });

    test('浅/深两档色档同键（C6/B9：只跟系统深浅色）', () {
      final light = File('$nativeRoot/res/values/colors.xml').readAsStringSync();
      final dark =
          File('$nativeRoot/res/values-night/colors.xml').readAsStringSync();
      for (final k in <String>[
        'lh_wg_bg',
        'lh_wg_fg',
        'lh_wg_sub',
        'lh_wg_acc',
        'lh_wg_btn_fg',
      ]) {
        expect(light, contains('name="$k"'), reason: '浅色档缺 $k');
        expect(dark, contains('name="$k"'), reason: '深色档缺 $k');
      }
      // 深色档强调色偏亮 ⇒ 按钮字必须换深色（白字 2.98:1 不达 AA · §5.6）。
      expect(dark, contains('#1E293B'), reason: '深色档按钮字应为深色');
    });

    test('小组件布局只用 RemoteViews 白名单控件（禁裸 View · 2026-10-15 8150 装机实锤）', () {
      // 实伤：`lh_widget_todo.xml` 用裸 `<View>` 当吸余高的 spacer，Launcher
      // inflate 默认视图时抛 `InflateException: Class not allowed to be inflated
      // android.view.View` ⇒ 桌面上显示「载入窗口小部件时出现问题」。
      // RemoteViews 只允许固定白名单里的类；`android.view.View` 不在其中。
      // 空 LinearLayout（0dp + weight=1）是安全的 spacer 写法。
      const allowed = <String>{
        'LinearLayout',
        'FrameLayout',
        'RelativeLayout',
        'GridLayout',
        'TextView',
        'ImageView',
        'Button',
        'ImageButton',
        'ProgressBar',
        'Chronometer',
        'AnalogClock',
        'ViewFlipper',
        'ListView',
        'GridView',
        'StackView',
        'AdapterViewFlipper',
      };
      for (final f in <String>[
        'lh_widget_overview.xml',
        'lh_widget_quick.xml',
        'lh_widget_todo.xml',
        'lh_widget_ledger.xml',
      ]) {
        final raw = File('$nativeRoot/res/layout/$f').readAsStringSync();
        // ⚠ 先剥 XML 注释再扫：本仓习惯在布局注释里写「为什么不能用 <View>」，
        // 不剥的话注释本身就会把这条守护判红（与守护五/Manifest 同族坑）。
        final src = raw.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');
        // 抓所有 `<Tag`（含 `<Tag ` 与 `<Tag/>`）。
        final tags = RegExp(r'<([A-Za-z][A-Za-z0-9_.]*)')
            .allMatches(src)
            .map((m) => m.group(1)!)
            .where((t) => t != 'xml' && t != '!--')
            .toSet();
        for (final t in tags) {
          expect(
            allowed.contains(t),
            isTrue,
            reason: '$f 用了 RemoteViews 不支持的控件 <$t>（白名单外，桌面会显示「载入窗口小部件时出现问题」）',
          );
        }
        // 裸 View 的显式断言（给出更直白的失败信息）。
        expect(src, isNot(contains('<View')), reason: '$f 禁裸 <View>（改用空 LinearLayout）');
      }
    });

    test('四枚元数据必须给真预览图（MIUI 只认 previewImage · 禁回落应用图标）', () {
      // 实伤（2026-10-15 装机）：元数据只写 `previewLayout` 时，MIUI 桌面**完全忽略它**，
      // 「添加小部件」列表里四枚全回落成同一个应用图标，用户分不清哪枚是哪枚。
      // 正解＝`previewLayout`（Android 12+ 标准口径）＋ `previewImage`（MIUI 这类只看图的
      // 桌面）双给，且 previewImage 必须指向**真预览图**，不能是 `@mipmap/ic_launcher`。
      const pairs = <String, String>{
        'lh_widget_overview_info.xml': 'overview',
        'lh_widget_quick_info.xml': 'quick',
        'lh_widget_todo_info.xml': 'todo',
        'lh_widget_ledger_info.xml': 'ledger',
      };
      for (final e in pairs.entries) {
        final raw = File('$nativeRoot/res/xml/${e.key}').readAsStringSync();
        final src = raw.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');
        expect(src, contains('android:previewLayout'),
            reason: '${e.key} 必须给 previewLayout（标准桌面走这条）');
        expect(
          src,
          contains('android:previewImage="@drawable/lh_widget_${e.value}_preview"'),
          reason: '${e.key} 必须给 previewImage 且指向真预览图（MIUI 只认这个）',
        );
        expect(src, isNot(contains('@mipmap/ic_launcher')),
            reason: '${e.key} 禁把应用图标当预览（MIUI 下四枚会长得一模一样）');
        // 浅/深两档图都得在（C6：跟随系统深浅色，不跟随 App 主题）。
        for (final d in <String>['drawable-nodpi', 'drawable-night-nodpi']) {
          final png = File('$nativeRoot/res/$d/lh_widget_${e.value}_preview.png');
          expect(png.existsSync(), isTrue, reason: '缺 ${e.value} 的 $d 预览图');
          expect(png.lengthSync(), greaterThan(1000),
              reason: '${e.value} 的 $d 预览图是空文件（重跑 tools/gen_widget_previews.py）');
        }
      }
    });

    test('Manifest 声明两枚 receiver 与配置 Activity', () {
      final m = File('$nativeRoot/AndroidManifest.xml').readAsStringSync();
      expect(m, contains('.TodayOverviewWidget'));
      expect(m, contains('.QuickRecordWidget'));
      expect(m, contains('android.appwidget.provider'));
      expect(m, contains('.WidgetConfigActivity'));
      expect(m, contains('android.appwidget.action.APPWIDGET_CONFIGURE'));
      // 既有通路一字不改（EPUB/MD 打开方式 + 悬浮窗 action）。
      expect(m, contains('android.intent.action.SEND'));
      expect(m, contains('android:scheme="lh"'));
    });
  });

  group('总开关真生效（死开关修复 · 2026-10-15）', () {
    final support = File('$kt/LhWidgetSupport.kt').readAsStringSync();

    test('两枚 Provider 各自读自己的总开关（禁只写偏好不读）', () {
      expect(File('$kt/TodayOverviewWidget.kt').readAsStringSync(),
          contains('isOverviewEnabled(context)'));
      expect(File('$kt/QuickRecordWidget.kt').readAsStringSync(),
          contains('isQuickEnabled(context)'));
      expect(support, contains('fun isOverviewEnabled'));
      expect(support, contains('fun isQuickEnabled'));
    });

    test('关掉的枚走删除路径，且删除必须反射兜底不裸调', () {
      expect(support, contains('fun applyEnabledFlags'));
      expect(support, contains('deleteIds(mgr, ids)'));
      // AppWidgetManager 没有公开的 deleteAppWidgetId（那是 AppWidgetHost 的），
      // 直调编译必红 ⇒ 必须经反射包装，且失败静默（回落空态）。
      expect(support, isNot(contains('mgr.deleteAppWidgetId(')));
      expect(support, contains('android.appwidget.AppWidgetService'));
      expect(support, contains('catch (_: LinkageError)'));
    });

    test('Dart 侧拨开关后必须通知原生执行 applyWidgetFlags', () {
      expect(File('lib/core/platform/desktop_shortcuts.dart').readAsStringSync(),
          contains("invokeMethod<bool>('applyWidgetFlags')"));
      expect(File('$kt/MainActivity.kt').readAsStringSync(),
          contains('applyWidgetFlags'));
    });
  });
}
