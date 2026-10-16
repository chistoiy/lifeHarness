/// NFC 卡片域模型（批1 · 需求模块 19 · V1.68）。
///
/// 规格＝docs/handoff/NFC卡片模块-冻结版开发方案-20261015.md（V3【方案冻结】）。
///
/// 域层只放**纯数据与纯判定**，零 IO、零 Flutter 依赖——判定逻辑（写入态、目标是否
/// 已绑、目标类名、目标类图标）是本模块最容易被"从 UI 反推"写歪的部分（AGENTS：
/// 写断言前先问期望是从需求推的还是从实现反推的），故全部集中在无依赖的域层，
/// 由 `nfc_card_dao_test`／`nfc_target_test` 直接钉。
library;

import '../../../core/database/schema/nfc.dart' show NfcTagKind, NfcTargetKind;

/// 卡片名硬上限（冻结档 B14：超出不接收）。
const int kNfcNameMaxLen = 12;

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

  bool get isWritten => writtenAt != null;

  /// 目标是否已绑定（判据同源＝`target_ref` 是否为空 · B39）。
  bool get hasTarget => (targetRef ?? '').isNotEmpty;

  /// 是否只读卡（UID 轨多为只读 ⇒ 只能登记指纹不能写 · C25/B27）。
  /// **只读卡显示「只读卡」而非「未写入」**（C31-B29 联动：两者语义不同，
  /// 「未写入」是可补的动作，「只读卡」是换卡才能解决的物理限制）。
  bool get isReadOnlyTag => tagKind == NfcTagKind.uid;

  /// 目标类名（徽标 chip 用 · B42）。未绑定时返回 null。
  ///
  /// ⚠ 这里**只给类名不查具体名**——具体目标名（"学习"／"《书名》"）由各模块库查，
  /// 走 `nfc_mounts.dart`；卡片表**只存 id 不存名**（B23：同名分类按 id 区分）。
  String? get targetKindLabel => targetKindLabelOf(targetKind, bound: hasTarget);

  /// 目标类图标键（列表图标块用 · 冻结档 §4.1：导航／计时／阅读三种）。
  String? get targetKindIcon => targetKindIconOf(targetKind, bound: hasTarget);

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
      );
}

/// 目标类名（徽标 chip 逐字 · B42：用目标类名如「学习」「《书名》」）。
///
/// [bound]＝false（未绑定）时返回 null——**未绑定的卡不显徽标**，
/// 与「已绑定才显静态绑定态」一致（C23 的进行中标记是另一枚动态标记）。
String? targetKindLabelOf(String kind, {required bool bound}) {
  if (!bound) return null;
  switch (kind) {
    case NfcTargetKind.nav:
      return '快捷动作';
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
String? targetKindIconOf(String kind, {required bool bound}) {
  if (!bound) return null;
  switch (kind) {
    case NfcTargetKind.nav:
      return 'nav';
    case NfcTargetKind.timerCat:
    case NfcTargetKind.timerDuration:
      return 'timer';
    case NfcTargetKind.readBook:
      return 'read';
    default:
      return null;
  }
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