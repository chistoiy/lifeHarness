/// NFC 标签**内容**的解析与重建（批3 · 卡片内容工具：读取 / 修改 / 清空）。
///
/// 与 `nfc_write_state.dart` 同一定位：**纯域层、零插件依赖**——`nfc_tag_io.dart`
/// 负责把插件的 `NdefRecord` 翻成这里的 [NfcRawRecord]，UI 只认这里的模型。
/// 于是「base64 判定」「URI 前缀还原」「文本记录重建」全都能在无硬件环境纯测。
///
/// 三条口径写在最前：
/// · **原文优先**：展示一律先给「卡片里实际存的那串」（[NfcContentRecord.text]），
///   base64 的再把解码结果作为副行（[NfcContentRecord.decodedText]）——不替用户猜。
/// · **改哪个、写哪个**：base64 卡让用户改**解码后的可读文本**，写回时按原样重新
///   base64（产品口径「按原样加密写回去」）；非 base64 卡直接改原文。
/// · **AAR 不可改**：`android.com:pkg` 是让系统拉起本 App 的锚点，改掉等于把卡写废；
///   该记录只读展示（[NfcContentRecord.editable]＝false）。
library;

import 'dart:convert';
import 'dart:typed_data';

/// 记录类型（只区分「用户看得懂」的四类；其余一律 [other]）。
enum NfcContentKind {
  /// RTD-URI（`tnf=1` ＋ type `U`）或 `tnf=3` 绝对 URI。
  uri,

  /// RTD-Text（`tnf=1` ＋ type `T`）。
  text,

  /// Android Application Record（`tnf=4` ＋ type `android.com:pkg`）。
  aar,

  /// 其它（MIME／外部类型／未知）——只读展示。
  other,
}

/// 一条**原始** NDEF 记录（插件对象的纯数据镜像；`tnf` 用数值，域层不认插件枚举）。
class NfcRawRecord {
  const NfcRawRecord({
    required this.tnf,
    required this.type,
    required this.payload,
  });

  /// NDEF TNF 数值（0 EMPTY / 1 WELL_KNOWN / 2 MIME / 3 ABSOLUTE_URI /
  /// 4 EXTERNAL / 5 UNKNOWN / 6 UNCHANGED）。
  final int tnf;

  /// 类型字段的原始字节（RTD-URI 是 `0x55`、RTD-Text 是 `0x54`、AAR 是 ASCII
  /// `android.com:pkg`、MIME 是 `text/plain` 这种）。
  final Uint8List type;

  /// 载荷原始字节（**写回时以它为准**：改内容只换 payload，tnf/type 一字不动）。
  final Uint8List payload;

  /// 类型字段的 UTF-8 读法（AAR/MIME 这类 ASCII 类型串用）。
  String get typeText => utf8.decode(type, allowMalformed: true);
}

/// 一条**给人看**的记录（解析结果）。
class NfcContentRecord {
  const NfcContentRecord({
    required this.index,
    required this.kind,
    required this.typeLabel,
    required this.text,
    required this.editable,
    this.decodedText,
    this.hex,
  });

  /// 在原始消息里的下标（写回时按它定位）。
  final int index;

  final NfcContentKind kind;

  /// 类型标签（「网址」「文本」「本 App 绑定」「MIME · text/plain」…）。
  final String typeLabel;

  /// **原文**：卡片里实际存的那串（URI 记录已还原前缀码，文本记录已剥语言码）。
  final String text;

  /// 是否允许在工具里改这一条。
  final bool editable;

  /// base64 卡才有的「解码后可读文本」；不是 base64 一律 null。
  final String? decodedText;

  /// 既不是文本也不是 base64 时给的十六进制串（只读，供排障）。
  final String? hex;

  /// 这条是不是 base64（决定编辑框里显示原文还是解码文、以及写回要不要再编码）。
  bool get isBase64 => decodedText != null;

  /// 编辑框的初值：base64 卡给解码文（改完按原样编码回去），否则给原文。
  String get editValue => decodedText ?? text;
}

/// 一张卡的内容视图。
class NfcTagContent {
  const NfcTagContent({required this.records, required this.raw});

  /// 给人看的记录（顺序＝原始顺序）。
  final List<NfcContentRecord> records;

  /// 原始记录（写回时的底稿：**未编辑的记录原样带回去**，不做任何重编码）。
  final List<NfcRawRecord> raw;

  bool get isEmpty => raw.isEmpty;

  /// 第一条可编辑记录的序号（没有则 null）。
  int? get firstEditableIndex {
    for (final r in records) {
      if (r.editable) return r.index;
    }
    return null;
  }

  /// 是否含 base64 内容（UI 用来决定要不要提示「将按原样编码写回」）。
  bool get hasBase64 => records.any((r) => r.isBase64);

  /// 是否是本 App 的卡片（`lh://nfc/...`）——改内容会让卡片失效，须提示。
  bool get isLifeHarnessCard => records.any(
        (r) => r.kind == NfcContentKind.uri && r.text.startsWith('lh://nfc/'),
      );

  /// 空内容（清空后的态）。
  static const NfcTagContent empty =
      NfcTagContent(records: <NfcContentRecord>[], raw: <NfcRawRecord>[]);
}

/// RTD-URI 的前缀码表（NDEF 规范 0x00~0x23；表外码一律按 0x00「无前缀」处理）。
const List<String> kNdefUriPrefixes = <String>[
  '', // 0x00 无前缀（完整 URI）
  'http://www.',
  'https://www.',
  'http://',
  'https://',
  'tel:',
  'mailto:',
  'ftp://anonymous:anonymous@',
  'ftp://ftp.',
  'ftps://',
  'sftp://',
  'smb://',
  'nfs://',
  'ftp://',
  'dav://',
  'news:',
  'telnet://',
  'imap:',
  'rtsp://',
  'urn:',
  'pop:',
  'sip:',
  'sips:',
  'tftp:',
  'btspp://',
  'btl2cap://',
  'btgoep://',
  'tcpobex://',
  'irdaobex://',
  'file://',
  'urn:epc:id:',
  'urn:epc:tag:',
  'urn:epc:pat:',
  'urn:epc:raw:',
  'urn:epc:',
  'urn:nfc:',
];

/// AAR 的类型串（与 `nfc_tag_io.dart` 的 `kNfcAarType` 同值；此处独立定义避免
/// 域层反向依赖 data 层）。
const String kNfcAarTypeName = 'android.com:pkg';

/// 把原始记录解析成可展示/可编辑的视图。
NfcTagContent nfcContentOf(List<NfcRawRecord> raw) {
  // ⚠ **TNF=EMPTY 记录一律过滤**（2026-10-17 真机实锤）：本模块「清空」写的正是
  // 一条 EMPTY 记录。它不承载内容，却**排在首位时会让整条消息在系统眼里是空的**
  // ——Android 的 NfcDispatcher 按**首条记录**取 URI／判类型，首条是 EMPTY ⇒
  // 读回来显示「类型 0（空）」（真机复现：清空→写入→再读＝空）。
  // 过滤后：① 清空过的卡读回如实显示为空；② 再写内容时底稿里已没有那条 EMPTY，
  // 新记录自然成为首条，不会再「追加在 EMPTY 后面仍读成空」。
  final kept = <NfcRawRecord>[
    for (final r in raw)
      if (r.tnf != 0) r,
  ];
  final out = <NfcContentRecord>[];
  for (var i = 0; i < kept.length; i++) {
    out.add(_recordOf(i, kept[i]));
  }
  return NfcTagContent(records: out, raw: kept);
}

NfcContentRecord _recordOf(int index, NfcRawRecord r) {
  // ---- AAR：只读（改掉＝卡废）----
  if (r.tnf == 4 && r.typeText == kNfcAarTypeName) {
    final pkg = utf8.decode(r.payload, allowMalformed: true);
    return NfcContentRecord(
      index: index,
      kind: NfcContentKind.aar,
      typeLabel: '本 App 绑定',
      text: pkg,
      editable: false,
    );
  }

  // ---- RTD-URI（tnf=1 ＋ type 'U'）----
  if (r.tnf == 1 && r.type.length == 1 && r.type[0] == 0x55) {
    final uri = _uriOfPayload(r.payload);
    return _textish(index, NfcContentKind.uri, '网址', uri);
  }

  // ---- 绝对 URI（tnf=3，payload 就是完整 URI）----
  if (r.tnf == 3) {
    final uri = utf8.decode(r.payload, allowMalformed: true);
    return _textish(index, NfcContentKind.uri, '网址', uri);
  }

  // ---- RTD-Text（tnf=1 ＋ type 'T'）----
  if (r.tnf == 1 && r.type.length == 1 && r.type[0] == 0x54) {
    final t = _textOfPayload(r.payload);
    return _textish(index, NfcContentKind.text, '文本', t);
  }

  // ---- 其余：只读 ----
  final typeLabel = r.tnf == 2
      ? 'MIME · ${r.typeText}'
      : r.tnf == 4
          ? '外部 · ${r.typeText}'
          : '类型 ${r.tnf}';
  final asText = utf8.decode(r.payload, allowMalformed: true);
  final printable = _printableRatio(asText) >= 0.9 && asText.trim().isNotEmpty;
  return NfcContentRecord(
    index: index,
    kind: NfcContentKind.other,
    typeLabel: typeLabel,
    text: printable ? asText : _hexOf(r.payload),
    editable: false,
    hex: printable ? null : _hexOf(r.payload),
  );
}

/// 文本类记录（URI / 文本）统一构造：顺带判 base64。
NfcContentRecord _textish(
  int index,
  NfcContentKind kind,
  String typeLabel,
  String text,
) {
  final decoded = decodeBase64Text(text);
  return NfcContentRecord(
    index: index,
    kind: kind,
    typeLabel: typeLabel,
    text: text,
    editable: true,
    decodedText: decoded,
  );
}

/// RTD-URI 载荷 → 完整 URI（首字节是前缀码；表外码按「无前缀」容错）。
String _uriOfPayload(Uint8List payload) {
  if (payload.isEmpty) return '';
  final code = payload[0];
  final prefix = code < kNdefUriPrefixes.length ? kNdefUriPrefixes[code] : '';
  return prefix + utf8.decode(payload.sublist(1), allowMalformed: true);
}

/// RTD-Text 载荷 → 纯文本（首字节＝状态位：bit7 UTF-16、低 6 位语言码长度）。
String _textOfPayload(Uint8List payload) {
  if (payload.isEmpty) return '';
  final status = payload[0];
  final langLen = status & 0x3F;
  final utf16 = (status & 0x80) != 0;
  if (1 + langLen > payload.length) return '';
  final body = payload.sublist(1 + langLen);
  if (!utf16) return utf8.decode(body, allowMalformed: true);
  // UTF-16：按 2 字节大端还原（标签上极少见，容错读，不做半字符处理）。
  final units = <int>[];
  for (var i = 0; i + 1 < body.length; i += 2) {
    units.add((body[i] << 8) | body[i + 1]);
  }
  return String.fromCharCodes(units);
}

/// base64 形态判定（**保守**：宁可漏判成普通文本，也不把普通文本误判成 base64）。
///
/// 四条同时满足才算：① 去空白后长度 ≥8 且 4 的整数倍；② 字符集合法（含 url-safe
/// 变体）；③ 能解码且解码结果是非空合法 UTF-8；④ 解码结果可打印比例 ≥0.9。
/// 另加一条「回环自证」：重新编码必须与原串逐字相同（挡住「看着像但其实不是」）。
String? decodeBase64Text(String s) {
  final t = s.trim();
  if (t.length < 8 || t.length % 4 != 0) return null;
  if (!RegExp(r'^[A-Za-z0-9+/_-]+={0,2}$').hasMatch(t)) return null;
  final normalized = t.replaceAll('-', '+').replaceAll('_', '/');
  try {
    final bytes = base64.decode(normalized);
    if (bytes.isEmpty) return null;
    final text = utf8.decode(bytes);
    if (text.trim().isEmpty) return null;
    if (_printableRatio(text) < 0.9) return null;
    // 回环自证：能被规范地重新编码回同一串，才认这是 base64。
    if (base64.encode(bytes) != normalized) return null;
    return text;
  } catch (_) {
    // catch-ok: 解码失败／非 UTF-8 ⇒ 不是 base64，调用方按普通文本处理。
    return null;
  }
}

/// 可打印字符比例（控制字符计入不可打印；换行/制表算可打印）。
double _printableRatio(String s) {
  if (s.isEmpty) return 0;
  var ok = 0;
  for (final r in s.runes) {
    if (r == 0x0A || r == 0x0D || r == 0x09) {
      ok++;
    } else if (r >= 0x20 && r != 0x7F) {
      ok++;
    }
  }
  return ok / s.runes.length;
}

String _hexOf(Uint8List b) {
  final sb = StringBuffer();
  for (var i = 0; i < b.length; i++) {
    if (i > 0) sb.write(' ');
    sb.write(b[i].toRadixString(16).padLeft(2, '0').toUpperCase());
  }
  return sb.toString();
}

/// 把「用户编辑后的可读文本」写回某条记录 → 新的原始记录（tnf/type 原样保留）。
///
/// · [NfcContentKind.uri]：沿用原记录的前缀码（编辑后仍以该前缀开头才沿用，否则
///   退回 0x00 全量写），保证写回形态与原来一致。
/// · [NfcContentKind.text]：沿用原记录的状态位与语言码（只换正文）。
/// · 其它：直接 UTF-8 覆盖 payload。
///
/// base64 的「编码回去」由调用方先做（见 [encodeBase64Text]）——本函数只管
/// 「文本 → 记录字节」，不掺业务判断。
NfcRawRecord nfcRecordWithText(NfcRawRecord orig, String text) {
  final bytes = utf8.encode(text);
  if (orig.tnf == 1 && orig.type.length == 1 && orig.type[0] == 0x55) {
    final code = orig.payload.isEmpty ? 0 : orig.payload[0];
    final prefix = code < kNdefUriPrefixes.length ? kNdefUriPrefixes[code] : '';
    final keep = prefix.isNotEmpty && text.startsWith(prefix);
    return NfcRawRecord(
      tnf: orig.tnf,
      type: orig.type,
      payload: Uint8List.fromList([
        keep ? code : 0,
        ...utf8.encode(keep ? text.substring(prefix.length) : text),
      ]),
    );
  }
  if (orig.tnf == 1 && orig.type.length == 1 && orig.type[0] == 0x54) {
    // 保留原状态位与语言码（长度按原 payload 里实际的语言段取，越界则退回 en）。
    final status = orig.payload.isEmpty ? 0x02 : orig.payload[0];
    final langLen = orig.payload.isEmpty ? 2 : (status & 0x3F);
    final lang = (1 + langLen <= orig.payload.length)
        ? orig.payload.sublist(1, 1 + langLen)
        : Uint8List.fromList(const [0x65, 0x6E]); // 'en'
    return NfcRawRecord(
      tnf: orig.tnf,
      type: orig.type,
      payload: Uint8List.fromList([
        orig.payload.isEmpty ? 0x02 : status,
        ...lang,
        ...bytes,
      ]),
    );
  }
  return NfcRawRecord(tnf: orig.tnf, type: orig.type, payload: Uint8List.fromList(bytes));
}

/// 文本 → base64（写回 base64 卡用）。
String encodeBase64Text(String s) => base64.encode(utf8.encode(s));

/// 新建一条 **RTD-URI 记录**（`tnf=1` ＋ type `U` ＋ `[0x00]+uri`）。
///
/// 前缀码取 `0x00`（「无前缀，后面就是完整 URI」）——`lh://`、`http://` 这类
/// 都不在 NDEF 缩写表内，用 `0x00` 才是 Android `NdefRecord.createUri` 同口径。
/// **存网址必须用这条**：存成文本记录系统不认，贴卡不会拉起 App（真机实锤）。
NfcRawRecord nfcNewUriRecord(String uri) => NfcRawRecord(
      tnf: 1,
      type: Uint8List.fromList(const [0x55]), // 'U'
      payload: Uint8List.fromList([0, ...utf8.encode(uri)]),
    );

/// 新建一条 **RTD-Text 记录**（`tnf=1` ＋ type `T` ＋ `[0x02 'en'] + 正文`）。
NfcRawRecord nfcNewTextRecord(String text) {
  final body = Uint8List(3 + utf8.encode(text).length);
  body[0] = 0x02; // 状态位：UTF-8 ＋ 语言码 2 字节
  body[1] = 0x65; // 'e'
  body[2] = 0x6E; // 'n'
  body.setRange(3, 3 + utf8.encode(text).length, utf8.encode(text));
  return NfcRawRecord(tnf: 1, type: Uint8List.fromList(const [0x54]), payload: body);
}

/// 清空后的记录集：**一条 TNF=EMPTY 空记录**（合法 NDEF、读侧 `firstUriOf` 得 null）。
///
/// 为什么不写「零记录」：Android 的 `Ndef.writeNdefMessage` 对空消息的行为各 ROM
/// 不一致（有的直接抛），而一条 EMPTY 记录是规范内的合法「无内容」形态，稳定可写。
List<NfcRawRecord> nfcEmptyRecords() => <NfcRawRecord>[
      NfcRawRecord(
        tnf: 0,
        type: Uint8List(0),
        payload: Uint8List(0),
      ),
    ];
