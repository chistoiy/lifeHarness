/// 小组件模块 批A · 按实例绑定域层（工单 §2 绑定层 · 评估件 §2.3 层3）。
///
/// 规格＝docs/handoff/小组件模块-批A按实例绑定与打卡试点.md §2＋
/// docs/handoff/评估结论-20261017-小组件Glance裁定与内容对齐NFC分类评估.md §2.3。
///
/// **为什么 widget 侧另立一份目标三件套**：NFC 的目标在 DB 行（`nfc_cards` 表），
/// widget 的绑定是「桌面实例 → 目标」的 prefs 映射（**不进 DB、不吃备份**·工单 §0 ③）。
/// 两者**同构不同存储**：kind/ref/sub 三字段口径与 `NfcTargetKind` 逐字一致——
/// 选择层参数化后两边同一份数据源，**禁两套常量**（域层只 import 常量类，零 IO）。
///
/// 本文件零 IO、零 Flutter 依赖：编码/解码/实例回收/老实例回落/失效三态判据
/// 全部是纯函数，由 `test/widget_binding_test.dart` 直接钉。
library;

import '../../../core/database/schema/nfc.dart' show NfcTargetKind;

/// 绑定值的字段分隔符（与 `desktop_widget.dart` 待办行编码同族：控制字符）。
///
/// ⚠ 禁 `|`/`\n`：`|` 是习惯名/书名里的合法字符，`\n` 会被 SharedPreferences 与
/// 原生布局两头反复转义 ⇒ 行数据错位（待办 2×2 实锤坑，见经验坑）。
const String kWidgetBindFieldSep = '\u001f';

/// 桌面实例绑定键前缀（**键带桌面实例 id** · 工单 §0 ③）。
///
/// ⚠ Dart 侧写无 `flutter.` 前缀（shared_preferences 插件自行加），原生侧读
/// `FlutterSharedPreferences` 时要带 `flutter.` 前缀——与 `desktop.*` 既有键
/// 同口径（`LhWidget.FLUTTER_KEY_PREFIX` · 禁两套）。
const String kWidgetBindKeyPrefix = 'desktop.widget_bind.';

/// 老实例回落用的**全局默认绑定**键（实例无绑定记录时读它）。
///
/// R2（评估件 §2.4）：升级后桌面老实例没有绑定记录，读空即全变占位——
/// 必须有回落与一次性迁移口径，测试覆盖「老实例升级」。
const String kWidgetBindDefaultKey = '${kWidgetBindKeyPrefix}default';

/// 「先选后落」的**预选绑定**键（一次性·工单 §2 配置页层）。
///
/// 来由：系统 `requestPinAppWidget` 是异步的，`appWidgetId` 只有落桌面那一刻
/// 才由系统分配，App 侧**拿不到**（`onSuccess` 回调里才有 id，且不在本进程的
/// Dart 侧）。故「先选」与「后落」之间必须有个**交接位**：App 把选好的目标写这里，
/// 原生配置页在 `onCreate` 拿到 `EXTRA_APPWIDGET_ID` 后读它写成本实例键、随即清除
/// ——用户看不到配置页（无感回写），桌面直接出现「打卡-单习惯」。
///
/// ⚠ 键尾 `pending` **不是**数字，[WidgetBindingStore.loadAll] 会跳过（不做实例）。
const String kWidgetBindPendingKey = '${kWidgetBindKeyPrefix}pending';

/// 预选绑定的有效期（毫秒）。
///
/// 为什么必须有期限：用户在**系统**那个「是否添加到主屏幕」弹窗里点取消时，
/// 预选就没有任何人来消费。不设期限，下次从桌面小部件库里随手拖一枚别的
/// 小组件出来，就会把这枚陈年预选吃掉——「我没选过它，它自己绑上了」。
const int kWidgetBindPendingTtlMs = 2 * 60 * 1000;

/// 允许的时钟回拨窗口（毫秒）：时间戳落在「未来」的脏值不该永久有效。
const int kWidgetBindPendingSkewMs = 60 * 1000;

/// 打卡-单习惯小组件的种类 id（与原生 `pinWidgetById` 的 when 分支、
/// `WidgetConfigActivity` 的 provider 判定**逐字一致**·守护测试交叉核对）。
const String kWidgetKindHabit = 'habit';

/// 一个桌面实例绑定的动作目标（NFC 目标三件套的 widget 侧同构体）。
class WidgetTarget {
  const WidgetTarget({required this.kind, required this.ref, this.sub});

  /// 目标大类（[NfcTargetKind] 之一：nav／timer_cat／read_book／timer_duration）。
  final String kind;

  /// 目标引用：动作 id / `categories.id` / `books.id` / 分钟数字符串。
  /// 打卡目标取 `'habit'`（与 NFC 的 [kNfcRefHabit] 同值·选择层同源）。
  final String ref;

  /// 二级参数：打卡＝习惯名（已剥装饰符）；呵护宝宝＝`<babyId>/<kindId>`；
  /// 其余为 null。
  final String? sub;

  /// 是否可绑（kind/ref 缺一即不可绑——与 NFC `hasTarget` 同判据）。
  bool get isValid => kind.isNotEmpty && ref.isNotEmpty;

  /// 紧凑编码（三字段恒显，sub 空则留空段）。
  String encode() => '$kind$kWidgetBindFieldSep$ref$kWidgetBindFieldSep${sub ?? ''}';

  /// 解码；**不猜**：字段数不符、kind/ref 为空、kind 不在已知集合 ⇒ null
  /// （脏数据按未绑定处理，由回落/失效态兜底，禁把猜测值渲染到桌面）。
  static WidgetTarget? decode(String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty) return null;
    final f = s.split(kWidgetBindFieldSep);
    if (f.length != 3) return null;
    final kind = f[0].trim();
    final ref = f[1].trim();
    final sub = f[2].trim();
    if (kind.isEmpty || ref.isEmpty) return null;
    if (!NfcTargetKind.all.contains(kind)) return null;
    return WidgetTarget(kind: kind, ref: ref, sub: sub.isEmpty ? null : sub);
  }

  @override
  bool operator ==(Object other) =>
      other is WidgetTarget &&
      other.kind == kind &&
      other.ref == ref &&
      other.sub == sub;

  @override
  int get hashCode => Object.hash(kind, ref, sub);

  @override
  String toString() => 'WidgetTarget($kind/$ref${sub == null ? '' : '/$sub'})';
}

/// 一条按实例绑定（桌面实例 id → 目标）。
class WidgetBinding {
  const WidgetBinding({required this.appWidgetId, required this.target});

  /// 桌面实例 id（`AppWidgetManager` 分配的 appWidgetId）。
  final int appWidgetId;

  final WidgetTarget target;
}

/// 绑定解析结果三态（R2 回落口径的判据）。
enum WidgetBindingState {
  /// 本实例有绑定记录且目标有效。
  bound,

  /// 本实例无绑定记录，但**全局默认绑定**存在（老实例升级的回落态）。
  fallbackDefault,

  /// 两者皆无 ⇒ 桌面显示「未选择内容，点此设置」。
  unbound,
}

class WidgetBindingResolution {
  const WidgetBindingResolution(this.state, [this.target]);

  final WidgetBindingState state;

  /// 生效目标（[WidgetBindingState.unbound] 时为 null）。
  final WidgetTarget? target;

  bool get isActionable => state != WidgetBindingState.unbound && target != null;
}

/// 实例 → 绑定 解析（**实例绑定优先于全局默认**）。
///
/// [globalDefault]＝老实例回落用的默认目标（无则实例无绑定时直接 [unbound]）。
WidgetBindingResolution resolveWidgetBinding(
  Map<int, WidgetBinding> bindings,
  int appWidgetId, {
  WidgetTarget? globalDefault,
}) {
  final own = bindings[appWidgetId];
  if (own != null && own.target.isValid) {
    return WidgetBindingResolution(WidgetBindingState.bound, own.target);
  }
  if (globalDefault != null && globalDefault.isValid) {
    return WidgetBindingResolution(WidgetBindingState.fallbackDefault, globalDefault);
  }
  return const WidgetBindingResolution(WidgetBindingState.unbound);
}

/// 实例删除回收：**只留在役实例**的绑定（liveIds＝原生 `AppWidgetManager`
/// 报的在役 appWidgetId 集）。
///
/// 纯函数：返回回收后的新 map（调用方决定是否落盘）；被清掉的 id 由
/// [deadInstanceIds] 单独给出（日志/排障用，不回显目标内容）。
Map<int, WidgetBinding> pruneBindings(
  Map<int, WidgetBinding> bindings,
  Set<int> liveIds,
) {
  final out = <int, WidgetBinding>{};
  bindings.forEach((id, b) {
    if (liveIds.contains(id)) out[id] = b;
  });
  return out;
}

/// 已不在役（该回收）的实例 id 集。
Set<int> deadInstanceIds(Map<int, WidgetBinding> bindings, Set<int> liveIds) {
  final out = <int>{};
  bindings.forEach((id, _) {
    if (!liveIds.contains(id)) out.add(id);
  });
  return out;
}

/// 小组件渲染的四态（失效三态·产品 2026-10-17 勾定文案见工单 §3 ⑤）。
enum WidgetInstanceState {
  /// 正常：有快照、有绑定、源数据在。
  ok,

  /// 无快照（App 从未写过／快照过期）⇒「等待数据」。
  noSnapshot,

  /// 无绑定（实例与全局默认皆无）⇒「未选择内容，点此设置」。
  noBinding,

  /// 源失效（目标被删/被隐藏）⇒「内容已失效，点此重新选择」。
  sourceInvalid,
}

/// 失效三态判据（纯函数·优先级自上而下）。
///
/// 优先级口径：**无快照压过无绑定**——首装/清数据后哪怕没绑定也先显示
/// 「等待数据」（B6：无快照不显示 0/不显示未选择的既有口径），等快照到了
/// 才暴露绑定态；绑定态里源失效压过正常。
WidgetInstanceState widgetInstanceState({
  required bool hasSnapshot,
  required WidgetBindingResolution resolution,
  required bool sourceExists,
}) {
  if (!hasSnapshot) return WidgetInstanceState.noSnapshot;
  if (!resolution.isActionable) return WidgetInstanceState.noBinding;
  if (!sourceExists) return WidgetInstanceState.sourceInvalid;
  return WidgetInstanceState.ok;
}

/// 实例绑定键（键带实例 id·原生 Provider 读自己那一枚）。
String widgetBindingKeyOf(int appWidgetId) => '$kWidgetBindKeyPrefix$appWidgetId';

/// 「先选后落」的预选绑定记录（一次性交接位·见 [kWidgetBindPendingKey]）。
///
/// 编码＝`<widgetKind>␟<kind>␟<ref>␟<sub>␟<atMs>`（五段·分隔符与目标同族）。
/// 带 [widgetKind] 是为了**防止串味**：预选是给「打卡-单习惯」选的，若用户在
/// 系统弹窗里取消、随后又从小部件库拖了一枚待办出来，配置页据种类不匹配即
/// 不消费（宁可让它过期，也不能把别的枚绑到不相关的目标上）。
class WidgetPendingBind {
  const WidgetPendingBind({
    required this.widgetKind,
    required this.target,
    required this.atMs,
  });

  /// 目标小组件种类（`habit` …·与原生 provider 判定同值）。
  final String widgetKind;

  /// 预选的目标三件套。
  final WidgetTarget target;

  /// 落盘时刻（epoch ms·判过期用）。
  final int atMs;

  String encode() =>
      '$widgetKind$kWidgetBindFieldSep${target.encode()}$kWidgetBindFieldSep$atMs';

  /// 解码；脏值一律 null（按「无预选」处理，绝不猜）。
  static WidgetPendingBind? decode(String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty) return null;
    final f = s.split(kWidgetBindFieldSep);
    if (f.length != 5) return null;
    final widgetKind = f[0].trim();
    if (widgetKind.isEmpty) return null;
    // 中间三段原样交回目标解码（sub 可为空段）。
    final target = WidgetTarget.decode(
      '${f[1]}$kWidgetBindFieldSep${f[2]}$kWidgetBindFieldSep${f[3]}',
    );
    if (target == null) return null;
    final at = int.tryParse(f[4].trim());
    if (at == null || at <= 0) return null;
    return WidgetPendingBind(widgetKind: widgetKind, target: target, atMs: at);
  }

  /// 是否仍在有效期内（[kWidgetBindPendingTtlMs] ＋ 时钟回拨容忍）。
  bool isFreshAt(int nowMs) {
    final age = nowMs - atMs;
    return age <= kWidgetBindPendingTtlMs && age >= -kWidgetBindPendingSkewMs;
  }

  @override
  bool operator ==(Object other) =>
      other is WidgetPendingBind &&
      other.widgetKind == widgetKind &&
      other.target == target &&
      other.atMs == atMs;

  @override
  int get hashCode => Object.hash(widgetKind, target, atMs);

  @override
  String toString() => 'WidgetPendingBind($widgetKind → $target @$atMs)';
}
