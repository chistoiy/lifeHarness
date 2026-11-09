// M5 · 导入歌单纯本地解析（零网络、零新增依赖、零 DB 迁移 · 2026-11-08）。
//
// 支持：m3u（`#EXTINF:` 元数据行被忽略）、每行一首、「艺人 - 曲目」取曲名、
// `1. ` 序号前缀、CRLF/LF/CR 混排；忽略 `#` 注释与空行、去重保序。
// 纯函数＝不读时钟、不碰 IO、不 import 任何包，供 test/m5_listen_test.dart 直接下判。

/// 把粘贴/导入的歌单文本解析成曲目名列表（去重、保序、去首尾空白）。
List<String> parsePlaylistText(String raw) {
  final out = <String>[];
  final seen = <String>{};
  for (final line in raw.split(RegExp(r'\r\n|\n|\r'))) {
    final t = line.trim();
    if (t.isEmpty || t.startsWith('#')) continue;
    final title = _trackTitle(t);
    if (title.isEmpty) continue;
    final key = title.toLowerCase();
    if (seen.add(key)) out.add(title);
  }
  return out;
}

String _trackTitle(String line) {
  var s = line.replaceFirst(RegExp(r'^\d+[\.、)）]\s*'), '');
  final dash = s.indexOf(' - ');
  if (dash >= 0) s = s.substring(dash + 3);
  return s.trim();
}

/// 听后感流时间戳（createdAt 毫秒 → `yyyy-MM-dd HH:mm`）；非正时刻＝空串。
/// 纯函数，测试可注入固定时刻。
String m5FormatStamp(int ms) {
  if (ms <= 0) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} '
      '${two(d.hour)}:${two(d.minute)}';
}
