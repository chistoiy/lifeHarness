import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/platform/desktop_actions.dart' show LaunchRoute;
import 'package:lifeharness/core/settings/settings_repository.dart';
import 'package:lifeharness/features/nfc/data/nfc_trigger.dart';
import 'package:lifeharness/features/nfc/domain/nfc_card.dart';
import 'package:lifeharness/shared/linkage/nfc_mounts.dart' show NfcTargetState;
import 'package:shared_preferences/shared_preferences.dart';

/// NFC 卡片批2b · 贴卡触发链（冻结档 §4.4 · F2-4~F2-9 · 工单 §1 受影响测试清单）。
///
/// 判定顺序本身是硬性要求（总闸 → 去抖 → id 校验 → 查表 → 失效 → 确认 → 执行），
/// 故本文件按顺序分组逐条钉：顺序若被改写，会有具体某组先红。
///
/// 用 `testWidgets` 而非 `test`：触发链要一个**真实且 mounted** 的 `BuildContext`
/// （`app.dart` 传的是根 Navigator context）。桩一个假 ctx 会掩盖 `mounted` 判定的
/// 真实行为，与 B31「host 不可用时降级」的验收不符。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 造一个「已绑定目标」的卡。
  NfcCard cardOf({
    String id = 'aBcD1234efGh',
    String name = '书房灯',
    String targetKind = 'nav',
    String? targetRef = 'journal',
    String? targetSub,
    int? writtenAt,
  }) =>
      NfcCard(
        id: id,
        name: name,
        targetKind: targetKind,
        targetRef: targetRef,
        targetSub: targetSub,
        writtenAt: writtenAt,
        createdAt: 0,
      );

  late List<String> goes;
  late List<String> pushes;
  late List<String> toasts;
  int now = 1000000;

  Future<SettingsRepository> prefsOf({
    bool enabled = true,
    bool confirm = false,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      SettingsRepository.kNfcEnabledKey: enabled,
      SettingsRepository.kNfcConfirmKey: confirm,
      SettingsRepository.kNfcPromptUnboundKey: true,
    });
    return SettingsRepository(await SharedPreferences.getInstance());
  }

  /// 组装 deps（默认全绿：总闸开、卡存在、目标有效、确认关）。
  ///
  /// [ctx] 由各 `testWidgets` 体内 `pumpWidget` 后取自根 widget。
  Future<NfcTriggerDeps> depsOf(
    BuildContext ctx, {
    required SettingsRepository prefs,
    required NfcCard? Function(String) byId,
    bool alive = true,
    String? targetName = '写日记',
    bool confirmResult = true,
    bool toggleResult = true,
    bool togglePresent = false,
    void Function(String kind, String? ref, String? sub, String name)? onToggle,
    bool hostUsable = true,
  }) async {
    return NfcTriggerDeps(
      prefs: prefs,
      hostContext: hostUsable ? ctx : null,
      byId: (id) async => byId(id),
      targetStateOf: (c) async =>
          NfcTargetState(name: targetName, alive: alive),
      goRoute: (p) => goes.add(p),
      pushRoute: (p) => pushes.add(p),
      confirm: (c, title, msg) async {
        toasts.add('CONFIRM:$title|$msg');
        return confirmResult;
      },
      toast: (c, msg) => toasts.add(msg),
      now: () => now,
      toggle: togglePresent
          ? (kind, ref, sub, name) async {
              onToggle?.call(kind, ref, sub, name);
              return toggleResult;
            }
          : null,
    );
  }

  setUp(() {
    debugResetNfcDebounce();
    goes = <String>[];
    pushes = <String>[];
    toasts = <String>[];
    now = 1000000;
  });

  /// 每个用例内先 pump 一个最小树以取得真实 BuildContext。
  Future<BuildContext> host(WidgetTester tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      _CtxGrabber(onCtx: (c) => ctx = c),
    );
    return ctx;
  }

  group('形态与总闸（C42：总闸先于一切）', () {
    testWidgets('非 nfc: 形态 → silent（不查库不执行）', (tester) async {
      final ctx = await host(tester);
      final deps = await depsOf(ctx, prefs: await prefsOf(), byId: (_) => null);
      final r =
          await nfcHandleLaunch(const LaunchRoute(action: 'journal'), deps);
      expect(r, NfcTriggerOutcome.silent);
      expect(toasts, isEmpty);
      expect(goes, isEmpty);
      expect(pushes, isEmpty);
    });

    testWidgets('总闸关 ⇒ 完全静默（不 toast 不弹层不跳屏不计次·C42）',
        (tester) async {
      final ctx = await host(tester);
      final deps = await depsOf(ctx,
          prefs: await prefsOf(enabled: false), byId: (_) => cardOf());
      final r = await nfcHandleLaunch(
          const LaunchRoute(action: 'nfc:aBcD1234efGh'), deps);
      expect(r, NfcTriggerOutcome.silent);
      expect(toasts, isEmpty, reason: '总闸关不报错不提示');
      expect(goes, isEmpty);
      expect(pushes, isEmpty);
    });

    testWidgets('总闸关时非法 id 亦静默（总闸判定在最前）', (tester) async {
      final ctx = await host(tester);
      final deps = await depsOf(ctx,
          prefs: await prefsOf(enabled: false), byId: (_) => null);
      final r = await nfcHandleLaunch(
          const LaunchRoute(action: 'nfc:bad!!'), deps);
      expect(r, NfcTriggerOutcome.silent);
    });
  });

  group('id 格式校验（B35：非法静默丢弃、不回显）', () {
    testWidgets('太短 → silent，且不进查表（byId 不被调）', (tester) async {
      final ctx = await host(tester);
      var called = false;
      final deps = await depsOf(ctx,
          prefs: await prefsOf(),
          byId: (_) {
            called = true;
            return null;
          });
      final r =
          await nfcHandleLaunch(const LaunchRoute(action: 'nfc:abc'), deps);
      expect(r, NfcTriggerOutcome.silent);
      expect(called, isFalse);
      expect(toasts.join(), isNot(contains('abc')), reason: '不回显 id');
    });

    testWidgets('含非 base62 字符（12 位）→ silent', (tester) async {
      final ctx = await host(tester);
      final deps = await depsOf(ctx, prefs: await prefsOf(), byId: (_) => null);
      final r = await nfcHandleLaunch(
          const LaunchRoute(action: 'nfc:abc_def12345'), deps);
      expect(r, NfcTriggerOutcome.silent);
    });

    testWidgets('12 位合法 base62 → 正常进入查表', (tester) async {
      final ctx = await host(tester);
      var called = false;
      final deps = await depsOf(ctx,
          prefs: await prefsOf(),
          byId: (_) {
            called = true;
            return cardOf();
          });
      await nfcHandleLaunch(
          const LaunchRoute(action: 'nfc:aBcD1234efGh'), deps);
      expect(called, isTrue);
    });
  });

  group('去抖 3 秒窗口与反馈分级（F2-6/B16/B43）', () {
    testWidgets('窗口内第二次 → debounced 且出一次 toast，且不执行', (tester) async {
      final ctx = await host(tester);
      final deps = await depsOf(ctx, prefs: await prefsOf(), byId: (_) => cardOf());
      const route = LaunchRoute(action: 'nfc:aBcD1234efGh');

      final r1 = await nfcHandleLaunch(route, deps);
      expect(r1, NfcTriggerOutcome.executed);
      expect(toasts, isEmpty, reason: 'nav.* 首次不给 toast（C22）');

      now += 1000; // 窗口内
      final r2 = await nfcHandleLaunch(route, deps);
      expect(r2, NfcTriggerOutcome.debounced);
      expect(toasts, contains(kNfcDebounceToast));
      expect(pushes.length, 1, reason: '第二次不执行（journal 全屏栈 → push）');
    });

    testWidgets('窗口内第三次起静默（B43：不再出 toast）', (tester) async {
      final ctx = await host(tester);
      final deps = await depsOf(ctx, prefs: await prefsOf(), byId: (_) => cardOf());
      const route = LaunchRoute(action: 'nfc:aBcD1234efGh');
      await nfcHandleLaunch(route, deps);
      now += 500;
      await nfcHandleLaunch(route, deps); // 第二次：出 toast
      final afterSecond = toasts.length;
      now += 500;
      final r3 = await nfcHandleLaunch(route, deps); // 第三次
      expect(r3, NfcTriggerOutcome.debounced);
      expect(toasts.length, afterSecond, reason: '第三次起静默');
    });

    testWidgets('窗口过期后（≥3s）再次贴卡 → 正常执行', (tester) async {
      final ctx = await host(tester);
      final deps = await depsOf(ctx, prefs: await prefsOf(), byId: (_) => cardOf());
      const route = LaunchRoute(action: 'nfc:aBcD1234efGh');
      await nfcHandleLaunch(route, deps);
      now += 3000; // 出窗口
      final r2 = await nfcHandleLaunch(route, deps);
      expect(r2, NfcTriggerOutcome.executed);
      expect(pushes.length, 2, reason: '两次都执行了（journal 全屏栈 → push）');
    });

    testWidgets('不同 cardId 各自独立窗口', (tester) async {
      final ctx = await host(tester);
      final deps = await depsOf(ctx,
          prefs: await prefsOf(), byId: (id) => cardOf(id: id));
      await nfcHandleLaunch(
          const LaunchRoute(action: 'nfc:aaaaaaaaaaaa'), deps);
      now += 100;
      final r = await nfcHandleLaunch(
          const LaunchRoute(action: 'nfc:bbbbbbbbbbbb'), deps);
      expect(r, NfcTriggerOutcome.executed, reason: '换卡不共享窗口');
    });
  });

  group('查表与未命中降级（B8/B35：禁落 unknownRouteFallback）', () {
    testWidgets('卡已删 → toast ＋ 回 /（绑定引导，不执行）', (tester) async {
      final ctx = await host(tester);
      final deps = await depsOf(ctx, prefs: await prefsOf(), byId: (_) => null);
      final r = await nfcHandleLaunch(
          const LaunchRoute(action: 'nfc:aBcD1234efGh'), deps);
      expect(r, NfcTriggerOutcome.unbound);
      expect(toasts, contains(kNfcUnboundToast));
      expect(goes, contains('/'));
      expect(goes, isNot(contains(kUnknownRouteFallback)));
      expect(pushes, isEmpty);
    });

    testWidgets('卡存在但未绑目标 → 落 /nfc 绑定引导（push·B8）', (tester) async {
      final ctx = await host(tester);
      final deps = await depsOf(ctx,
          prefs: await prefsOf(), byId: (_) => cardOf(targetRef: null));
      final r = await nfcHandleLaunch(
          const LaunchRoute(action: 'nfc:aBcD1234efGh'), deps);
      expect(r, NfcTriggerOutcome.unbound);
      expect(pushes, contains('/nfc'), reason: '/nfc 是全屏栈路由，须 push');
      expect(goes, isNot(contains('/nfc')));
    });
  });

  group('目标失效（C24/F2-8）', () {
    testWidgets('目标已删 → toast ＋ 回 /，不执行', (tester) async {
      final ctx = await host(tester);
      final deps = await depsOf(ctx,
          prefs: await prefsOf(), byId: (_) => cardOf(), alive: false);
      final r = await nfcHandleLaunch(
          const LaunchRoute(action: 'nfc:aBcD1234efGh'), deps);
      expect(r, NfcTriggerOutcome.targetGone);
      expect(toasts, contains(kNfcTargetGoneToast));
      expect(goes, contains('/'));
      expect(goes.length, 1, reason: '回 / 是唯一跳转');
    });
  });

  group('确认开关（F2-9：标题＝卡名·正文＝目标名）', () {
    testWidgets('确认关 → 直接执行（默认，无确认弹层）', (tester) async {
      final ctx = await host(tester);
      final deps = await depsOf(ctx, prefs: await prefsOf(), byId: (_) => cardOf());
      final r = await nfcHandleLaunch(
          const LaunchRoute(action: 'nfc:aBcD1234efGh'), deps);
      expect(r, NfcTriggerOutcome.executed);
      expect(toasts.where((t) => t.startsWith('CONFIRM:')), isEmpty);
    });

    testWidgets('确认开 → 出确认（标题＝卡名），确认后执行', (tester) async {
      final ctx = await host(tester);
      final deps = await depsOf(ctx,
          prefs: await prefsOf(confirm: true),
          byId: (_) => cardOf(name: '书房灯'),
          targetName: '写日记');
      final r = await nfcHandleLaunch(
          const LaunchRoute(action: 'nfc:aBcD1234efGh'), deps);
      expect(r, NfcTriggerOutcome.executed);
      final c = toasts.firstWhere((t) => t.startsWith('CONFIRM:'));
      expect(c, 'CONFIRM:书房灯|要去「写日记」吗');
      expect(pushes.length, 1, reason: 'journal 全屏栈 → push');
    });

    testWidgets('确认开但取消 → cancelled，不执行', (tester) async {
      final ctx = await host(tester);
      final deps = await depsOf(ctx,
          prefs: await prefsOf(confirm: true),
          byId: (_) => cardOf(),
          confirmResult: false);
      final r = await nfcHandleLaunch(
          const LaunchRoute(action: 'nfc:aBcD1234efGh'), deps);
      expect(r, NfcTriggerOutcome.cancelled);
      expect(goes, isEmpty);
      expect(pushes, isEmpty);
    });

    testWidgets('host 不可用（首帧前·B31）→ 确认开关开着也直接执行，不排队补弹',
        (tester) async {
      final ctx = await host(tester);
      final deps = await depsOf(ctx,
          prefs: await prefsOf(confirm: true),
          byId: (_) => cardOf(),
          hostUsable: false);
      final r = await nfcHandleLaunch(
          const LaunchRoute(action: 'nfc:aBcD1234efGh'), deps);
      expect(r, NfcTriggerOutcome.executed, reason: 'B31：只落库/执行，放弃弹层');
      expect(toasts, isEmpty);
    });
  });

  group('执行两制（§4.4）', () {
    testWidgets('nav.* 壳内目标 → go（不给 toast·C22）', (tester) async {
      final ctx = await host(tester);
      final deps = await depsOf(ctx,
          prefs: await prefsOf(), byId: (_) => cardOf(targetRef: 'today'));
      final r = await nfcHandleLaunch(
          const LaunchRoute(action: 'nfc:aBcD1234efGh'), deps);
      expect(r, NfcTriggerOutcome.executed);
      expect(goes, contains('/'));
      expect(toasts, isEmpty);
    });

    testWidgets('nav.* 全屏栈目标 → push（V1.67 黑屏伤）', (tester) async {
      final ctx = await host(tester);
      final deps = await depsOf(ctx,
          prefs: await prefsOf(), byId: (_) => cardOf(targetRef: 'journal'));
      await nfcHandleLaunch(
          const LaunchRoute(action: 'nfc:aBcD1234efGh'), deps);
      expect(pushes, contains('/journal/edit'));
      expect(goes, isEmpty);
    });

    testWidgets('有状态卡（timer_cat）在 toggle 未接入时静默（不误当 nav go）',
        (tester) async {
      final ctx = await host(tester);
      final deps = await depsOf(ctx,
          prefs: await prefsOf(),
          byId: (_) => cardOf(targetKind: 'timer_cat', targetRef: '3'),
          togglePresent: false);
      final r = await nfcHandleLaunch(
          const LaunchRoute(action: 'nfc:aBcD1234efGh'), deps);
      expect(r, NfcTriggerOutcome.silent);
      expect(goes, isEmpty);
      expect(pushes, isEmpty);
    });

    testWidgets('有状态卡（read_book）toggle 接入后执行（不跳屏）', (tester) async {
      final ctx = await host(tester);
      String? gotKind;
      String? gotRef;
      final deps = await depsOf(ctx,
          prefs: await prefsOf(),
          byId: (_) => cardOf(targetKind: 'read_book', targetRef: 'bk1'),
          togglePresent: true,
          onToggle: (k, r, s, n) {
            gotKind = k;
            gotRef = r;
          });
      final r = await nfcHandleLaunch(
          const LaunchRoute(action: 'nfc:aBcD1234efGh'), deps);
      expect(r, NfcTriggerOutcome.executed);
      expect(gotKind, 'read_book');
      expect(gotRef, 'bk1');
      expect(goes, isEmpty, reason: '有状态卡不跳屏');
      expect(pushes, isEmpty);
    });
  });

  group('辅助纯函数', () {
    test('nfcCardIdOfRoute 取 nfc: 后的 id', () {
      expect(nfcCardIdOfRoute(const LaunchRoute(action: 'nfc:abcd1234efgh')),
          'abcd1234efgh');
      expect(nfcCardIdOfRoute(const LaunchRoute(action: 'nfc:')), isNull);
      expect(nfcCardIdOfRoute(const LaunchRoute(action: 'journal')), isNull);
    });

    test('nfcNavIsFullScreen 与动作表同源', () {
      expect(nfcNavIsFullScreen('journal'), isTrue);
      expect(nfcNavIsFullScreen('today'), isFalse);
      expect(nfcNavIsFullScreen('不存在的动作'), isFalse);
    });
  });
}

/// `unknownRouteFallback` 字面量（B4 定义值·测试自带一份防被守护常量牵连）。
const String kUnknownRouteFallback = 'unknownRouteFallback';

/// 抓一个真实且 mounted 的 [BuildContext]（触发链要宿主 context）。
class _CtxGrabber extends StatefulWidget {
  const _CtxGrabber({required this.onCtx});

  final void Function(BuildContext) onCtx;

  @override
  State<_CtxGrabber> createState() => _CtxGrabberState();
}

class _CtxGrabberState extends State<_CtxGrabber> {
  @override
  void initState() {
    super.initState();
    widget.onCtx(context);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
