import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/features/read/data/xray/xray_engine.dart';
import 'package:lifeharness/features/read/data/xray/xray_lexicon.dart';

/// X-Ray 抽取引擎通道守护（需求 V1.54 · 设计书 §4）
///
/// 这些用例钉的是**通道语义**（每条正则该抓什么、不该抓什么、位标志归谁），
/// 与预研脚本 `code/xray_extract.py` 逐条对照。抽取**质量**（命中/噪声比）由批1e 的
/// golden 用例对着简史与阿加莎两本真书验收，这里不掺和。
void main() {
  const dir = 'assets/xray/dicts/';
  final bank = XrayWordBank.parse({
    for (final n in XrayWordBank.assetNames) n: File('$dir$n').readAsStringSync(),
  });

  // 小语料用低阈值；PMI 门先放开（专门的 PMI 用例另说）。
  const loose = XrayThresholds(
    per: 1,
    loc: 1,
    org: 1,
    abbr: 1,
    term: 2,
    pmiFloor: -999,
  );

  XrayEngine engine({
    XrayUserLayer global = XrayUserLayer.none,
    XrayUserLayer book = XrayUserLayer.none,
    XrayThresholds th = loose,
  }) =>
      XrayEngine(bank: bank, global: global, book: book, thresholds: th);

  /// 一章跑完并定榜，返回 `名字 → 实体`。
  Map<String, XrayEntity> runOnce(List<String> paras,
      {List<String> toc = const [], XrayEngine? e}) {
    final eng = e ?? engine();
    eng.runChapter(XrayChapter(idx: 0, paras: paras));
    return {for (final x in eng.finish(tocTitles: toc)) x.name: x};
  }

  test('通道 1a 译名：整名与 `·` 分段名都进人名榜', () {
    final r = runOnce(['查尔斯·布朗。布朗没有回答。']);
    expect(r.containsKey('查尔斯·布朗'), isTrue);
    expect(r['查尔斯·布朗']!.type, XrayType.person);
    expect(r.containsKey('查尔斯'), isTrue, reason: '分段名也记一条（预研双记口径）');
    expect(r.containsKey('布朗'), isTrue);
  });

  test('通道 1a 已知局限：译名后紧跟汉字会被整段吞进名字（预研同款过抓）', () {
    final r = runOnce(['查尔斯·布朗推开门']);
    expect(r.containsKey('查尔斯·布朗推开门'), isTrue,
        reason: '机制天花板：设计书 §10 坑② 由面板折叠 + 用户移除消化。'
            '这条断言是**故意钉住现状**的，真要收紧边界得先过批1e 的 GT 复测，别顺手改语义');
  });

  test('通道 1b/1c 姓氏：语境动词形命中；边界形要求前面不是汉字', () {
    final r = runOnce(['李伟说过这件事。', '赵强。']);
    expect(r.containsKey('李伟'), isTrue, reason: '「X说」语境动词前瞻');
    expect(r['李伟']!.type, XrayType.person);
    expect(r.containsKey('赵强'), isTrue, reason: '段首 + 后不接汉字');

    final noBoundary = runOnce(['他看见赵强离开了']);
    expect(noBoundary.containsKey('赵强'), isFalse,
        reason: '前后都是汉字时预研边界正则不抓——宁可漏，不可把「看见赵」当名');
  });

  test('通道 1d 称谓路由：X 已在名人榜才并条，组合形进别名', () {
    final r = runOnce(['李伟说过一句话。', '李伟探长来了，李伟探长又走了。']);
    final e = r['李伟'];
    expect(e, isNotNull, reason: 'say 通道先把李伟立成人名，路由才有锚');
    expect(e!.type, XrayType.person);
    expect(e.aliases, contains('李伟探长'));
    expect(r.containsKey('李伟探长'), isFalse, reason: '组合形不另立门户（同一个人两条）');
  });

  test('通道 1d 称谓路由：X 不在名人榜时降权留术语，不误升人名', () {
    final r = runOnce(['船长莫尔温来了，船长莫尔温又走了。']);
    expect(r.containsKey('船长莫尔温'), isTrue);
    expect(r['船长莫尔温']!.type, isNot(XrayType.person),
        reason: '预研口径：head 未知时只降权（×0.4）留术语，不当人名造');
  });

  test('通道 3：地名后缀段首可精确切出，gazetteer 位标志独立可辨', () {
    final r = runOnce(['河北省来了客人。', '他航经地中海。']);
    expect(r.containsKey('河北省'), isTrue);
    expect(r['河北省']!.channels & XrayChan.regex, isNonZero);
    final med = r['地中海'];
    expect(med, isNotNull);
    expect(med!.type, XrayType.place);
    expect(med.channels & XrayChan.gazetteer, isNonZero,
        reason: 'gazetteer 是地名主通道，位标志必须留下（面板要显示来源）');
    expect(r.values.where((e) => e.name == '地中海'), hasLength(1));
  });

  test('通道 3a 已知局限：后缀通道无左边界，句中地名被过抓+虚词过滤联手漏掉', () {
    final r = runOnce(['他先到了河北省。']);
    expect(r.containsKey('河北省'), isFalse);
    expect(r.keys.where((k) => k.endsWith('河北省')), isEmpty,
        reason: '后缀正则贪婪前粘成「他先到了河北省」，又因含虚字「了/到」被 bad_word 丢弃 → '
            '该通道只在段首/边界处有效。**句中地名召回靠 gazetteer 主通道**（§5），'
            '所以批1b 那张地名词典的规模直接决定漏报率，别把它当可选增强');
  });

  test('通道 3b 机构：后缀命中；单字易误伤的尾缀按排除表不抓', () {
    final r = runOnce(['恒信公司。', '他在北京站下车']);
    expect(r.containsKey('恒信公司'), isTrue);
    expect(r['恒信公司']!.type, XrayType.org);
    expect(r.containsKey('北京站'), isFalse, reason: '「站」在预研排除表里，误伤率太高');
  });

  test('通道 4：英文缩写与《》书名', () {
    final r = runOnce(['DNA 比对完成，详见《人类简史》。']);
    expect(r['DNA']!.type, XrayType.abbr);
    expect(r['人类简史']!.type, XrayType.book, reason: '书名号通道取号内文，不含《》');
  });

  test('后处理：常用名词与虚词一律出局（小说术语噪声的那一刀）', () {
    final r = runOnce(['朋友说朋友的事，声音很轻，朋友还在等']);
    expect(r.containsKey('朋友'), isFalse, reason: '常用名词表命中→永不成术语');
    expect(r.containsKey('事情'), isFalse);
  });

  test('通道 2 术语：n-gram 频次门槛 + 包含抑制丢短', () {
    final r = runOnce(['革命火种燃烧，革命火种不灭，革命是火种']);
    expect(r.containsKey('革命火种'), isTrue, reason: '4 字候选达标且跨位置复现');
    expect(r['革命火种']!.type, XrayType.term);
    expect(r.containsKey('革命'), isFalse, reason: '被更长候选包含→丢短（预研包含抑制①）');
  });

  test('通道 2 内存护栏：章内只出现一次的候选不并入全局', () {
    final e = engine();
    // 同一个 4 字串在三章各出现 1 次：全局看是 3 次，但每章都 <2 → 按 §8 剪枝口径不入榜
    for (var i = 0; i < 3; i++) {
      e.runChapter(XrayChapter(idx: i, paras: ['罕见合金登场']));
    }
    final names = e.finish().map((x) => x.name).toSet();
    expect(names, isNot(contains('罕见合金')),
        reason: '章内低频先剪枝，才守得住 1062 万字全集的内存曲线');
  });

  test('跨类型仲裁：同名只留优先级最高的一类，计数与通道并入', () {
    final r = runOnce(['李伟说过，李伟又来，李伟再次出现']);
    final hits = r['李伟'];
    expect(hits, isNotNull);
    expect(hits!.type, XrayType.person, reason: '同名同时成 term 与 per → 留 per');
    expect(r.values.where((e) => e.name == '李伟'), hasLength(1));
    expect(hits.n, greaterThanOrEqualTo(3));
  });

  test('用户层：屏蔽是状态位（阈值再低也不复活）；加词只免频次门槛、不凭空造条', () {
    final blocked = runOnce(['河北省来了客人。'],
        e: engine(global: const XrayUserLayer(forbidden: {'河北省'})));
    expect(blocked.containsKey('河北省'), isFalse, reason: 'F8② 永久屏蔽＝状态位，不是降分');

    // 加词的「全书补扫」是调度器的活（批1d）：引擎只保证「抽得到的词不再被频次门槛挤掉」，
    // 抽不到的词不在这里凭空造条目——否则 F8① 的补扫进度与锚点归属会错。
    const strict = XrayThresholds(per: 99, loc: 99, org: 99, abbr: 99, term: 99);
    final withAdd = engine(book: const XrayUserLayer(added: {'李伟'}), th: strict);
    withAdd.runChapter(XrayChapter(idx: 0, paras: ['李伟说过一句话。']));
    expect(withAdd.finish().map((x) => x.name), contains('李伟'),
        reason: '抽到了就该越过频次门槛留下');

    final noHit = engine(book: const XrayUserLayer(added: {'李伟'}), th: strict);
    noHit.runChapter(XrayChapter(idx: 0, paras: ['今天没有这个人出现']));
    expect(noHit.finish(), isEmpty, reason: '没抽到就不硬造——补扫归批1d 的调度器');
  });

  test('目录加权：目录标题里出现的实体打标并加成', () {
    final plain = runOnce(['他航经地中海。']);
    final toc = runOnce(['他航经地中海。'], toc: ['地中海的航路']);
    expect(toc['地中海']!.tocFlag, isTrue);
    expect(toc['地中海']!.channels & XrayChan.toc, isNonZero);
    expect(toc['地中海']!.score, greaterThan(plain['地中海']!.score),
        reason: '目录词提分（§4 通道 5）');
  });

  test('术语锚点走第二遍：定榜后才回填，且不重复计提及数', () {
    final e = engine();
    e.runChapter(XrayChapter(idx: 0, paras: ['革命火种燃烧，革命火种不灭']));
    final list = e.finish();
    final term = list.firstWhere((x) => x.name == '革命火种');
    expect(term.mentions, isEmpty, reason: '术语在第一遍没有锚点（入选集当时未知）');

    e.anchorPass(XrayChapter(idx: 0, paras: ['革命火种燃烧，革命火种不灭']));
    final n = term.n;
    expect(term.mentions, isNotEmpty);
    expect(term.mentions.first.ch, 0);
    e.anchorPass(XrayChapter(idx: 0, paras: ['革命火种燃烧，革命火种不灭']));
    expect(term.n, n, reason: 'anchorPass 只登记位置，不得再抬提及数');
  });

  test('调用顺序守护：未定榜就想取锚点 → 直接抛错', () {
    final e = engine();
    e.runChapter(XrayChapter(idx: 0, paras: ['革命火种燃烧']));
    expect(() => e.anchorPass(XrayChapter(idx: 0, paras: ['x'])), throwsStateError);
  });
}
