/// NFC 卡片域模型（批1 · 需求模块 19 · V1.68；批1b 补三字段与标签口径）。
///
/// 规格＝docs/handoff/NFC卡片模块-冻结版开发方案-20261015.md（V3【方案冻结】）
/// ＋批1b 工单 docs/handoff/NFC卡片模块-批1b管理屏交互改造.md。
///
/// 域层只放**纯数据与纯判定**，零 IO、零 Flutter 依赖——判定逻辑（写入态、目标是否
/// 已绑、目标类名、目标类图标、目标标签全文、装饰符剥离）是本模块最容易被"从 UI 反推"
/// 写歪的部分（AGENTS：写断言前先问期望是从需求推的还是从实现反推的），故全部集中在
/// 无依赖的域层，由 `nfc_card_dao_test`／`nfc_linkage_test` 直接钉。
library;

import '../../../core/database/schema/nfc.dart' show NfcTagKind, NfcTargetKind;
import '../../../core/platform/desktop_actions.dart' show kDesktopActions;

/// 卡片名硬上限（冻结档 B14：超出不接收）。
const int kNfcNameMaxLen = 12;

/// 卡片默认描述硬上限（批1b §1：选填 ≤16 字）。
const int kNfcDescMaxLen = 16;

/// 卡片颜色档数（批1b §1：6 色色板；色表在 UI 层 token 常量）。
const int kNfcColorCount = 6;

/// 卡片颜色表（原型 `NFC_COLORS` 六色逐值同源 · 批1b §2「色表进域层常量」）。
///
/// 存的是 ARGB 整数而非 Flutter `Color`——域层保持零 Flutter 依赖，
/// UI 侧 `Color(kNfcColors[i])` 一转即可。色值属**卡片身份色**（列表左右节点
/// 用它区分条目），不是主题色：故不随主题/明暗变，也不进色值棘轮白名单。
const List<int> kNfcColors = [
  0xFFF59E0B, // 琥珀
  0xFFEF4444, // 珊瑚红
  0xFF3B82F6, // 天青蓝
  0xFF10B981, // 薄荷绿
  0xFF8B5CF6, // 紫罗兰
  0xFF64748B, // 石墨灰
];

/// 颜色名（无障碍语义 / 选色器 tooltip 用 · 原型 `NFC_COLOR_NAMES` 同序）。
const List<String> kNfcColorNames = ['琥珀', '珊瑚红', '天青蓝', '薄荷绿', '紫罗兰', '石墨灰'];

/// `id` 长度（C33：12 位 base62）。
const int kNfcIdLen = 12;

/// 一张 NFC 卡片（`nfc_cards` 行）。
class NfcCard {
  const NfcCard({
    required this.id,
    required this.name,
    required this.targetKind,
    this.targetRef,
    this.tagKey,
    this.tagKind,
    required this.createdAt,
    this.lastUsedAt,
    this.useCount = 0,
    this.writtenAt,
    this.descText,
    this.color,
    this.targetSub,
  });

  /// 标签里只存这一串（C1：`lh://nfc/<id>`）。
  final String id;

  final String name;

  /// 四类目标之一（见 [NfcTargetKind]）。**不可为空**——建行时必给一个默认类
  /// （新建流程默认选中第一区块第一项，冻结档 §4.2）。
  final String targetKind;

  /// 目标引用：动作 id / `categories.id` / `books.id` / 分钟数字符串。
  /// **可空**＝卡已建行但尚未绑定目标（B39：此时贴卡只更新写入态、不执行）。
  final String? targetRef;

  /// `ndef:<id>` 或 `uid:<指纹>`；null＝还没写入过任何标签。
  final String? tagKey;

  /// 见 [NfcTagKind]；null＝未写入。
  final String? tagKind;

  final int createdAt;
  final int? lastUsedAt;
  final int useCount;

  /// **写入态的唯一判据**（C31）：null＝未写入，毫秒＝最后成功写入时刻。
  /// 判据**只读本列**，不靠读标签反推（写入态是历史事实，反推不可行）。
  final int? writtenAt;

  /// 默认描述（选填 ≤16 字 · 批1b）。列表右节点副行优先显示它。
  final String? descText;

  /// 颜色索引（0~5 · 批1b）。null＝未设；越界值由 [colorIndex] 兜回 0。
  final int? color;

  /// **二级参数**（批1b §2）：打卡＝习惯名（已剥离装饰符）；呵护宝宝＝
  /// `<babyId>/<kindId>`；其余目标为 null。
  ///
  /// ⚠ 不新增 `NfcTargetKind` 枚举值——「打卡」「呵护宝宝」是 `nav` 大类下的
  /// 两枚具体动作（`target_ref` 分别取 `'habit'`/`'care'`），二级落本列。
  final String? targetSub;

  bool get isWritten => writtenAt != null;

  /// 目标是否已绑定（判据同源＝`target_ref` 是否为空 · B39）。
  bool get hasTarget => (targetRef ?? '').isNotEmpty;

  /// 是否只读卡（UID 轨多为只读 ⇒ 只能登记指纹不能写 · C25/B27）。
  /// **只读卡显示「只读卡」而非「未写入」**（C31-B29 联动：两者语义不同，
  /// 「未写入」是可补的动作，「只读卡」是换卡才能解决的物理限制）。
  bool get isReadOnlyTag => tagKind == NfcTagKind.uid;

  /// 打卡目标（`nav` 大类下的 `habit` 动作 · 批1b）。
  bool get isHabitTarget =>
      targetKind == NfcTargetKind.nav && targetRef == kNfcRefHabit;

  /// 呵护宝宝目标（`nav` 大类下的 `care` 动作 · 批1b）。
  bool get isCareTarget =>
      targetKind == NfcTargetKind.nav && targetRef == kNfcRefCare;

  /// 颜色索引（越界/null 一律兜回 0 · 防脏数据把色板索引炸掉）。
  int get colorIndex =>
      (color == null || color! < 0 || color! >= kNfcColorCount) ? 0 : color!;

  /// 目标类名（徽标 chip / 列表主行前缀用 · B42）。未绑定时返回 null。
  ///
  /// ⚠ 这里**只给类名不查具体名**——具体目标名（"学习"／"《书名》"）由各模块库查，
  /// 走 `nfc_mounts.dart`；卡片表**只存 id 不存名**（B23：同名分类按 id 区分）。
  String? get targetKindLabel =>
      targetKindLabelOf(targetKind, bound: hasTarget, ref: targetRef);

  /// 目标类图标键（列表图标块用 · 冻结档 §4.1：导航／计时／阅读三种）。
  String? get targetKindIcon =>
      targetKindIconOf(targetKind, bound: hasTarget, ref: targetRef);

  factory NfcCard.fromRow(Map<String, Object?> row) => NfcCard(
        id: row['id'] as String? ?? '',
        name: row['name'] as String? ?? '',
        targetKind: row['target_kind'] as String? ?? NfcTargetKind.nav,
        targetRef: row['target_ref'] as String?,
        tagKey: row['tag_key'] as String?,
        tagKind: row['tag_kind'] as String?,
        createdAt: row['created_at'] as int? ?? 0,
        lastUsedAt: row['last_used_at'] as int?,
        useCount: row['use_count'] as int? ?? 0,
        writtenAt: row['written_at'] as int?,
        descText: row['desc_text'] as String?,
        color: row['color'] as int?,
        targetSub: row['target_sub'] as String?,
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'name': name,
        'target_kind': targetKind,
        'target_ref': targetRef,
        'tag_key': tagKey,
        'tag_kind': tagKind,
        'created_at': createdAt,
        'last_used_at': lastUsedAt,
        'use_count': useCount,
        'written_at': writtenAt,
        'desc_text': descText,
        'color': color,
        'target_sub': targetSub,
      };

  NfcCard copyWith({
    String? name,
    String? targetKind,
    String? targetRef,
    String? tagKey,
    String? tagKind,
    int? lastUsedAt,
    int? useCount,
    int? writtenAt,
    String? descText,
    int? color,
    String? targetSub,
  }) =>
      NfcCard(
        id: id,
        name: name ?? this.name,
        targetKind: targetKind ?? this.targetKind,
        targetRef: targetRef ?? this.targetRef,
        tagKey: tagKey ?? this.tagKey,
        tagKind: tagKind ?? this.tagKind,
        createdAt: createdAt,
        lastUsedAt: lastUsedAt ?? this.lastUsedAt,
        useCount: useCount ?? this.useCount,
        writtenAt: writtenAt ?? this.writtenAt,
        descText: descText ?? this.descText,
        color: color ?? this.color,
        targetSub: targetSub ?? this.targetSub,
      );
}

/// 「打卡」目标的 `target_ref`（习惯条目 · 批1b）。
const String kNfcRefHabit = 'habit';

/// 「呵护宝宝」目标的 `target_ref`（宝宝档案＋记录类型 · 批1b）。
const String kNfcRefCare = 'care';

/// 目标类名（徽标 chip 逐字 · B42：用目标类名如「学习」「《书名》」）。
///
/// [bound]＝false（未绑定）时返回 null——**未绑定的卡不显徽标**，
/// 与「已绑定才显静态绑定态」一致（C23 的进行中标记是另一枚动态标记）。
/// [ref]＝动作 id；`nav` 大类下「打卡」「呵护宝宝」两枚具体动作各有自己的类名
/// （批1b：不再笼统显示「快捷动作」）。
String? targetKindLabelOf(String kind, {required bool bound, String? ref}) {
  if (!bound) return null;
  if (kind == NfcTargetKind.nav) {
    if (ref == kNfcRefHabit) return '打卡';
    if (ref == kNfcRefCare) return '呵护宝宝';
    return '快捷动作';
  }
  switch (kind) {
    case NfcTargetKind.timerCat:
      return '计时';
    case NfcTargetKind.readBook:
      return '阅读';
    case NfcTargetKind.timerDuration:
      return '定时长';
    default:
      return null;
  }
}

/// 目标类图标键（线性 SVG · 禁 emoji · 禁彩块）。
String? targetKindIconOf(String kind, {required bool bound, String? ref}) {
  if (!bound) return null;
  if (kind == NfcTargetKind.nav) {
    if (ref == kNfcRefHabit) return 'habit';
    if (ref == kNfcRefCare) return 'care';
    return 'nav';
  }
  switch (kind) {
    case NfcTargetKind.timerCat:
    case NfcTargetKind.timerDuration:
      return 'timer';
    case NfcTargetKind.readBook:
      return 'read';
    default:
      return null;
  }
}

/// 目标标签全文（列表左节点主行／「卡片信息」形态的目标摘要 · 批1b §5 逐字口径）。
///
/// 口径（原型 `nfcTargetLabel` 同构）：
/// · 动作类 → **动作名本身**（不加「快捷动作 · 」前缀）；
/// · 计时／阅读 → `计时 · 学习`／`阅读 · 书名`；
/// · 打卡 → `打卡 · 习惯名`；呵护宝宝 → `呵护宝宝 · 宝宝 · 类型`。
///
/// [targetName]＝目标具体名（分类名／书名／宝宝·类型），由 `nfc_mounts.dart`
/// 查库给出；打卡的习惯名直接取 `target_sub`（不必查库，见 §2）。
String nfcTargetLabelOf(NfcCard c, {String? targetName}) {
  if (!c.hasTarget) return '未绑定';
  if (c.isHabitTarget) {
    final n = (targetName ?? c.targetSub ?? '').trim();
    return '打卡 · ${n.isEmpty ? '未选条目' : n}';
  }
  if (c.isCareTarget) {
    final n = (targetName ?? '').trim();
    return '呵护宝宝 · ${n.isEmpty ? '未选' : n}';
  }
  switch (c.targetKind) {
    case NfcTargetKind.timerCat:
      return '计时 · ${(targetName ?? '').trim()}';
    case NfcTargetKind.readBook:
      return '阅读 · ${(targetName ?? '').trim()}';
    case NfcTargetKind.timerDuration:
      return '定时长 · ${c.targetRef ?? ''} 分钟';
    default:
      return navActionLabelOf(c.targetRef) ?? '未绑定';
  }
}

/// 动作 id → 动作名（C9/C18：动作表唯一来源＝`core/platform/desktop_actions.dart`，
/// 本模块**禁再写一份动作常量**）。查不到（旧数据里的退役动作）返回 null。
String? navActionLabelOf(String? actionId) {
  if (actionId == null || actionId.isEmpty) return null;
  for (final a in kDesktopActions) {
    if (a.id == actionId) return a.label;
  }
  return null;
}

/// 呵护宝宝二级参数拼装（`<babyId>/<kindId>`）。
String nfcCareSubOf(int babyId, String kindId) => '$babyId/$kindId';

/// 呵护宝宝二级参数拆解；格式不合返回 null（**不猜**——脏数据当失效处理）。
(int babyId, String kindId)? nfcCareSubParse(String? sub) {
  final raw = (sub ?? '').trim();
  if (raw.isEmpty) return null;
  final i = raw.indexOf('/');
  if (i <= 0 || i == raw.length - 1) return null;
  final id = int.tryParse(raw.substring(0, i));
  final kind = raw.substring(i + 1).trim();
  if (id == null || kind.isEmpty) return null;
  return (id, kind);
}

/// 装饰符剥离（**NFC 模块零 emoji 硬要求** · 批1b §1）。
///
/// 引用其他模块数据时同样适用：习惯模块的习惯名自带 emoji，本模块渲染前一律剥离，
/// **且 `target_sub` 存剥离后的名字、失效判定亦按剥离后比对**（三处同源）。
/// 范围照原型 `nfcStripEmoji`（emoji 主区／杂项符号／装饰符号／变体选择符／键帽／零宽连接符）。
String nfcStripEmoji(String s) => s.replaceAll(_kEmojiRe, '').trim();

final RegExp _kEmojiRe = RegExp(
  r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}\u{FE0E}\u{FE0F}\u{20E3}\u{200D}]',
  unicode: true,
);

/// 习惯名的显示／存储口径：剥离装饰符；**剥完为空则回落原名**（习惯名只由
/// 装饰符组成时，空 chip 既不可点也不可辨——回落原名至少可用，且显示、存储、
/// 失效比对三处同源，不会出现「选得上却判失效」）。
String nfcHabitDisplayName(String name) {
  final raw = name.trim();
  final stripped = nfcStripEmoji(raw);
  return stripped.isEmpty ? raw : stripped;
}

/// `id` 是否为合规的 12 位 base62（C33/B35）。
///
/// **格式校验是防注入的唯一闸**：外部 `lh://nfc/<id>`（URL Scheme／NDEF 分发）都能
/// 带任意字符串进来，不校验就可能带着引号或超长串进 SQL 参数或日志。
/// 校验失败**静默丢弃、不得回显 id**（B35）。
bool isValidNfcCardId(String id) {
  if (id.length != kNfcIdLen) return false;
  for (final c in id.codeUnits) {
    final isDigit = c >= 0x30 && c <= 0x39; // 0-9
    final isLower = c >= 0x61 && c <= 0x7A; // a-z
    final isUpper = c >= 0x41 && c <= 0x5A; // A-Z
    if (!isDigit && !isLower && !isUpper) return false;
  }
  return true;
}

/// NDEF 标签的 `tag_key` 全文（`ndef:<id>`）——C1：标签里就写这一串。
String ndefTagKeyOf(String cardId) => 'ndef:$cardId';

/// **脱敏后的排障串**：指纹只留后 4 位（C11/F1-1b）。
///
/// ⚠ **UID 指纹永不进任何日志（含 debug 级）**——UID 可反查物理卡序列，比卡号更敏感。
/// 本函数是唯一允许出现在日志/调试输出里的形态，且仅供人工排障。
String maskedTagKey(String? tagKey) {
  if (tagKey == null || tagKey.isEmpty) return '(无)';
  final idx = tagKey.indexOf(':');
  if (idx < 0) return '(无前缀)';
  final prefix = tagKey.substring(0, idx);
  final body = tagKey.substring(idx + 1);
  if (body.length <= 4) return '$prefix:****';
  return '$prefix:****${body.substring(body.length - 4)}';
}