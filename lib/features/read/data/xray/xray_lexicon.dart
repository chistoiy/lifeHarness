/// X-Ray 词库资产加载与三层词库（需求 V1.54 · 设计书 §5）
///
/// 三层口径（**同构 loader**，设计书 §5 定案）：
///   预置只读（APK 资产 `assets/xray/dicts/*.txt`）
///     → 全局用户词典（`xray_userdict.scope == 'GLOBAL'`）
///       → 按书覆盖层（`xray_userdict.scope == book_md5`）
/// 覆盖层只登记「动作」（add / forbid / merge_pair），**不回写预置表**——
/// 这样重解析、增量解析、MD5 复用三条路径都能走同一套叠加逻辑（§7）。
///
/// 资产文件形态：一行一词，`#` 开头为注释，空行忽略。
/// 词表内容由 `docs/预研/xray-全书索引/code/` 的实测常量机械导出（见 git 历史里的生成器说明），
/// **不要手改内容口径**：简史 地名 23/23、小说术语噪声 7/40→0/40 这些 GT 都挂在这批词上。
library;

import 'dart:async';

/// 预置词表（只读）。加载一次供 isolate 复用；冷启目标 ~5ms（§5）。
class XrayWordBank {
  const XrayWordBank({
    required this.funcWords,
    required this.commonNouns,
    required this.titles,
    required this.singleSurnames,
    required this.compoundSurnames,
    required this.locSuffix,
    required this.orgSuffix,
    required this.stopEn,
    required this.gazetteer,
    required this.gazByFirst,
  });

  /// n-gram 首尾过滤用虚字/虚词（§4 通道 2）。
  final Set<String> funcWords;

  /// 常用名词表——**必须含裸称谓/亲属/日常名词**（§4 后处理：小说术语噪声 7/40→0/40 的那一刀）。
  final Set<String> commonNouns;

  /// 称谓词表：人名通道 + 组合名路由 + 别名合并三用（§4）。
  final Set<String> titles;

  /// 单姓（一字一姓，防伪用）。
  final Set<String> singleSurnames;

  /// 复姓：整体匹配，按长度倒序（§4 通道 1）。
  final List<String> compoundSurnames;

  final Set<String> locSuffix;
  final Set<String> orgSuffix;

  /// 英文虚词（防 eng 缩写通道被 the/and 污染）。
  final Set<String> stopEn;

  /// 地名词典（§4 通道 3 主通道）：按长度倒序，供最长匹配。
  final List<String> gazetteer;

  /// 首字分桶索引——设计书 §12 明令「禁 200 词大正则直译」，这里就是它的替代物。
  final Map<String, List<String>> gazByFirst;

  /// 资产文件名（顺序即 §5 表序；测试与生产共用同一份名单）。
  static const List<String> assetNames = [
    'func_words.txt',
    'common_nouns.txt',
    'titles.txt',
    'surnames.txt',
    'loc_suffix.txt',
    'org_suffix.txt',
    'stop_en.txt',
    'gazetteer.txt',
  ];

  static const String _dir = 'assets/xray/dicts/';

  /// 纯解析：`名字 → 文件正文`。不做 IO，便于 golden 用例直接喂 fixture。
  static XrayWordBank parse(Map<String, String> raw) {
    List<String> words(String name) {
      final src = raw[name];
      if (src == null) {
        throw StateError('X-Ray 词表缺文件：$name');
      }
      final out = <String>[];
      final seen = <String>{};
      for (final line in src.split('\n')) {
        final t = line.trim();
        if (t.isEmpty || t.startsWith('#')) continue;
        if (seen.add(t)) out.add(t);
      }
      if (out.isEmpty) throw StateError('X-Ray 词表为空：$name');
      return out;
    }

    final surnames = words('surnames.txt');
    final gaz = words('gazetteer.txt')
      ..sort((a, b) => a.length != b.length
          ? b.length.compareTo(a.length)
          : a.compareTo(b));
    final byFirst = <String, List<String>>{};
    for (final w in gaz) {
      (byFirst[w.substring(0, 1)] ??= <String>[]).add(w);
    }

    final bank = XrayWordBank(
      funcWords: words('func_words.txt').toSet(),
      commonNouns: words('common_nouns.txt').toSet(),
      titles: words('titles.txt').toSet(),
      singleSurnames: {for (final s in surnames) if (s.length == 1) s},
      compoundSurnames: [
        for (final s in surnames) if (s.length > 1) s,
      ]..sort((a, b) => a.length != b.length
          ? b.length.compareTo(a.length)
          : a.compareTo(b)),
      locSuffix: words('loc_suffix.txt').toSet(),
      orgSuffix: words('org_suffix.txt').toSet(),
      stopEn: words('stop_en.txt').toSet(),
      gazetteer: gaz,
      gazByFirst: byFirst,
    );
    return bank;
  }

  /// 通用装载：由调用方给「读哪个文件」的实现（生产=rootBundle，测试=File，isolate=预读字符串表）。
  static Future<XrayWordBank> load(
      FutureOr<String> Function(String path) read) async {
    final raw = <String, String>{};
    for (final n in assetNames) {
      raw[n] = await read(_dir + n);
    }
    return parse(raw);
  }

  /// 地名最长匹配：给定位置上的候选串，返回命中的最长地名（未命中=null）。
  /// 引擎侧按「首字分桶 + 长度倒序逐个前缀比」使用，避免大正则回溯。
  List<String> gazetteerStartingWith(String firstChar) =>
      gazByFirst[firstChar] ?? const <String>[];
}

/// 一个作用域的用户覆盖（来自 `xray_userdict`）。
class XrayUserLayer {
  const XrayUserLayer({this.added = const {}, this.forbidden = const {}});

  /// 用户加词（F8①）：即使抽取不到也成词条。
  final Set<String> added;

  /// 用户屏蔽（F8②）：**状态位而非降分**——阈值再低也不复活（§7）。
  final Set<String> forbidden;

  static const XrayUserLayer none = XrayUserLayer();
}

/// 三层词库视图：预置 → 全局 → 按书（后者优先）。
class XrayLexicon {
  const XrayLexicon(this.bank,
      {this.global = XrayUserLayer.none, this.book = XrayUserLayer.none});

  final XrayWordBank bank;
  final XrayUserLayer global;
  final XrayUserLayer book;

  /// 屏蔽判定：任一层 forbid 即永久屏蔽（含预置地名/常用词）。
  bool blocked(String word) =>
      book.forbidden.contains(word) || global.forbidden.contains(word);

  /// 加词判定：按书优先于全局（同词不同动作时，本书说了算）。
  bool userAdded(String word) =>
      book.added.contains(word) || global.added.contains(word);

  /// 常用名词噪声判定：预置表命中且未被用户显式加词救回。
  bool looksCommonNoun(String word) =>
      !userAdded(word) &&
      (bank.commonNouns.contains(word) || bank.funcWords.contains(word));

  /// 称谓命中（§4 路由：「称谓+名」组合名归到人名）。
  bool isTitle(String word) => bank.titles.contains(word);
}
