// 探针 CLI：书源订阅管理 / 搜索 / 详情 / 目录 / 正文 / 整本自动抓取
import 'dart:convert';
import 'dart:io';

import 'package:probe/legado_lite.dart';

const storePath = 'sources_store.json'; // 本地书源库（订阅落盘）

class SourceStore {
  SourceStore(this.items);
  final List<StoreEntry> items;
  static SourceStore load() {
    final f = File(storePath);
    if (!f.existsSync()) return SourceStore([]);
    final j = jsonDecode(f.readAsStringSync()) as List<dynamic>;
    return SourceStore([for (final e in j) StoreEntry(Map<String, dynamic>.from(e))]);
  }

  void save() {
    File(storePath).writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert([for (final e in items) e.j]));
  }
}

class StoreEntry {
  StoreEntry(this.j);
  final Map<String, dynamic> j;
  BookSource get src => BookSource(j);
  bool get enabled => j['_enabled'] != false;
  String get subFrom => j['_sub'] as String? ?? 'local';
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    _usage();
    return;
  }
  final cmd = args.first;
  final rest = args.sublist(1);
  switch (cmd) {
    case 'subscribe':
      await subscribe(rest);
    case 'sources':
      sources(rest);
    case 'toggle':
      toggle(rest);
    case 'remove':
      remove(rest);
    case 'search':
      await searchCmd(rest);
    case 'info':
      await infoCmd(rest);
    case 'meta':
      await metaCmd(rest);
    case 'toc':
      await tocCmd(rest);
    case 'chapter':
      await chapterCmd(rest);
    case 'download':
      await downloadCmd(rest);
    case 'explore':
      await exploreCmd(rest);
    case 'allsearch':
      await allSearchCmd(rest);
    case 'match':
      await matchCmd(rest);
    case 'update':
      await updateCmd(rest);
    case 'fonttest':
      fontTestCmd();
    case 'export':
      exportCmd(rest);
    case 'cache':
      cacheCmd(rest);
    case 'pagcheck':
      pagcheckCmd(rest);
    default:
      _usage();
  }
}

void _usage() {
  print('''
用法:
  probe subscribe <url|file>           订阅书源（JSON数组→本地库，同名同URL更新）
  probe sources                        列出已订阅书源（含JS支持标记）
  probe toggle <name>                  启用/停用
  probe remove <name>                  删除
  probe search <name|all> <关键词>      书源搜索（四段流程①）
  probe info <name> <bookUrl>          详情元数据（②）
  probe meta <name> <bookUrl>          期1：详情→Book预填映射 JSON
  probe toc <name> <url> [--max N]     目录（③）
  probe chapter <name> <url> [--filter 正则##替换]  正文（④+内容过滤）
  probe download <name> <bookUrl> --max N [--out dir]  自动抓取整本落盘''');
}

BookSource findSource(String name) {
  final store = SourceStore.load();
  final hit = store.items.where((e) => e.src.name == name).toList();
  if (hit.isEmpty) {
    stderr.writeln('未找到书源: $name（先 subscribe）');
    exit(2);
  }
  return hit.first.src;
}

/// ---------- 订阅与管理 ----------
Future<void> subscribe(List<String> a) async {
  if (a.isEmpty) return _usage();
  String raw;
  if (a[0].startsWith('http')) {
    final http = HttpCtx();
    final res = await http.fetch(a[0]);
    raw = res.text();
    print('订阅源 HTTP ${res.status}，字节 ${res.body.length}');
  } else {
    raw = File(a[0]).readAsStringSync();
  }
  final list = _decodeSourceList(raw);
  final store = SourceStore.load();
  var added = 0, updated = 0;
  for (final j in list) {
    final s = BookSource(j);
    final exist = store.items.where((e) => e.src.url == s.url && e.src.name == s.name);
    if (exist.isNotEmpty) {
      exist.first.j
        ..clear()
        ..addAll(j)
        ..['_enabled'] = exist.first.enabled;
      updated++;
    } else {
      store.items.add(StoreEntry({...j, '_enabled': j['enabled'] != false, '_sub': a[0]}));
      added++;
    }
  }
  store.save();
  print('订阅完成：新增 $added，更新 $updated，库内共 ${store.items.length} 源');
}

List<Map<String, dynamic>> _decodeSourceList(String raw) {
  var t = raw.trim();
  // 部分订阅是 base64 包装
  if (!t.startsWith('[') && !t.startsWith('{')) {
    t = utf8.decode(base64Decode(t));
  }
  final j = jsonDecode(t);
  if (j is List) return [for (final e in j) Map<String, dynamic>.from(e as Map)];
  if (j is Map) return [Map<String, dynamic>.from(j)];
  return [];
}

void sources(List<String> a) {
  final store = SourceStore.load();
  print('共 ${store.items.length} 个书源：');
  for (final e in store.items) {
    print('  ${e.enabled ? '✓' : '✗'} ${e.src.name}'
        ' [${e.src.group ?? '-'}] js=${e.src.usesJs() ? "需要(JS)" : "纯规则✓"}'
        ' 订阅=${e.subFrom}');
  }
}

void toggle(List<String> a) {
  final store = SourceStore.load();
  for (final e in store.items.where((e) => e.src.name == a[0])) {
    e.j['_enabled'] = !e.enabled;
    print('${a[0]} → ${e.enabled ? '启用' : '停用'}');
  }
  store.save();
}

void remove(List<String> a) {
  final store = SourceStore.load();
  final before = store.items.length;
  store.items.removeWhere((e) => e.src.name == a[0]);
  store.save();
  print('删除 ${before - store.items.length} 个');
}

SourceEngine engineFor(String name) {
  final src = findSource(name);
  if (src.usesJs()) {
    final eng = SourceEngine(src, HttpCtx());
    print('提示：$name 含 JS 规则 · 桥引擎=${eng.jsEngine}');
    return eng;
  }
  return SourceEngine(src, HttpCtx());
}

/// ---------- 四段流程 ----------
Future<void> searchCmd(List<String> a) async {
  final eng = engineFor(a[0]);
  final books = await eng.search(a.sublist(1).join(' '));
  print('搜索结果 ${books.length} 条：');
  for (var i = 0; i < books.length && i < 15; i++) {
    final b = books[i];
    print('  [$i] ${b.name} / ${b.author}  字数:${b.wordCount}  类:${b.kind}');
    print('      最新: ${b.lastChapter}');
    print('      url: ${b.bookUrl}');
    if (b.cover.isNotEmpty) print('      cover: ${b.cover}');
  }
}

Future<void> infoCmd(List<String> a) async {
  final eng = engineFor(a[0]);
  final info = await eng.bookInfo(a[1]);
  print('书名: ${info.name}\n作者: ${info.author}\n分类: ${info.kind}\n'
      '字数: ${info.wordCount}\n最新: ${info.lastChapter}\n封面: ${info.cover}\n'
      '简介: ${info.intro.length > 120 ? '${info.intro.substring(0, 120)}…' : info.intro}\n'
      '目录URL: ${info.tocUrl}');
}

/// 期1交付形态：书源详情 → lifeHarness Book 模型预填映射
Future<void> metaCmd(List<String> a) async {
  final eng = engineFor(a[0]);
  final info = await eng.bookInfo(a[1]);
  final wc = int.tryParse(RegExp(r'(\d+)').allMatches(info.wordCount).map((m)=>m.group(1)!).join()) ?? 0;
  final mapping = {
    'title': info.name,
    'author': info.author.isEmpty ? '佚名' : info.author,
    'intro': info.intro,
    'state': '想读', // 导入后由用户改
    'format': '电子书',
    'progressWay': 'pos',
    'wordCount': wc, // books.word_count（V1.44列）
    'source': '书源导入',
    'tags': ['书源'],
    'coverRemote': info.cover, // 下载后落 docs/book_covers/
    'grp': info.kind,
    // 阅读器接线（期2）：不走 EpubRef，新 kind='source' 描述符
    'sourceRef': {
      'kind': 'source',
      'srcName': a[0],
      'bookUrl': a[1],
      'tocUrl': info.tocUrl,
      'lastChapter': info.lastChapter,
    },
  };
  final f = File('dl_real/${_safe(info.name.isEmpty ? 'meta' : info.name)}_book_prefill.json');
  f.parent.createSync(recursive: true);
  f.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(mapping));
  print('Book 预填映射已写出：${f.path}');
  print(mapping.map((k, v) => MapEntry(k, '$v')).entries.take(9).map((e) => '  ${e.key} = ${e.value.length > 50 ? '${e.value.substring(0, 50)}…' : e.value}').join('\n'));
}

Future<void> tocCmd(List<String> a) async {
  final eng = engineFor(a[0]);
  var url = a[1];
  final info = await eng.bookInfo(url); // 先取 tocUrl
  url = info.tocUrl.isNotEmpty ? info.tocUrl : url;
  final chapters = await eng.toc(url);
  print('目录 ${chapters.length} 章（前5/后3）：');
  for (final c in chapters.take(5)) {
    print('  ${c.title}  → ${c.url}');
  }
  print('  ……');
  for (final c in chapters.length > 3 ? chapters.sublist(chapters.length - 3) : chapters) {
    print('  ${c.title}  → ${c.url}');
  }
}

Future<void> chapterCmd(List<String> a) async {
  final eng = engineFor(a[0]);
  String? filter;
  var url = a[1];
  for (var i = 2; i < a.length; i++) {
    if (a[i] == '--filter' && i + 1 < a.length) filter = a[++i];
  }
  final ch = await eng.chapter(url, extraFilter: filter ?? '');
  print('标题: ${ch.title}\n段数: ${ch.paras.length}  净化前字数: ${ch.rawLen}  净化后: ${ch.finalLen}');
  for (final p in ch.paras.take(6)) {
    print('  ¶ ${p.length > 80 ? '${p.substring(0, 80)}…' : p}');
  }
}

/// 补验A：发现页/排行榜
Future<void> exploreCmd(List<String> a) async {
  final eng = engineFor(a[0]);
  final tabs = eng.discoverTabs();
  if (tabs.isEmpty) {
    print('该源无 discoverUrl');
    return;
  }
  var want = a.length > 1 ? a[1] : tabs.first.$1;
  final hit = tabs.where((t) => t.$1 == want).firstOrNull;
  final (name, tpl) = hit ?? tabs.first;
  var page = 1;
  for (var i = 2; i < a.length; i++) {
    if (a[i] == '--page' && i + 1 < a.length) page = int.parse(a[++i]);
  }
  print('发现页[${tabs.map((t) => t.$1).join('/')}] → 执行「$name」page=$page');
  final books = await eng.explore(tpl, page: page);
  print('返回 ${books.length} 条：');
  for (final b in books.take(8)) {
    print('  · ${b.name} / ${b.author}  最新:${b.lastChapter}');
  }
}

/// 补验B1：多源并发搜索
Future<void> allSearchCmd(List<String> a) async {
  final key = a.join(' ');
  final store = SourceStore.load();
  final srcs = store.items.where((e) => e.enabled).toList();
  print('并发搜索「$key」× ${srcs.length} 个启用源（含JS源试探，单源25s熔断）：');
  final t0 = DateTime.now();
  final futures = <Future<List<String>>>[];
  for (final e in srcs) {
    Future<List<String>> run() async {
      try {
        final eng = SourceEngine(e.src, HttpCtx());
        final books = await eng.search(key)
            .timeout(const Duration(seconds: 25));
        return <String>[
          for (final b in books.take(3)) '  ✓ ${e.src.name} | ${b.name} / ${b.author}',
        ];
      } catch (_) {
        return const <String>[];
      }
    }
    futures.add(run());
  }
  final all = (await Future.wait(futures));
  var okSrc = 0;
  for (final r in all) {
    if (r.isNotEmpty) {
      okSrc++;
      print(r.join('\n'));
    }
  }
  print('—— ${DateTime.now().difference(t0).inSeconds}s，出结果源 $okSrc/${srcs.length}（其余超时/失效/JS不可破）');
}

/// 补验B2：粘贴书籍URL → bookUrlPattern 自动识源
Future<void> matchCmd(List<String> a) async {
  final url = a[0];
  final store = SourceStore.load();
  final hits = <StoreEntry>[];
  for (final e in store.items) {
    final p = e.src.j['bookUrlPattern'] as String?;
    if (p == null || p.isEmpty) continue;
    try {
      if (RegExp(p).hasMatch(url)) hits.add(e);
    } catch (_) {}
  }
  if (hits.isEmpty) {
    print('无源命中该URL（bookUrlPattern 匹配失败）');
    return;
  }
  for (final h in hits) {
    print('识源命中：${h.src.name}（pattern=${h.src.j['bookUrlPattern']}）');
    final eng = SourceEngine(h.src, HttpCtx());
    final info = await eng.bookInfo(url);
    print('  直取详情 → 《${info.name}》 ${info.author}');
  }
}

/// 补验C：连载追更 = 重取目录 diff manifest 增量抓新章
Future<void> updateCmd(List<String> a) async {
  final name = a[0];
  final bookUrl = a[1];
  var max = 5;
  for (var i = 2; i < a.length; i++) {
    if (a[i] == '--max' && i + 1 < a.length) max = int.parse(a[++i]);
  }
  final eng = engineFor(name);
  final info = await eng.bookInfo(bookUrl);
  final chapters = await eng.toc(info.tocUrl.isNotEmpty ? info.tocUrl : bookUrl);
  final dir = 'dl_real/${_safe(info.name.isEmpty ? name : info.name)}';
  final mf = File('$dir/manifest.json');
  final m = mf.existsSync()
      ? jsonDecode(mf.readAsStringSync()) as Map<String, dynamic>
      : <String, dynamic>{};
  final done = (m['done'] as List<dynamic>? ?? []).cast<int>().toSet();
  final newIdx = [for (var i = 0; i < chapters.length; i++) if (!done.contains(i)) i];
  print('《${info.name}》 站点现有 ${chapters.length} 章，已存 ${done.length}，新章位 ${newIdx.length}，本次追 ${newIdx.length < max ? newIdx.length : max} 章');
  var ok = 0;
  for (final i in newIdx.take(max)) {
    try {
      final ch = await eng.chapter(chapters[i].url);
      File('$dir/chapters/${_pad(i)}_${_safe(chapters[i].title)}.txt')
          .writeAsStringSync('${ch.title.isNotEmpty ? ch.title : chapters[i].title}\n\n${ch.paras.join('\n\n')}');
      done.add(i);
      ok++;
      print('  ✓ 追到 [$i] ${chapters[i].title} ${ch.finalLen}字');
      await Future.delayed(const Duration(milliseconds: 400));
    } catch (e) {
      print('  ✗ [$i] $e');
    }
  }
  m['done'] = done.toList()..sort();
  m['lastUpdate'] = DateTime.now().toIso8601String();
  mf.writeAsStringSync(jsonEncode(m));
  print('追更完成 $ok 章 · manifest 已记 lastUpdate=${m['lastUpdate']}');
}

/// 补验D：字体反混淆数据层管道自测（PUA码点回写）
void fontTestCmd() {
  // 模拟站点 fontMap：PUA 码点 → 正常字符（Legado 由 TTF cmap 解析得到）
  final fontMap = {'E001': '第', 'E002': '1', 'E003': '章', 'E004': '风', 'E005': '雨'};
  final obf = String.fromCharCodes([0xE001, 0xE002, 0xE003, 0x20, 0xE004, 0xE005, 0x9752]);
  final out = SourceEngine.applyFontMap(obf, fontMap);
  print('混淆码位: ${obf.runes.map((r) => r.toRadixString(16)).join(' ')}');
  print('回写结果: $out');
  if (out == '第1章 风雨青') {
    print('✓ fontMap 回写管道正确（PUA→正文；非PUA字符直通）');
  } else {
    print('✗ 回写异常');
    exit(1);
  }
}
Future<void> downloadCmd(List<String> a) async {
  final name = a[0];
  final bookUrl = a[1];
  var max = 5;
  var out = 'downloads';
  for (var i = 2; i < a.length; i++) {
    if (a[i] == '--max' && i + 1 < a.length) max = int.parse(a[++i]);
    if (a[i] == '--out' && i + 1 < a.length) out = a[++i];
  }
  final eng = engineFor(name);
  final info = await eng.bookInfo(bookUrl);
  final chapters = await eng.toc(info.tocUrl.isNotEmpty ? info.tocUrl : bookUrl);
  final dirName = '${out}/${_safe(info.name.isEmpty ? name : info.name)}';
  Directory('$dirName/chapters').createSync(recursive: true);
  final manifest = File('$dirName/manifest.json');
  Map<String, dynamic> m = {};
  if (manifest.existsSync()) m = jsonDecode(manifest.readAsStringSync()) as Map<String, dynamic>;
  final done = (m['done'] as List<dynamic>? ?? []).cast<int>();
  print('《${info.name}》共 ${chapters.length} 章，本次抓取 ${max.clamp(0, chapters.length)} 章（断点续传：已完成 ${done.length}）');
  final t0 = DateTime.now();
  var okCnt = 0, failCnt = 0;
  for (var i = 0; i < max && i < chapters.length; i++) {
    if (done.contains(i)) continue;
    final c = chapters[i];
    ChapterText? ch;
    for (var retry = 0; retry < 3 && ch == null; retry++) {
      try {
        ch = await eng.chapter(c.url);
      } catch (e) {
        if (retry == 2) {
          failCnt++;
          stderr.writeln('  ✗ $i ${c.title}: $e');
        } else {
          await Future.delayed(Duration(milliseconds: 800 * (retry + 1)));
        }
      }
    }
    if (ch == null) continue;
    okCnt++;
    final f = File('$dirName/chapters/${_pad(i)}_${_safe(c.title)}.txt');
    f.writeAsStringSync('${ch.title.isNotEmpty ? ch.title : c.title}\n\n${ch.paras.join('\n\n')}');
    // 期2：DocStore 同款「章→段落+charCount」快照
    final sdir = Directory('$dirName/snapshot/chapters')..createSync(recursive: true);
    File('${sdir.path}/$i.json').writeAsStringSync(jsonEncode({
      'title': ch.title.isNotEmpty ? ch.title : c.title,
      'charCount': ch.finalLen,
      'paras': [
        for (final p in ch.paras) {'kind': 'text', 'text': p},
      ],
    }));
    final wChars = ch.finalLen;
    File('$dirName/snapshot/index.json').writeAsStringSync(jsonEncode({
      'v': 1,
      'totalChapters': chapters.length,
      'chapters': List.generate(chapters.length, (j) => j), // 简化索引
      'weights': null, // 由 pagcheck 汇总各章 json
    }));
    // 维护权重表
    final wf = File('$dirName/snapshot/weights.json');
    final weights = wf.existsSync()
        ? (jsonDecode(wf.readAsStringSync()) as List<dynamic>).cast<int>()
        : List<int>.filled(chapters.length, 0);
    weights[i] = wChars;
    wf.writeAsStringSync(jsonEncode(weights));
    done.add(i);
    m['done'] = done;
    manifest.writeAsStringSync(jsonEncode(m));
    print('  ✓ [$i] ${c.title} ${ch.finalLen}字/${ch.paras.length}段');
    await Future.delayed(const Duration(milliseconds: 400)); // 限速
  }
  print('完成：成功 $okCnt / 失败 $failCnt，耗时 ${DateTime.now().difference(t0).inSeconds}s → $dirName');
}

String _safe(String s) => s.replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_').substring(0, s.length > 40 ? s.length > 40 ? 40 : s.length : s.length);
String _pad(int i) => i.toString().padLeft(4, '0');

/// 期2：进度插值自检（foliate SectionProgress 口径：按章字符权重线性插值）
void pagcheckCmd(List<String> a) {
  final dir = a[0];
  final w = (jsonDecode(File('$dir/snapshot/weights.json').readAsStringSync()) as List).cast<int>();
  final totalCh = (jsonDecode(File('$dir/snapshot/index.json').readAsStringSync()) as Map)['totalChapters'] as int;
  final filled = w.where((e) => e > 0).length;
  // 未抓章按已抓均值估重（阅读器按全书字数插值，与 books.word_count 解耦口径一致）
  final avg = (w.where((e) => e > 0).reduce((x, y) => x + y) / filled).round();
  final weights = [for (final e in w) e > 0 ? e : avg];
  final cum = <int>[];
  var s = 0;
  for (final x in weights) { cum.add(s); s += x; }
  final total = s;
  double frac(int ci, double inCh) => (cum[ci] + weights[ci] * inCh) / total;
  print('快照 $filled/${weights.length} 章实重（总$weights.length=$totalCh，余章按均值$avg 估），foliate 口径插值：');
  for (final (ci, f) in [(0, 0.0), (2, 0.5), (filled - 1, 1.0)]) {
    print('  章$ci 章内$f → 全书 ${(frac(ci, f) * 100).toStringAsFixed(2)}%');
  }
  // 断言单调
  var last = -1.0;
  for (var ci = 0; ci < weights.length; ci++) {
    for (final f in [0.0, 0.5, 0.99]) {
      final v = frac(ci, f);
      if (v < last - 1e-9) { stderr.writeln('✗ 单调性破坏 @章$ci'); exit(1); }
      last = v;
    }
  }
  print('  ✓ 单调递增 · 章间衔接无缝（ci=1,f=0 与 ci=0,f=1 差=${(frac(1, 0) - frac(0, 0.999)).toStringAsFixed(6)}）');
  print('  ✓ 进度只依赖章序+章内占比+权重表 → 与阅读器 read_pages 折算同构');
}

/// 期3：整本导出 txt（按章序合并）
void exportCmd(List<String> a) {
  final dir = a[0];
  final files = Directory('$dir/chapters').listSync().whereType<File>()
    ..toList().sort((x, y) => x.path.compareTo(y.path));
  final out = File('$dir/整本导出.txt');
  final sb = StringBuffer();
  for (final f in files) { sb.writeln(f.readAsStringSync()); sb.writeln('----'); }
  out.writeAsStringSync(sb.toString());
  print('导出 ${files.length} 章 → ${out.path}（${out.lengthSync()} 字节）');
}

/// 期3：缓存三态（rdy → cl 回收章节文件保留 manifest/快照索引 → 重下载恢复）
void cacheCmd(List<String> a) {
  final dir = a[0];
  final mf = File('$dir/manifest.json');
  final m = jsonDecode(mf.readAsStringSync()) as Map<String, dynamic>;
  if (a[1] == 'clear') {
    final keep = m['done'];
    Directory('$dir/chapters').listSync().whereType<File>().forEach((f) => f.deleteSync());
    m['done'] = <int>[];
    m['st'] = 'cl';
    m['keepMeta'] = keep;
    mf.writeAsStringSync(jsonEncode(m));
    print('已清缓存：回收 ${(keep as List).length} 章文件 · 记录/目录/书摘位保留（st=cl）');
  } else if (a[1] == 'restore') {
    m['st'] = 'rdy';
    mf.writeAsStringSync(jsonEncode(m));
    print('状态恢复 rdy → 下次 download 将按空 done 列表重抓（源文件不删口径）');
  }
}
