/// NFC 写卡状态机（批2a · 冻结档 §4.3「唯一真相」＋ 原型 `NFC_STATE_TEXT` 文案表）。
///
/// 规格＝docs/handoff/NFC卡片模块-冻结版开发方案-20261015.md §4.3 / §4.5 / §4.6
/// ＋`docs/handoff/NFC卡片模块-批2写卡与触发.md` §3。
///
/// 域层只放**纯数据与纯判定**，零 IO、零 Flutter 依赖（同 `nfc_card.dart` 口径）——
/// 五档失败分派、占用二态、超时分支这三处最容易被 UI 反推着写歪，故集中在无依赖层，
/// 由 `test/nfc_write_state_test.dart` 直接钉。
///
/// **文案表逐字照原型**（`prototype/index.html` 的 `NFC_STATE_TEXT`）：改文案＝改这里一处，
/// 层内不得就地写字面量。
library;

import 'dart:convert' show Utf8Decoder;

/// 写卡层十二态（原型同序同名；`idle` 只在层外表示「未进入」）。
enum NfcWriteState {
  idle,
  waiting,
  reading,
  writing,
  done,
  occupied,
  occupiedOwn,
  errReadonly,
  errNonNdef,
  errCapacity,
  errBroken,
  errNfcOff,
}

/// 写入超时（B7/B34）：**30 秒无卡即关层**，不 toast。
///
/// B34：计时**自首次进入起算，切后台不重置**；切后台期间读卡回调**丢弃**（不缓存 tag），
/// 回前台须**重新贴**。
const int kNfcWriteTimeoutMs = 30000;

/// 成功对勾停留时长（§4.3/§4.5：done 后 1.2s 自动关层回下层）。
///
/// ⚠ 与 B39「写卡成功不自动退出/清空**弹层**」不冲突：B39 说的是**下层的编辑/绑定弹层**
/// 不得被自动关掉或清空（用户可能还没填完名称），本常量只关**写卡层自己**。
const Duration kNfcWriteDoneHold = Duration(milliseconds: 1200);

/// 写卡层两行文案（主文案 ＋ 副文案）。副文案为空＝该态不显第二行。
class NfcWriteCopy {
  const NfcWriteCopy(this.main, this.hint);

  final String main;
  final String hint;
}

/// 文案表（**逐字照原型 `NFC_STATE_TEXT`**，禁在层内重写字面量）。
const Map<NfcWriteState, NfcWriteCopy> kNfcWriteCopy = {
  NfcWriteState.waiting: NfcWriteCopy('把卡片贴到手机背面', '保持贴住不要移动'),
  NfcWriteState.reading: NfcWriteCopy('正在读这张卡…', ''),
  NfcWriteState.writing: NfcWriteCopy('正在写入…', '保持贴住不要移动'),
  NfcWriteState.done: NfcWriteCopy('已写入', '可以移开了'),
  NfcWriteState.occupied: NfcWriteCopy('这张卡里已有内容', '覆盖后原内容会消失'),
  NfcWriteState.occupiedOwn:
      NfcWriteCopy('已经是本机的卡片', '这张卡属于另一张卡片记录，只能取消'),
  NfcWriteState.errReadonly: NfcWriteCopy('这张卡是只读的', '换一张可写入的卡'),
  NfcWriteState.errNonNdef:
      NfcWriteCopy('认不出这张卡', '请用 NDEF 可写标签（NTAG213/215/216）'),
  NfcWriteState.errCapacity: NfcWriteCopy('卡片容量不足', '这张卡剩余空间放不下'),
  NfcWriteState.errBroken: NfcWriteCopy('写入中断', '把卡片贴住不要移动'),
  NfcWriteState.errNfcOff: NfcWriteCopy('系统 NFC 未开启', '去系统设置里打开后再试'),
};

/// 取某态的两行文案；`idle` 不在表内，回空文案（层内不该停在 idle）。
NfcWriteCopy nfcWriteCopyOf(NfcWriteState s) =>
    kNfcWriteCopy[s] ?? const NfcWriteCopy('', '');

/// 呼吸圆环显示判据（§4.5：等待/读/写三态才转）。
bool nfcWriteIsBusy(NfcWriteState s) =>
    s == NfcWriteState.waiting ||
    s == NfcWriteState.reading ||
    s == NfcWriteState.writing;

/// 错误态（层内换红图标 ＋ 出重试/换卡/去设置钮）。
bool nfcWriteIsError(NfcWriteState s) =>
    s == NfcWriteState.errReadonly ||
    s == NfcWriteState.errNonNdef ||
    s == NfcWriteState.errCapacity ||
    s == NfcWriteState.errBroken ||
    s == NfcWriteState.errNfcOff;

/// 占用确认态（出确认块；其中 `occupiedOwn` 只给取消）。
bool nfcWriteIsOccupy(NfcWriteState s) =>
    s == NfcWriteState.occupied || s == NfcWriteState.occupiedOwn;

/// 占用确认块是否给「覆盖写入」钮（C12：本机另一张卡**仅可取消**）。
bool nfcWriteCanOverwrite(NfcWriteState s) => s == NfcWriteState.occupied;

/// 错误态主钮文案（原型：只读＝「换卡」／系统 NFC 关＝「去设置」／其余＝「重试」）。
String nfcWriteRetryLabel(NfcWriteState s) => switch (s) {
      NfcWriteState.errReadonly => '换卡',
      NfcWriteState.errNfcOff => '去设置',
      _ => '重试',
    };

/// 30 秒超时是否生效（B7：**只对 `waiting` 生效**——已读到卡后的读/写过程不掐）。
bool nfcWriteShouldTimeout(NfcWriteState s) => s == NfcWriteState.waiting;

/// 读到标签后的下一态（§4.3 的 `reading` 分支 · **唯一分派点**）。
///
/// 判定顺序＝**非 NDEF → 只读 → 占用**：非 NDEF 的卡谈不上「可写不可写」，
/// 只读卡也谈不上「有没有内容」，顺序反了会把 B3/B4 两档文案张冠李戴。
///
/// · [hasContent]＝标签里已有 NDEF 内容；
/// · [isSelfCard]＝已有内容且解析出的 cardId **就是本卡**（重写自己的卡，不必确认）；
/// · [isOwnOtherCard]＝已有内容且 cardId 属于本机**另一张**卡（C12：仅可取消）。
NfcWriteState nfcWriteStateAfterRead({
  required bool isNdef,
  required bool isWritable,
  required bool hasContent,
  bool isSelfCard = false,
  bool isOwnOtherCard = false,
}) {
  if (!isNdef) return NfcWriteState.errNonNdef;
  if (!isWritable) return NfcWriteState.errReadonly;
  if (hasContent && !isSelfCard) {
    return isOwnOtherCard
        ? NfcWriteState.occupiedOwn
        : NfcWriteState.occupied;
  }
  return NfcWriteState.writing;
}

/// 写前容量预判（B5：**N 取系统报数，不写死**）——放不下就别写，直接给容量档。
///
/// 返回 null ＝ 容量够（继续写）；非 null ＝ 应落的错误态。
NfcWriteState? nfcWriteCapacityPrecheck({
  required int messageBytes,
  required int maxSize,
}) {
  if (maxSize <= 0) return null; // 个别标签报不出容量：不预判，交给写入报错分档
  return messageBytes > maxSize ? NfcWriteState.errCapacity : null;
}

/// 写入失败 → 错误态（F2-2：**以系统报错类别为准，不靠字符串匹配**）。
///
/// `nfc_manager` 走 Pigeon，原生异常以 `exception.javaClass.simpleName` 当
/// `PlatformException.code` 传出（见插件 `Pigeon.kt` 的 `wrapError`）⇒ 这里拿到的
/// 就是**类别本身**，不是人话 message。
///
/// 映射（Android `Ndef.writeNdefMessage` 的实际抛出面）：
/// · `TagLostException`（移开/抖动）／`IllegalStateException`（未连接）→ 写入中断；
/// · `IOException`（Not enough space 等）→ 容量不足；
/// · `FormatException`（内容不是合法 NDEF）→ 认不出这张卡；
/// · `tag_not_found`（插件 FlutterError：标签转换失败/会话已关）→ 写入中断；
/// · `nfc_disabled`（本模块 IO 层自造的哨兵：系统 NFC 未开）→ 去设置档；
/// · 其余/未知 → 写入中断（**兜底给可重试的那一档**，不给「认不出卡」这种误导档）。
NfcWriteState nfcWriteFailureOf(String? errorCode) => switch (errorCode) {
      'nfc_disabled' => NfcWriteState.errNfcOff,
      'TagLostException' => NfcWriteState.errBroken,
      'IllegalStateException' => NfcWriteState.errBroken,
      'tag_not_found' => NfcWriteState.errBroken,
      'IOException' => NfcWriteState.errCapacity,
      'FormatException' => NfcWriteState.errNonNdef,
      _ => NfcWriteState.errBroken,
    };

/// NDEF 记录 → URI 串（读侧用：判断「已有内容」与「本机另一张卡」）。
///
/// 两种合法承载：
/// · `tnf = 1`（wellKnown）且 `type = "U"`：payload 首字节是缩写码，余下是 UTF-8 尾部
///   ——**本机写入用这一支**（Android 系统唯一可靠识别的 URI 形式，见
///   `nfc_tag_io.dart` 的 `nfcUriRecordOf` 段注）；
/// · `tnf = 3`（absoluteUri）：payload 直接是 UTF-8 的 URI——**兼容别处写过的卡**，
///   读得进来，但 ⚠ 本机**不再**用此格式写（真机实锤系统解析为空、NDEF 匹配失败）。
///
/// 返回 null ＝ 本条不是 URI 记录（**不猜**：认不出就当没有）。
String? nfcUriOfNdefRecord({
  required int tnf,
  required List<int> type,
  required List<int> payload,
}) {
  if (tnf == 3) {
    return _utf8(payload);
  }
  if (tnf == 1 && type.length == 1 && type.first == 0x55 /* 'U' */) {
    if (payload.isEmpty) return null;
    final prefix = _kNdefUriPrefixes[payload.first] ?? '';
    final rest = _utf8(payload.sublist(1));
    return rest == null ? null : '$prefix$rest';
  }
  return null;
}

/// UTF-8 解码；非法字节序列返回 null（不抛——脏标签不该把写卡层炸掉）。
String? _utf8(List<int> bytes) {
  try {
    return const Utf8Decoder(allowMalformed: false).convert(bytes);
  } on FormatException {
    return null;
  }
}

/// NDEF RTD URI 缩写码表（RFC 3986 附录 · 标准 36 项）。
///
/// 我方 `lh://` 不在表内（用码 0x00＝无前缀），但**读侧必须认全表**——
/// 用户拿一张别处写过的标签来覆盖时，前缀码认不出就会把 URI 读成残串。
const Map<int, String> _kNdefUriPrefixes = {
  0x00: '',
  0x01: 'http://www.',
  0x02: 'https://www.',
  0x03: 'http://',
  0x04: 'https://',
  0x05: 'tel:',
  0x06: 'mailto:',
  0x07: 'ftp://anonymous:anonymous@',
  0x08: 'ftp://ftp.',
  0x09: 'ftps://',
  0x0A: 'sftp://',
  0x0B: 'smb://',
  0x0C: 'nfs://',
  0x0D: 'ftp://',
  0x0E: 'dav://',
  0x0F: 'news:',
  0x10: 'telnet://',
  0x11: 'imap:',
  0x12: 'rtsp://',
  0x13: 'urn:',
  0x14: 'pop:',
  0x15: 'sip:',
  0x16: 'sips:',
  0x17: 'tftp:',
  0x18: 'btspp://',
  0x19: 'btl2cap://',
  0x1A: 'btgoep://',
  0x1B: 'tcpobex://',
  0x1C: 'irdaobex://',
  0x1D: 'file://',
  0x1E: 'urn:epc:id:',
  0x1F: 'urn:epc:tag:',
  0x20: 'urn:epc:pat:',
  0x21: 'urn:epc:raw:',
  0x22: 'urn:epc:',
  0x23: 'urn:nfc:',
};
