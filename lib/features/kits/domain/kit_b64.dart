/// 小工具合集 · Base64 转换纯计算（批3）。
///
/// 四类转换（图→串 / 串→图 / 文本→串 / 串→文本）全部走 `dart:convert` 的真实
/// UTF-8 + Base64 通道，界面上的字符数与体积都是实算；错误口径逐条对齐原型
/// （非法字符 / 长度非 4 倍数 / 解码失败），留痕结构与 `KITS.b64Recent`·
/// `KITS.b64Hist` 同构（近期 8 条 · 记录 6 条）。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'kit_calc.dart' show kitBytesText, kitRelText;

/// 四个 tab（原型 `b64Tab` 的 M 映射）。
const String kKitB64TabEnc = 'enc';
const String kKitB64TabDec = 'dec';
const String kKitB64TabTextEnc = 'xenc';
const String kKitB64TabTextDec = 'xdec';

const List<String> kKitB64Tabs = [
  kKitB64TabEnc,
  kKitB64TabDec,
  kKitB64TabTextEnc,
  kKitB64TabTextDec,
];

String kitB64TabLabel(String tab) => switch (tab) {
  kKitB64TabEnc => '图片 → Base64',
  kKitB64TabDec => 'Base64 → 图片',
  kKitB64TabTextEnc => '文本 → Base64',
  _ => 'Base64 → 文本',
};

/// 留痕条数上限（原型 `slice(0,8)` / `slice(0,6)`）。
const int kKitB64RecentMax = 8;
const int kKitB64HistMax = 6;

/// 示例 data URI（24×24 PNG · 真图字节，供「填入示例」一键还原验证）。
const String kKitB64SampleDataUri =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABgAAAAYCAIAAABvFaqv'
    'AAAAQklEQVR42mNMTvvIQA3AxEAlwAKh5szkw6UiJf0TXV00atCINohxsGYRgoBgHqK7i7BmYGRn'
    'jiZIagc2nkQwjLMIAH6oD6c8/hcIAAAAAElFTkSuQmCC';

/// 拆分输入：是否带 data URI 前缀 + 裸串（去掉前缀与空白/引号）。
({bool hasUri, String mime, String raw}) kitB64Split(String input) {
  final v = input.trim();
  final hasUri = v.startsWith('data:');
  final mime = hasUri
      ? RegExp(r'^data:([^;,]*)').firstMatch(v)?.group(1) ?? ''
      : '';
  final raw = v
      .replaceFirst(RegExp(r'^data:[^;]*;base64,'), '')
      // 原型只清洗空白与成对引号；三引号原始串才能同时装下 " 和 '。
      .replaceAll(RegExp(r'''[\s"']'''), '');
  return (hasUri: hasUri, mime: mime, raw: raw);
}

/// 补 data URI 前缀（原型 `b64Copy('prefix')`：缺前缀时按 png 补）。
String kitB64AddPrefix(String input) {
  final s = kitB64Split(input);
  if (s.hasUri) return input.trim();
  return 'data:image/png;base64,${s.raw}';
}

/// 裸串合法性校验（返回 null=通过；否则给原型同款错误文案）。
String? kitB64Validate(String raw) {
  if (raw.isEmpty) return '先粘贴 Base64 字符串';
  if (RegExp(r'[^A-Za-z0-9+/=]').hasMatch(raw)) {
    return '含非法 Base64 字符 · 仅允许 A-Z a-z 0-9 + / =';
  }
  if (raw.length % 4 != 0) return '长度不是 4 的倍数 · 串可能被截断';
  return null;
}

/// 文本 → Base64（UTF-8 字节真实编码）。
String kitB64EncodeText(String text) => base64Encode(utf8.encode(text));

/// Base64 → 文本；非法或截断返回 null（屏侧按原型文案报错）。
String? kitB64DecodeText(String raw) {
  try {
    return utf8.decode(base64Decode(raw));
  } catch (_) {
    return null;
  }
}

/// Base64 → 字节（图片流）；非法返回 null。
Uint8List? kitB64DecodeBytes(String raw) {
  try {
    return base64Decode(raw);
  } catch (_) {
    return null;
  }
}

/// 字节 → 裸 Base64。
String kitB64EncodeBytes(List<int> bytes) => base64Encode(bytes);

/// 拼 data URI（原型 `data:image/png;base64,` 口径，mime 缺省按 png）。
String kitB64DataUri(String raw, {String mime = 'image/png'}) =>
    'data:$mime;base64,$raw';

/// 文本 tab 的计数行（原型 `#b64TxtMeta`，「字」按 UTF-16 长度计=原型 str.length）。
String kitB64Meta({required String text}) {
  final bytes = utf8.encode(text).length;
  return '${text.length} 字 · UTF-8 $bytes B · '
      'Base64 ${text.isEmpty ? 0 : kitB64EncodeText(text).length} 字符';
}

/// 图片 tab 的产出说明行（原型 `#b64OutLen`）。
String kitB64OutLenText({required int srcBytes, required int b64Len}) {
  final kb = b64Len / 1024;
  return '原文件 ${kitBytesText(srcBytes)} · Base64 $b64Len 字符 ≈ '
      '${kb < 10 ? kb.toStringAsFixed(1) : kb.toStringAsFixed(0)} KB（约 +33%）';
}

/// 串头预览（原型 `raw.slice(0,180)`）。
String kitB64Peek(String raw, {int len = 180}) =>
    raw.length <= len ? raw : '${raw.substring(0, len)} …';

/// 近期转换一项（原型 `KITS.b64Recent` 元素）。
class KitB64Recent {
  const KitB64Recent({
    required this.name,
    required this.size,
    required this.len,
    required this.ts,
  });

  final String name;
  final int size;
  final int len;
  final int ts;

  String text(DateTime now) =>
      '$name · ${kitBytesText(size)} → ${kitBytesText(len)}'
      '${size == 0 ? ' · 空文件' : ''} · ${kitRelText(ts, now)}';

  Map<String, Object?> toJson() => {
    'name': name,
    'size': size,
    'len': len,
    'ts': ts,
  };

  static KitB64Recent fromJson(Map<String, Object?> j) => KitB64Recent(
    name: j['name'] as String? ?? '',
    size: (j['size'] as num?)?.toInt() ?? 0,
    len: (j['len'] as num?)?.toInt() ?? 0,
    ts: (j['ts'] as num?)?.toInt() ?? 0,
  );
}

/// 操作记录一项（原型 `KITS.b64Hist` 元素）。
class KitB64Log {
  const KitB64Log({required this.t, required this.ok, required this.ts});

  final String t;
  final bool ok;
  final int ts;

  String mark() => ok ? '✔' : '✖';

  Map<String, Object?> toJson() => {'t': t, 'ok': ok, 'ts': ts};

  static KitB64Log fromJson(Map<String, Object?> j) => KitB64Log(
    t: j['t'] as String? ?? '',
    ok: j['ok'] == true,
    ts: (j['ts'] as num?)?.toInt() ?? 0,
  );
}

/// 头部插入并截断（原型 unshift + slice）。
List<T> kitB64Push<T>(List<T> list, T item, int max) =>
    <T>[item, ...list].take(max).toList();

/// 落库结构（`kit_tool_data.tool='b64'`）。
Map<String, Object?> kitB64Encode({
  required List<KitB64Recent> recent,
  required List<KitB64Log> hist,
}) => {
  'b64Recent': [for (final e in recent) e.toJson()],
  'b64Hist': [for (final e in hist) e.toJson()],
};

class KitB64State {
  const KitB64State({required this.recent, required this.hist});

  final List<KitB64Recent> recent;
  final List<KitB64Log> hist;

  static KitB64State decode(Map<String, Object?> d) => KitB64State(
    recent: _list(d['b64Recent'], KitB64Recent.fromJson),
    hist: _list(d['b64Hist'], KitB64Log.fromJson),
  );

  static List<T> _list<T>(Object? raw, T Function(Map<String, Object?>) f) {
    if (raw is! List) return const [];
    return [
      for (final e in raw)
        if (e is Map<String, Object?>) f(e),
    ];
  }
}
