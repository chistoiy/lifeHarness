part of 'epub_doc.dart';

/// XHTML → 段落序列（p/div/section/h1-6/blockquote/img/figure/li/aside；其余块并入文本流）。
/// 段内 <a> 记为 [EpubLink]（内链解析成 zip 路径，外链保留原样）。
/// R3-2 止血带出的语义（① 注释体 · ③ 自带缩进 · ④ 站内锚点）在此**一次判定完**，
/// 渲染层只读 [EpubPara.annotation]/[EpubPara.ownIndent]/[EpubLink.usesLinkColor]。
///
/// 批三实现批·刀2 追加：文档自带 CSS（`<link>`＋`<style>`）经 [EpubStyleSheet] 级联后，
/// 段级排版意图进 [EpubPara.style]、段内区间语义进 [EpubPara.runs]。
/// **裁剪判据＝有没有声明白名单属性**（[EpubStyle.hasSemantics]，§5.4 拍板②），
/// 不看 class 名；与段级样式同值的区间不重复记一刀（省 span）。
/// [css] 由调用方按包提供（同书多章共用解析结果）；[sink] 非空时顺手记「不支持声明」留痕。
List<EpubPara> _extractParas(
  String xhtml,
  String docPath,
  _CssSheets css, [
  EpubUnsupportedSink? sink,
]) {
  final out = <EpubPara>[];
  final doc = hparser.parse(xhtml);
  final body = doc.body ?? doc.documentElement;
  if (body == null) return out;
  final base = _dirName(docPath);
  final sheet = css.sheetFor(doc, docPath);

  String norm(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

  // ④ 外链＝带 scheme（http:/https:/mailto:/tel:/ftp:/…）或协议相对 //host。
  bool hasScheme(String href) =>
      RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*:').hasMatch(href) ||
      href.startsWith('//');

  // ① 注释体判定（工单 R3-2 原文口径）：epub:type 含 footnote/note ·
  // 类名含 note|footnote|annotation（noteref/notes/annotation-* 都落在这三词里）。
  final noteTypeRe = RegExp(r'footnote|note', caseSensitive: false);
  final noteClassRe = RegExp(r'note|footnote|annotation', caseSensitive: false);
  bool isNoteEl(h.Element el) {
    final t = el.attributes['epub:type'] ?? el.attributes['type'];
    if (t != null && noteTypeRe.hasMatch(t)) return true;
    final c = el.attributes['class'];
    return c != null && noteClassRe.hasMatch(c);
  }

  // ③ 书内自带缩进：原书 CSS 声明了 text-indent（含祖先 class，走级联），或正文
  // 本身以全角空格/持续空白起头（中文古籍常见写法）。换行起头的源码缩进不算。
  bool ownIndentOf(h.Element el, String lead, EpubStyle st) {
    if (st.indentEm != null && st.indentEm != 0) return true;
    // 段首空白码位：半角空格/制表/NBSP/全角空格（不含换行——源码缩进不算）。
    const leadWs = {0x20, 0x09, 0x00a0, 0x3000};
    var n = 0;
    while (n < lead.length && leadWs.contains(lead.codeUnitAt(n))) {
      n++;
    }
    if (n == 0) return false;
    final head = lead.substring(0, n);
    // 全角空格/NBSP 单个即算自带缩进；普通空白要 2 个以上。
    return head.codeUnits.contains(0x3000) ||
        head.codeUnits.contains(0x00a0) ||
        n >= 2;
  }

  /// 元素链（自内而外，`html` 收尾）——[EpubStyleSheet.resolve] 要的视图。
  List<EpubElementRef> chainOf(h.Element el) {
    final chain = <EpubElementRef>[];
    h.Node? n = el;
    while (n is h.Element) {
      chain.add(EpubElementRef(n.localName ?? '', n.classes.toSet(), n.id));
      n = n.parent;
    }
    return chain;
  }

  EpubStyle styleOf(h.Element el) => sheet.resolve(
    chainOf(el),
    inline: el.attributes['style'] ?? '',
    sink: sink,
  );

  /// 收集元素文本 + 链接区间 + 样式区间。**折叠口径与 [norm] 同源**：
  /// 空白串折成一个空格、首尾裁掉——偏移必须在折叠后的坐标上记，
  /// 否则 runs/links 与 text 对不齐（旧实现先记原始偏移再 norm，链接区间只是近似）。
  ({String lead, String text, List<EpubLink> links, List<EpubStyleRun> runs})
      grab(h.Element el, EpubStyle paraStyle) {
    final sb = StringBuffer();
    final leadSb = StringBuffer();
    final links = <EpubLink>[];
    final runs = <EpubStyleRun>[];
    var got = false, pendingWs = false;

    void emit(int from, int to, EpubStyle st) {
      if (to <= from || !st.hasSemantics || st == paraStyle) return;
      if (runs.isNotEmpty) {
        final last = runs.last;
        if (last.style == st && last.end == from) {
          runs[runs.length - 1] = EpubStyleRun(start: last.start, end: to, style: st);
          return;
        }
      }
      runs.add(EpubStyleRun(start: from, end: to, style: st));
    }

    void write(String s, EpubStyle st) {
      final from = sb.length;
      var wrote = false;
      for (var i = 0; i < s.length; i++) {
        final ch = s[i];
        if (_spaceRunes.contains(ch.codeUnitAt(0))) {
          if (!got) leadSb.write(ch); // 段首空白原样留着给 ③ 判缩进
          pendingWs = true;
          continue;
        }
        if (pendingWs) {
          pendingWs = false;
          if (got) sb.write(' ');
        }
        got = true;
        wrote = true;
        sb.write(ch);
      }
      if (wrote) emit(from, sb.length, st);
    }

    void walkNode(h.Node n, EpubStyle st) {
      if (n is h.Text) {
        write(n.text, st);
        return;
      }
      if (n is! h.Element) return;
      final tag = n.localName ?? '';
      if (tag == 'br') {
        pendingWs = true; // 换行算空白，与旧 norm 口径一致
        return;
      }
      // 快筛：自身没被样式表点到（无 class/id/内联 style 且标签不在索引）就沿用父样式，
      // 672k span 逐个级联付不起（预研 §5.3；祖先的贡献在父元素解析时已进过一轮）。
      final inline = n.attributes['style'] ?? '';
      final child = sheet.mayAffect(tag, n.classes.toSet(), hasInline: inline.isNotEmpty)
          ? sheet.resolve(chainOf(n), inline: inline, sink: sink)
          : st;
      final href = n.attributes['href'];
      if (tag == 'a' && href != null && href.isNotEmpty) {
        final s = sb.length;
        for (final c in n.nodes) {
          walkNode(c, child);
        }
        final isExt = hasScheme(href);
        // ④ sameDoc＝纯 #fragment 或解析后仍落在本文档。**不改 href 口径**
        // （内链点击行为沿用批2 的「命中 spine 章即跳章」，改它会顺手动到跳转语义）。
        final same = !isExt &&
            (href.startsWith('#') || _resolve(base, href.split('#').first) == docPath);
        links.add(
          EpubLink(
            start: s,
            end: sb.length,
            href: isExt ? href : _resolve(base, href.split('#').first),
            external: isExt,
            annotation: isNoteEl(n),
            sameDoc: same,
          ),
        );
        return;
      }
      for (final c in n.nodes) {
        walkNode(c, child);
      }
    }

    for (final c in el.nodes) {
      walkNode(c, paraStyle);
    }
    return (lead: leadSb.toString(), text: sb.toString(), links: links, runs: runs);
  }

  void pushText(
    h.Element el,
    EpubParaKind k, {
    int level = 0,
    bool annotation = false,
  }) {
    final st = styleOf(el);
    final g = grab(el, st);
    if (g.text.isEmpty) return;
    out.add(
      EpubPara(
        kind: k,
        text: g.text,
        headingLevel: level,
        links: g.links,
        runs: g.runs,
        style: st.isEmpty ? null : st,
        annotation: annotation || isNoteEl(el),
        ownIndent: ownIndentOf(el, g.lead, st),
      ),
    );
  }

  void pushImg(String src, String alt) {
    if (src.isEmpty) return;
    out.add(
      EpubPara(
        kind: EpubParaKind.image,
        imgSrc: _resolve(base, src),
        alt: norm(alt),
      ),
    );
  }

  /// [note]＝祖先容器已是注释体（`<div class="footnotes">`/`<section epub:type=...>`），
  /// 段级继承下去——这是「按段判断、不一刀切」的另一半。
  void walk(h.Element el, {bool note = false}) {
    final tag = el.localName ?? '';
    final ann = note || isNoteEl(el);
    switch (tag) {
      case 'p':
        pushText(el, EpubParaKind.text, annotation: ann);
      case 'div':
      case 'section':
      case 'article':
      case 'footer':
      case 'header':
        // 容器含子块则下钻（注释语义随之下传），纯文本容器当段落。
        if (el.children.isEmpty) {
          pushText(el, EpubParaKind.text, annotation: ann);
          return;
        }
        for (final c in el.children) {
          walk(c, note: ann);
        }
      case 'aside':
        // ① aside 整块即注释体（工单原文点名）。
        if (el.children.isEmpty) {
          pushText(el, EpubParaKind.text, annotation: true);
        } else {
          for (final c in el.children) {
            walk(c, note: true);
          }
        }
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        pushText(
          el,
          EpubParaKind.heading,
          level: int.parse(tag.substring(1)),
          annotation: ann,
        );
      case 'blockquote':
        if (el.children.where((c) => c.localName == 'p').isEmpty) {
          pushText(el, EpubParaKind.quote, annotation: ann);
        } else {
          for (final c in el.children) {
            if (c.localName == 'p') {
              pushText(c, EpubParaKind.quote, annotation: ann);
            }
          }
        }
      case 'img':
        pushImg(el.attributes['src'] ?? '', el.attributes['alt'] ?? '');
      case 'figure':
        final img = el.querySelector('img');
        final cap = el.querySelector('figcaption');
        if (img != null) {
          pushImg(
            img.attributes['src'] ?? '',
            (cap?.text ?? img.attributes['alt'] ?? ''),
          );
        }
      case 'li':
        pushText(el, EpubParaKind.text, annotation: ann);
        for (final c in el.children) {
          if (c.localName == 'li' ||
              c.localName == 'ul' ||
              c.localName == 'ol') {
            walk(c, note: ann);
          }
        }
      case 'ul':
      case 'ol':
        for (final c in el.children) {
          walk(c, note: ann);
        }
      case 'br':
        break;
      case 'table':
      case 'tr':
      case 'tbody':
      case 'thead':
        for (final c in el.children) {
          walk(c, note: ann);
        }
      default:
        // 未知块（span 直接挂 body 之类）：整块当一段，样式照走级联。
        final st = styleOf(el);
        final g = grab(el, st);
        if (g.text.isEmpty) return;
        out.add(
          EpubPara(
            kind: EpubParaKind.text,
            text: g.text,
            links: g.links,
            runs: g.runs,
            style: st.isEmpty ? null : st,
            annotation: ann,
            ownIndent: ownIndentOf(el, g.lead, st),
          ),
        );
    }
  }

  for (final c in body.children) {
    walk(c);
  }
  // body 只有裸文本（无包裹元素）时兜底整段。
  if (out.isEmpty && norm(body.text).isNotEmpty) {
    final st = styleOf(body);
    final g = grab(body, st);
    out.add(
      EpubPara(
        kind: EpubParaKind.text,
        text: g.text,
        links: g.links,
        runs: g.runs,
        style: st.isEmpty ? null : st,
        annotation: isNoteEl(body),
        ownIndent: ownIndentOf(body, g.lead, st),
      ),
    );
  }
  return out;
}

/// 与 [norm] 里 `\s` 同集的码位表（**探测生成**：拿同一个正则引擎逐候选字符问一遍，
/// 免得手写表与 RegExp 语义漂移——全角空格/NBSP 在 Dart 里也属 `\s`，实测确认）。
final Set<int> _spaceRunes = {
  for (final u in _wsCandidates.codeUnits)
    if (RegExp(r'\s').hasMatch(String.fromCharCode(u))) u,
};

const String _wsCandidates =
    '\t\n\v\f\r \u0085\u00a0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006'
    '\u2007\u2008\u2009\u200a\u2028\u2029\u202f\u205f\u3000\ufeff';

/// 一篇文档的样式表装载器（批三刀2）：`<link rel=stylesheet>` 指向的包内 CSS
/// ＋文档内 `<style>` 块，按「外链在前、文档内块在后」合并规则序
/// （同特异性时后写覆盖先写，所以文档内块压外链）。
/// **按 zip 路径缓存**：通鉴 306 篇共用 2 份 CSS、阿加莎 85 册各一份，
/// 逐篇重解＝白付几十倍解析成本（预研 §1 结论 A）。
class _CssSheets {
  _CssSheets(this._files);

  final _Source _files;
  final Map<String, EpubStyleSheet> _cache = {};

  /// 跨表全局规则序（见 [_loadInline]）。
  int _nextOrder = 0;

  static final _cssRefRe = RegExp(
    r'\.(css|style)(\?|#|$)',
    caseSensitive: false,
  );

  EpubStyleSheet sheetFor(h.Document doc, String docPath) {
    final base = _dirName(docPath);
    final rules = <EpubRule>[];
    for (final link in doc.querySelectorAll('link')) {
      final rel = (link.attributes['rel'] ?? '').toLowerCase();
      final href = link.attributes['href'] ?? '';
      if (href.isEmpty) continue;
      if (rel.isNotEmpty && !rel.contains('stylesheet')) continue;
      if (!_cssRefRe.hasMatch(href) && rel.isEmpty) continue;
      final path = _resolve(base, href);
      rules.addAll((_cache[path] ??= _load(path)).rules);
    }
    for (final st in doc.querySelectorAll('style')) {
      final text = st.text;
      if (text.trim().isEmpty) continue;
      // 文档内 style 块没有独立路径，按内容做缓存键（同一串重复出现在多章）。
      final key = 'inline:${text.hashCode}:${text.length}';
      rules.addAll((_cache[key] ??= _loadInline(text)).rules);
    }
    return rules.isEmpty ? EpubStyleSheet.empty() : EpubStyleSheet(rules);
  }

  /// 文档内 `<style>` 块：序号步长给足 1000，保证它压过同篇文档引用的外链 CSS
  /// （同特异性时后写的规则胜；跨表合并不能各自从 0 编号）。
  EpubStyleSheet _loadInline(String text) {
    final at = _nextOrder;
    _nextOrder += 1000;
    return EpubStyleSheet.parse(text, orderBase: at);
  }

  EpubStyleSheet _load(String path) {
    final bytes = _files.bytes(path);
    if (bytes == null) return EpubStyleSheet.empty();
    final sheet = EpubStyleSheet.parse(
      utf8.decode(bytes, allowMalformed: true),
      orderBase: _nextOrder,
    );
    _nextOrder += sheet.rules.length + 1;
    return sheet;
  }
}
