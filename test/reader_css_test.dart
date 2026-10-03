import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/features/read/data/epub_css.dart';

// 批三实现批·刀1 原书样式翻译器（V1.59 轮4②「完整档 CSS 解析」的抽取面）。
// 规格＝docs/预研/原书样式保真CSS画像-20261002.md §5.4 拍板 ＋ docs/handoff/
// 交棒话术-20261002-下一版实现批-F01-批C-R32精修.md §3B 末行「第一刀清单」。
// fixture 用《資治通鑑 特殊標點版》style0001.css **全文逐字**（画像 §5.1 实测件）：
// 分层信息到底在不在包里，这条测试就是回归——断言里出现的 class 名只是**样本数据**，
// 实现侧禁按 class 名映射（闸＝architecture_test R9）。

/// 卷一首篇所在文档的样式表（逐字取自包内 OEBPS/Styles/style0001.css）。
const _ztjCss = '''
body {
  line-height: 150%;
  word-spacing: 0;
  letter-spacing: 0;
  text-align: left;
  writing-mode: vertical-rl;
  -webkit-writing-mode: vertical-rl;
  -webkit-writing-mode: vertical-rl;
  margin-top: 2em;
  margin-bottom: 0.5em;
}

.origin {
  font-size: 1rem;
  font-weight: normal;
  text-indent: 2em;
}

.comment {
  color: navy;
  font-size: 1rem;
  font-weight: normal;
  text-indent: 2em;
  -webkit-margin-start: 2em;
}

.reign-title {
  color: SaddleBrown;
  font-size: 1rem;
  font-weight: bold;
  -webkit-margin-before: 0em;
}

.emperor {
  font-size: 1rem;
  font-weight: normal;
  text-indent: 2em;
  -webkit-margin-before: 2em;
}

.h1 {
  font-size: 1.5rem;
  font-weight: bold;
}

.h2 {
  font-size: 1rem;
}

.note {
  color: DarkGreen;
  font-weight: normal;
  font-size: 0.75rem;
  -webkit-margin-start: 0.5em;
  -webkit-margin-end: 0.5em;
}

.note1 {
  color: maroon;
  font-weight: normal;
  font-size: 0.75rem;
  -webkit-margin-start: 2.5em;
}

.note2 {
  color: DimGray;
  font-weight: bold;
  font-size: 0.88rem;
  -webkit-margin-before: 0.5em;
  -webkit-margin-after: 1em;
  text-align: right;
}

.note3 {
  color: DimGray;
  font-weight: normal;
  font-size: 0.6rem;
  line-height: 100%;
  -webkit-margin-before: 0em;
  -webkit-margin-after: 0em;
  text-align: right;
}

.note4 {
  color: DimGray;
  font-weight: normal;
}

.note5 {
  color: Purple;
  font-weight: normal;
  font-size: 0.75rem;
  -webkit-margin-start: 0.5em;
  -webkit-margin-end: 0.5em;
}

.ytz {
  height: 1em;
  width: 1em;
}

.ji {
  font-weight: bold;
  background-color: DimGray;
  color: White;
  border: 3px double White;
}

.kong {
  color: white;
  border: 1px solid black;
  background-color: DimGray;
  -webkit-margin-start: 0.15em;
  -webkit-margin-end: 0.15em;
}

.number {
  color: DimGray;
  font-weight: bold;
  font-size: 0.6rem;
  -webkit-text-combine: horizontal;
  -webkit-text-combine: horizontal;
  -webkit-margin-start: 0.35em;
  -webkit-margin-end: 0.35em;
}

.book-title {
  background-image: url(../Images/image02.gif);
  background-repeat: repeat-y;
  background-size: 1em 1em;
  background-position: 0% 0%;
  padding-left: 0.15em;
  margin-bottom: 0em;
}

.name {
  border-left: 0.12em solid;
}

.name1 {
  border: 0.1em solid;
}
''';

/// 章内另挂的目录样式表（style0002.css，含 tag+class 复合选择器）。
const _ztjTocCss = '''
div.sgc-toc-title {
  font-size: 1.5rem;
  margin-left: 0.2em;
  font-weight: bold;
}

div.sgc-toc-level-1 {
  margin-left: 0.5em;
}

div.sgc-toc-level-2 {
  margin-left: 1em;
}
''';

/// 从样式表里按「标签 + class」取一个元素的级联结果（祖先链带上 body/html，
/// 与真实文档树同构——竖排声明就在 body 上，不挂链就测不到「不静默」）。
EpubStyle _of(
  EpubStyleSheet sheet,
  String tag,
  Set<String> classes, {
  String inline = '',
  EpubUnsupportedSink? sink,
}) {
  final chain = [
    EpubElementRef(tag, classes, null),
    EpubElementRef('p', const {'origin'}, null),
    EpubElementRef('div', const {}, null),
    EpubElementRef('body', const {}, null),
    EpubElementRef('html', const {}, null),
  ];
  return sheet.resolve(chain, inline: inline, sink: sink);
}

String? _hex(EpubStyle s) =>
    s.color == null ? null : _hexOf(s.color!.toARGB32());
String _hexOf(int v) => v.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase();

/// CSS4 命名色实测值（画像 §5.2.2：本包零个 #rrggbb，只写十六进制解析＝全丢）。
void expectNamed(String name, String argbHex) {
  final c = cssColor(name);
  expect(c, isNotNull, reason: '命名色 $name 必须解出（预研 §5.2.2）');
  expect(_hexOf(c!.toARGB32()), argbHex, reason: '命名色 $name 取值');
}

void main() {
  final sheet = EpubStyleSheet.parse(_ztjCss);

  group('命名色与颜色形态', () {
    test('五层语义色逐字命中（蓝·绿·紫·棕·栗·灰）', () {
      expectNamed('navy', '000080');
      expectNamed('DarkGreen', '006400');
      expectNamed('Purple', '800080');
      expectNamed('SaddleBrown', '8B4513');
      expectNamed('maroon', '800000');
      expectNamed('DimGray', '696969');
      expectNamed('White', 'FFFFFF');
      expectNamed('white', 'FFFFFF');
    });

    test('十六进制/函数式/脏值', () {
      expect(_hexOf(cssColor('#6c483e')!.toARGB32()), '6C483E');
      expect(_hexOf(cssColor('#abc')!.toARGB32()), 'AABBCC');
      expect(_hexOf(cssColor('rgb(18, 52, 86)')!.toARGB32()), '123456');
      expect(_hexOf(cssColor('rgba(0, 128, 0, .5)')!.toARGB32()), '008000');
      expect(cssColor('rgba(0, 128, 0, .5)')!.a, closeTo(.5, .01));
      expect(_hexOf(cssColor('hsl(120, 100%, 50%)')!.toARGB32()), '00FF00');
      expect(cssColor('transparent'), isNull);
      expect(cssColor('currentColor'), isNull);
      expect(cssColor('not-a-color'), isNull);
      expect(cssColor(''), isNull);
    });
  });

  group('单位认账（预研 §2.4 与 §5.2.3）', () {
    test('rem 是本书主力单位：0.75rem＝注的小字', () {
      expect(cssFontRatio('0.75rem'), 0.75);
      expect(cssFontRatio('1.5rem'), 1.5);
      expect(cssFontRatio('1rem'), 1.0);
    });
    test('em/%/px/pt 换算；pt-px 换算后超 0.6~2.5 视同缺失', () {
      expect(cssFontRatio('1.2em'), 1.2);
      expect(cssFontRatio('75%'), closeTo(0.75, .001));
      expect(cssFontRatio('19px'), closeTo(1.1875, .0001));
      expect(cssFontRatio('9pt'), closeTo(0.75, .0001));
      expect(cssFontRatio('40px'), closeTo(2.5, .0001)); // 边界内
      expect(cssFontRatio('60px'), isNull, reason: '3.75× 超界＝脏值，按缺失处理');
      expect(cssFontRatio('12'), isNull, reason: '无单位非零值 CSS 本就非法');
      expect(cssFontRatio('calc(1em + 2px)'), isNull, reason: '认不了就跳过，不许抛');
      expect(cssFontRatio('vh'), isNull);
    });
    test('logical/webkit 边距与 text-indent 都按 em 记账', () {
      expect(cssLengthInEm('2em'), 2.0);
      expect(cssLengthInEm('.5em'), 0.5);
      expect(cssLengthInEm('0em'), 0.0);
      expect(cssLengthInEm('3px'), closeTo(3 / 16, .0001));
      expect(cssLengthInEm('150%'), 1.5);
    });
    test('line-height 数字/百分比，normal 与超界＝缺失', () {
      expect(cssLineRatio('150%'), 1.5);
      expect(cssLineRatio('1.2'), 1.2);
      expect(cssLineRatio('normal'), isNull);
      expect(cssLineRatio('9'), isNull);
    });
    test('font-weight：关键字与数值归一，拼写错误＝ null（预研 §2.2）', () {
      expect(cssFontWeight('bold'), 700);
      expect(cssFontWeight('normal'), 400);
      expect(cssFontWeight('600'), 600);
      expect(cssFontWeight('blod'), isNull, reason: '上游拼写错误必须静默回落');
    });
    test('text-align：webkit 前缀与 start/end 归一', () {
      expect(cssTextAlign('right'), 'right');
      expect(cssTextAlign('-webkit-center'), 'center');
      expect(cssTextAlign('start'), 'left');
      expect(cssTextAlign('auto'), isNull);
    });
  });

  group('通鉴分层：五层色＋字号＋边距按声明翻出（画像 §5.1 的回归）', () {
    test('注＝绿 + 0.75 倍 + 左右 0.5em 夹注距', () {
      final s = _of(sheet, 'span', {'note'});
      expect(_hex(s), '006400');
      expect(s.fontRatio, 0.75);
      expect(s.marginLeftEm, 0.5);
      expect(s.marginRightEm, 0.5);
      expect(s.hasSemantics, isTrue, reason: '有白名单属性才进 runs（§5.4 拍板②）');
    });

    test('校勘记＝紫 · 异体注＝栗 · 按语＝灰 · 纪年＝棕粗体', () {
      expect(_hex(_of(sheet, 'span', {'note5'})), '800080');
      expect(_hex(_of(sheet, 'span', {'note1'})), '800000');
      final n2 = _of(sheet, 'span', {'note2'});
      expect(_hex(n2), '696969');
      expect(n2.fontRatio, closeTo(0.88, .0001));
      expect(n2.align, 'right');
      final reign = _of(sheet, 'span', {'reign-title'});
      expect(_hex(reign), '8B4513');
      expect(reign.weight, 700);
    });

    test('史评段（p.comment）＝蓝 + 段前缩进 2em，且继承 body 的行距与对齐', () {
      final s = _of(sheet, 'p', {'comment'});
      expect(_hex(s), '000080');
      expect(s.indentEm, 2.0);
      expect(s.marginLeftEm, 2.0, reason: '-webkit-margin-start 必须认账（§5.2.4）');
      expect(s.lineRatio, 1.5);
      expect(s.align, 'left');
      expect(s.marginTopEm, 2.0, reason: 'body 的 margin-top 沿祖先链级联下来');
    });

    test('「与基准同值」不记语义：1rem / normal 不产生 span（§5.3 性能口径）', () {
      final s = _of(sheet, 'p', {'origin'});
      expect(s.fontRatio, isNull, reason: '1rem 与用户基准同值，进 runs 是白拆一刀');
      expect(s.weight, isNull, reason: 'normal 同 400＝默认字重');
      expect(s.indentEm, 2.0, reason: '但缩进是段级语义，照记');
      expect(s.hasSemantics, isFalse);
    });

    test('色块标签（臣光曰/考异）＝白字灰底 + 描边，底色与字色都要管（§5.2.5）', () {
      final ji = _of(sheet, 'span', {'ji'});
      expect(_hex(ji), 'FFFFFF');
      expect(_hexOf(ji.backgroundColor!.toARGB32()), '696969');
      expect(ji.weight, 700);
      expect(ji.hasBorder, isTrue);
      expect(ji.borderTop!.style, 'double');
      expect(ji.borderTop!.widthPx, 3.0, reason: 'border: 3px double White 顺序不固定也要认');
      expect(_hexOf(ji.borderTop!.color!.toARGB32()), 'FFFFFF');
      final kong = _of(sheet, 'span', {'kong'});
      expect(kong.borderLeft!.style, 'solid');
      expect(_hexOf(kong.borderLeft!.color!.toARGB32()), '000000');
    });

    test('专名线走通用 border 通道：border-left 无边色＝跟字色', () {
      final nm = _of(sheet, 'span', {'name'});
      expect(nm.borderLeft?.isLine, isTrue);
      expect(nm.borderLeft!.widthEm, closeTo(0.12, .0001));
      expect(nm.borderLeft!.color, isNull, reason: '未声明边色＝currentColor，由渲染处跟字色');
      expect(nm.borderTop, isNull);
      final nm1 = _of(sheet, 'span', {'name1'});
      expect(nm1.hasBorder, isTrue, reason: 'border 简写＝四边');
      expect(nm1.borderBottom?.isLine, isTrue);
    });

    test('书名线（background-image 平铺 gif）＝近似降级为下划线，且不静默', () {
      final sink = EpubUnsupportedSink();
      final bt = _of(sheet, 'span', {'book-title'}, sink: sink);
      expect(bt.underline, isTrue, reason: '原型 ?r32=st1 用波浪线示意，通用落点＝下划线');
      final keys = sink.toList().map((u) => u.key).toSet();
      expect(keys, contains('padding'), reason: '行内 padding 表达不了→近似降级');
      expect(keys, contains('background-image'), reason: 'gif 平铺线也要留痕');
      expect(
        sink.toList()
            .where((u) => u.key == 'padding')
            .every((u) => u.kind == EpubUnsupportedKind.cssFlattened),
        isTrue,
      );
    });

    test('卷次编号：0.6 倍小字 + 灰，-webkit-text-combine 记近似降级', () {
      final sink = EpubUnsupportedSink();
      final n = _of(sheet, 'span', {'number'}, sink: sink);
      expect(n.fontRatio, 0.6);
      expect(_hex(n), '696969');
      expect(n.marginLeftEm, 0.35);
    });
  });

  group('不静默降级（§5.4 与路线说明：结构性丢弃必须留痕）', () {
    test('body 的 writing-mode: vertical-rl → 竖排提示项非空', () {
      final sink = EpubUnsupportedSink();
      _of(sheet, 'span', {'note'}, sink: sink);
      final structural =
          sink.toList().where((u) => u.kind == EpubUnsupportedKind.cssStructural).toList();
      expect(structural, isNotEmpty, reason: '用例断言「不支持项」标记非空＝可测口径');
      expect(structural.map((u) => u.key), contains('writing-mode'));
      expect(structural.first.describe(), contains('竖排直排'));
      expect(structural.first.describe(), contains('当前按横排单栏显示'));
    });

    test('多栏/浮动/表格/RTL 各自留痕，且不产出样式', () {
      final s = EpubStyleSheet.parse('''
        .a { column-count: 2; color: red; }
        .b { float: left; }
        .c { display: table; }
        .d { direction: rtl; }
      ''');
      final sink = EpubUnsupportedSink();
      final red = s.resolve([EpubElementRef('p', {'a'}, null)], sink: sink);
      expect(_hex(red), 'FF0000', reason: '结构性丢弃只丢那一条，同规则其余照用');
      expect(sink.toList().map((u) => u.key), contains('column-count'));
      s.resolve([EpubElementRef('p', {'b'}, null)], sink: sink);
      s.resolve([EpubElementRef('p', {'c'}, null)], sink: sink);
      s.resolve([EpubElementRef('p', {'d'}, null)], sink: sink);
      final keys = sink.toList().map((u) => u.key).toSet();
      expect(keys, containsAll(['column-count', 'float', 'display', 'direction']));
      expect(
        sink.toList()
            .where((u) => u.key != 'column-count')
            .every((u) => u.kind == EpubUnsupportedKind.cssStructural),
        isTrue,
        reason: '结构性丢弃那一类都要留痕，不许混进近似降级',
      );
    });

    test('float:none 与 vertical-rl 之外的 writing-mode 不算结构性丢弃', () {
      final s = EpubStyleSheet.parse('.x { float: none; writing-mode: horizontal-tb; }');
      final sink = EpubUnsupportedSink();
      s.resolve([EpubElementRef('p', {'x'}, null)], sink: sink);
      expect(sink.toList(), isEmpty);
    });
  });

  group('级联与选择器', () {
    test('特异性：#id > .class tag > .class > tag；同值后写覆盖先写', () {
      final s = EpubStyleSheet.parse('''
        p { color: red; }
        .c { color: green; }
        p.c { color: blue; }
        #i { color: black; }
      ''');
      EpubStyle pick(String tag, Set<String> cls, {String? id}) =>
          s.resolve([EpubElementRef(tag, cls, id)]);
      expect(_hexOf(pick('p', {}).color!.toARGB32()), 'FF0000');
      expect(_hexOf(pick('p', {'c'}).color!.toARGB32()), '0000FF', reason: 'p.c(11) 压 .c(10)');
      expect(_hexOf(pick('p', {'c'}, id: 'i').color!.toARGB32()), '000000');
      final later = EpubStyleSheet.parse('p { color: red; } p { color: blue; }');
      expect(
        _hexOf(later.resolve([EpubElementRef('p', {}, null)]).color!.toARGB32()),
        '0000FF',
        reason: '同特异性按源码序后写者胜',
      );
    });

    test('!important 恒胜普通声明（跨特异性）；样式表 !important 压过内联普通值', () {
      final s = EpubStyleSheet.parse('#i { color: red; } .c { color: green !important; }');
      final r = s.resolve([EpubElementRef('p', {'c'}, 'i')]);
      expect(_hexOf(r.color!.toARGB32()), '008000');
      final r2 = s.resolve([
        EpubElementRef('p', {'c'}, 'i'),
      ], inline: 'color: blue;');
      expect(_hexOf(r2.color!.toARGB32()), '008000', reason: '内联普通压不过样式表 important');
      final r3 = s.resolve([
        EpubElementRef('p', {}, null),
      ], inline: 'color: blue !important;');      expect(_hexOf(r3.color!.toARGB32()), '0000FF', reason: '内联 important 恒胜');
    });

    test('内联 style 压过样式表普通值（优先级表末位仍要能用）', () {
      final s = EpubStyleSheet.parse('p { color: red; }');
      final r = s.resolve([EpubElementRef('p', {}, null)], inline: ';color:black;');
      expect(_hexOf(r.color!.toARGB32()), '000000', reason: '预研 §2.1：值以分号起头要滤空段');
    });

    test('逗号选择器组与 tag+class 复合段、后代链', () {
      final s = EpubStyleSheet.parse('h1, .lead { font-size: 1.5rem; }');
      expect(s.resolve([EpubElementRef('h1', {}, null)]).fontRatio, 1.5);
      expect(s.resolve([EpubElementRef('p', {'lead'}, null)]).fontRatio, 1.5);
      final toc = EpubStyleSheet.parse(_ztjTocCss);
      expect(_of(toc, 'div', {'sgc-toc-title'}).fontRatio, 1.5);
      final desc = EpubStyleSheet.parse('body p { color: red; }');
      expect(
        _hexOf(desc
            .resolve([
              EpubElementRef('p', {}, null),
              EpubElementRef('div', {}, null),
              EpubElementRef('body', {}, null),
            ])
            .color!
            .toARGB32()),
        'FF0000',
        reason: '后代选择器（中间隔一层也算）',
      );
      expect(
        desc.resolve([EpubElementRef('p', {}, null), EpubElementRef('div', {}, null)]).color,
        isNull,
        reason: '缺 body 就不该命中',
      );
    });

    test('不支持的选择器形态整条不参与（宁可不涂不可错涂）', () {
      final s = EpubStyleSheet.parse('''
        p:first-child { color: red; }
        div > span { color: red; }
        a[href] { color: red; }
        .ok { color: green; }
      ''');
      expect(s.resolve([EpubElementRef('p', {}, null)]).color, isNull);
      expect(
        s.resolve([
          EpubElementRef('span', {}, null),
          EpubElementRef('div', {}, null),
        ]).color,
        isNull,
      );
      expect(
        _hexOf(s.resolve([EpubElementRef('a', {'ok'}, null)]).color!.toARGB32()),
        '008000',
        reason: '同一条 a[href] 不命中，但 .ok 仍要生效',
      );
    });

    test('注释、at-rule、未闭合规则都不炸（脏包容忍）', () {
      final s = EpubStyleSheet.parse('''
        /* 前置说明：分层在 class 上 */
        .late { color: red; }
        @charset "utf-8";
        @font-face { font-family: X; src: url(a.otf); }
        @media (max-width: 300px) { .q { color: blue; } }
        p { color: green }
        .broken { color: red;
      ''');
      expect(_hexOf(s.resolve([EpubElementRef('p', {}, null)]).color!.toARGB32()), '008000');
      expect(_hexOf(s.resolve([EpubElementRef('div', {'late'}, null)]).color!.toARGB32()),
          'FF0000', reason: '注释结束后的规则照常解析');
      expect(s.resolve([EpubElementRef('div', {'q'}, null)]).color, isNull,
          reason: '@media 整块跳过：本项目不跟媒体查询');
    });

    test('空样式表与空 body 都得到「无声明」样式（跟随用户主题）', () {
      expect(EpubStyleSheet.parse('').rules, isEmpty);
      final s = EpubStyleSheet.empty().resolve([EpubElementRef('p', {}, null)]);
      expect(s.isEmpty, isTrue);
      expect(s.hasSemantics, isFalse);
    });
  });

  group('样式叠加与合并', () {
    test('merge 取后者非空值（run 样式＝段级叠 span）', () {
      const para = EpubStyle(color: null, fontRatio: 0.75, indentEm: 2);
      const run = EpubStyle(color: null, weight: 700);
      final m = para.merge(run);
      expect(m.fontRatio, 0.75);
      expect(m.weight, 700);
      expect(m.indentEm, 2.0);
      expect(para.merge(null), same(para));
    });

    test('命中快筛按最右复合段建桶（672k span 不能逐元素全表扫，§5.3）', () {
      expect(sheet.mayAffect('span', {'note'}), isTrue);
      expect(sheet.mayAffect('body', const {}), isTrue, reason: 'body{…} 的落点就是 body');
      expect(EpubStyleSheet.parse(_ztjTocCss).mayAffect('div', {'sgc-toc-title'}), isTrue,
          reason: 'div.sgc-toc-title 复合段的两段都算落点');
      expect(sheet.mayAffect('div', {'sgc-toc-title'}), isFalse,
          reason: '另一份样式表里没有这条规则');
      expect(sheet.mayAffect('em', const {}), isFalse, reason: '包里没有 em 规则');
      expect(sheet.mayAffect('em', const {}, hasInline: true), isTrue,
          reason: '内联 style 与样式表无关，必须解析');
    });

    test('相等判定与边/颜色同值合并（runs 合并与快照样式字典都靠它）', () {
      const a = EpubStyle(color: null, fontRatio: 0.75);
      const b = EpubStyle(color: null, fontRatio: 0.75);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a.merge(const EpubStyle(weight: 700)), isNot(equals(a)));
      expect(
        EpubBorder(widthEm: 0.12, style: 'solid'),
        equals(EpubBorder(widthEm: 0.12, style: 'solid')),
      );
    });
  });
}
