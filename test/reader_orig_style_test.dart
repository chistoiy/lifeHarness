import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lifeharness/features/read/data/epub_cache.dart' show PagStore;
import 'package:lifeharness/features/read/data/epub_css.dart';
import 'package:lifeharness/features/read/data/epub_doc.dart';
import 'package:lifeharness/features/read/domain/reader_cfg.dart';
import 'package:lifeharness/features/read/presentation/reader/reader_pager.dart';

// 批三实现批·刀3「原书样式消费面」回归（工单 §3D 刀3 段＋预研 §5.4 拍板）。
// 钉四件事：① 总开关默认开且进分页指纹；② 原书声明优先、未声明回落止血口径；
// ③ 边线→文本线的通用映射与深色调和（能力边界不许装能画框）；
// ④ 测量与渲染同吃一张 runs→TextStyle 分段表（paraStyle 红线，两处各算必出空页）。
// 纯函数级用例，不建库不 pump（真包结构在 reader_css_runs_test，上屏在刀4 的 widget 件）。

const _dayBg = Color(0xFFFAF6EE), _dayFg = Color(0xFF3B3630);
const _nightBg = Color(0xFF101317), _nightFg = Color(0xFF9AA4B0);

/// 用户基准样式（fs19/lh1.62，日间正文色）。
TextStyle _base({Color? fg}) =>
    TextStyle(fontSize: 19, height: 1.62, color: fg ?? _dayFg);

/// WCAG 对比度（调和判据用同一算法，用例才不至於自证自）。
double _contrast(Color a, Color b) {
  double lum(Color c) {
    double lin(double v) => v <= 0.03928
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b);
  }

  final x = lum(a), y = lum(b);
  return ((x > y ? x : y) + 0.05) / ((x > y ? y : x) + 0.05);
}

EpubPara _para(
  String text, {
  EpubStyle? style,
  List<EpubStyleRun> runs = const [],
  bool annotation = false,
  EpubParaKind kind = EpubParaKind.text,
}) =>
    EpubPara(
      kind: kind,
      text: text,
      annotation: annotation,
      style: style,
      runs: runs,
    );

void main() {
  group('① 总开关「跟随原书样式」', () {
    test('默认开（§5.4 拍板③：一个总开关、默认开、不拆子开关）', () {
      expect(ReaderCfg.defaults.orig, isTrue);
      expect(ReaderCfg.fromMap(const {}).orig, isTrue,
          reason: '老用户落库缺键＝吃默认开，不是遗漏');
      expect(ReaderCfg.fromMap(const {'orig': false}).orig, isFalse);
    });

    test('落库/读回不丢，且 copyWith 只动这一键', () {
      final off = ReaderCfg.defaults.copyWith(orig: false);
      expect(ReaderCfg.decode(off.encode()).orig, isFalse);
      expect(ReaderCfg.decode(off.encode()).fs, ReaderCfg.defaults.fs);
      expect(ReaderCfg.defaults.copyWith(orig: false).theme,
          ReaderCfg.defaults.theme);
    });

    test('开关进 ReaderLayout 并进分页指纹——切了不重排＝真机假生效', () {
      final on = ReaderLayout.of(ReaderCfg.defaults, width: 393, height: 851);
      final off = ReaderLayout.of(
        ReaderCfg.defaults.copyWith(orig: false),
        width: 393,
        height: 851,
      );
      expect(on.orig, isTrue);
      expect(off.orig, isFalse);
      expect(PagStore.fingerprint(on), contains('og1'));
      expect(PagStore.fingerprint(off), contains('og0'));
      expect(PagStore.fingerprint(on), isNot(PagStore.fingerprint(off)));
    });
  });

  group('② applyOrigStyle：声明才叠，未声明保持 base', () {
    test('字号比相对用户基准字号（不是止血小字之上的再乘）', () {
      final st = const EpubStyle(fontRatio: .75, weight: 700, italic: true);
      final s = applyOrigStyle(_base(), st);
      expect(s.fontSize, closeTo(19 * .75, 0.001));
      expect(s.fontWeight, FontWeight.w700);
      expect(s.fontStyle, FontStyle.italic);
    });

    test('一条声明都没有＝原样返回（不许凭空造色造线）', () {
      final b = _base();
      expect(applyOrigStyle(b, null), same(b));
      expect(applyOrigStyle(b, const EpubStyle()), same(b));
    });

    test('左/右/下边线一律落下划线，上边线落上划线（Flutter 无内联盒＝画不出整框）', () {
      final b = _base(fg: const Color(0xFF1B3A6B));
      for (final side in ['left', 'right', 'bottom']) {
        final st = side == 'left'
            ? const EpubStyle(borderLeft: EpubBorder(widthEm: .12, style: 'solid'))
            : side == 'right'
                ? const EpubStyle(
                    borderRight: EpubBorder(widthEm: .12, style: 'solid'))
                : const EpubStyle(
                    borderBottom: EpubBorder(widthEm: .12, style: 'solid'));
        final s = applyOrigStyle(b, st);
        expect(s.decoration, TextDecoration.underline, reason: '$side 边线');
        expect(s.decorationColor, const Color(0xFF1B3A6B),
            reason: '$side 边线缺色＝跟字色（通鉴 .name 形态）');
        expect(s.decorationThickness, greaterThan(0));
      }
      final top = applyOrigStyle(
        b,
        const EpubStyle(borderTop: EpubBorder(widthEm: .1, style: 'solid')),
      );
      expect(top.decoration, TextDecoration.overline);
    });

    test('线形态优先取边线自己的 style，缺边线形态才回落段级 deco', () {
      final st = const EpubStyle(
        borderLeft: EpubBorder(widthEm: .1, style: 'double'),
        deco: 'wavy',
      );
      expect(applyOrigStyle(_base(), st).decorationStyle,
          TextDecorationStyle.double);
      // 书名线：原书是 gif 平铺，刀2 已通用回落成 deco=wavy（无 border）。
      final bt = const EpubStyle(underline: true, deco: 'wavy');
      expect(applyOrigStyle(_base(), bt).decorationStyle,
          TextDecorationStyle.wavy);
    });

    test('text-decoration 声明＝下划线；overline/line-through 各自到位', () {
      expect(applyOrigStyle(_base(), const EpubStyle(underline: true)).decoration,
          TextDecoration.underline);
      expect(applyOrigStyle(_base(), const EpubStyle(overline: true)).decoration,
          TextDecoration.overline);
      expect(
          applyOrigStyle(_base(), const EpubStyle(lineThrough: true)).decoration,
          TextDecoration.lineThrough);
    });

    test('深色调和：夜间底下的原书深蓝被提亮，色相不动且对比达标', () {
      const navy = Color(0xFF000080); // 通鉴 .brp-cmt 史评色（CSS navy）
      final raw = _base(fg: _nightFg);
      expect(_contrast(navy, _nightBg), lessThan(4.5), reason: '前提：原色在黑底上读不出');
      final s = applyOrigStyle(raw, const EpubStyle(color: navy),
          pageBg: _nightBg);
      final out = s.color!;
      expect(out, isNot(navy), reason: '不达标必须调');
      expect(HSVColor.fromColor(out).hue, closeTo(240, 4));
      expect(_contrast(out, _nightBg), greaterThanOrEqualTo(4.5));
    });

    test('深色调和：日间底下原书色一字不改（不许无脑压暗）', () {
      const navy = Color(0xFF000080);
      final s = applyOrigStyle(_base(), const EpubStyle(color: navy),
          pageBg: _dayBg);
      expect(s.color, navy);
    });

    test('底色声明一起判：白字灰底标签块的对比按**底色**算，白字保留', () {
      final s = applyOrigStyle(
        _base(fg: _nightFg),
        const EpubStyle(
            color: Color(0xFFFFFFFF), backgroundColor: Color(0xFF696969)),
        pageBg: _nightBg,
      );
      expect(_contrast(const Color(0xFFFFFFFF), const Color(0xFF696969)),
          greaterThanOrEqualTo(4.5), reason: '前提：白字压灰底本来就读得出');
      expect(s.color, const Color(0xFFFFFFFF));
      expect(s.backgroundColor, const Color(0xFF696969),
          reason: '禁直接压黑底＝灰底块要跟着保留');
    });

    test('同色相调明度救不回来（灰字压灰底）＝回落主题正文色，不许硬留一个读不出的色', () {
      const grey = Color(0xFF808080);
      final s = applyOrigStyle(_base(fg: _nightFg), const EpubStyle(color: grey),
          pageBg: grey);
      expect(s.color, _nightFg);
    });

    test('测量路径（pageBg 为 null）不参与调和：色不影响度量', () {
      const navy = Color(0xFF000080);
      final s = applyOrigStyle(_base(fg: _nightFg), const EpubStyle(color: navy));
      expect(s.color, navy, reason: 'null＝不比对，原色照抄');
      expect(s.fontSize, 19);
    });
  });

  group('③ paraStyle：原书声明优先，未声明走止血', () {
    test('orig 关＝现状逐字节（段带原书声明也不许漏色进去）', () {
      final p = _para(
        '按语：臣光曰',
        annotation: true,
        style: const EpubStyle(color: Color(0xFF000080), fontRatio: 1.0),
      );
      final off = paraStyle(p, _base());
      expect(off.color, _dayFg.withValues(alpha: kAnnotationAlpha));
      expect(off.fontSize, 19 * kAnnotationFsFactor);
      expect(paraStyle(_para('正文'), _base(), orig: false), _base());
    });

    test('orig 开：原书蓝＋1rem 压过止血「正文色小一号」（§5.4 拍板）', () {
      final p = _para(
        '臣光曰：……',
        annotation: true,
        style: const EpubStyle(color: Color(0xFF000080), fontRatio: 1.0),
      );
      final s = paraStyle(p, _base(), orig: true);
      expect(s.color, const Color(0xFF000080));
      expect(s.fontSize, 19.0, reason: '原书 1rem＝基准字号，止血的小一号让位');
    });

    test('orig 开：原书只声明字号比时颜色仍走止血口径（未声明不抢）', () {
      final p = _para('注：小字注',
          annotation: true, style: const EpubStyle(fontRatio: .75));
      final s = paraStyle(p, _base(), orig: true);
      expect(s.fontSize, closeTo(19 * .75, 0.001));
      expect(s.color, _dayFg.withValues(alpha: kAnnotationAlpha));
    });

    test('orig 开但段无原书声明＝与关态同值（零原书声明的书不许变样）', () {
      final p = _para('普通正文段');
      expect(paraStyle(p, _base(), orig: true), paraStyle(p, _base()));
    });

    test('段级行距声明进 height（测量与渲染同吃一份）', () {
      final s = paraStyle(
        _para('段', style: const EpubStyle(lineRatio: 2.0)),
        _base(),
        orig: true,
      );
      expect(s.height, 2.0);
    });
  });

  group('④ paraRunStyles：测量与渲染共用的分段表', () {
    test('空 runs＝单段，样式与 paraStyle 同值（同源红线）', () {
      final p = _para('一段正文');
      final segs = paraRunStyles(p, _base(), orig: true);
      expect(segs.length, 1);
      expect(segs.single.start, 0);
      expect(segs.single.end, p.text.length);
      expect(segs.single.style, paraStyle(p, _base(), orig: true));
    });

    test('runs 折成分段表：覆盖全部原文区间，未覆盖处用段样式', () {
      const note = Color(0xFF006400);
      final p = _para('甲乙丙丁戊', runs: [
        const EpubStyleRun(
            start: 1, end: 3, style: EpubStyle(color: note, fontRatio: .75)),
      ]);
      final segs = paraRunStyles(p, _base(), orig: true);
      expect(segs.map((s) => s.end - s.start).fold(0, (a, b) => a + b),
          p.text.length, reason: '分段表必须无缝覆盖');
      expect(segs.first.style.color, _dayFg);
      final mid = segs.firstWhere((s) => s.start == 1);
      expect(mid.style.color, note);
      expect(mid.style.fontSize, closeTo(19 * .75, 0.001));
      expect(mid.end, 3);
    });

    test('orig 关＝分段表里没有原书色（关态逐字节退化）', () {
      final p = _para('甲乙丙', runs: [
        const EpubStyleRun(start: 0, end: 1, style: EpubStyle(color: Color(0xFF800080))),
      ]);
      for (final s in paraRunStyles(p, _base(), orig: false)) {
        expect(s.style.color, isNot(const Color(0xFF800080)));
      }
    });

    test('run 的下划线（专名线）与段样式互不吞：线到位、色保留', () {
      final p = _para('智宣子将', runs: [
        const EpubStyleRun(
            start: 0,
            end: 3,
            style: EpubStyle(
                borderLeft: EpubBorder(widthEm: .12, style: 'solid'))),
      ]);
      final segs = paraRunStyles(p, _base(), orig: true);
      expect(segs.first.style.decoration, TextDecoration.underline);
      expect(segs.first.style.color, _dayFg);
      expect(segs.last.style.color, _dayFg);
    });
  });

  group('⑤ 测量同源：paraHeight 吃同一张表', () {
    test('含大字号 run 的段按 span 树整段量，比平文本高', () {
      final p = _para('正文' * 20, runs: [
        const EpubStyleRun(
            start: 0, end: 2, style: EpubStyle(fontRatio: 1.6)),
      ]);
      final on = ReaderLayout(
          width: 393, height: 2000, orig: true, indent: false, indMode: 'none');
      final off = ReaderLayout(
          width: 393, height: 2000, orig: false, indent: false, indMode: 'none');
      expect(EpubPager.paraHeight(p, on),
          greaterThan(EpubPager.paraHeight(p, off)));
    });

    test('orig 关＝与无声明的同文本段同高（平文本路径逐字节不退化）', () {
      final p = _para('普通段' * 12, style: const EpubStyle(fontRatio: .5));
      final plain = _para('普通段' * 12);
      final l = ReaderLayout(width: 393, height: 2000, indMode: 'none');
      expect(
          EpubPager.paraHeight(p, l.copyWith(orig: false)),
          EpubPager.paraHeight(plain, l.copyWith(orig: false)));
      expect(
          EpubPager.paraHeight(p, l.copyWith(orig: true)),
          lessThan(EpubPager.paraHeight(p, l.copyWith(orig: false))),
          reason: '原书 0.5× 小字必须被量到，否则按大字画页会溢出');
    });
  });
}
