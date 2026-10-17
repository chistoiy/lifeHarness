import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/ai/ai_review.dart' show aiRootNavKey;
import 'core/logging/app_log.dart' show AppLog, LhLogLine;
import 'core/platform/desktop_actions.dart' show LaunchRoute;
import 'core/platform/launch_route.dart'
    show markLaunchRouteReady, moveTaskToBack, takeLaunchRoute;
import 'core/platform/open_intent.dart'
    show classifyOpenIntent, kOpenUnsupportedToast, takeOpenFile;
import 'core/providers.dart';
import 'features/journal/presentation/note_open_with.dart' show noteOpenConsume;
import 'features/nfc/data/nfc_tag_io.dart' show kNfcChannel;
import 'features/nfc/data/nfc_trigger.dart'
    show NfcTriggerOutcome, nfcHandleLaunch, nfcTriggerDepsOf;
import 'features/read/presentation/open_with.dart' show handleOpenWithEpub;
import 'shared/linkage/desktop_mounts.dart';
import 'shared/linkage/desktop_widget_mounts.dart';
import 'shared/linkage/habit_mounts.dart';
import 'shared/linkage/journal_mounts.dart';
import 'shared/linkage/ledger_mounts.dart';
import 'shared/linkage/sys_pill_sync.dart'
    show drainPillEvents, sysPillAppActiveProvider, sysPillMarkStale,
        sysPillSyncProvider;
import 'shared/widgets/ui_kit.dart' show AppToast;

/// 冷启动首帧窗口内根 Navigator 可能还没挂上：等它就绪再取路由（批3c）。
///
/// 8 × 80ms＝最多等 640ms，只发生在「有启动意图、界面还没就绪」的那一次。
const int _kLaunchCtxRetries = 8;
const Duration _kLaunchCtxRetryGap = Duration(milliseconds: 80);

/// 应用根 Widget：主题三件套（light/dark/mode）+ go_router。
/// V1.53.4⑥：兼作系统「打开方式」EPUB 意图的消费点——冷启动首帧后取一次，
/// 热启动（singleTop onNewIntent 入队）在 resumed 时再取；弹层挂根 Navigator
/// （aiRootNavKey 同源，分支页要盖住底栏，参照 R14 弹层三成因护栏）。
/// V1.64 批1：通道泛化为多类型——分派在组合根（R1：read/journal 互不 import），
/// epub→读库导入、note→笔记「系统打开」归集、''→统一人话拒收提示。
class LifeHarnessApp extends ConsumerStatefulWidget {
  const LifeHarnessApp({super.key});

  @override
  ConsumerState<LifeHarnessApp> createState() => _LifeHarnessAppState();
}

class _LifeHarnessAppState extends ConsumerState<LifeHarnessApp>
    with WidgetsBindingObserver {
  bool _firstFrameDone = false;
  bool _consuming = false;
  bool _launchConsuming = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 批3c：接住透明中转界面直投的贴卡事件（进程活着时的零闪现路径）。
    _listenNfcRelay();
    // 批B：系统悬浮窗同步器保活（listenManual＝订阅但不重建 UI；
    // 内部挂秒级 ticker，逐 tick 推内容/收视图/消费 ■结束 事件）。
    ref.listenManual(sysPillSyncProvider, (_, _) {});
    // 冷启动：首帧后路由与根 Navigator 均已就绪，再消费入队意图。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _firstFrameDone = true;
      // 桌面批1（B15）：`lh://` 冷启动意图**先入队不丢弃**——门禁必须到首帧
      // 完成后才开，否则这一取就把队列读空、意图永久丢失（判不合格）。
      markLaunchRouteReady();
      _consumeLaunchRoute();
      _consumeOpen();
      // 批B：冷启动经 ■结束 意图入队的场景，首帧即探一次悬浮窗事件。
      drainPillEvents(ref);
    });
  }

  @override
  void dispose() {
    kNfcChannel.setMethodCallHandler(null);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _firstFrameDone) {
      _consumeLaunchRoute(); // 桌面批1：热启动（singleTop onNewIntent）同路径消费
      _consumeOpen();
      // 批B：回前台时补消费一次悬浮窗事件（冷启动经 ■结束 意图入队的场景，
      // 同步器尚未起 tick 也要兜住）。
      drainPillEvents(ref);
      // 批B 热修 6130：回前台强制重断言——原生服务可能已被 ROM（HyperOS 冻结/
      // 杀后台 FGS）停掉而备忘还在，清 sig 后下个 tick 必推（前台起服务合法）。
      sysPillMarkStale();
    }
    // 批B：app 前台时系统悬浮窗隐藏（免与 app 内胶囊重复），退后台恢复。
    // hidden 同 paused 处理（HyperOS 上事件序列可能只有 hidden·无 paused，
    // 事件标志滞留在 true＝app 外永不显示·6132 热修）。
    if (state == AppLifecycleState.resumed ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      ref.read(sysPillAppActiveProvider.notifier).state =
          state == AppLifecycleState.resumed;
      // 不等下一 tick：事件当场促重算一次（退后台瞬间推可见态＝前台起服务
      // 合法；也绕开「退后台后 tick 可能被系统挂起」的窗口）。
      ref.invalidate(sysPillSyncProvider);
    }
  }

  /// 根 Navigator 的 context（未挂载／已销毁时 null）。
  ///
  /// 抽成方法是因为它现在有两个调用点：重试等待期间反复探、取到路由后再复查。
  BuildContext? _rootNavContext() {
    final ctx = aiRootNavKey.value?.currentState?.context;
    return (ctx != null && ctx.mounted) ? ctx : null;
  }

  /// 桌面批1 · `lh://` 启动路由消费（L3 单一消费端 · B15/B16）。
  ///
  /// **单次消费**：原生侧读到即清空，二次调用拿不到（防重放）。
  /// **C18**：写入类带参只预填，提交仍须 App 内确认——本方法只负责 `go` 到目标路由，
  /// 预填由目标页自己读偏好，不在此处拼提交。
  /// **NFC 透传**：`nfc:<cardId>` 不解释业务，原样投给 NFC 模块（其 cardId 校验归它）。
  Future<void> _consumeLaunchRoute() async {
    if (_launchConsuming) return;
    _launchConsuming = true;
    try {
      // ⚠ **先等根 Navigator 就绪、再 take**（2026-10-17 真机排障发现）：
      // `takeLaunchRoute` 是**单次消费**（原生读即清空），先 take 后查会把路由
      // 白白吃掉——冷启动首帧窗口内 `navCtx` 可能仍为 null，那一刻 take 出来的
      // 意图既没执行也没法重试，表现为「贴卡把 App 拉起来了但什么都没发生」，
      // 且违反 B31「冷启动贴有状态卡，计时必须落库」。顺序反过来＝没就绪就
      // 不取，意图原样留在原生队列里，下一轮（首帧后／回前台）自然取到。
      //
      // 批3c（2026-10-17 真机报障·报障②）：只「没就绪就不取」还不够——冷启动
      // 时首帧回调往往只跑一次，那一刻 `currentState` 偶尔仍为 null，于是意图
      // **永久滞留**在原生队列里（真机现象：贴卡闪一下 App 页面、日志无任何 NFC
      // 行）。改为在首帧窗口内**短暂重试等它就绪**（≤640ms），仍不就绪才放弃
      // （此时队列未取，下一次 resumed 还有机会）。
      var navCtx = _rootNavContext();
      for (var i = 0; navCtx == null && i < _kLaunchCtxRetries; i++) {
        await Future<void>.delayed(_kLaunchCtxRetryGap);
        if (!mounted) return;
        navCtx = _rootNavContext();
      }
      if (navCtx == null) return;
      final route = await takeLaunchRoute();
      if (route == null) return;
      // 排障留痕（只记「收到了」与前后台态，**不记 cardId**·C11 红线）。
      // 真机再报「贴卡没反应」时，日志里有没有这一行就能一刀切开两类原因：
      // 没有 ⇒ 系统根本没把 NFC 意图派给本 App（丢 AAR / 只弹通知）；
      // 有 ⇒ 派到了，问题在执行链。
      if (route.isNfc) {
        AppLog.add(
            'NFC 贴卡：已收到系统派发（fromBackground=${route.fromBackground}）',
            src: LhLogLine.srcSystem);
      }
      // await 之后再复查一次：这中间可能已退出页面/销毁 Navigator。
      if (!navCtx.mounted) return;
      if (route.isNfc) {
        await _runNfcRoute(route);
        return;
      }
      // 目标路由查不到 → 走 unknownRouteFallback（B4），不抛 GoException。
      final router = GoRouter.of(navCtx);
      if (route.fullScreen) {
        // 全屏栈路由（/journal/edit、/ledger/add）：**必须 push**。
        // `go` 会把栈底那条壳页一并换掉 ⇒ 页内 `Navigator.pop()` 无处可去 ⇒
        // 返回黑屏且退不出去（V1.67 真机报障：快捷方式进日记编辑页后返回黑屏）。
        unawaited(router.push(route.route));
      } else {
        // 壳内路由（等价点底栏 tab）：`go` 让栈顶唯一、底栏高亮正确。
        router.go(route.route);
      }
    } catch (e) {
      AppLog.reportError('启动路由消费失败：$e', src: LhLogLine.srcSystem);
    } finally {
      _launchConsuming = false;
    }
  }

  /// 接收**透明中转界面**（原生 `NfcRelayActivity`）推来的贴卡事件（批3c）。
  ///
  /// App 进程活着时，系统的 NDEF 派发落在那个透明界面上，它把 `nfc:<cardId>` 直接
  /// 推到这里——**主界面全程不出现**，所以贴卡零闪现（对照同类 App 实测做法）。
  /// 进程被杀时走原生的冷启动分支（转交主界面），不会进到这里。
  void _listenNfcRelay() {
    kNfcChannel.setMethodCallHandler((call) async {
      if (call.method != 'dispatch') return null;
      final args = call.arguments;
      final action = args is Map ? args['action'] as String? : null;
      if (action == null || action.isEmpty) return null;
      await _runNfcRoute(LaunchRoute(
        action: action,
        fromBackground: args is Map && args['fromBackground'] == true,
      ));
      return null;
    });
  }

  /// 贴卡触发链的统一执行入口（两条来源：原生启动队列 / 透明中转直投）。
  ///
  /// 总闸/去抖/查表/失效/确认/执行全在 `nfc_trigger` 内；本处只负责组装 ref/host
  /// （C32/B31：自取，不接受外部 context），并按结果决定要不要把界面让回去。
  Future<void> _runNfcRoute(LaunchRoute route) async {
    final navCtx = _rootNavContext();
    if (navCtx == null) return;
    try {
      final outcome = await nfcHandleLaunch(route, nfcTriggerDepsOf(ref, navCtx));
      // 排障留痕：只记结果枚举，无卡号/指纹（不在 C11 红线内）。真机复现
      // 「贴卡没反应／没横幅」时，到 App 内日志页看这一行就知道走到了哪一支。
      AppLog.add('NFC 贴卡结果：$outcome（fromBackground=${route.fromBackground}）',
          src: LhLogLine.srcSystem);
      // 批3（2026-10-17 产品令）：**「没办成需要看界面的事」的结果一律退回原处**。
      // 透明中转路径下 App 本来就没到前台，这一步无害（等于再确认一次）。
      // `nav.*`（记一笔等）不适用——它的目的就是打开某个页面；未识别卡也不适用
      // （B8 绑定引导需要留在 `/nfc`）。
      if (route.fromBackground &&
          (outcome == NfcTriggerOutcome.executedSilent ||
              outcome == NfcTriggerOutcome.needsRebind ||
              outcome == NfcTriggerOutcome.targetGone ||
              outcome == NfcTriggerOutcome.silent)) {
        await moveTaskToBack();
      }
    } catch (e) {
      AppLog.reportError('NFC 贴卡触发失败：$e', src: LhLogLine.srcSystem);
    }
  }

  Future<void> _consumeOpen() async {
    if (_consuming) return; // 弹层在途时 resumed 不重入
    _consuming = true;
    try {
      final f = await takeOpenFile();
      final kind = classifyOpenIntent(f);
      if (kind == null || f == null) return;
      final navCtx = aiRootNavKey.value?.currentState?.context;
      if (navCtx == null || !navCtx.mounted) return;
      if (kind.isEmpty) {
        AppToast.show(navCtx, kOpenUnsupportedToast);
      } else if (kind == 'note') {
        await noteOpenConsume(navCtx, ref, f);
      } else {
        await handleOpenWithEpub(navCtx, ref, f.path);
      }
    } finally {
      _consuming = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // L10 习惯联动订阅（待办完成 → 打卡回写 · 应用全程存活）。
    ref.watch(habitLinkageProvider);
    // L3 日记联动订阅（语义断链批：待办完成 → 日记 ☐ 行回勾 · 应用全程存活）。
    ref.watch(journalLinkageProvider);
    // 记账批2d §5：周期账单 App 启动到期扫尾（一次性静默生成，无常驻 Timer）。
    ref.watch(ledgerRecurMountProvider);
    // 桌面批1（C2/B1/F1-2）：首启以默认 4 枚初始化动态快捷方式——不这么做，
    // 新装用户不打开「设置→桌面与快捷方式」就永远没有长按菜单。
    ref.watch(desktopShortcutSeedProvider);
    // 桌面批2（F2-3/C5）：小组件快照同步——App 存活时按需下发（三源变化或
    // 设置页改动触发），widget 只读快照、永不直读 sqlite。
    ref.watch(desktopWidgetSyncProvider);
    return MaterialApp.router(
      title: 'LifeHarness',
      debugShowCheckedModeBanner: false,
      theme: ref.watch(lightThemeProvider),
      darkTheme: ref.watch(darkThemeProvider),
      themeMode: ref.watch(appThemeModeProvider),
      routerConfig: ref.watch(appRouterProvider),
    );
  }
}
