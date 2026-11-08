/// C09 · 离线元数据补全（纯函数、纯离线、零新增网络目的地）。
///
/// 绕开「在线补全需 API Key」红线（X09）的替代路径：
/// - **扩阅读现有渠道 / 剪贴板本地解析覆盖**：从粘贴文本抽取书名 / 作者 /
///   ISBN / 章节 / 页码 / 位置 / 渠道来源，纯正则，不发起任何请求；
/// - **影音游 external_id 批量粘贴映射**：把批量粘贴的 `来源:id`、站内 URL、
///   「标题, tmdb:123」解析成本地字典条目；封面仍只本地上传（口径注）。
///
/// 本层不 import `isbn_enrich.dart`（联网豆瓣）、不构造请求 Uri、不引新依赖。
library;

/// 一条从剪贴板本地解析出的书目元数据。
class ClipboardMeta {
  const ClipboardMeta({
    this.book = '',
    this.author = '',
    this.isbn,
    this.chapter,
    this.page,
    this.loc,
    this.source = '',
  });

  final String book;
  final String author;
  final String? isbn;
  final String? chapter;
  final int? page;
  final double? loc;

  /// 渠道来源 id（weread / dedao / apple / kindle / douban …；空＝未识别）。
  final String source;

  bool get isEmpty => book.isEmpty && author.isEmpty && isbn == null;
}

final RegExp _bookRe = RegExp(r'《([^》]{1,80})》');

/// 单段剪贴板文本 → 书目元数据。坏数据返回全空（不抛、不臆造）。
ClipboardMeta parseClipboardMeta(String raw) {
  final text = raw.replaceFirst('\uFEFF', '').trim();
  if (text.isEmpty) return const ClipboardMeta();

  // ISBN：优先带标注，其次裸 13/10 位；统一大写，保留校验位 X。
  String? isbn = RegExp(
    r'ISBN\s*[-:]?\s*(97[89]\d{10}|\d{9}[\dXx])',
    caseSensitive: false,
  ).firstMatch(text)?.group(1);
  isbn ??= RegExp(r'\b(97[89]\d{10}|\d{9}[\dXx])\b').firstMatch(text)?.group(1);
  isbn = isbn?.toUpperCase();

  // 书名：《…》 > 「书名：」/「标题：」行 > 首行（短且非脚注）。
  String book = '';
  final bm = _bookRe.firstMatch(text);
  if (bm != null) {
    book = bm.group(1)!.trim();
  } else {
    final hm = RegExp(r'^[#＃]?\s*(?:书名|标题)[:：]\s*(.+)$', multiLine: true)
        .firstMatch(text);
    if (hm != null) {
      book = hm.group(1)!.trim();
    } else {
      final first = text.split('\n').first.trim();
      final looksLikeFootnote = RegExp(
        r'^(来自|原文|划线|笔记|想法|◆|--|\d+\s*个笔记)',
      ).hasMatch(first);
      if (!looksLikeFootnote && first.length <= 40) book = first;
    }
  }

  // 作者：「作者：」/「Author：」 > 《书名》（作者）括号。
  String author = '';
  final am = RegExp(
    r'(?:作者|Author)\s*[:：]\s*([^\n，,]{1,30})',
    caseSensitive: false,
  ).firstMatch(text);
  if (am != null) {
    author = am.group(1)!.trim();
  } else {
    final paren = RegExp(r'《[^》]+》\s*[（(]([^）)]{1,30})[）)]').firstMatch(text);
    if (paren != null) author = paren.group(1)!.trim();
  }

  // 渠道来源（纯本地关键词，不据此发起请求）。
  var source = '';
  if (text.contains('微信读书') || text.contains('来自微信读书')) {
    source = 'weread';
  } else if (text.contains('得到')) {
    source = 'dedao';
  } else if (RegExp(r'Apple Books|iBooks', caseSensitive: false).hasMatch(text)) {
    source = 'apple';
  } else if (RegExp(r'Kindle|My Clippings', caseSensitive: false).hasMatch(text)) {
    source = 'kindle';
  } else if (text.contains('豆瓣')) {
    source = 'douban';
  }

  final chapter = RegExp(r'(第[0-9一二三四五六七八九十百]+[章节部卷篇][^\s，。]{0,12})')
      .firstMatch(text)
      ?.group(1);
  final pm = RegExp(
    r'(?:P|页码\s*[:：]?\s*|第)(\d{1,5})\s*页?',
    caseSensitive: false,
  ).firstMatch(text);
  final page = int.tryParse(pm?.group(1) ?? '');
  final lm = RegExp(
    r'(?:位置|Location)\s*[:：]?\s*([\d,\.]+)',
    caseSensitive: false,
  ).firstMatch(text);
  final loc = double.tryParse((lm?.group(1) ?? '').replaceAll(',', ''));

  return ClipboardMeta(
    book: book,
    author: author,
    isbn: isbn,
    chapter: chapter,
    page: page,
    loc: loc,
    source: source,
  );
}

/// 批量粘贴：按空行分块逐段解析，过滤全空块（保序）。
List<ClipboardMeta> parseClipboardBatch(String raw) {
  final out = <ClipboardMeta>[];
  for (final block in raw.split(RegExp(r'\n\s*\n'))) {
    final m = parseClipboardMeta(block);
    if (!m.isEmpty) out.add(m);
  }
  return List<ClipboardMeta>.unmodifiable(out);
}

/// 一行是否是 external_id / 站内 URL（用于把「影音游批量粘贴」挡在建书之外）。
/// 来源集合复用 [kExternalIdSources]，避免两处名单漂移。
final String _extSrcAlt = kExternalIdSources.map(RegExp.escape).join('|');
final RegExp _extIdLineRe = RegExp(
  '^(?:$_extSrcAlt)\\s*[:：=]?\\s*[A-Za-z0-9_]+\$',
  caseSensitive: false,
);
final RegExp _extIdAnywhereRe = RegExp(
  '\\b(?:$_extSrcAlt)\\s*[:：=]\\s*[A-Za-z0-9_]+',
  caseSensitive: false,
);
final RegExp _urlLineRe = RegExp(
  r'^(?:https?://|www\.)\S+$',
  caseSensitive: false,
);

/// 这行文本是 external_id 映射/URL 而非书名（导入页据此分流预览）。
bool looksLikeExternalIdLine(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return false;
  return _extIdLineRe.hasMatch(s) ||
      _extIdAnywhereRe.hasMatch(s) ||
      _urlLineRe.hasMatch(s);
}

/// 渠道 id → 中文来源名（建书 `source` 列用；空/未知＝「离线粘贴」）。
String clipboardSourceLabel(String id) => switch (id) {
      'weread' => '微信读书',
      'dedao' => '得到',
      'apple' => 'Apple Books',
      'kindle' => 'Kindle',
      'douban' => '豆瓣',
      _ => '离线粘贴',
    };

/// 批量粘贴书目元数据 → 建书行（书名 / 作者 / ISBN）。
///
/// 导入页「批量粘贴 · 离线解析」的确认写入只吃这三列：章节/页码/位置是
/// **摘录级**字段，建书阶段无处可落，不塞进书名（不臆造）。
/// 无书名的块跳过；external_id / URL 行也跳过（它们是影音游映射，不是书）。
List<({String title, String author, String? isbn})> clipboardBookRows(
  List<ClipboardMeta> metas,
) {
  final out = <({String title, String author, String? isbn})>[];
  for (final m in metas) {
    final title = m.book.trim();
    if (title.isEmpty || looksLikeExternalIdLine(title)) continue;
    out.add((title: title, author: m.author.trim(), isbn: m.isbn));
  }
  return List<({String title, String author, String? isbn})>.unmodifiable(out);
}

/// 影音游本地 external_id 字典键（纯离线标识，**不据此发起任何请求**）。
const Set<String> kExternalIdSources = <String>{
  'tmdb', 'igdb', 'imdb', 'douban', 'bangumi', 'steam', 'anilist', 'trakt',
};

/// 一条批量粘贴映射出的 external_id 条目。
class ExternalIdEntry {
  const ExternalIdEntry({
    required this.source,
    required this.id,
    this.title = '',
  });

  final String source;
  final String id;
  final String title;
}

final RegExp _pairRe = RegExp(
  r'\b(tmdb|igdb|imdb|douban|bangumi|steam|anilist|trakt)\s*[:：=]?\s*([A-Za-z0-9_]+)',
  caseSensitive: false,
);

/// 站内 URL → (正则, 来源 id)。只做**字符串匹配**，不是网络目的地。
final List<(RegExp, String)> _urlRules = <(RegExp, String)>[
  (RegExp(r'(?:themoviedb\.org|tmdb\.org)/(?:movie|tv)/(\d+)'), 'tmdb'),
  (RegExp(r'movie\.douban\.com/subject/(\d+)'), 'douban'),
  (RegExp(r'store\.steampowered\.com/app/(\d+)'), 'steam'),
  (RegExp(r'imdb\.com/title/(tt\d+)'), 'imdb'),
  (RegExp(r'(?:bgm\.tv|bangumi\.tv)/subject/(\d+)'), 'bangumi'),
];

/// 批量粘贴映射：每行支持
///   `tmdb:123` · `imdb tt1234567` · `标题, douban:123` · 站内 URL。
/// 未知来源 / 空行 / 注释一律跳过；同 (source,id) 去重保序。
/// 纯离线：只产出字典条目，不查库、不联网，封面仍只本地上传。
List<ExternalIdEntry> parseExternalIdBatch(String raw) {
  final out = <ExternalIdEntry>[];
  final seen = <String>{};

  void add(String src, String id, String title) {
    if (id.isEmpty || !kExternalIdSources.contains(src)) return;
    final key = '$src:$id';
    if (!seen.add(key)) return;
    out.add(ExternalIdEntry(source: src, id: id, title: title.trim()));
  }

  for (final line in raw.split(RegExp(r'\r?\n'))) {
    final s = line.trim();
    if (s.isEmpty || s.startsWith('#')) continue;

    // 1) 站内 URL（先于 kv 对，避免把域名里的字母误当来源前缀）。
    var handled = false;
    for (final rule in _urlRules) {
      final re = rule.$1;
      final src = rule.$2;
      final m = re.firstMatch(s);
      if (m != null) {
        final rest = s
            .replaceAll(m.group(0)!, '')
            .replaceAll(RegExp(r'[,，\s]+'), ' ')
            .trim();
        add(src, m.group(1)!, rest);
        handled = true;
        break;
      }
    }
    if (handled) continue;

    // 2) 「来源:id」对（可带标题）。
    final m = _pairRe.firstMatch(s);
    if (m == null) continue;
    final src = m.group(1)!.toLowerCase();
    final id = m.group(2)!;
    final title = s
        .replaceAll(m.group(0)!, '')
        .replaceAll(RegExp(r'^[,\-—:：\s]+|[,\-—:：\s]+$'), '')
        .trim();
    add(src, id, title);
  }
  return List<ExternalIdEntry>.unmodifiable(out);
}
