import 'dart:convert' show jsonDecode, jsonEncode, utf8;
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/providers.dart' show sharedPreferencesProvider;
import 'package:lifeharness/features/read/data/epub_cache.dart';
import 'package:lifeharness/features/read/data/epub_doc.dart';
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:lifeharness/features/read/domain/book.dart';
import 'package:lifeharness/features/read/domain/reader_cfg.dart';
import 'package:lifeharness/features/read/presentation/read_providers.dart';
import 'package:lifeharness/features/read/presentation/reader/reader_page.dart';
import 'package:lifeharness/features/read/presentation/reader/reader_pager.dart';

// 实现批2 · 工单 R3-2「EPUB 精排止血四条」段级判定回归（真机轮3《資治通鑑》反馈）。
//   ① 注释/脚注体 → 正文色 + 小一号（不再套链接绿）
//   ② 正文取消两端对齐（默认左对齐，两端对齐只在外观里开·默认关）
//   ③ 书内自带缩进的段不再叠加我们的两全角缩进（按段判断，不一刀切）
//   ④ 行内 <a> 只有外链（带 scheme 或跨章）给链接色，站内锚点给正文色
// 独立文件防 isolate 污染；fixture 用 ZipEncoder 现场打包，不引外部书。

/// 全角空格（源码里放不可见字符会被编辑器/工具链吞掉，按码位构造）。
final String _fw = String.fromCharCode(0x3000);

Uint8List _zipBytes(Map<String, String> files) {
  final a = Archive();
  files.forEach((name, content) {
    final bytes = utf8.encode(content);
    a.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  return Uint8List.fromList(ZipEncoder().encode(a)!);
}

const _container =
    '''<?xml version="1.0"?>
<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>''';

const _opf = '''<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>資治通鑑 特殊標點版（樣本）</dc:title><dc:creator>司馬光</dc:creator>
  </metadata>
  <manifest>
    <item id="c1" href="text/c1.xhtml" media-type="application/xhtml+xml"/>
    <item id="c2" href="text/c2.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine><itemref idref="c1"/><itemref idref="c2"/></spine>
</package>''';

/// 卷一：标题分级 + 四种缩进写法（style 非 0 / 全角空格起头 / text-indent:0 反例 /
/// 源码换行缩进反例）+ 四种链接（脚注引用 · 站内锚点 · 跨章内链 · 外链）+
/// 三种注释体容器（aside epub:type=footnote · 祖先 div.class=footnote · div.class=annotation）。
String get _c1 =>
    '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head><title>卷一</title></head>
<body>
  <h1>資治通鑑卷第一</h1>
  <h2>周紀一</h2>
  <p style="text-indent:2em">起著雍攝提格，盡戊申，凡一年有奇。</p>
  <p>$_fw$_fw全角空格起头段。</p>
  <p style="text-indent:0">声明零缩进段。</p>
  <p>
    源码换行缩进段。
  </p>
  <p>普通正文段。<a epub:type="noteref" href="#fn1">注一</a><a href="#s2">站内锚点</a><a href="c2.xhtml">跨章内链</a><a href="https://example.org/x">外链</a></p>
  <section epub:type="footnotes">
    <aside epub:type="footnote" id="fn1"><p>胡三省注：作，謂能創制。</p></aside>
    <div class="footnote">類名腳注段。</div>
  </section>
  <div class="annotation">类名注释段。</div>
  <p>注释之后的普通段。</p>
</body></html>''';

const _c2 = '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>卷二</title></head>
<body><h1>周紀二</h1><p>次卷正文。</p></body></html>''';

Uint8List _gujiEpub() => _zipBytes({
  'mimetype': 'application/epub+zip',
  'META-INF/container.xml': _container,
  'OEBPS/content.opf': _opf,
  'OEBPS/text/c1.xhtml': _c1,
  'OEBPS/text/c2.xhtml': _c2,
});

void main() {
  group('R3-2 解析层 · 段级判定（注释体 / 自带缩进 / 链接语义）', () {
    final doc = EpubDoc.parse(_gujiEpub());
    final ps = doc.chapters[0].paras;
    EpubPara by(String frag) => ps.firstWhere((p) => p.text.contains(frag));

    test('标题分级仍按 heading 落段（注释判定不误伤）', () {
      expect(by('資治通鑑卷第一').kind, EpubParaKind.heading);
      expect(by('資治通鑑卷第一').headingLevel, 1);
      expect(by('周紀一').headingLevel, 2);
      expect(by('周紀一').annotation, isFalse);
    });

    test('③ 自带缩进按段判定：style text-indent 与全角空格起头算，0 与源码缩进不算', () {
      expect(by('起著雍攝提格').ownIndent, isTrue, reason: '段内 style text-indent:2em');
      expect(by('全角空格起头段').ownIndent, isTrue, reason: '正文以全角空格起头');
      expect(by('声明零缩进段').ownIndent, isFalse, reason: 'text-indent:0 是显式不缩进');
      expect(by('源码换行缩进段').ownIndent, isFalse, reason: '源码排版缩进不算书内缩进');
      expect(by('普通正文段').ownIndent, isFalse);
    });

    test('① 注释体：epub:type 含 footnote/note、aside、类名 note|footnote|annotation 都算', () {
      expect(by('胡三省注').annotation, isTrue, reason: 'aside epub:type=footnote');
      expect(by('類名腳注段').annotation, isTrue, reason: '祖先 div class=footnote 段级继承');
      expect(by('类名注释段').annotation, isTrue, reason: 'div class=annotation');
    });

    test('① 注释体不扩散：容器外的普通段仍是正文（按段判断不一刀切）', () {
      expect(by('注释之后的普通段').annotation, isFalse);
      expect(by('普通正文段').annotation, isFalse);
      expect(by('全角空格起头段').annotation, isFalse);
    });

    test('④ 链接语义：脚注引用与站内锚点不给链接色，跨章与外链才给', () {
      final p = by('普通正文段');
      EpubLink one(String label) =>
          p.links.firstWhere((e) => p.text.substring(e.start, e.end) == label);
      final ref = one('注一');
      expect(ref.annotation, isTrue, reason: 'a epub:type=noteref');
      expect(ref.external, isFalse);
      expect(ref.sameDoc, isTrue);
      expect(ref.usesLinkColor, isFalse, reason: '①＋④ 注释引用一律正文色');
      final anchor = one('站内锚点');
      expect(anchor.sameDoc, isTrue, reason: '#s2 纯 fragment＝站内锚点');
      expect(anchor.annotation, isFalse);
      expect(anchor.usesLinkColor, isFalse, reason: '④ 站内锚点不给链接色');
      final cross = one('跨章内链');
      expect(cross.href, 'OEBPS/text/c2.xhtml');
      expect(cross.external, isFalse);
      expect(cross.usesLinkColor, isTrue, reason: '④ 跨章＝跳出去，给链接色');
      final ext = one('外链');
      expect(ext.external, isTrue);
      expect(ext.usesLinkColor, isTrue, reason: '④ 带 scheme 外链给链接色');
    });
  });

  group('R3-2 渲染层纯函数 · 判定分派', () {
    const plain = EpubPara(kind: EpubParaKind.text, text: '正文段。');
    const own = EpubPara(
      kind: EpubParaKind.text,
      text: '自带缩进段。',
      ownIndent: true,
    );
    const note = EpubPara(
      kind: EpubParaKind.text,
      text: '胡三省注：…',
      annotation: true,
    );
    const head = EpubPara(
      kind: EpubParaKind.heading,
      text: '章标题',
      headingLevel: 1,
      annotation: true,
    );

    test('③ auto 跟随原书：自带缩进的段不叠加，普通段照旧两全角', () {
      expect(paraDisplayText(plain, indMode: 'auto'), startsWith(kParaIndent));
      expect(paraDisplayText(own, indMode: 'auto'), isNot(startsWith(kParaIndent)));
      // 强制档与关闭档由用户说了算（配置面 R3-7 三档）。
      expect(paraDisplayText(own, indMode: '2'), startsWith(kParaIndent));
      expect(paraDisplayText(plain, indMode: 'none'), isNot(startsWith(kParaIndent)));
      // 旧两档调用口径不破：indent=false 等价 none。
      expect(paraDisplayText(plain, indent: false), plain.text);
      expect(paraDisplayText(plain), startsWith(kParaIndent));
      // 标题/引文/插图永不加前缀。
      expect(paraIndented(head, '2'), isFalse);
      expect(
        paraIndented(const EpubPara(kind: EpubParaKind.quote, text: 'q'), '2'),
        isFalse,
      );
    });

    test('① 注释体样式＝正文色 + 小一号；未标记的段零改动', () {
      final base = const TextStyle(fontSize: 19, color: Color(0xFF3B3630));
      final s = paraStyle(note, base);
      expect(s.fontSize, 19 * kAnnotationFsFactor);
      expect(s.color, const Color(0xFF3B3630).withValues(alpha: kAnnotationAlpha));
      expect(paraStyle(plain, base), same(base), reason: '未标记的段原对象返回');
      expect(paraStyle(head, base), same(base), reason: '标题另有字号档，不在此叠');
      expect(
        paraStyle(
          const EpubPara(
            kind: EpubParaKind.quote,
            text: '引文型注释。',
            annotation: true,
          ),
          base,
        ).fontSize,
        19 * kAnnotationFsFactor,
        reason: '引文型注释体也小一号（与 reader_stage 上屏同源）',
      );
    });

    test('④ 链接样式分派：外链绿 · 站内锚点正文色下划线 · 注释引用小字', () {
      final base = const TextStyle(fontSize: 19, color: Color(0xFF3B3630));
      const extLink = EpubLink(
        start: 0,
        end: 1,
        href: 'https://x.cn',
        external: true,
      );
      const crossLink = EpubLink(
        start: 0,
        end: 1,
        href: 'c2.xhtml',
        external: false,
      );
      const anchorLink = EpubLink(
        start: 0,
        end: 1,
        href: 'c1.xhtml',
        external: false,
        sameDoc: true,
      );
      const refLink = EpubLink(
        start: 0,
        end: 1,
        href: 'c1.xhtml',
        external: false,
        sameDoc: true,
        annotation: true,
      );
      expect(linkStyleFor(base, extLink).color, const Color(0xFF6366F1));
      expect(linkStyleFor(base, extLink).decoration, TextDecoration.underline);
      expect(linkStyleFor(base, crossLink).color, const Color(0xFF6366F1));
      expect(linkStyleFor(base, anchorLink).color, const Color(0xFF3B3630));
      expect(linkStyleFor(base, anchorLink).decoration, TextDecoration.underline);
      final r = linkStyleFor(base, refLink);
      expect(r.color, const Color(0xFF3B3630), reason: '① 注释引用绝不套绿');
      expect(r.fontSize, 19 * kAnnotationFsFactor);
    });

    test('① 测量随注释体字号一起缩（分页与上屏同源，否则按小字排、大字画）', () {
      const l = ReaderLayout(width: 400, height: 800);
      final body = '注' * 120;
      final annotated = EpubPara(
        kind: EpubParaKind.text,
        text: body,
        annotation: true,
      );
      final normal = EpubPara(kind: EpubParaKind.text, text: body);
      expect(
        EpubPager.paraHeight(annotated, l),
        lessThan(EpubPager.paraHeight(normal, l)),
      );
    });
  });

  group('R3-2 缓存与指纹', () {
    test('③ indMode 进分页指纹（改了缩进必须重排，否则真机假生效）', () {
      String fp(String im) => PagStore.fingerprint(
        const ReaderLayout(width: 400, height: 800).copyWith(indMode: im),
      );
      expect(fp('auto'), isNot(fp('2')));
      expect(fp('auto'), isNot(fp('none')));
      expect(fp('2'), isNot(fp('none')));
    });

    test('ReaderLayout.of 把 cfg 的缩进三档带进布局（预载与主屏同源）', () {
      final l = ReaderLayout.of(
        const ReaderCfg(indMode: 'none'),
        width: 400,
        height: 800,
      );
      expect(l.indMode, 'none');
      expect(l.indent, isFalse);
      expect(PagStore.fingerprint(l), contains('imnone'));
      final back = const ReaderLayout(width: 400, height: 800).copyWith(indMode: '2');
      expect(PagStore.fingerprint(l), isNot(PagStore.fingerprint(back)));
    });

    test('①③ 段级语义过 DocStore round-trip 不失真', () async {
      final tmp = Directory.systemTemp.createTempSync('lh_r32snap');
      final src = '${tmp.path}/book.epub';
      File(src).writeAsBytesSync(List.filled(64, 3));
      final doc = EpubDoc.parse(_gujiEpub());
      await DocStore.save(tmp.path, 'b1', DocStore.fingerprint(src), doc);
      final back = await DocStore.load(tmp.path, 'b1', DocStore.fingerprint(src));
      expect(back, isNotNull);
      final ps = back!.chapters[0].paras;
      EpubPara by(String frag) => ps.firstWhere((p) => p.text.contains(frag));
      expect(by('胡三省注').annotation, isTrue);
      expect(by('起著雍攝提格').ownIndent, isTrue);
      expect(by('注释之后的普通段').annotation, isFalse);
      final links = by('普通正文段').links;
      expect(
        links.firstWhere((e) => e.href == 'OEBPS/text/c2.xhtml').usesLinkColor,
        isTrue,
      );
      expect(
        links.firstWhere((e) => e.annotation).usesLinkColor,
        isFalse,
        reason: '注释引用标记随快照落盘',
      );
      back.lazy?.dispose();
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('旧版（v2）快照一律失效：缺新字段按 false 解出＝假生效，必须重解', () async {
      final tmp = Directory.systemTemp.createTempSync('lh_r32v2');
      final src = '${tmp.path}/book.epub';
      File(src).writeAsBytesSync(List.filled(64, 3));
      final fp = DocStore.fingerprint(src);
      await DocStore.save(tmp.path, 'b2', fp, EpubDoc.parse(_gujiEpub()));
      final idx = File('${DocStore.dirFor(tmp.path, 'b2')}/index.json');
      final m = (jsonDecode(idx.readAsStringSync()) as Map).cast<String, Object?>();
      expect(m['v'], DocStore.snapVersion);
      idx.writeAsStringSync(jsonEncode({...m, 'v': 2}));
      expect(await DocStore.load(tmp.path, 'b2', fp), isNull);
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
  });

  group('R3-2 阅读主屏端到端（② 左对齐 · ①③ 上屏）', () {
    sqfliteFfiInit();
    TestWidgetsFlutterBinding.ensureInitialized();

    late Database db;
    late ReadRepository repo;
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
      for (final sql in DbSchema.createStatements) {
        await db.execute(sql);
      }
      repo = ReadRepository(db);
    });
    tearDown(() => db.close());

    final doc = EpubDoc(
      format: 'EPUB3',
      title: '古籍书',
      author: '司馬光',
      toc: const [],
      chapters: [
        EpubChapter(href: 'c1', title: '卷一', paras: [
          const EpubPara(
            kind: EpubParaKind.heading,
            text: '資治通鑑卷第一',
            headingLevel: 1,
          ),
          const EpubPara(kind: EpubParaKind.text, text: '普通正文段。'),
          const EpubPara(
            kind: EpubParaKind.text,
            text: '自带缩进段。',
            ownIndent: true,
          ),
          const EpubPara(
            kind: EpubParaKind.text,
            text: '胡三省注：作，謂能創制。',
            annotation: true,
          ),
          const EpubPara(
            kind: EpubParaKind.text,
            text: '链接段：站内跨章外链注一',
            links: [
              EpubLink(
                start: 4,
                end: 6,
                href: 'c1.xhtml',
                external: false,
                sameDoc: true,
              ),
              EpubLink(start: 6, end: 8, href: 'c2.xhtml', external: false),
              EpubLink(start: 8, end: 10, href: 'https://x.cn', external: true),
              EpubLink(
                start: 10,
                end: 12,
                href: 'c1.xhtml',
                external: false,
                sameDoc: true,
                annotation: true,
              ),
            ],
          ),
        ]),
      ],
      imageCount: 0,
      totalChars: 60,
    );

    Future<void> open(WidgetTester t, String id) async {
      await useSurface(t, const Size(420, 780));
      await repo.addBook(
        Book(
          id: id,
          title: '古籍书',
          local: true,
          epub: const EpubRef(fmt: 'EPUB3', size: 10, path: 'mem'),
          createdAt: 1,
          updatedAt: 1,
        ),
      );
      await t.pumpWidget(
        ProviderScope(
          overrides: [
            readRepositoryProvider.overrideWithValue(repo),
            sharedPreferencesProvider.overrideWithValue(prefs),
            epubDocLoaderProvider.overrideWithValue((_) async => doc),
          ],
          child: MaterialApp(home: ReaderPage(bookId: id)),
        ),
      );
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 200));
      }
    }

    Text para(WidgetTester t, int pi) => t.widget<Text>(
      find
          .descendant(
            of: find.byKey(ValueKey('brp-0-$pi')),
            matching: find.byType(Text),
          )
          .first,
    );

    // 正文段走的是 Text.rich → 段内容在 textSpan 上（data 只给纯字符串构造）。
    TextSpan root(WidgetTester t, int pi) => para(t, pi).textSpan as TextSpan;
    List<InlineSpan> spans(WidgetTester t, int pi) => root(t, pi).children!;

    testWidgets('② 默认左对齐（不再两端对齐）', (t) async {
      await open(t, 'r32a');
      expect(ReaderCfg.defaults.just, isFalse, reason: '② 两端对齐默认关');
      expect(para(t, 1).textAlign, TextAlign.start);
      expect(para(t, 4).textAlign, TextAlign.start);
    });

    testWidgets('② 两端对齐是外观项：开 just 才 justify（渲染处没写死）', (t) async {
      await repo.setKv(
        'reader.cfg',
        jsonEncode({...ReaderCfg.defaults.toMap(), 'just': true}),
      );
      await open(t, 'r32c');
      expect(para(t, 1).textAlign, TextAlign.justify);
      expect(para(t, 4).textAlign, TextAlign.justify);
    });

    testWidgets('①③④ 注释体小字正文色 · 自带缩进不叠加 · 链接色只给外链', (t) async {
      await open(t, 'r32b');
      final fg = ReaderCfg.defaults.textColor;
      // ③ 普通段有我们的两全角前缀；书自带缩进的段没有（不叠加＝双重缩进止血）。
      expect((spans(t, 1).first as TextSpan).text, startsWith(kParaIndent));
      expect((spans(t, 2).first as TextSpan).text, isNot(startsWith(kParaIndent)));
      // ① 注释体＝正文色 + 小一号，且绝不是链接绿。
      final noteStyle = root(t, 3).style!;
      expect(noteStyle.fontSize, 19 * kAnnotationFsFactor);
      expect(noteStyle.color, fg.withValues(alpha: kAnnotationAlpha));
      // ④ 段内四类链接各得其所。
      final ls = spans(t, 4);
      TextSpan seg(String s) =>
          ls.firstWhere((e) => (e as TextSpan).text == s) as TextSpan;
      expect(seg('站内').style!.color, fg, reason: '站内锚点＝正文色');
      expect(seg('站内').style!.decoration, TextDecoration.underline);
      expect(seg('跨章').style!.color, const Color(0xFF6366F1), reason: '跨章给链接色');
      expect(seg('外链').style!.color, const Color(0xFF6366F1), reason: '外链给链接色');
      expect(seg('注一').style!.color, fg, reason: '① 注释引用绝不套绿');
      expect(seg('注一').style!.fontSize, 19 * kAnnotationFsFactor);
    });
  });
}
