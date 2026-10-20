import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// 导入渠道数据包（计划 §5 · `assets/read_import/*.json`）。
///
/// 口径：
/// - 格式表不写死在 Dart 常量：渠道 id、字段映射、去重键、示例片段全部走资源包，
///   格式漂移只换包不改码（需求清单「解析器数据包」插件化方向）；
/// - 解析引擎按 [ImportChannel.parser] 分发五类：
///   `kindle`（My Clippings.txt 块）· `csv`（表头别名映射）· `json`（数组/对象）·
///   `clip`（剪贴板模板正则·命名组）· `md`（`#` 书名 + `>` 引用块卡片）；
/// - `none`＝授权/电脑端/API 通道，UI 只给指引与粘贴兜底。
class ImportChannel {
  const ImportChannel({
    required this.id,
    required this.cat,
    required this.name,
    required this.fmt,
    this.fields = '',
    this.dedupKey = '',
    this.parser = 'none',
    this.kind = 'clips',
    this.config = const {},
    this.sample = '',
    this.hint = '',
  });

  final String id;

  /// auth|pc|api|file|clip（计划 §5 五类）。
  final String cat;
  final String name;

  /// 格式说明（渠道卡副标题）。
  final String fmt;

  /// 可带字段说明。
  final String fields;

  /// 去重键说明（预览卡显示）。
  final String dedupKey;
  final String parser;

  /// clips＝摘录导入；booklist＝按清单建书。
  final String kind;

  /// 解析器参数（alias/pattern/root…）。
  final Map<String, Object?> config;

  /// 示例片段（UI「粘贴示例」按钮）。
  final String sample;

  /// auth/pc/api 通道的操作指引。
  final String hint;

  static ImportChannel fromJson(Map<String, Object?> j) => ImportChannel(
    id: j['id'] as String,
    cat: (j['cat'] as String?) ?? 'file',
    name: j['name'] as String,
    fmt: (j['fmt'] as String?) ?? '',
    fields: (j['fields'] as String?) ?? '',
    dedupKey: (j['dedupKey'] as String?) ?? '',
    parser: (j['parser'] as String?) ?? 'none',
    kind: (j['kind'] as String?) ?? 'clips',
    config: ((j['config'] as Map?) ?? const {}).cast<String, Object?>(),
    sample: (j['sample'] as String?) ?? '',
    hint: (j['hint'] as String?) ?? '',
  );
}

/// 数据包：manifest 列分文件，逐文件合并渠道。
class ImportPack {
  ImportPack(this.channels);

  final List<ImportChannel> channels;

  static const catOrder = ['auth', 'pc', 'api', 'file', 'clip'];
  static const catLabels = {
    'auth': '授权导入',
    'pc': '电脑端',
    'api': 'API',
    'file': '文件导入',
    'clip': '剪贴板',
  };

  ImportChannel? byId(String id) =>
      channels.where((c) => c.id == id).firstOrNull;

  List<ImportChannel> ofCat(String cat) =>
      channels.where((c) => c.cat == cat).toList();

  static Future<ImportPack> load({
    Future<String> Function(String path)? read,
  }) async {
    final reader = read ?? rootBundle.loadString;
    final man = jsonDecode(
      await reader('assets/read_import/manifest.json'),
    ) as List;
    final all = <ImportChannel>[];
    for (final f in man) {
      final j = jsonDecode(await reader('assets/read_import/$f'))
          as Map<String, dynamic>;
      for (final c in (j['channels'] as List)) {
        all.add(ImportChannel.fromJson(Map<String, Object?>.from(c)));
      }
    }
    return ImportPack(all);
  }
}

/// 一条已解析、尚未落库的摘录。
class ParsedClip {
  ParsedClip({
    required this.book,
    this.author = '',
    this.isbn,
    this.chapter,
    this.page,
    this.loc,
    this.body = '',
    this.thought,
    this.at,
  });

  final String book;
  final String author;
  final String? isbn;
  final String? chapter;
  final int? page;
  final double? loc;
  final String body;
  final String? thought;
  final DateTime? at;
}

/// 按清单建书的一条底稿。
class ParsedBookRow {
  ParsedBookRow({required this.title, this.author = '', this.isbn});
  final String title;
  final String author;
  final String? isbn;
}

/// 预览行：解析结果 + 一二级书匹配（[bookId] null＝需建档）+ 三级摘录查重。
class ImportRow {
  ImportRow(this.clip, this.bookId, this.dup);
  final ParsedClip clip;
  final String? bookId;
  final bool dup;
}

/// 整批落库结果（[ids] 供「撤销本批」硬删）。
typedef ImportOutcome
    = ({int added, int skipped, int booksCreated, List<int> ids});

// ---- 归一化工具（三级去重之 1/2 级共用）----

/// ISBN 归一：只留数字与校验位 X，忽略连字符与空格。
String normIsbn(String? raw) =>
    (raw ?? '').toUpperCase().replaceAll(RegExp(r'[^0-9X]'), '');

/// 书名/作者归一：去《》〈〉「」与空白标点、转小写。
String normTitle(String? raw) => (raw ?? '')
    .replaceAll(RegExp(r'[《》〈〉「」『』\s\-—_·:：,，.。!！?？()（）]'), '')
    .toLowerCase();

DateTime? _parseDate(String? raw) {
  if (raw == null) return null;
  var s = raw.trim();
  final cn = RegExp(
    r'(\d{4})[年\-/](\d{1,2})[月\-/](\d{1,2})',
  ).firstMatch(s);
  if (cn != null) {
    return DateTime(
      int.parse(cn.group(1)!),
      int.parse(cn.group(2)!),
      int.parse(cn.group(3)!),
    );
  }
  s = s.replaceAll('T', ' ');
  return DateTime.tryParse(s);
}

/// 渠道解析总入口：坏数据返回空列表（不抛，UI 提示「未解析出条目」）。
List<ParsedClip> parseClips(ImportChannel ch, String raw) {
  final text = raw.replaceFirst('\uFEFF', '');
  try {
    return switch (ch.parser) {
      'kindle' => _parseKindle(text),
      'csv' => _parseCsv(ch, text),
      'json' => _parseJson(ch, text),
      'clip' => _parseClip(ch, text),
      'md' => _parseMd(text),
      _ => const [],
    };
  } catch (_) {
    return const [];
  }
}

/// 清单解析（书名 [作者] [ISBN]，`-`/`/`/制表符/多空格分列）。
List<ParsedBookRow> parseBookList(String raw) {  final isbnRe = RegExp(r'^(97[89]\d{10}|\d{9}[\dX])$');
  final out = <ParsedBookRow>[];
  for (final line in raw.split('\n')) {
    final s = line.trim();
    if (s.isEmpty || s.startsWith('#')) continue;
    final parts = s
        .split(RegExp(r'\s*[/|\t]\s*|\s*[-—]+\s*|\s{2,}'))
        .where((p) => p.trim().isNotEmpty)
        .map((p) => p.trim())
        .toList();
    if (parts.isEmpty) continue;
    var title = parts.first;
    title = RegExp(r'^《(.+)》$').firstMatch(title)?.group(1) ?? title;
    String author = '';
    String? isbn;
    for (final p in parts.skip(1)) {
      final clean = p.replaceAll(RegExp(r'[-\s]'), '');
      if (isbn == null && isbnRe.hasMatch(clean)) {
        isbn = clean;
      } else if (author.isEmpty) {
        author = p;
      }
    }
    out.add(ParsedBookRow(title: title, author: author, isbn: isbn));
  }
  return out;
}

/// CSV 书架清单（晒书房式：表头别名列 book/author/isbn）。
List<ParsedBookRow> parseCsvBookList(ImportChannel ch, String text) {
  final alias = _cfgMap(ch.config['alias']);
  final rows = _csvRows(text.replaceFirst('\uFEFF', ''));
  if (rows.isEmpty) return const [];
  final cols = _csvCols(rows.first, alias);
  final out = <ParsedBookRow>[];
  for (final r in rows.skip(1)) {
    final title = _cell(r, cols[0]);
    if (title == null) continue;
    out.add(
      ParsedBookRow(
        title: RegExp(r'^《(.+)》$').firstMatch(title)?.group(1) ?? title,
        author: _cell(r, cols[1]) ?? '',
        isbn: _cell(r, cols[2]),
      ),
    );
  }
  return out;
}

// ---- 五类解析器 ----

final _kHead = RegExp(r'^(.*?)\s*\((.*?)\)\s*-\s*(.*)$');

/// Kindle 行状态机：头行 `书名 (作者) - 位置/页面…` 开条目，头行后紧跟的
/// 短日期/标记行是元信息（真实导出里正文在元信息后的空行下，不能按空行分块），
/// `批注：` 起为想法，其余归正文；下个条目开始才入账。
List<ParsedClip> _parseKindle(String text) {
  final out = <ParsedClip>[];
  final marker = RegExp(
    r'^(?:\s*[·|·]\s*)?(?:你的)?(划线|批注|笔记|标记|备注|高亮|Highlight|Note|Bookmark|My (?:Note|Bookmark|Highlight))',
    caseSensitive: false,
  );
  String? book, author, thought;
  final body = <String>[];
  double? loc;
  int? page;
  DateTime? at;
  var expectMeta = false, open = false;
  void flush() {
    if (open && (body.isNotEmpty || thought != null)) {
      out.add(
        ParsedClip(
          book: book ?? '',
          author: author ?? '',
          loc: loc,
          page: page,
          body: body.join('\n').trim(),
          thought: thought,
          at: at,
        ),
      );
    }
    book = author = thought = null;
    body.clear();
    loc = null;
    page = null;
    at = null;
  }

  for (final raw in text.split('\n')) {
    final l = raw.trim();
    if (l.isEmpty) continue;
    final m = _kHead.firstMatch(l);
    if (m != null) {
      flush();
      open = true;
      expectMeta = true;
      book = m.group(1)!.trim();
      author = m.group(2)!.trim();
      final tail = m.group(3) ?? '';
      final locM = RegExp(
        r'(?:位置|Location)\s*([\d,\.]+)',
        caseSensitive: false,
      ).firstMatch(tail);
      final pgM = RegExp(
        r'(?:页面|Page|position)\s*(\d+)',
        caseSensitive: false,
      ).firstMatch(tail);
      loc = double.tryParse((locM?.group(1) ?? '').replaceAll(',', ''));
      page = int.tryParse(pgM?.group(1) ?? '');
      at = _parseDate(tail);
      continue;
    }
    if (!open) continue;
    // 元信息行：以 划线/批注 类词起头，或短行且能解析出日期。
    if (expectMeta &&
        (marker.hasMatch(l) || (l.length < 48 && _parseDate(l) != null))) {
      at ??= _parseDate(l);
      expectMeta = false;
      continue;
    }
    expectMeta = false;
    final tm = RegExp(
      r'^(?:批注|笔记|想法|Your (?:Notes?|Comment))[:：]\s*(.*)$',
    ).firstMatch(l);
    if (tm != null) {
      thought = tm.group(1)!.trim();
    } else {
      body.add(l);
    }
  }
  flush();
  return out;
}

/// 轻量 CSV（支持双引号包裹与 "" 转义）。
List<List<String>> _csvRows(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var inQ = false;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (inQ) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          inQ = false;
        }
      } else {
        cell.write(c);
      }
    } else if (c == '"') {
      inQ = true;
    } else if (c == ',') {
      row.add(cell.toString().trim());
      cell.clear();
    } else if (c == '\n') {
      row.add(cell.toString().trim());
      cell.clear();
      if (row.any((e) => e.isNotEmpty)) rows.add(row);
      row = [];
    } else if (c != '\r') {
      cell.write(c);
    }
  }
  row.add(cell.toString().trim());
  if (row.any((e) => e.isNotEmpty)) rows.add(row);
  return rows;
}

Map<String, Object?> _cfgMap(Object? v) =>
    ((v as Map?) ?? const {}).map((k, e) => MapEntry(k.toString(), e));

/// 表头别名 → 规范列（config.alias：{规范名: [别名...]}）。
List<int> _csvCols(List<String> header, Map<String, Object?> alias) {
  final idx = <String, int>{};
  for (var i = 0; i < header.length; i++) {
    idx[header[i]] = i;
  }
  final cols = <String, int>{};
  alias.forEach((canon, names) {
    for (final n in (names as List).map((e) => e.toString())) {
      final hit = idx[n];
      if (hit != null) {
        cols[canon] = hit;
        break;
      }
    }
  });
  final order = ['book', 'author', 'isbn', 'chapter', 'page', 'loc', 'body', 'thought', 'at'];
  return order.map((k) => cols[k] ?? -1).toList();
}

String? _cell(List<String> r, int i) =>
    i >= 0 && i < r.length && r[i].isNotEmpty ? r[i] : null;

List<ParsedClip> _parseCsv(ImportChannel ch, String text) {
  final alias = _cfgMap(ch.config['alias']);
  final rows = _csvRows(text);
  if (rows.isEmpty) return const [];
  final cols = _csvCols(rows.first, alias);
  final out = <ParsedClip>[];
  for (final r in rows.skip(1)) {
    final book = _cell(r, cols[0]) ?? '';
    final body = _cell(r, cols[6]) ?? '';
    if (book.isEmpty || body.isEmpty) continue;
    out.add(
      ParsedClip(
        book: book,
        author: _cell(r, cols[1]) ?? '',
        isbn: _cell(r, cols[2]),
        chapter: _cell(r, cols[3]),
        page: int.tryParse(_cell(r, cols[4]) ?? ''),
        loc: double.tryParse(_cell(r, cols[5]) ?? ''),
        body: body,
        thought: _cell(r, cols[7]),
        at: _parseDate(_cell(r, cols[8])),
      ),
    );
  }
  return out;
}

List<ParsedClip> _parseJson(ImportChannel ch, String text) {
  final alias = _cfgMap(ch.config['alias']);
  final v = jsonDecode(text);
  final list = v is List
      ? v
      : ((v is Map ? v[(ch.config['root'] ?? 'clips').toString()] : null) as List? ?? const []);
  final out = <ParsedClip>[];
  for (final e in list.whereType<Map>()) {
    final m = e.map((k, val) => MapEntry(k.toString(), val));
    String? get(String canon) {
      final names = (alias[canon] ?? [canon]) as List;
      for (final n in names.map((x) => x.toString())) {
        final val = m[n];
        if (val != null && val.toString().trim().isNotEmpty) {
          return val.toString().trim();
        }
      }
      return null;
    }
    final book = get('book') ?? '';
    final body = get('body') ?? '';
    if (book.isEmpty || body.isEmpty) continue;
    out.add(
      ParsedClip(
        book: book,
        author: get('author') ?? '',
        isbn: get('isbn'),
        chapter: get('chapter'),
        page: int.tryParse(get('page') ?? ''),
        loc: double.tryParse(get('loc') ?? ''),
        body: body,
        thought: get('thought'),
        at: _parseDate(get('at')),
      ),
    );
  }
  return out;
}

List<ParsedClip> _parseClip(ImportChannel ch, String text) {
  final pat = (ch.config['pattern'] as String?) ?? '';
  if (pat.isEmpty) return const [];
  final re = RegExp(pat, multiLine: true, dotAll: true);
  final out = <ParsedClip>[];
  for (final m in re.allMatches(text)) {
    String? g(String name) {
      try {
        final v = m.namedGroup(name);
        return (v == null || v.trim().isEmpty) ? null : v.trim();
      } catch (_) {
        return null;
      }
    }

    final whole = m.group(0) ?? '';
    // 二级扫描：模板脚注行里常混排 章节/页码/位置/日期，命名组缺省时整段兜底再抓。
    final body = g('body') ?? '';
    final book = g('book') ?? (ch.config['book'] as String?) ?? '';
    if (body.isEmpty || book.isEmpty) continue;
    out.add(
      ParsedClip(
        book: book.replaceAll(RegExp(r'[《》]'), '').trim(),
        author: g('author') ?? '',
        chapter:
            g('chapter') ??
            RegExp(r'(第[0-9一二三四五六七八九十百]+[章节部卷篇][^\s，。]*)')
                .firstMatch(whole)
                ?.group(1),
        page:
            int.tryParse(g('page') ?? '') ??
            int.tryParse(
              RegExp(r'(?:P|页码?[:：]?\s*)(\d+)', caseSensitive: false)
                      .firstMatch(whole)
                      ?.group(1) ??
                  '',
            ),
        loc:
            double.tryParse(
              (g('loc') ?? '')
                  .replaceAll(',', ''),
            ) ??
            double.tryParse(
              RegExp(r'(?:位置|Location)[:：]?\s*([\d,\.]+)', caseSensitive: false)
                      .firstMatch(whole)
                      ?.group(1)
                      ?.replaceAll(',', '') ??
                  '',
            ),
        body: body.trim().replaceAll(RegExp(r'^[「“]|["”]$'), ''),
        thought: g('thought'),
        at: _parseDate(g('at')) ?? _parseDate(whole),
      ),
    );
  }
  return out;
}

/// MD 卡片：`#`/`##` 行定当前书（可带（作者）），`>` 行为原文，
/// `想法：`/`— ` 归因行给想法与页码/章节/日期。
List<ParsedClip> _parseMd(String text) {
  final out = <ParsedClip>[];
  var book = '', author = '';
  String? chapter;
  List<String> body = [];
  String? thought;
  int? page;
  DateTime? at;
  void flush() {
    if (book.isNotEmpty && (body.isNotEmpty || thought != null)) {
      out.add(
        ParsedClip(
          book: book,
          author: author,
          chapter: chapter,
          page: page,
          body: body.join('\n').trim(),
          thought: thought,
          at: at,
        ),
      );
    }
    body = [];
    thought = null;
    page = null;
    at = null;
  }

  for (final raw in text.split('\n')) {
    final l = raw.trim();
    if (l.isEmpty) continue;
    final hm = RegExp(r'^#{1,3}\s+(.*)$').firstMatch(l);
    if (hm != null) {
      flush();
      var t = hm.group(1)!.trim();
      final am = RegExp(r'^(.*?)\s*[（(](.*?)[）)]$').firstMatch(t);
      if (am != null) {
        t = am.group(1)!.trim();
        author = am.group(2)!.trim();
      }
      book = RegExp(r'^《(.+)》$').firstMatch(t)?.group(1) ?? t;
      continue;
    }
    if (l.startsWith('>')) {
      final t = l.substring(1).trim();
      if (t.isNotEmpty) body.add(t);
      continue;
    }
    final tm = RegExp(r'^(?:想法|感想|笔记|批注)[:：]\s*(.*)$').firstMatch(l);
    if (tm != null) {
      thought = tm.group(1)!.trim();
      continue;
    }
    final cm = RegExp(r'^(?:章节| chapter)[:：]?\s*(.+)$', caseSensitive: false).firstMatch(l);
    if (cm != null) {
      chapter = cm.group(1)!.trim();
      continue;
    }
    final pm = RegExp(r'(?:页[码]?\s*[:：]?\s*P?|P)(\d+)').firstMatch(l);
    if (pm != null) page = int.parse(pm.group(1)!);
    final dm = RegExp(
      r'(\d{4})[年\-/](\d{1,2})[月\-/](\d{1,2})',
    ).firstMatch(l);
    if (dm != null) at = _parseDate(l);
    final attr = RegExp(r'^[—\-–]{1,2}\s*《?(.+?)》?\s*$').firstMatch(l);
    if (attr != null && book.isEmpty) book = attr.group(1)!.trim();
  }
  flush();
  return out;
}
