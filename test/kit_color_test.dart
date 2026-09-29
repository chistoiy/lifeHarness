import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/features/kits/domain/kit_color.dart';

/// V1.47 批2 · 色彩域层用例（原型 `h2r`/`r2hsl`/`hsl2r`/`cmpShow` 口径锚定）。
void main() {
  group('1 · 换算与解析', () {
    test('hex ↔ rgb 往返一致，非法串返回 null', () {
      expect(kitHexToRgb('#6366f1'), const KitRgb(99, 102, 241));
      expect(kitHexToRgb('6366F1'), const KitRgb(99, 102, 241));
      expect(kitRgbToHex(const KitRgb(99, 102, 241)), '#6366f1');
      expect(kitHexToRgb('#12345'), isNull);
      expect(kitHexToRgb('rgb(1,2,3)'), isNull);
    });

    test('hex → hsl 锚点（原型 indigo 预设 = 239/84/67）', () {
      final c = kitHexToHsl('#6366f1');
      expect(c.h.round(), 239);
      expect(c.s.round(), 84);
      expect(c.l.round(), 67);
      // 灰阶：饱和 0，明度按均值。
      final g = kitHexToHsl('#808080');
      expect(g.s.round(), 0);
      expect(g.l.round(), 50);
      // HSL 只保留整数位会丢精度，往返到 hex 有量化漂移，只断言「接近」。
      expect(kitHexToRgb(kitHslToHex(c))!.r, closeTo(99, 2));
      expect(kitHexToRgb(kitHslToHex(c))!.b, closeTo(241, 2));
    });

    test('色串解析支持 hex / rgb() / hsl()，未知格式返回 null', () {
      expect(kitParseColor('#2DD4BF'), '#2dd4bf');
      expect(kitParseColor('2dd4bf'), '#2dd4bf');
      expect(kitParseColor('rgb(45, 212, 191)'), '#2dd4bf');
      expect(kitParseColor('rgba(45 212 191 / 0.8)'), '#2dd4bf');
      expect(kitParseColor('hsl(172, 70%, 52%)'), '#2fdac3');
      expect(kitParseColor('  '), isNull);
      expect(kitParseColor('red'), isNull);
    });

    test('三串展示（HEX 大写 / rgb() / hsl()）', () {
      final r = kitColorReadouts('#6366f1');
      expect(r[0], '#6366F1');
      expect(r[1], 'rgb(99, 102, 241)');
      expect(r[2], 'hsl(239, 84%, 67%)');
    });
  });

  group('2 · 最近取色（上限 10 · 表头去重）', () {
    test('新色插表头，重复表头不动，超 10 截尾', () {
      var l = <String>[];
      l = kitTouchRecent(l, '#aaaaaa');
      l = kitTouchRecent(l, '#bbbbbb');
      expect(l, ['#bbbbbb', '#aaaaaa']);
      l = kitTouchRecent(l, '#bbbbbb');
      expect(l.first, '#bbbbbb');
      expect(l.length, 2);
      for (var i = 0; i < 12; i++) {
        l = kitTouchRecent(l, '#${i.toRadixString(16).padLeft(2, '0')}0000');
      }
      expect(l.length, kKitRecentMax);
    });

    test('移除指定色', () {
      expect(
        kitDropRecent(['#111111', '#222222'], '#111111'),
        ['#222222'],
      );
    });
  });

  group('3 · 配色方案（原型 CMP_SCHEMES）', () {
    test('五方案的色数与偏移照登记', () {
      expect(kKitSchemes.map((s) => s.name).toList(),
          ['互补', '类似', '三角', '分裂互补', '四方']);
      expect(kKitSchemes[0].offsets, [0, 180]);
      expect(kKitSchemes[4].offsets, [0, 90, 180, 270]);
    });

    test('生成规则：S +4（84→88 附近），L>72→52 否则 clamp(L+6, 46, 66)', () {
      final cs = kitSchemeColors('#6366f1', kKitSchemes[0]);
      expect(cs.length, 2);
      expect(cs[0].name, '主色');
      expect(cs[1].name, '互补色 180°');
      for (final c in cs) {
        final hsl = kitHexToHsl(c.hex);
        expect(hsl.s.round(), closeTo(88, 1));
        expect(hsl.l.round(), closeTo(66, 1));
      }
      // 亮主色（L>72）走 52 档。
      final light = kitSchemeColors('#dbeafe', kKitSchemes[0]);
      expect(kitHexToHsl(light[0].hex).l.round(), 52);
    });

    test('首色色相=主色色相；三角方案用「偏移 +N°」命名', () {
      final cs = kitSchemeColors('#6366f1', kKitSchemes[2]);
      expect(cs[0].deg.round(), closeTo(239, 1));
      expect(cs[1].deg.round(), closeTo((239 + 120) % 360, 2));
      expect(cs[2].deg.round(), closeTo((239 + 240) % 360, 2));
      expect(cs[0].name, '主色');
      expect(cs[1].name, '偏移 +120°');
      expect(kitSchemeColorName(-30, kKitSchemes[1]), '偏移 -30°');
    });

    test('类似方案首项是 -30°（非主色居首）', () {
      final cs = kitSchemeColors('#6366f1', kKitSchemes[1]);
      expect(cs.first.name, '偏移 -30°');
      expect(cs[1].name, '主色');
    });
  });

  group('4 · 色环', () {
    test('60 段 · 饱和度取 max(40, S) · 明度取 clamp(L, 44, 62)', () {
      final segs = kitWheelSegments(const KitHsl(239, 10, 30));
      expect(segs.length, 60);
      expect(segs[0], '#9d4343');
      expect(segs[9], '#9d9443');
      for (final s in segs) {
        final hsl = kitHexToHsl(s);
        expect(hsl.s.round(), closeTo(40, 1));
        expect(hsl.l.round(), closeTo(44, 1));
      }
    });

    test('拖动只换色相、保留饱和与明度；中心抖动忽略', () {
      const keep = KitHsl(239, 84, 67);
      expect(kitHueFromAngle(dx: 60, dy: 0, keep: keep), '#abf264');
      expect(kitHexToHsl(kitHueFromAngle(dx: 0, dy: -60, keep: keep)).h.round(), 0);
      expect(kitHexToHsl(kitHueFromAngle(dx: -60, dy: 0, keep: keep)).h.round(), 270);
      expect(kitHexToHsl(kitHueFromAngle(dx: 60, dy: 0, keep: keep)).s.round(), closeTo(84, 1));
      expect(kitHexToHsl(kitHueFromAngle(dx: 60, dy: 0, keep: keep)).l.round(), closeTo(67, 1));
      expect(kitHueFromAngle(dx: 0.5, dy: 0.5, keep: keep), kitHslToHex(keep));
    });
  });
}
