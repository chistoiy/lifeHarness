import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/app_database.dart';
import 'package:lifeharness/core/providers.dart' show sharedPreferencesProvider;
import 'package:lifeharness/core/settings/settings_repository.dart';
import 'package:lifeharness/features/habit/data/habit_repository.dart';
import 'package:lifeharness/features/habit/domain/habit.dart';
import 'package:lifeharness/features/habit/domain/habit_calc.dart';
import 'package:lifeharness/shared/linkage/desktop_widget_mounts.dart'
    show desktopWidgetKickProvider;
import 'package:lifeharness/shared/linkage/widget_checkin_mounts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 小组件批A · **交互闭环层**守护（打卡-单习惯 2×2 第五刀）。
///
/// 规格＝`docs/handoff/小组件模块-批A按实例绑定与打卡试点.md` §2 交互闭环层＋
/// `docs/handoff/评估结论-20261017-…评估.md` §4.1/§4.2。
///
/// 这一刀的全貌＝「点击 → 原生乐观回显 → 无头引擎跑 Dart → 同源仓库出口 →
/// 推习惯三键收敛；失败回滚＋入待排空队列」。断在任何一环，症状都是桌面
/// **静默不对**（不崩、不报错），所以逐环钉死：
///
/// ① isolate 出口同源（入口点/通道/方法名两侧逐字一致；闭环出口**禁碰
///    sqlite**——打卡不是单列写，禁原生复刻；Dart 写库走 NFC 同款
///    `habitCheckinWrite`；后台入口不初始化 UI 依赖·B8）；
/// ② 回显三态（乐观回显借已打卡分支只画自己一枚；收敛只推习惯三键禁整包
///    下发；失败回滚＋入队、超时只入队不回滚）；
/// ③ 待排空队列行为（真库 ffi：按名打卡/二次 already/归档不可写/死名清除/
///    失败保留）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const kt = 'android/app/src/main/kotlin/com/lifeharness/lifeharness';
  const mainSrc = 'lib/main.dart';
  const mountsSrc = 'lib/shared/linkage/widget_checkin_mounts.dart';
  const habitMountsSrc = 'lib/shared/linkage/habit_mounts.dart';
  const bridgeSrc = 'lib/core/platform/desktop_widget.dart';

  /// 去掉块注释与行注释后再扫（否则源码自己的说明文字会自指红）。
  String stripComments(String src) => src
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
      .replaceAll(RegExp(r'//.*'), '');

  group('① isolate 出口同源性（禁两套）', () {
    test('入口点/通道/方法名两侧逐字一致', () {
      final main = File(mainSrc).readAsStringSync();
      final recv = File('$kt/HabitCheckReceiver.kt').readAsStringSync();
      // Dart 侧：根库顶层函数＋pragma（release 树摇后会删无引用函数）。
      expect(main, contains('@pragma(\'vm:entry-point\')'));
      expect(main, contains('void widgetBackgroundMain()'));
      // 原生侧：入口点函数名与通道/方法名。
      expect(recv, contains('private const val ENTRYPOINT = "widgetBackgroundMain"'));
      expect(recv, contains('private const val CHANNEL = "lh/widget_bg"'));
      expect(recv, contains('private const val CHECKIN = "habitCheckin"'));
      // Dart 侧常量同值（写错＝引擎起不来但静默超时·最劣故障形态）。
      expect(main, contains("const String kWidgetBgChannel = 'lh/widget_bg'"));
      expect(main, contains("const String kWidgetBgCheckin = 'habitCheckin'"));
    });

    test('闭环出口**禁碰 sqlite**（打卡不是单列写·禁原生复刻）', () {
      final recv = File('$kt/HabitCheckReceiver.kt').readAsStringSync();
      final code = stripComments(recv).toUpperCase();
      for (final banned in <String>[
        'SELECT',
        'QUERY',
        'RAWQUERY',
        'EXECSQL',
        'UPDATE ',
        'INSERT ',
        'SQLITEDATABASE',
      ]) {
        expect(code, isNot(contains(banned)),
            reason: '闭环 Receiver 出现 $banned ⇒ 原生在复刻写库（评估件 §4.1 禁）');
      }
      // 它该做的只有：起无头引擎＋等回执＋收摊。
      expect(recv, contains('FlutterEngine(app)'));
      expect(recv, contains('DartExecutor.DartEntrypoint('));
      expect(recv, contains('findAppBundlePath()'));
    });

    test('Dart 写库走 NFC 同款核心 habitCheckinWrite（唯一写出口）', () {
      final mounts = File(mountsSrc).readAsStringSync();
      final habitMounts = File(habitMountsSrc).readAsStringSync();
      // 新出口必须复用抽出的写库核心，而不是另抄一份 upsert。
      expect(mounts, contains('habitCheckinWrite('));
      // 数值型走加量核心（2026-10-18 报障补）；两条核心都定义在 habit_mounts。
      expect(mounts, contains('habitIncrementWrite('));
      // 核心定义在 habit_mounts，且 NFC 出口（habitCheckInById）也走它——
      // 三处入口（App 内/NFC 贴卡/小组件后台）只有一个写实现。
      expect(habitMounts, contains('Future<HabitCheckOutcome> habitCheckinWrite('));
      expect(habitMounts, contains('await habitCheckinWrite(repo, h, now: now)'));
      // 后台出口自己**一处 upsert 都不许有**（它只调核心，不写库）。
      expect(RegExp(r'upsertEntry\(').allMatches(stripComments(mounts)), isEmpty,
          reason: '后台 isolate 出口出现 upsertEntry ⇒ 又在复刻写库（禁两套）');
      // 剥注释后：habit_mounts 只有**两条**核心各自的 upsertEntry——布尔打卡一条、
      // 数值加量一条。第三条就是有人又抄了一份写实现。
      final code = stripComments(habitMounts);
      final upserts = RegExp(r'upsertEntry\(').allMatches(code).length;
      expect(upserts, 2, reason: 'upsertEntry 出现 $upserts 处 ⇒ 有第三份写实现');
      expect(code, contains('checked: true'));
      expect(code, contains('origin: HabitEntry.oManual'));
      // 三条核心必须各司其职：布尔核心不带 value；加量核心只是「当前值＋一档」
      // 的**薄包装**（自己不 upsert）；绝对量核心（批D 一次提交）才写 value。
      final iInc = habitMounts.indexOf('Future<HabitCheckOutcome> habitIncrementWrite(');
      expect(iInc, greaterThan(0), reason: '缺数值加量核心');
      final iVal = habitMounts.indexOf('Future<HabitCheckOutcome> habitValueWrite(');
      expect(iVal, greaterThan(iInc), reason: '缺绝对量写核心（批D 桌面「打卡」一次提交）');
      expect(RegExp(r'value:').allMatches(code).length, 2,
          reason: '「写 value」只许两处：加量核心转发给它 + 绝对量核心 upsert 一处');
      final incBody = stripComments(habitMounts.substring(iInc, iVal));
      expect(RegExp(r'upsertEntry\(').allMatches(incBody), isEmpty,
          reason: '加量核心自己 upsert ⇒ 又出现第二套写实现');
      final iBool = habitMounts.indexOf('Future<HabitCheckOutcome> habitCheckinWrite(');
      final iCall = habitMounts.indexOf('await repo.upsertEntry(', iBool);
      final boolCall =
          habitMounts.substring(iCall, habitMounts.indexOf('\n  );', iCall));
      expect(boolCall, isNot(contains('value:')),
          reason: '布尔打卡的 upsert 不许带 value —— 那是数值型的活');
    });

    test('后台入口不初始化 UI 依赖（B8）', () {
      final main = File(mainSrc).readAsStringSync();
      final body = RegExp(r'void widgetBackgroundMain\(\)[\s\S]*?\n}')
          .firstMatch(main)
          ?.group(0) ??
          '';
      expect(body, isNotEmpty, reason: '缺 widgetBackgroundMain 函数体');
      expect(body, contains('runWidgetHabitCheckin'));
      // 后台 isolate 起 FlutterView/runApp 都会炸（无界面）——只跑入库＋推快照。
      expect(body, isNot(contains('WidgetsFlutterBinding')));
      expect(body, isNot(contains('runApp')));
      expect(body, isNot(contains('ProviderScope')));
    });
  });

  group('② 回显三态（乐观 / 收敛 / 回滚入队）', () {
    test('乐观回显：借已打卡分支、只画自己一枚、查不到不猜', () {
      final habit = File('$kt/HabitCheckWidget.kt').readAsStringSync();
      expect(habit, contains('fun echoChecked('));
      // done=true 走 renderHabit 已打卡分支 ⇒ 观感与真打卡逐像素一致。
      expect(habit, contains('row.copy(done = true)'));
      // 只改自己这一枚（不走广播重绘——回显要的是即时）。
      expect(habit, contains('mgr.updateAppWidget(appWidgetId, views)'));
      // 快照表里查不到 ⇒ 不猜一个状态画上去（源失效走占位）。
      expect(habit, contains('firstOrNull { it.name == habitName } ?: return'));
    });

    test('收敛：只推习惯三键＋重绘两枚（禁整包下发）', () {
      final bridge = File(bridgeSrc).readAsStringSync();
      // ⚠ 源码是 CRLF：行位 `\n}` 会先撞上签名里 `}) async {` 的右花括号，
      //   必须要求右花括号**收尾行**（`\n}\r?\n`）才是函数尾。
      final body = RegExp(r'Future<void> pushWidgetHabitSnapshot\([\s\S]*?\n}\r?\n')
          .firstMatch(bridge)
          ?.group(0) ??
      '';
      expect(body, isNotEmpty, reason: '缺 pushWidgetHabitSnapshot');
      // 签名块（`}` 后跟 `)`）不算函数体：起码得把函数体收进来。
      expect(body, contains('try {'), reason: '只截到签名，没截到函数体');
      for (final key in <String>['habitItems', 'habitDone', 'habitTotal']) {
        expect(body, contains('LhWidgetKeys.$key'), reason: '收敛漏推 $key');
      }
      // 只重绘消费这三键的两枚；整包重绘会闪且没必要。
      expect(body, contains("updateWidget(androidName: LhWidgetNames.habitCheck)"));
      expect(body, contains("updateWidget(androidName: LhWidgetNames.todayOverview)"));
      // 整包路径的四个其余键/三枚**不许**出现在本函数（会把待办/金额推成空值）。
      expect(body, isNot(contains('LhWidgetKeys.todoItems')));
      expect(body, isNot(contains('LhWidgetNames.quickRecord')));
      expect(body, isNot(contains('LhWidgetNames.todoList')));
      expect(body, isNot(contains('LhWidgetNames.ledgerOverview')));
    });

    test('明确失败：回滚显示态＋入队（闭环不丢）', () {
      final recv = File('$kt/HabitCheckReceiver.kt').readAsStringSync();
      final support = File('$kt/LhWidgetSupport.kt').readAsStringSync();
      // 批D：入队带上**本次量**（名字␟量），排空时才不会退化成「加一档」。
      expect(recv, contains('LhWidget.enqueuePendingCheck(app, name, amount)'));
      expect(recv, contains('rollback(app, widgetId)'));
      expect(recv, contains('LhWidget.notifyWidget(app, HabitCheckWidget::class.java'));
      expect(support, contains('fun enqueuePendingCheck('));
      expect(support, contains('PREF_PENDING_CHECKS'));
    });

    test('超时只入队不回滚（写成功但回执慢了的那半自纠）', () {
      final recv = File('$kt/HabitCheckReceiver.kt').readAsStringSync();
      final timeoutBody = RegExp(r'if \(!replied\)[\s\S]*?return')
          .firstMatch(recv)
          ?.group(0) ??
          '';
      expect(timeoutBody, isNotEmpty, reason: '缺超时分支');
      expect(timeoutBody, contains('LhWidget.enqueuePendingCheck(app, name, amount)'));
      expect(timeoutBody, isNot(contains('rollback(')),
          reason: '超时回滚会把「写成功但回执慢了」的那半也画错');
    });
  });

  group('③ 待排空队列行为（真库 ffi）', () {
    late Directory tmp;
    late ProviderContainer container;
    late SharedPreferences prefs;

    String key(int back) => dayKey(DateTime.now().subtract(Duration(days: back)));

    Future<Habit> newHabit(HabitRepository repo,
            {String name = '早起', int backStart = 60}) =>
        repo.saveHabit(Habit(name: name, startDate: key(backStart)));

    setUp(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      SharedPreferences.setMockInitialValues(<String, Object>{});
      tmp = Directory.systemTemp.createTempSync('lh_widget_echo_');
      await AppDatabase.instance.open(pathOverride: '${tmp.path}/app.db');
      prefs = await SharedPreferences.getInstance();
      container = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ]);
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

    test('按名打卡 ⇒ checked；二次调用 already 且不重复写', () async {
      final repo = HabitRepository(AppDatabase.instance.db);
      final h = await newHabit(repo);
      final first = await widgetCheckinByName(h.name);
      expect(first, isNotNull);
      expect(first!.checked, isTrue);
      expect(first.already, isFalse);
      // 库里真的落了今日流水。
      final k = dayKey(DateTime.now());
      expect((await repo.entriesOf(h.id))[k]?.checked, isTrue);
      // 第二次：already（已打卡不重复计、也不撤销）。
      final second = await widgetCheckinByName(h.name);
      expect(second!.checked, isFalse);
      expect(second.already, isTrue);
    });

    test('查无此名/空名 ⇒ null（不猜）', () async {
      final repo = HabitRepository(AppDatabase.instance.db);
      await newHabit(repo, name: '喝水');
      expect(await widgetCheckinByName('不存在的习惯'), isNull);
      expect(await widgetCheckinByName('  '), isNull);
      // 名字对但已归档 ⇒ null（与快照表只含未归档同口径）。
      final h = await newHabit(repo, name: '健身');
      await repo.setArchived(h.id, true);
      expect(await widgetCheckinByName('健身'), isNull);
    });

    test('runWidgetHabitCheckin：办成 true、空名 false', () async {
      final repo = HabitRepository(AppDatabase.instance.db);
      final h = await newHabit(repo, name: '阅读');
      // 收敛推送在测试环境无 home_widget 通道（内部已静默降级）⇒ 仍算成功。
      expect(await runWidgetHabitCheckin(h.name), isTrue);
      expect((await repo.entriesOf(h.id))[dayKey(DateTime.now())]?.checked, isTrue);
      expect(await runWidgetHabitCheckin(''), isFalse);
      expect(await runWidgetHabitCheckin('查无此名'), isFalse);
    });

    test('批D：带量打卡＝绝对量写（覆盖当日量），不带量仍是加一档', () async {
      final repo = HabitRepository(AppDatabase.instance.db);
      final h = await repo.saveHabit(
          Habit(name: '喝水', startDate: key(60), goal: 8, unit: '杯'));
      final k = dayKey(DateTime.now());
      // 桌面步进行调到 3 再提交 ⇒ 库里就是 3（不是「0 + 一档」）。
      await widgetCheckinByName('喝水', amount: 3);
      expect((await repo.entriesOf(h.id))[k]?.value, 3);
      // 再来一次带量 5 ⇒ **设成** 5（一次提交是「设为这个量」，不是累加）。
      await widgetCheckinByName('喝水', amount: 5);
      expect((await repo.entriesOf(h.id))[k]?.value, 5);
      // 不带量（布尔/老意图/老队列条目）⇒ 加一档，老口径不破。
      await widgetCheckinByName('喝水');
      expect((await repo.entriesOf(h.id))[k]?.value, greaterThan(5));
    });

    test('批D：队列里的「名字␟量」按量补写，老条目（只有名字）仍走加一档', () async {
      final repo = HabitRepository(AppDatabase.instance.db);
      final h = await repo.saveHabit(
          Habit(name: '阅读', startDate: key(60), goal: 30, unit: '分钟'));
      final k = dayKey(DateTime.now());
      // 两条：带量的「阅读␟12」＋老格式的「冥想」（无第二段）。
      final h2 = await newHabit(repo, name: '冥想');
      prefs.setString(
        kWidgetPendingChecksKey,
        '阅读${kWidgetCheckFieldSep}12$kWidgetCheckSep冥想',
      );
      var done = false;
      container.read(Provider<void>((ref) {
        Future(() async {
          await drainPendingWidgetChecks(ref);
          done = true;
        });
      }));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(done, isTrue, reason: '排空应跑完');
      expect(prefs.getString(kWidgetPendingChecksKey), '', reason: '队列应清空');
      // 带量的：库里是 12（按量写）；老条目：布尔打卡成功。
      expect((await repo.entriesOf(h.id))[k]?.value, 12);
      expect((await repo.entriesOf(h2.id))[k]?.checked, isTrue);
    });

    test('drain：队列逐名补写并清空＋踢一脚；死名也清除', () async {
      final repo = HabitRepository(AppDatabase.instance.db);
      final h = await newHabit(repo, name: '冥想');
      prefs.setString(kWidgetPendingChecksKey, '冥想$kWidgetCheckSep evergreen-dead');
      final kickBefore = container.read(desktopWidgetKickProvider);

      var done = false;
      container.read(Provider<void>((ref) {
        Future(() async {
          await drainPendingWidgetChecks(ref);
          done = true;
        });
      }));
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(done, isTrue, reason: '排空应跑完');
      // 活名补写成功；死名（查无此习惯）也清除——重试一万次不会活过来。
      expect(prefs.getString(kWidgetPendingChecksKey), '');
      expect((await repo.entriesOf(h.id))[dayKey(DateTime.now())]?.checked, isTrue);
      expect(container.read(desktopWidgetKickProvider), kickBefore + 1);
    });

    test('补写队列：含逗号的习惯名不被切开＋逐名移除', () async {
      // 行为级（禁只扫源码文本）：逗号分隔会把「喝水, 运动」切成两条，
      // 排空时写进两个不存在的习惯——所以用控制字符，且名字原样进出。
      final repo = SettingsRepository(prefs);
      await repo.saveDesktopPendingChecks(['喝水, 运动', '早起', '喝水, 运动']);
      final back = repo.loadDesktopPendingChecks();
      expect(back.length, 2, reason: '去重后应剩两条：$back');
      expect(back, contains('喝水, 运动'));
      expect(back, contains('早起'));
      await repo.removeDesktopPendingCheck('早起');
      expect(repo.loadDesktopPendingChecks(), ['喝水, 运动']);
    });

    test('drain：库没开（极端）⇒ 原样保留队列，不丢闭环意图', () async {
      final repo = HabitRepository(AppDatabase.instance.db);
      final h = await newHabit(repo, name: '跑步');
      prefs.setString(kWidgetPendingChecksKey, '跑步');

      await AppDatabase.instance.close();
      var done = false;
      container.read(Provider<void>((ref) {
        Future(() async {
          await drainPendingWidgetChecks(ref);
          done = true;
        });
      }));
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(done, isTrue);
      // 队列原样在，等下次 App 起来接着排。
      expect(prefs.getString(kWidgetPendingChecksKey), '跑步');
      // 重开库验「真的没写」：注意旧 repo 握着已关的句柄，必须换新 repo。
      await AppDatabase.instance.open(pathOverride: '${tmp.path}/app.db');
      final repo2 = HabitRepository(AppDatabase.instance.db);
      expect((await repo2.entriesOf(h.id))[dayKey(DateTime.now())], isNull);
    });
  });
}
