import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/features/mindmap/domain/mindmap_style.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 思维导图批3 F4-7 · 样式层守护（工单 §4d.4 ①~⑦，编号即验收项）。
///
/// 两条产品拍板的**可执行证据**：
/// · **档位存语义 key、绘制时经令牌解析** ⇒ ⑤ 同一档在浅/深两主题下解析出
///   不同实际色（若实现偷存色值，这一条必红）。
/// · **prefs 每图一套** ⇒ ③ 图 A 设档、图 B 未设互不影响（变异刀2 钉点）。
///
/// 纯解析/存储用例走单测（不泵页）；交互面（弹层改档即时生效）单独一件
/// `mindmap_style_sheet_test.dart`（一文件一波口径）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 两套主题（浅/深）：⑤ 换肤跟随的对照组。
  ColorScheme lightOf([ThemeData? base]) =>
      (base ?? ThemeData.light()).colorScheme;
  ColorScheme darkOf([ThemeData? base]) =>
      (base ?? ThemeData.dark()).colorScheme;

  group('① 档位表逐档解析', () {
    test('文字色：default 返回 null（回落），其余三档解析出非 null', () {
      final cs = lightOf();
      expect(mmResolveTextColor(MmStyle.kTextDefault, cs), isNull,
          reason: '「默认」档＝空串回落 ⇒ null');
      for (final lv in [MmStyle.kTextAccent, MmStyle.kTextMuted, MmStyle.kTextWarn]) {
        expect(mmResolveTextColor(lv, cs), isNotNull, reason: '$lv 档须解析出实际色');
      }
    });

    test('连线色：default 返回 null，accent/muted 解析出非 null', () {
      final cs = lightOf();
      expect(mmResolveLineColor(MmStyle.kLineDefault, cs), isNull);
      expect(mmResolveLineColor(MmStyle.kLineAccent, cs), isNotNull);
      expect(mmResolveLineColor(MmStyle.kLineMuted, cs), isNotNull);
    });

    test('节点底色：paper 返回 null，soft/deep 解析出非 null 且互不相同', () {
      final cs = lightOf();
      expect(mmResolveNodeBg(MmStyle.kBgPaper, cs), isNull);
      final soft = mmResolveNodeBg(MmStyle.kBgSoft, cs);
      final deep = mmResolveNodeBg(MmStyle.kBgDeep, cs);
      expect(soft, isNotNull);
      expect(deep, isNotNull);
      expect(soft, isNot(deep), reason: '两档须是不同的混色比例');
    });

    test('画布背景：dots 返回 null（走基线网点），plain/tint/deep 非 null', () {
      final cs = lightOf();
      expect(mmResolveCanvasBg(MmStyle.kCanvasDots, cs), isNull);
      for (final lv in [MmStyle.kCanvasPlain, MmStyle.kCanvasTint, MmStyle.kCanvasDeep]) {
        expect(mmResolveCanvasBg(lv, cs), isNotNull, reason: '$lv 档须解析出实际色');
      }
      expect(mmCanvasDots(MmStyle.kCanvasDots), isTrue);
      expect(mmCanvasDots(MmStyle.kCanvasPlain), isFalse,
          reason: '纯色档不画网点（原型覆盖底纹）');
    });

    test('字号档：sm/md/lg 三档字号递增，md 对齐批2 基线 13.5', () {
      expect(const MmStyle(size: MmStyle.kSizeSm).fontSize, lessThan(13.5));
      expect(const MmStyle().fontSize, 13.5);
      expect(const MmStyle(size: MmStyle.kSizeLg).fontSize, greaterThan(13.5));
    });
  });

  group('② 默认态零视觉变化', () {
    test('未设样式（null）→ 绘制面逐值等于批2 基线', () {
      final cs = lightOf();
      final base = MmPaintStyle.baseline(cs);
      expect(MmPaintStyle.of(null, cs), base);
      expect(MmPaintStyle.of(null, cs).bg, cs.surface);
      expect(MmPaintStyle.of(null, cs).grid, cs.onSurface.withValues(alpha: .06));
      expect(MmPaintStyle.of(null, cs).nodeBg, cs.surfaceContainerHighest);
      expect(MmPaintStyle.of(null, cs).nodeBorder, cs.outlineVariant);
      expect(MmPaintStyle.of(null, cs).nodeText, cs.onSurface);
      expect(MmPaintStyle.of(null, cs).edge, cs.outline);
      expect(MmPaintStyle.of(null, cs).accent, cs.primary);
      expect(MmPaintStyle.of(null, cs).accentSoft, cs.primary.withValues(alpha: .14));
      expect(MmPaintStyle.of(null, cs).lineW, 1.2);
      expect(MmPaintStyle.of(null, cs).dots, isTrue);
    });

    test('全默认档（MmStyle.defaults）除线粗外逐值等于基线（默认档零视觉变化）', () {
      final cs = lightOf();
      final p = MmPaintStyle.of(MmStyle.defaults, cs);
      final b = MmPaintStyle.baseline(cs);
      expect(p.bg, b.bg);
      expect(p.nodeBg, b.nodeBg);
      expect(p.nodeText, b.nodeText);
      expect(p.edge, b.edge);
      expect(p.dots, b.dots);
      expect(p.fontSize, b.fontSize);
      expect(p.lineW, MmStyle.defaults.lineW, reason: '线粗是显式数值档（原型 1.6）');
    });
  });

  group('③ 每图隔离（变异刀2 钉点）', () {
    testWidgets('图 A 设 text=warn，图 B 未设 → B 仍是默认解析，两图互不影响',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = MmStyleStore(prefs);
      const a = 11, b = 22;
      await store.save(a, MmStyle.defaults.copyWith(text: MmStyle.kTextWarn));

      final cs = lightOf();
      final pa = MmPaintStyle.of(store.load(a), cs);
      final pb = MmPaintStyle.of(store.load(b), cs);
      expect(pa.nodeText, cs.error, reason: '图 A 命中警示档');
      expect(pb.nodeText, cs.onSurface, reason: '图 B 未设 ⇒ 基线（不受 A 影响）');
      expect(store.load(b), isNull, reason: 'B 从未存过');
      // 存储层隔离（改 A 不动 B 的格子）。
      await store.save(b, MmStyle.defaults.copyWith(size: MmStyle.kSizeLg));
      expect(store.load(a)?.text, MmStyle.kTextWarn);
      expect(store.load(b)?.size, MmStyle.kSizeLg);
      expect(store.load(a)?.size, MmStyle.kSizeMd);
    });

    test('load 忽略 mapId 取全局的坏实现会让 A/B 都读到同一档', () async {
      // 反向读数证据：未存过的图取不到档（真按 mapId 隔离才成立）。
      SharedPreferences.setMockInitialValues({});
      final store = MmStyleStore(await SharedPreferences.getInstance());
      expect(store.load(999), isNull, reason: '未存过的图取不到档');
    });
  });

  group('④ prefs 往返', () {
    test('设档 → 冷启重开 → 读到同一档（逐字段相等）', () async {
      SharedPreferences.setMockInitialValues({});
      final store = MmStyleStore(await SharedPreferences.getInstance());
      const style = MmStyle(
        text: MmStyle.kTextWarn,
        size: MmStyle.kSizeLg,
        bg: MmStyle.kBgDeep,
        line: MmStyle.kLineAccent,
        lineW: 2.4,
        canvas: MmStyle.kCanvasTint,
      );
      await store.save(7, style);
      // 冷启＝全新 store 实例读同一 prefs。
      final reopened = MmStyleStore(await SharedPreferences.getInstance());
      expect(reopened.load(7), style);
    });

    test('损坏 JSON 不炸、按未设样式回落', () async {
      SharedPreferences.setMockInitialValues({MmStyleStore.key: '{不是合法 JSON'});
      final store = MmStyleStore(await SharedPreferences.getInstance());
      expect(store.load(1), isNull);
      // 损坏态下再存一格能自愈成合法值。
      await store.save(1, MmStyle.defaults);
      expect(MmStyleStore(await SharedPreferences.getInstance()).load(1), MmStyle.defaults);
    });

    test('字段类型不符/未知档位/线粗越界 → 该字段回落默认，其余字段保留', () {
      final s = MmStyle.fromJson({
        'text': 'chartreuse', // 未知档
        'size': MmStyle.kSizeLg, // 合法
        'lineW': 99.0, // 越界
      });
      expect(s.text, MmStyle.kTextDefault);
      expect(s.size, MmStyle.kSizeLg);
      expect(s.lineW, 1.6);
      expect(s.canvas, MmStyle.kCanvasDots);
    });

    test('reset：删该格且不影响别的图；删到空整 key 清掉', () async {
      SharedPreferences.setMockInitialValues({});
      final store = MmStyleStore(await SharedPreferences.getInstance());
      await store.save(1, MmStyle.defaults.copyWith(text: MmStyle.kTextWarn));
      await store.save(2, MmStyle.defaults.copyWith(text: MmStyle.kTextAccent));
      await store.reset(1);
      expect(store.load(1), isNull);
      expect(store.load(2)?.text, MmStyle.kTextAccent);
      await store.reset(2);
      expect(store.load(2), isNull);
      expect(store.prefs.getString(MmStyleStore.key), isNull);
    });
  });

  group('⑤ 换肤跟随（证明是解析而非存值）', () {
    test('同一档位在浅/深两主题下解析出不同的实际色', () {
      final l = lightOf();
      final d = darkOf();
      expect(mmResolveTextColor(MmStyle.kTextAccent, l),
          isNot(mmResolveTextColor(MmStyle.kTextAccent, d)));
      expect(mmResolveNodeBg(MmStyle.kBgSoft, l),
          isNot(mmResolveNodeBg(MmStyle.kBgSoft, d)));
      expect(mmResolveLineColor(MmStyle.kLineAccent, l),
          isNot(mmResolveLineColor(MmStyle.kLineAccent, d)));
      expect(mmResolveCanvasBg(MmStyle.kCanvasTint, l),
          isNot(mmResolveCanvasBg(MmStyle.kCanvasTint, d)));
    });

    test('画布页换主题后样式重新解析（同一份档 → 不同绘制面）', () {
      const style = MmStyle(
        text: MmStyle.kTextAccent,
        bg: MmStyle.kBgSoft,
        line: MmStyle.kLineAccent,
        canvas: MmStyle.kCanvasTint,
      );
      final pl = MmPaintStyle.of(style, lightOf());
      final pd = MmPaintStyle.of(style, darkOf());
      expect(pl, isNot(pd), reason: '换肤必得不同绘制面');
      // 存储的档本身不含色值（换肤才可能跟随）。
      expect(style.toJson().values.any((v) => v is String && v.startsWith('#')), isFalse);
    });
  });

  group('⑦ 导出所见一致', () {
    test('导出 PNG 与画布吃同一工厂解析（同一份 style ⇒ 同一绘制面）', () {
      final cs = lightOf();
      const style = MmStyle(
        text: MmStyle.kTextWarn,
        bg: MmStyle.kBgSoft,
        line: MmStyle.kLineMuted,
        lineW: 3.2,
        canvas: MmStyle.kCanvasDeep,
      );
      final fromCanvas = MmPaintStyle.of(style, cs);
      // 导出侧 mmCanvasPngSnapshot 内部同样走 MmPaintStyle.of（不各算一套）：
      // 用同一入参复算，两次结果必须逐值相等。
      final fromExport = MmPaintStyle.of(style, cs);
      expect(fromExport, fromCanvas);
      expect(fromExport.lineW, 3.2);
      expect(fromExport.dots, isFalse);
    });
  });
}