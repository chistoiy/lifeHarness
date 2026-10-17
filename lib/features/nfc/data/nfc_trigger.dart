/// NFC 卡片模块批2 · 贴卡触发链（冻结档 §4.4 通用段 · F2-4~F2-9）。
///
/// 规格源＝`docs/handoff/NFC卡片模块-冻结版开发方案-20261015.md`（V3 冻结档），
/// 落地口径＝`docs/handoff/NFC卡片模块-批2写卡与触发.md` §0/§4。
///
/// **本文件是贴卡触发的唯一判定入口**：`app.dart` 的 `route.isNfc` 分支把
/// `LaunchRoute`（action 形如 `nfc:<cardId>`）投进来，剩下的总闸/去抖/查表/
/// 失效/确认/执行全在本文件。原生侧只解析出 cardId，一字不判业务（C36/C37/B35）。
///
/// 判定顺序（冻结档 F2-9／§4.4，**顺序本身是硬性要求**）：
///   ① 总闸 `nfc.enabled` 关 ⇒ **完全静默**（不报错不弹提示不震动不计次·C42，先于一切）
///   ② 去抖 3 秒窗口（同 cardId）：第二次出 toast「刚刚触发过，等一下」、第三次起静默（B43）
///   ③ cardId 格式校验（12 位 base62）：非法静默丢弃、不回显（B35）
///   ④ 卡号查表：未命中 ⇒ 绑定引导（B8）／**禁落 unknownRouteFallback**（B35）
///   ⑤ 目标失效（分类/书已删）⇒ toast ＋ 回 `/`（C24/F2-8）
///   ⑥ 确认开关 `nfc.confirmBeforeRun` 开 ⇒ 先出确认（标题＝卡名 · 正文＝目标名）
///   ⑦ 执行：`nav.*` ⇒ `go(动作路由)`；有状态卡 ⇒ toggle（2c，本文件只出口）
///
/// ⚠ **去抖窗口是内存态**（B43）：不落盘、不查库——它只是「别让一次物理贴卡因系统
/// 重复派发而执行两遍」的护栏，进程重启即清空（用户重启 App 后贴卡是合法的新意图）。
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/schema/nfc.dart' show NfcTargetKind;
import '../../../core/platform/desktop_actions.dart'
    show LaunchRoute, desktopActionOf;
import '../../../core/providers.dart' show settingsRepositoryProvider;
import '../../../core/settings/settings_repository.dart';
import '../../../shared/linkage/nfc_mounts.dart'
    show
        NfcTargetState,
        nfcHabitCheckIn,
        nfcTargetStateOf,
        nfcToggleRead,
        nfcToggleTimer;
import '../../../shared/widgets/confirm_dialog.dart' show lhConfirm;
import '../../../shared/widgets/ui_kit.dart' show AppToast;
import '../domain/nfc_card.dart';
import 'nfc_repo.dart';

/// 去抖窗口（F2-6：同 cardId 3 秒内只执行一次）。
const Duration kNfcDebounceWindow = Duration(milliseconds: 3000);

/// 去抖窗口内的第二次提示文案（B16/B43 逐字）。
const String kNfcDebounceToast = '刚刚触发过，等一下';

/// 目标失效回执（C24/F2-8 逐字）。
const String kNfcTargetGoneToast = '这张卡绑的分类/书已经不在了';

/// 未识别卡片的绑定引导 toast（B17/F2-5 逐字）。
const String kNfcUnboundToast = '这张卡还没绑定';

/// 贴卡触发的一次结果（供上层决定后续动作；也便于测试断言「发生了什么」）。
enum NfcTriggerOutcome {
  /// 静默结束：总闸关 / 去抖窗口内 / id 非法 / 卡已删且提示关闭。
  silent,

  /// 去抖窗口内第二次（出过一次提示）。
  debounced,

  /// 走了确认但用户取消。
  cancelled,

  /// 已执行（`nav.*` 的 go，或有状态卡的 toggle）。
  executed,

  /// 已执行且**不需要用户看界面**（打卡卡 / 计时与阅读 toggle）。
  ///
  /// 与 [executed] 的区别只在「要不要把界面让回去」：贴卡时 App 若不在前台，
  /// 系统已因 AAR 把本 App 拉到前台，这类动作执行完应立刻退回用户原来的界面，
  /// 结果由横幅通知呈现（2026-10-17 产品令）。`nav.*` 不适用——它就是要去某个页面。
  executedSilent,

  /// 目标失效：toast ＋ 回 `/`。
  targetGone,

  /// 未绑定：落 `/nfc` 绑定引导。
  unbound,
}

/// 触发链依赖（注入以便测试；生产由 `nfcHandleLaunch` 从 ref/host 组装）。
///
/// **C32/B31 口径**：ref 与 host（根 Navigator 的 BuildContext）由组合根自取，
/// 不接受外部传 context。`host.mounted` 假时「只落库、放弃 toast 与弹层」——
/// 本类把「host 是否可用」显式暴露为 [hostContext]，调用方据此降级。
class NfcTriggerDeps {
  NfcTriggerDeps({
    required this.prefs,
    required this.hostContext,
    required this.byId,
    required this.targetStateOf,
    required this.goRoute,
    required this.pushRoute,
    this.confirm,
    this.toast,
    this.now,
    this.toggle,
    this.habitCheckIn,
  });

  final SettingsRepository prefs;

  /// 根 Navigator 的 context；null／未 mounted ⇒ 降级为「只执行、不回执不弹层」。
  final BuildContext? hostContext;

  /// 查卡（按 id）。
  final Future<NfcCard?> Function(String id) byId;

  /// 目标有效性＋目标名解析（走 `nfc_mounts.dart`）。
  final Future<NfcTargetState> Function(NfcCard card) targetStateOf;

  /// `nav.*` 执行：`context.go(path)`。
  final void Function(String path) goRoute;

  /// 全屏栈路由用 push（`LaunchRoute.fullScreen`＝true 时）。
  final void Function(String path) pushRoute;

  /// 有状态卡 toggle 出口（2c 注入；null ⇒ 本批只支持 `nav.*`）。
  ///
  /// 传 (kind, ref, targetName, cardName) → 是否已执行（false＝目标不可用）。
  /// `targetName`＝目标具体名（计时分类名／书名），回执文案用（C22）。
  final Future<bool> Function(
    String targetKind,
    String? targetRef,
    String? targetName,
    String cardName,
  )? toggle;

  /// 打卡卡出口（`nav.habit` ＋ `targetSub`＝习惯名）：返回打卡结果。
  ///
  /// null ＝ 名字对不上在册习惯（目标失效）。缺省 null ⇒ 该卡退化为「只跳页」
  /// （与批2 行为一致，防注入缺失时误判）。
  final Future<NfcHabitCheck?> Function(String? habitName)? habitCheckIn;

  /// 确认开关开时的确认框；缺省用真实 `lhConfirm`。测试可注入桩。
  final Future<bool> Function(BuildContext ctx, String title, String message)?
      confirm;

  /// toast；缺省用真实 `AppToast.show`。测试可注入桩。
  final void Function(BuildContext ctx, String msg)? toast;

  /// 当前毫秒（去抖窗口用）。缺省 `DateTime.now()`。
  final int Function()? now;

  int get nowMs => (now ?? () => DateTime.now().millisecondsSinceEpoch)();
}

/// 去抖窗口内存表（**进程级**·跨调用保留）：cardId → 上次执行毫秒。
///
/// **只增不去**会随卡片数无界增长？不会——键是 cardId，量级＝用户手上的卡数；
/// 且每次触发只写自己那把。测试可用 [debugResetNfcDebounce] 清空。
final Map<String, int> _nfcLastFireMs = <String, int>{};

/// 窗口内「第几次」计数（B43：第二次出提示、第三次起静默）。
///
/// 与 [_nfcLastFireMs] 同寿命：**执行成功后**清掉计数，故计数只描述「同一窗口内
/// 的第几次重复」。窗口过期后再次贴卡＝新窗口，计数归 1。
final Map<String, int> _nfcWindowHits = <String, int>{};

/// 清空去抖内存（仅测试用）。
void debugResetNfcDebounce() {
  _nfcLastFireMs.clear();
  _nfcWindowHits.clear();
}

/// 从一条 `LaunchRoute` 取出 `cardId`（`nfc:<id>`）；不合形态返回 null。
String? nfcCardIdOfRoute(LaunchRoute route) {
  if (!route.isNfc) return null;
  final id = route.action.substring('nfc:'.length);
  return id.isEmpty ? null : id;
}

/// 贴卡触发主入口（由 `app.dart` 的 `route.isNfc` 分支调用）。
///
/// 返回 [NfcTriggerOutcome] 说明发生了什么（测试与真机排障用）。
Future<NfcTriggerOutcome> nfcHandleLaunch(
  LaunchRoute route,
  NfcTriggerDeps deps,
) async {
  final cardId = nfcCardIdOfRoute(route);
  // 形态不合（`nfc:` 后为空）：静默（B35 精神——不理解的一律不炸不回显）。
  if (cardId == null) return NfcTriggerOutcome.silent;

  // ① 总闸（C42：先于一切；关＝完全静默，不报错不提示不震动不计次）。
  if (!deps.prefs.loadNfcEnabled()) {
    return NfcTriggerOutcome.silent;
  }

  // ③ cardId 格式校验（B35：非法静默丢弃，不回显 id）。
  //    放在去抖之前——非法 id 不占去抖窗口，也不产生任何可见反应。
  if (!isValidNfcCardId(cardId)) return NfcTriggerOutcome.silent;

  // ② 去抖窗口（B16/B43）。放格式校验之后：合法 id 才进窗口统计。
  final now = deps.nowMs;
  final last = _nfcLastFireMs[cardId];
  if (last != null && now - last < kNfcDebounceWindow.inMilliseconds) {
    final hits = (_nfcWindowHits[cardId] ?? 1) + 1;
    _nfcWindowHits[cardId] = hits;
    // 第二次出提示、第三次起静默（B43）。
    if (hits == 2) {
      _showToast(deps, kNfcDebounceToast);
    }
    return NfcTriggerOutcome.debounced;
  }

  // 进入新窗口：记时间、命中计数归 1。
  _nfcLastFireMs[cardId] = now;
  _nfcWindowHits[cardId] = 1;

  // ④ 查表。
  final card = await deps.byId(cardId);
  if (card == null) {
    // 卡已删（或被删且提示关闭）：走 B8 绑定引导口径，**禁落 unknownRouteFallback**（B35）。
    // 因 card==null 查不到目标，无法给「目标名」；提示开关关则完全静默（B17）。
    if (deps.prefs.loadNfcPromptUnbound()) {
      _showToast(deps, kNfcUnboundToast);
    }
    _goHome(deps);
    return NfcTriggerOutcome.unbound;
  }

  // 未绑定目标（B39：卡建行但没绑目标）⇒ 绑定引导，落 `/nfc`。
  if (!card.hasTarget) {
    if (deps.prefs.loadNfcPromptUnbound()) {
      _showToast(deps, kNfcUnboundToast);
    }
    _goNfcList(deps);
    return NfcTriggerOutcome.unbound;
  }

  // ⑤ 目标失效（C24/F2-8）：分类删／书删 ⇒ toast ＋ 回 `/`，不执行、不自动重绑。
  final target = await deps.targetStateOf(card);
  if (!target.alive) {
    _showToast(deps, kNfcTargetGoneToast);
    _goHome(deps);
    return NfcTriggerOutcome.targetGone;
  }

  // ⑥ 确认开关（F2-9：默认关＝直接执行；开则先问一次，标题＝卡名、正文＝目标名）。
  if (deps.prefs.loadNfcConfirmBeforeRun()) {
    final ctx = deps.hostContext;
    // B31：host 不可用（首帧前）⇒ 放弃弹层，直接执行（不排队补弹）。
    if (ctx != null && ctx.mounted) {
      final ok = await _askConfirm(deps, ctx, card, target.name);
      if (!ok) return NfcTriggerOutcome.cancelled;
    }
  }

  // ⑦ 执行。
  return _execute(deps, card, target.name);
}

/// 执行一个已确认有效的卡（`nav.*` 直接 go；有状态卡走 toggle 出口）。
Future<NfcTriggerOutcome> _execute(
  NfcTriggerDeps deps,
  NfcCard card,
  String? targetName,
) async {
  // 有状态卡（计时分类 / 阅读书目）：走 toggle 出口（2c 落地）。
  if (card.targetKind == NfcTargetKind.timerCat ||
      card.targetKind == NfcTargetKind.readBook) {
    final toggle = deps.toggle;
    if (toggle == null) {
      // 本批（2b）尚未接入 toggle ⇒ 视为不可用，静默（不误当 nav 直接 go）。
      return NfcTriggerOutcome.silent;
    }
    try {
      final done = await toggle(
        card.targetKind,
        card.targetRef,
        targetName, // 目标名（计时分类名／书名；回执文案用·C22）
        card.name,
      );
      return done ? NfcTriggerOutcome.executedSilent : NfcTriggerOutcome.silent;
    } catch (_) {
      // 有状态卡 toggle 抛异常 ⇒ 静默不打断（C11：NFC 模块内零日志，卡号/指纹敏感）。
      return NfcTriggerOutcome.silent;
    }
  }

  // 打卡卡（`nav.habit` ＋ `target_sub`＝习惯名）：贴卡**直接打卡**，不只跳页
  //（2026-10-17 产品令）。此前只 `go('/habits')`，用户还得自己在列表里找那条习惯
  // 点一下——贴卡等于只是个快捷入口，卡上绑的具体习惯形同虚设。
  if (card.targetRef == kNfcRefHabit) {
    final sub = (card.targetSub ?? '').trim();
    final check = deps.habitCheckIn;
    if (sub.isNotEmpty && check != null) {
      final r = await check(sub);
      if (r == null) {
        // 名字对不上在册习惯（已删/改名）⇒ 失效口径（与其它目标一致）。
        _showToast(deps, kNfcTargetGoneToast);
        _goHome(deps);
        return NfcTriggerOutcome.targetGone;
      }
      if (r.checked) {
        _showToast(deps, '${r.name} 已打卡 · 连续 ${r.streak} 天');
      } else {
        // 今天已打过：**不重复计、不撤销**，只回执（贴卡是「补一下」不是「切换」）。
        _showToast(deps, '${r.name} 今天已打卡');
      }
      return NfcTriggerOutcome.executedSilent;
    }
    // 老卡只绑了动作 id、没绑具体习惯 ⇒ 退回跳页（保持批2 行为，不误判失效）。
  }

  // `nav.*`（含打卡 / 呵护宝宝两枚具体动作）：解析动作路由并 go/push。
  final label = navActionLabelOf(card.targetRef);
  if (label == null) {
    // 动作表里查不到（旧数据退役动作）⇒ 目标失效口径。
    _showToast(deps, kNfcTargetGoneToast);
    _goHome(deps);
    return NfcTriggerOutcome.targetGone;
  }
  final path = _navPathOf(card.targetRef);
  if (path == null) {
    _showToast(deps, kNfcTargetGoneToast);
    _goHome(deps);
    return NfcTriggerOutcome.targetGone;
  }
  // 全屏栈动作须 push（V1.67 真机伤：go 会换掉栈底壳页 ⇒ 页内 pop 无处可去 ⇒ 返回黑屏）。
  if (nfcNavIsFullScreen(card.targetRef)) {
    deps.pushRoute(path);
  } else {
    deps.goRoute(path);
  }
  // 记一笔（2026-10-17 产品令·改冻结档 C22「nav.* 一律不给 toast」）：
  // 贴卡直接跳进编辑页，页面上没有任何「这张卡被认出来了」的痕迹——给一行回执，
  // 否则用户分不清是卡生效还是误触。其余 nav.* 仍静默（跳转本身已够显性）。
  if (card.targetRef == 'ledger') {
    _showToast(deps, '已打开记一笔');
  }
  return NfcTriggerOutcome.executed;
}

/// 动作 id → 目标路由（`go` 的 path）。查表唯一来源＝动作表（C9/C18）。
///
/// `nav.*` 一律用 `go`（壳内 tab 等价）——但动作表里 `fullScreen`＝true 的目标
/// 须 `push`（V1.67 真机伤：`go` 会换掉栈底壳页 ⇒ 页内 pop 无处可去 ⇒ 返回黑屏）。
/// NFC 的快捷动作目标若落在全屏栈路由上，用 push（与 `app.dart` 的 `lh://` 消费同口径）。
String? _navPathOf(String? actionId) {
  final a = desktopActionOf(actionId ?? '');
  return a?.path;
}

/// 与 [NfcTriggerDeps.goRoute] 配合：全屏栈动作须 push。
///
/// 拆成独立函数以便测试注入 path→是否全屏（生产取动作表 [desktopActionOf]）。
bool nfcNavIsFullScreen(String? actionId) =>
    desktopActionOf(actionId ?? '')?.fullScreen ?? false;

/// toast（host 不可用时静默丢弃·B31）。
void _showToast(NfcTriggerDeps deps, String msg) {
  final ctx = deps.hostContext;
  if (ctx == null || !ctx.mounted) return;
  final t = deps.toast;
  if (t != null) {
    t(ctx, msg);
  } else {
    AppToast.show(ctx, msg);
  }
}

/// 确认框（标题＝卡名 · 正文＝目标名）。返回是否确认。
Future<bool> _askConfirm(
  NfcTriggerDeps deps,
  BuildContext ctx,
  NfcCard card,
  String? targetName,
) async {
  final title = card.name;
  final name = (targetName ?? '').trim();
  final msg = name.isEmpty ? '要去「${card.name}」绑定的目标吗' : '要去「$name」吗';
  final c = deps.confirm;
  if (c != null) return c(ctx, title, msg);
  // 执行类确认：destructive=false（不把「要去某页」染成删除的玫红）。
  return lhConfirm(ctx, msg, title: title, okLabel: '执行', destructive: false);
}

/// 回首页（`/`）：用 go（壳内 tab）。
void _goHome(NfcTriggerDeps deps) => deps.goRoute('/');

/// 落 `/nfc` 管理屏做绑定引导（B8）。
///
/// ⚠ `/nfc` 是**全屏栈路由**（`nfcPageRoutes`，不占底栏）⇒ 必须 `push`
/// （V1.67 真机伤：`go` 会换掉栈底壳页 ⇒ 页内 pop 无处可去 ⇒ 返回黑屏）。
void _goNfcList(NfcTriggerDeps deps) => deps.pushRoute('/nfc');

// ==================== 生产组装（组合根调用 · 非测试路径） ====================

/// 由 `app.dart` 组装触发链依赖（C32/B31：ref/host 自取）。
///
/// [ref]＝组合根的 `WidgetRef`；[navCtx]＝根 Navigator 的 context
/// （`aiRootNavKey.value?.currentState?.context`），**必须首帧后非 null**，
/// 否则回执与弹层会被丢弃（只落库，见 B31）。
///
/// toggle 出口（有状态卡）在 2c 由 `nfc_mounts` 提供；本批（2b）传 null ⇒ 有状态卡
/// 贴卡时静默（不误当 nav 直接 go）。2c 落地后在此接入 `nfcToggleOf`。
NfcTriggerDeps nfcTriggerDepsOf(WidgetRef ref, BuildContext navCtx) {
  final prefs = ref.read(settingsRepositoryProvider);
  final repo = NfcRepo(AppDatabase.instance.db);
  return NfcTriggerDeps(
    prefs: prefs,
    hostContext: navCtx,
    byId: repo.byId,
    targetStateOf: (card) async {
      final s = await nfcTargetStateOf(card);
      return s;
    },
    goRoute: (path) => GoRouter.of(navCtx).go(path),
    pushRoute: (path) => GoRouter.of(navCtx).push(path),
    toggle: (kind, targetRef, targetName, cardName) async {
      // 有状态卡执行出口（2c）：经 linkage 转发口（内部自取 ref/host·C32）。
      if (kind == NfcTargetKind.timerCat) {
        return nfcToggleTimer(ref, navCtx, catId: targetRef, catName: targetName ?? '');
      }
      if (kind == NfcTargetKind.readBook) {
        return nfcToggleRead(ref, navCtx, bookId: targetRef);
      }
      return false;
    },
    // 打卡卡出口（2026-10-17 产品令）：经 linkage 直连习惯模块（守 R1），
    // 按卡上 `target_sub` 的习惯名直接落库，不再只是跳页。
    habitCheckIn: (habitName) => nfcHabitCheckIn(habitName),
  );
}
