/// X-Ray 全书索引 · 抽取引擎（需求 V1.54 · 设计书 §4）
///
/// 参考实现＝预研脚本：`code/xray_extract.py`（通道与候选计数）、
/// `code/e_tier.py`（PMI 结合度、常用词与称谓过滤）、`code/a_tier.py`（章节 df/TF-IDF）。
/// **移植不改判定语义**：简史 地名 23/23、小说术语噪声 7/40→0/40 两个 GT 按这套口径测出，
/// 任何"顺手优化"都会让批1e 的 golden 基线失去意义。
///
/// 三条硬约束：
/// - 纯计算、零 IO、零 Flutter（批1d 在 isolate 里按章流式喂它）；
/// - 章内先低频剪枝再把候选并入全局（§8 内存护栏落点：预研峰值 275MB → 目标 30~60MB）；
/// - 用户层永远叠加在产出之上（§7）：`blocked` 命中即出局，`userAdded` 强制进榜。
library;

import 'dart:math' as math;

import 'xray_lexicon.dart';

/// 实体类型（`xray_entity.type` 列取值）。
enum XrayType {
  person('per'),
  place('loc'),
  org('org'),
  term('term'),
  abbr('abbr'),
  book('book');

  const XrayType(this.code);
  final String code;

  static XrayType fromCode(String c) =>
      values.firstWhere((t) => t.code == c, orElse: () => term);
}

/// 跨类型仲裁优先级：同名只留排前面的那一类（§4 后处理第 1 条）。
const List<XrayType> xrayTypePrecedence = [
  XrayType.person,
  XrayType.place,
  XrayType.org,
  XrayType.abbr,
  XrayType.book,
  XrayType.term,
];

/// 通道位标志（`xray_entity.src_channels`·位序＝设计书 §4 通道号）。
class XrayChan {
  static const int regex = 1 << 0;
  static const int ngram = 1 << 1;
  static const int gazetteer = 1 << 2;
  static const int dialog = 1 << 3;
  static const int toc = 1 << 4;
}

/// 出场锚点：只存「章+段」，页码按当前排版现算（§6）。
class XrayMention {
  const XrayMention(this.ch, this.para, [this.snippet]);
  final int ch;
  final int para;
  final String? snippet;
}

/// 候选实体（引擎产出物；落库映射见批1d DAO）。
class XrayEntity {
  XrayEntity(this.name, this.type);

  final String name;
  XrayType type;
  int channels = 0;
  int n = 0;
  bool tocFlag = false;
  double score = 0;
  double pmi = 0;

  /// 后处理降权系数（称谓后缀未并条时 0.4，其余 1.0）。
  double weight = 1.0;
  final Set<int> _chs = {};
  final List<XrayMention> mentions = [];

  /// 别名（称谓组合名：`探长李伟` / `李伟探长` → 核心名 `李伟` 的 alias）。
  final List<String> aliases = [];

  /// 跨章数（`xray_entity.chs`）。
  int get chs => _chs.length;
  int get firstCh => mentions.isEmpty ? 0 : mentions.first.ch;
  int get firstPara => mentions.isEmpty ? 0 : mentions.first.para;

  /// 锚点全量存，context 截断存（§6/§10 体积决策：出场 1.2 万锚点 ≈100KB 可全存，
  /// 但带文摘到 6~25MB 必须限流——只有**前 6 条**允许携带 snippet）。
  /// 批A 补齐：此前 `mentions.length < 6` 把锚点本身也截断了，F5 出场列表/
  /// 迷你分布条/F12 剧透过滤都要求全量锚点；计分路径（n/_chs）一字未动，GT 不受影响。
  void hit(int ch, int para, {String? snippet}) {
    n++;
    _chs.add(ch);
    mentions.add(XrayMention(ch, para, snippet));
  }

  /// 只登记位置、不加重提及数（术语的第二遍用这条：计数已由全局 n-gram 给出）。
  void anchorOnly(int ch, int para, {String? snippet}) {
    _chs.add(ch);
    mentions.add(XrayMention(ch, para, snippet));
  }
}

/// 自适应阈值（§4「按文本量自适应」·设置项「索引灵敏度」= sens）。
class XrayThresholds {
  const XrayThresholds({
    required this.per,
    required this.loc,
    required this.org,
    required this.abbr,
    required this.term,
    this.book = 1,
    this.pmiFloor = 0.5,
    this.pmiMinLen = 3,
  });

  final int per;
  final int loc;
  final int org;
  final int abbr;
  final int term;
  final int book;
  final double pmiFloor;
  final int pmiMinLen;

  /// 预研口径：`scale = max(1, chars ~/ 500000)`，各类 `min(cap, step*scale)`。
  factory XrayThresholds.forChars(int chars, {double sens = 1.0}) {
    final scale = math.max(1, chars ~/ 500000);
    int cap(int maxV, int step) => math.min(maxV, step * scale);
    return XrayThresholds(
      per: cap(20, 3),
      loc: cap(20, 3),
      org: cap(12, 2),
      abbr: cap(10, 3),
      term: cap(200, 15),
    ).scaled(sens);
  }

  /// 灵敏度倍率（低=1.6 收得更紧 / 中=1.0 / 高=0.7 收得更松）。
  XrayThresholds scaled(double k) => k == 1.0
      ? this
      : XrayThresholds(
          per: (per * k).round().clamp(1, 9999),
          loc: (loc * k).round().clamp(1, 9999),
          org: (org * k).round().clamp(1, 9999),
          abbr: (abbr * k).round().clamp(1, 9999),
          term: (term * k).round().clamp(1, 99999),
          pmiFloor: pmiFloor,
          pmiMinLen: pmiMinLen,
        );

  int of(XrayType t) => switch (t) {
        XrayType.person => per,
        XrayType.place => loc,
        XrayType.org => org,
        XrayType.abbr => abbr,
        XrayType.book => book,
        XrayType.term => term,
      };
}

/// 一章（批1d 从 DocStore 快照取段喂进来；[tocTitles] 全书目录标题，只传一次即可）。
class XrayChapter {
  const XrayChapter({required this.idx, required this.paras});
  final int idx;
  final List<String> paras;
}

/// 逐章流式抽取器。用法：`for (ch in chapters) e.runChapter(ch); final list = e.finish(tocTitles);`
class XrayEngine {
  XrayEngine({
    required this.bank,
    XrayUserLayer global = XrayUserLayer.none,
    XrayUserLayer book = XrayUserLayer.none,
    XrayThresholds? thresholds,
    int totalChars = 500000,
    double sens = 1.0,
    this.maxNgramSampleChars = 4000000,
  })  : lexicon = XrayLexicon(bank, global: global, book: book),
        thresholds = thresholds ??
            XrayThresholds.forChars(totalChars, sens: sens);

  final XrayWordBank bank;
  final XrayLexicon lexicon;
  final XrayThresholds thresholds;

  /// n-gram 采样正文字符上限（§8：大书按此截断，与预研 `term_sample_limit` 同口径）。
  final int maxNgramSampleChars;

  final Map<String, XrayEntity> _ents = {};
  final Map<String, int> _df = {};
  final Map<String, int> _gram = {};
  final Set<String> _chGrams = {};
  int _chapters = 0;
  int _sampled = 0;

  // ---------- 通道正则（逐条对照 xray_extract.py 的 pat_*）----------

  static final RegExp _trName =
      RegExp(r'[\u4e00-\u9fa5]{1,7}·[\u4e00-\u9fa5]{1,7}(?:·[\u4e00-\u9fa5]{1,7})*');
  static final RegExp _abbrPat = RegExp(r'\b[A-Z][A-Z0-9]{1,7}\b');
  static final RegExp _bookPat =
      RegExp(r'《([\u4e00-\u9fa5A-Za-z0-9·，,！？!?]{1,24})》');
  late final RegExp _locPat = RegExp('[\u4e00-\u9fa5]{1,6}(?:${_alt(bank.locSuffix)})');
  late final RegExp _orgPat = RegExp('[\u4e00-\u9fa5]{2,8}(?:${_alt(_orgSuffix)})');
  late final RegExp _sayPat = RegExp(
      '([$_surChars])([\u4e00-\u9fa5]{1,2})(?=说|道|问|答|笑道|喊道|低声|心想|认为|指出|回答|看着)');
  late final RegExp _surPat = RegExp(
      '(?:^|[^\u4e00-\u9fa5])([$_surChars])([\u4e00-\u9fa5]{1,2})(?![\u4e00-\u9fa5])');

  /// 通道 1d 的正确形态是**后处理路由**（见 [finish]），不是正则通道：
  /// 预研 `e_tier.py` 拿「已知名人集」当锚，只有 `X+称谓` 且 X 已在榜才并条；
  /// 我之前自造的前缀/后缀正则会把「探长李伟到场」整串当名，抓出 `李伟到场` 这种鬼。

  /// 单字机构尾缀易误伤（预研同一份排除表照搬）。
  static const Set<String> _orgExcluded = {
    '局', '署', '厅', '营', '连', '排', '班', '厂', '场', '站', '库', '部门', '科室',
  };

  List<String> get _orgSuffix =>
      bank.orgSuffix.where((s) => !_orgExcluded.contains(s)).toList();
  String get _surChars => bank.singleSurnames.toList().join();
  static String _alt(Iterable<String> ws) => ws.map(RegExp.escape).join('|');

  /// log2：dart:math 没有 log2，别写 `math.log2`（那是 Python 的习惯，会直接编不过）。
  static double _log2(double x) => math.log(x) / math.ln2;

  /// 含任一虚词字 → 丢弃（预研 `bad_word`）。
  bool _badWord(String w) {
    for (final r in w.runes) {
      if (bank.funcWords.contains(String.fromCharCode(r))) return true;
    }
    return false;
  }

  /// 跑一章：正则通道 + gazetteer + n-gram 计数（章内低频剪枝在末尾做）。
  void runChapter(XrayChapter ch) {
    _chapters++;
    _chGrams.clear();
    final chapterGram = <String, int>{};

    for (var pi = 0; pi < ch.paras.length; pi++) {
      final text = ch.paras[pi];
      if (text.isEmpty) continue;

      // 通道 1a：译名（整名 + `·` 拆出的分段名各算一次命中）
      for (final m in _trName.allMatches(text)) {
        final full = m.group(0)!;
        if (full.length >= 3 && !_badWord(full)) {
          _hit(full, XrayType.person, XrayChan.regex, ch.idx, pi, text);
        }
        for (final part in full.split('·')) {
          if (part.length >= 2 && !_badWord(part)) {
            _hit(part, XrayType.person, XrayChan.regex, ch.idx, pi, text);
          }
        }
      }

      // 通道 1b/1c：姓氏+名（语境动词版与边界版）
      for (final m in _sayPat.allMatches(text)) {
        _personFromSurname(m, ch.idx, pi, text);
      }
      for (final m in _surPat.allMatches(text)) {
        _personFromSurname(m, ch.idx, pi, text);
      }

      // 通道 3a：地名后缀兜底
      for (final m in _locPat.allMatches(text)) {
        final w = m.group(0)!;
        if (_badWord(w)) continue;
        _hit(w, XrayType.place, XrayChan.regex, ch.idx, pi, text);
      }
      // 通道 3b：机构后缀
      for (final m in _orgPat.allMatches(text)) {
        final w = m.group(0)!;
        if (_badWord(w)) continue;
        _hit(w, XrayType.org, XrayChan.regex, ch.idx, pi, text);
      }
      // 通道 4：英文缩写 / 书名号
      for (final m in _abbrPat.allMatches(text)) {
        _hit(m.group(0)!, XrayType.abbr, XrayChan.regex, ch.idx, pi, text);
      }
      for (final m in _bookPat.allMatches(text)) {
        _hit(m.group(1)!, XrayType.book, XrayChan.regex, ch.idx, pi, text);
      }
      // 通道 3c：地名词典最长匹配（首字分桶·禁大正则——§12）
      for (final w in _gazetteerHits(text)) {
        _hit(w, XrayType.place, XrayChan.gazetteer, ch.idx, pi, text);
      }

      // 通道 2：n-gram 计数（2~5 字·首尾虚词字过滤）
      if (_sampled < maxNgramSampleChars) {
        for (final seg in text.split(RegExp('[^\u4e00-\u9fa5]+'))) {
          _sampled += seg.length;
          for (var len = 2; len <= 5; len++) {
            for (var i = 0; i + len <= seg.length; i++) {
              final g = seg.substring(i, i + len);
              if (bank.funcWords.contains(g[0]) ||
                  bank.funcWords.contains(g[g.length - 1])) {
                continue;
              }
              chapterGram[g] = (chapterGram[g] ?? 0) + 1;
              _chGrams.add(g);
            }
          }
        }
      }
    }

    for (final g in _chGrams) {
      _df[g] = (_df[g] ?? 0) + 1;
    }
    // §8 内存护栏：章内只出现一次的候选不并入全局（跨章复现才有术语资格）
    for (final e in chapterGram.entries) {
      if (e.value < 2) continue;
      _gram[e.key] = (_gram[e.key] ?? 0) + e.value;
    }
  }

  void _personFromSurname(RegExpMatch m, int ch, int pi, String text) {
    final name = '${m.group(1)}${m.group(2)}';
    if (lexicon.looksCommonNoun(name) || name == m.group(1) || _badWordTail(name)) {
      return;
    }
    _hit(name, XrayType.person, XrayChan.regex, ch, pi, text);
  }

  /// 「X+名」里名部分整体是虚词/高频切割字时丢弃（预研 `name[1:] in CUTOFF`）。
  bool _badWordTail(String name) =>
      name.length > 1 && bank.funcWords.contains(name.substring(1));

  List<String> _gazetteerHits(String text) {
    final out = <String>[];
    for (var i = 0; i < text.length; i++) {
      for (final w in bank.gazetteerStartingWith(text[i])) {
        if (i + w.length > text.length) continue;
        if (text.substring(i, i + w.length) != w) continue;
        out.add(w);
        i += w.length - 1; // 消费整条地名：「地中海」命中后不再重复命中「中海」
        break;
      }
    }
    return out;
  }

  void _hit(String name, XrayType type, int chan, int ch, int pi, String text) {
    if (name.length < 2 || name.length > 24) return;
    if (lexicon.blocked(name) || lexicon.looksCommonNoun(name)) return;
    final key = '${type.code}|$name';
    final e = _ents.putIfAbsent(key, () => XrayEntity(name, type));
    e.channels |= chan;
    e.hit(ch, pi, snippet: e.mentions.length < 6 ? _window(text, name) : null);
  }

  /// 上下文摘录窗口：前 30 / 后 40 字（预研 `add_hit` 同口径）。
  static String _window(String text, String name) {
    final pos = text.indexOf(name);
    if (pos < 0) return name;
    final s = math.max(0, pos - 30);
    final e = math.min(text.length, pos + name.length + 40);
    return '${s > 0 ? '…' : ''}${text.substring(s, e)}${e < text.length ? '…' : ''}';
  }

  /// 通道 2 收口：全局 gram 计数 → 频次门槛 → PMI 结合度 → 包含抑制 → 成 term。
  void _harvestTerms() {
    final minFreq = thresholds.term;
    final cands = _gram.entries
        .where((e) => e.value >= minFreq)
        .where((e) => !bank.funcWords.contains(e.key) && !_badWord(e.key))
        .where((e) => !lexicon.blocked(e.key) && !bank.commonNouns.contains(e.key))
        .toList()
      ..sort((a, b) {
        if (a.key.length != b.key.length) return b.key.length.compareTo(a.key.length);
        return b.value.compareTo(a.value);
      });

    final kept = <String>[];
    final total = math.max(1, _gram.values.fold<int>(0, (s, v) => s + v));
    for (final e in cands) {
      final g = e.key, c = e.value;
      // 包含抑制①：已被更长候选包含 → 丢短
      if (kept.any((k) => k != g && k.contains(g))) continue;
      // 包含抑制②：更长版本计数不占优 → 丢这个扩展形
      //   （预研实测系数 0.5；设计书 §4 写的 0.7 未复现，此处以能过 GT 的实测值为准，批1e 复核）
      final supers = kept.where((k) => g != k && g.contains(k)).toList();
      if (supers.isNotEmpty) {
        final best = supers.map((k) => _gram[k] ?? 0).reduce(math.max);
        if (c < best * 0.5) continue;
      }
      // PMI 结合度：≥3 字且任一切分位 < 阈值 → 松散拼接（碎片/短语合成）丢弃
      double pm = double.infinity;
      if (g.length >= thresholds.pmiMinLen) {
        for (var k = 1; k < g.length; k++) {
          final ca = _gram[g.substring(0, k)] ?? 0;
          final cb = _gram[g.substring(k)] ?? 0;
          if (ca > 0 && cb > 0) {
            pm = math.min(pm, _log2(c * total / (ca * cb)));
          }
        }
        if (pm < thresholds.pmiFloor) continue;
      }
      kept.add(g);
      final e2 = _ents.putIfAbsent('${XrayType.term.code}|$g',
          () => XrayEntity(g, XrayType.term));
      e2.channels |= XrayChan.ngram;
      e2.pmi = pm.isFinite ? pm : 0;
      if (e2.n == 0) e2.n = c; // 术语的「提及数」＝全局计数（锚点不逐条存，见下方注释）
    }
  }

  /// 跨类型仲裁 + 称谓路由 + TOC 加权 + 置信分（§4 后处理三条）。
  List<XrayEntity> finish({List<String> tocTitles = const []}) {
    _harvestTerms();

    // 称谓组合名路由（预研 e_tier 口径：**后处理**，不是正则通道）——
    // 只有「X+称谓」里的 X 已经在人名榜上才并条；X 是常用词或太短就丢弃；
    // 其余留术语但乘 0.4（title-suffix 降权）。自造正则会把「探长李伟到场」整串当名。
    final perset = <String>{
      for (final e in _ents.values)
        if (e.type == XrayType.person) e.name,
    };
    for (final k in _ents.keys.toList()) {
      final e = _ents[k]!;
      if (e.type != XrayType.term) continue;
      String? t;
      for (final tt in bank.titles) {
        if (e.name.endsWith(tt) && e.name.length > tt.length) {
          t = tt;
          break;
        }
      }
      if (t == null) continue;
      final head = e.name.substring(0, e.name.length - t.length);
      if (perset.contains(head)) {
        final win = _ents['${XrayType.person.code}|$head']!;
        win.channels |= e.channels;
        win.n += e.n;
        if (!win.aliases.contains(e.name)) win.aliases.add(e.name);
        win.mentions.addAll(e.mentions);
        _ents.remove(k);
        continue;
      }
      if (head.length < 2 || bank.commonNouns.contains(head)) {
        _ents.remove(k);
        continue;
      }
      e.weight = 0.4;
    }

    // TOC 加权（通道 5）：目录标题里出现的实体提分并打标
    if (tocTitles.isNotEmpty) {
      final tocText = tocTitles.join(' ');
      for (final e in _ents.values) {
        if (e.name.length >= 2 && tocText.contains(e.name)) {
          e.tocFlag = true;
          e.channels |= XrayChan.toc;
        }
      }
    }

    // 跨类型仲裁：同名只留优先级最高的一类，其余的锚点/通道/计数并入保留者
    final byName = <String, List<XrayEntity>>{};
    for (final e in _ents.values) {
      (byName[e.name] ??= []).add(e);
    }
    final winners = <XrayEntity>[];
    for (final group in byName.values) {
      group.sort((a, b) => xrayTypePrecedence.indexOf(a.type)
          .compareTo(xrayTypePrecedence.indexOf(b.type)));
      final win = group.first;
      for (final loser in group.skip(1)) {
        win.channels |= loser.channels;
        win.n += loser.n;
        win._chs.addAll(loser._chs);
        win.mentions.addAll(loser.mentions);
      }
      winners.add(win);
    }

    // 置信分：√提及数 × 跨章对数增益 + 目录词加成。
    // **必须排在仲裁之后**——合并进来的 n 与跨章数要一起计分（先计分再合并＝白算）。
    final chs = math.max(1, _chapters);
    for (final e in winners) {
      final idf = _log2(1 + chs / math.max(1, e.chs));
      e.score = (math.sqrt(e.n) * idf + (e.tocFlag ? 1.0 : 0.0)) * e.weight;
    }

    final keep = winners
        .where((e) => e.n >= thresholds.of(e.type) || lexicon.userAdded(e.name))
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    _decided = true;
    // 术语的锚点不在第一遍收集（那时还不知道谁入选）→ 由 [anchorPass] 补第二遍。
    _pending = keep.where((e) => e.mentions.isEmpty).toList()
      ..sort((a, b) => b.name.length.compareTo(a.name.length));
    return keep;
  }

  /// 是否已定榜（决定术语走不走第二遍）。
  bool _decided = false;
  List<XrayEntity> _pending = const [];

  /// 定榜后是否还有「入选但无锚点」的实体（第二遍是否要跑）——批A 调度器
  /// 在 isolate 侧用它决定是否申请补扫章节，不触碰任何计分状态。
  bool get needsAnchorPass => _decided && _pending.isNotEmpty;

  /// 第二遍：只补**已入选但还没锚点**的实体（主要是术语），按章流式跑，不做整本驻留（§8）。
  /// 术语的「提及数」用的是全局计数（不是这一遍累加的），所以这里只登记位置与跨章集合。
  void anchorPass(XrayChapter ch) {
    if (!_decided) {
      throw StateError('anchorPass 必须在 finish() 定榜之后调用（术语锚点依赖入选集）');
    }
    if (_pending.isEmpty) return;
    for (var pi = 0; pi < ch.paras.length; pi++) {
      final text = ch.paras[pi];
      if (text.isEmpty) continue;
      for (final e in _pending) {
        var from = 0;
        while (true) {
          final at = text.indexOf(e.name, from);
          if (at < 0) break;
          e.anchorOnly(ch.idx, pi,
              snippet: e.mentions.length < 6 ? _window(text, e.name) : null);
          from = at + e.name.length;
        }
      }
    }
  }
}
