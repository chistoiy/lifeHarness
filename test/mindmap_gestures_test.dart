import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/providers.dart' show sharedPreferencesProvider;
import 'package:lifeharness/features/mindmap/data/mindmap_dao.dart';
import 'package:lifeharness/features/mindmap/domain/mindmap_measure.dart';
import 'package:lifeharness/features/mindmap/domain/mindmap_style.dart';
import 'package:lifeharness/features/mindmap/domain/mindmap_viewport.dart';
import 'package:lifeharness/features/mindmap/presentation/mindmap_canvas_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mindmap_test_harness.dart';

/// 思维导图批P6 · 画布手势补强守护（2026-10-21）。
///
/// 本批四件：
/// 1. **滚轮/触控板缩放**（原先桌面上完全没反应）；
/// 2. **按钮缩放锚点＝画布中心**（原先只改缩放比不动平移，观感是从左上角往外撑）；
/// 3. **双击空白＝fit 全图**；
/// 4. **缩得很小时节点仍有 44dp 最小可点面**（25% 档行高只剩 10dp）。
///
/// 两条断言纪律（本项目反复踩）：
/// - 缩放比/平移是**页面私有状态**，屏上没有任何可读口子 ⇒ 几何一律用
///   「节点屏幕矩形」反算，且**每条用例都要先证反算口径在同一帧里自洽**
///   （否则算出个恒等式，怎么写都绿）。
/// - 「双击」不能靠 `tester.tap` 连点两次就以为成了——两次之间必须 pump 帧，
///   否则两次都落在同一帧的 `_lastEmptyTapTime` 上（那也能过，但不是真路径）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late dynamic db;
  late SharedPreferences mmPrefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    mmPrefs = await SharedPreferences.getInstance();
    db = await openMmDb();
  });
  tearDown(() async {
    await (db as CloseableDb).close();
  });

  Future<int> pumpMap(WidgetTester tester,
      {required Future<void> Function(MindmapDao, int) seed,
      TextScaler textScaler = TextScaler.noScaling}) async {
    final dao = mindmapDaoOf(db);
    final mapId = await dao.createMap('图');
    await seed(dao, mapId);
    // 全局字号一律钉死（noScaling 也钉）：不钉的话测试字体替身量出来的字宽
    // 恒是 14px/字，与真机排版不是一回事——「系统字号」那条用例就靠这一点。
    tester.platformDispatcher.textScaleFactorTestValue = 1.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(MediaQuery(
      data: MediaQueryData(textScaler: textScaler),
      child: ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(mmPrefs)],
        child: MaterialApp(
            home: MindmapCanvasPage(mapId: mapId, dao: dao, db: db)),
      ),
    ));
    await tester.pumpAndSettle();
    return mapId;
  }

  /// 某节点当前的屏幕矩形（读屏语义层的几何与画布同源，故意与命中区区分开：
  /// 命中区放宽过，语义层没有）。
  Rect rectOf(WidgetTester tester, String title) {
    final f = find.byWidgetPredicate(
        (w) => w is Semantics && (w.properties.label ?? '') == title);
    expect(f, findsOneWidget, reason: '找不到「$title」的语义块');
    return tester.getRect(f);
  }

  Rect canvasRect(WidgetTester tester) =>
      tester.getRect(find.byKey(const ValueKey('mm-canvas-paint')));

  /// 屏幕中心相对画布中心的偏移——「以中心为锚」的判据就是它不随缩放变。
  Offset centerOffsetOf(WidgetTester tester, String title) {
    final r = rectOf(tester, title);
    final c = canvasRect(tester);
    return r.center - c.center;
  }

  testWidgets('按钮放大以画布中心为锚：内容中心不随缩放漂移（负档：旧口径会漂）',
      (tester) async {
    await pumpMap(tester, seed: (d, m) async {
      final root = await d.addNode(mapId: m, parentId: null, title: '根');
      for (var i = 1; i <= 4; i++) {
        await d.addNode(mapId: m, parentId: root.id, title: '子$i');
      }
    });

    final w0 = rectOf(tester, '根').width;
    final off0 = centerOffsetOf(tester, '根');
    await tester.tap(find.byIcon(Icons.add_outlined));
    await tester.pumpAndSettle();

    final w1 = rectOf(tester, '根').width;
    final off1 = centerOffsetOf(tester, '根');
    // 正档：确实放大了（否则下面那条「不漂移」在对没放大时也成立＝空转）。
    expect(w1, greaterThan(w0 * 1.1), reason: '放大钮没生效，后续断言无意义');
    // 负档：内容中心不许漂。旧口径（只改缩放比不动平移）的漂移量＝
    // (k−1)×(内容中心到画布原点距离)，本场景 k=1.25 ⇒ 约 50dp；改锚中心后
    // 只剩「视口留白」那点余量（实测 25dp）。断 35 能把两种口径分开。
    expect((off1 - off0).distance, lessThan(35),
        reason: '以画布中心为锚时内容中心不该漂：$off0 → $off1');
  });

  testWidgets('缩小钮以画布中心为锚且顶到 25% 后不再变', (tester) async {
    await pumpMap(tester, seed: (d, m) async {
      await d.addNode(mapId: m, parentId: null, title: '唯一根');
    });
    final off0 = centerOffsetOf(tester, '唯一根');
    final w0 = rectOf(tester, '唯一根').width;
    // 单节点图 fit 后是 100%，连点六次（1/1.25^6 ≈ 0.26）到 25% 附近。
    for (var i = 0; i < 8; i++) {
      await tester.tap(find.byIcon(Icons.remove_outlined));
      await tester.pumpAndSettle();
    }
    final wLow = rectOf(tester, '唯一根').width;
    await tester.tap(find.byIcon(Icons.remove_outlined));
    await tester.pumpAndSettle();
    expect(rectOf(tester, '唯一根').width, closeTo(wLow, .01),
        reason: '顶到 25% 后继续点缩小不该再变');
    expect(centerOffsetOf(tester, '唯一根'), off0,
        reason: '钳位时锚点也不许把内容推走');
    // 25% 是硬下限：八次 1/1.25 早就顶穿，盒宽不该比 fit（100%）宽度的
    // 三成还大——否则说明钳位压根没生效，上面「再点一次不变」等于空转。
    expect(wLow, lessThan(w0 * .3), reason: '没缩到 25% 档，钳位断言空转');
  });

  testWidgets('滚轮缩放：向上滚放大、向下滚缩小，且锚在鼠标处', (tester) async {
    await pumpMap(tester, seed: (d, m) async {
      final root = await d.addNode(mapId: m, parentId: null, title: '根');
      for (var i = 1; i <= 4; i++) {
        await d.addNode(mapId: m, parentId: root.id, title: '子$i');
      }
    });
    final canvas = canvasRect(tester);
    // 锚点钉在**画布中心**：滚轮事件按画布左上的位置派发（见 `_onPointerSignal`
    // 的实现注），放中心＝鼠标与缩放锚点同一点，「锚点没跑」才判得干净。
    // 不取节点中心：叶子节点本身没有可量几何，且向下滚后它可能已移出屏外，
    // 语义块不在渲染树里，取矩形会直接抛。
    final anchor = canvas.center;
    final w0 = rectOf(tester, '根').width;
    final left0 = rectOf(tester, '根').left;

    await tester.sendEventToBinding(PointerScrollEvent(
        position: anchor, scrollDelta: const Offset(0, -300)));
    await tester.pumpAndSettle();
    final w1 = rectOf(tester, '根').width;
    final left1 = rectOf(tester, '根').left;
    expect(w1, greaterThan(w0 * 1.1), reason: '向上滚＝放大');
    // 锚点判据（三条，一起才有意义）：锚点钉在画布中心 a、倍率 m＝w1/w0 时，
    //   ① 根左沿 L → a + (L−a)m；
    //   ② 节点宽度 w → wm（已由 w1 自带）；
    //   几何上「根中心」应满足 a + (L−a)m + wm/2 = (L + w/2 − a)m + a。
    // 把它整理成「以 a 为原点、除以 m」的形式，就是下面两行：
    // 偏差若来自「按左上角缩放」（L 不变），左边会残留 (a−L)(m−1)，本场景约 20dp。
    expect(((left1 - anchor.dx) / (w1 / w0)) - (left0 - anchor.dx), closeTo(0, 2),
        reason: '以画布中心为锚缩放：根左沿到锚点的距离除以缩放比应不变');

    await tester.sendEventToBinding(PointerScrollEvent(
        position: anchor, scrollDelta: const Offset(0, 300)));
    await tester.pumpAndSettle();
    final w2 = rectOf(tester, '根').width;
    expect(w2, lessThan(w1 - 1), reason: '向下滚＝缩小');
    // 往返对称（指数折算的可逆性）：缩放比 = exp(-dy/300)，±300 互为倒数
    // ⇒ 回程应把放大那一档原样抵消，盒宽回到出发布。
    expect(w2 / w0, closeTo(1.0, .02), reason: '一进一出的缩放比应互相抵消');
    expect(rectOf(tester, '根').left, closeTo(left0, 2),
        reason: '缩放比抵消了，平移也该回原处（锚点没跑）');
  });

  testWidgets('双击空白＝fit 全图（单点空白只取消选中，不动视口）', (tester) async {
    await pumpMap(tester, seed: (d, m) async {
      final root = await d.addNode(mapId: m, parentId: null, title: '根');
      for (var i = 1; i <= 6; i++) {
        await d.addNode(mapId: m, parentId: root.id, title: '子$i');
      }
    });
    final canvas = canvasRect(tester);
    // 先把视口弄乱：放大两档（内容跑出画布），再确认「双击空白」能拉回来。
    await tester.tap(find.byIcon(Icons.add_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add_outlined));
    await tester.pumpAndSettle();
    final wZoomed = rectOf(tester, '根').width;

    // 空白点：画布左下角（节点都在中上部纵向排，左下必空）。
    final blank = Offset(canvas.left + 20, canvas.bottom - 30);
    await tester.tapAt(blank);
    await tester.pump(const Duration(milliseconds: 40));
    // 第一击只取消选中，视口一个像素都不该动。
    expect(rectOf(tester, '根').width, closeTo(wZoomed, .01),
        reason: '单击空白不该改视口（B5 口径）');

    await tester.tapAt(blank);
    await tester.pumpAndSettle();
    final wFit = rectOf(tester, '根').width;
    expect(wFit, lessThan(wZoomed * .95),
        reason: '双击空白应回到 fit（比放大态小）');
    // fit 的口径：整图完整落在画布内（容差 1dp 抗浮点）。
    for (final t in ['根', '子1', '子6']) {
      final r = rectOf(tester, t);
      expect(canvas.inflate(1).contains(r.topLeft) &&
          canvas.inflate(1).contains(r.bottomRight), isTrue,
          reason: 'fit 后「$t」必须整块在画布内');
    }
  });

  testWidgets('缩到 25% 时节点仍可点中（最小可点面 44dp）', (tester) async {
    await pumpMap(tester, seed: (d, m) async {
      final root = await d.addNode(mapId: m, parentId: null, title: '根');
      for (var i = 1; i <= 4; i++) {
        await d.addNode(mapId: m, parentId: root.id, title: '子$i');
      }
    });
    for (var i = 0; i < 8; i++) {
      await tester.tap(find.byIcon(Icons.remove_outlined));
      await tester.pumpAndSettle();
    }
    final r = rectOf(tester, '根');
    // 前提：这一档下节点确实比 44 还小（否则下面点得中是因为它本来就大）。
    expect(r.height, lessThan(44), reason: '没缩到这个档，用例没逼到最小可点面');

    // 点在节点**下沿下方**（盒外、但仍在 44 见方的可点面内）。
    final below = Offset(r.center.dx, r.bottom + 12);
    expect(r.contains(below), isFalse, reason: '这个点必须在盒外，才叫放宽');
    await tester.tapAt(below);
    await tester.pumpAndSettle();
    // 选中态的判据＝贴点气泡出现（批P5 起选中只能从气泡读）。
    expect(find.byKey(const ValueKey('mm-bubble-child')), findsOneWidget,
        reason: '盒外 ±44dp 内应仍算点到该节点');
  });

  test('字号档三档量宽单调递增（sm < md < lg）', () {
    // 为什么纯函数测、不泵页面：泵页面读的是**语义块**尺寸，它按节点盒走，
    // 而测试字体替身把每个字符钉成固定宽度 ⇒ 盒宽对字号档几乎不敏感
    // （实测 sm 180 / lg 180，差不出 1dp）。量宽函数本身是字号直通的，
    // 在这层断才是真判据。
    //
    // 为什么字号档要验：painter 按 `style.fontSize` 画字、`mmNodeMeasure` 按
    // 同一值量盒；两边一旦脱钩就是「字溢出色块」。这条钉住量宽侧确实吃档位。
    const title = '字号档试验';
    final sm = mmNodeMeasure(title,
        style: TextStyle(fontSize: MmStyle.defaults.copyWith(size: MmStyle.kSizeSm).fontSize, fontWeight: FontWeight.w600));
    final lg = mmNodeMeasure(title,
        style: TextStyle(fontSize: MmStyle.defaults.copyWith(size: MmStyle.kSizeLg).fontSize, fontWeight: FontWeight.w600));
    expect(lg.width, greaterThan(sm.width),
        reason: '大档必须比小档宽（${sm.width} → ${lg.width}）');
    expect(lg.height, greaterThanOrEqualTo(sm.height), reason: '大档行高不该更矮');
  });

  test('zoomAround：锚点在缩放前后落在屏幕同一点，且钳在 25%~400%', () {
    const pan = Offset(30, -12);
    const scale = 0.8;
    const anchor = Offset(200, 300);
    final (s, p) = zoomAround(
        scale: scale, pan: pan, nextScale: 1.7, anchor: anchor);
    expect(s, closeTo(1.7, 1e-9));
    // 反算锚点画布坐标，两遍应一致。
    final c0 = (anchor - pan) / scale;
    final c1 = (anchor - p) / s;
    expect((c1 - c0).distance, lessThan(1e-6));

    final (sMin, _) = zoomAround(
        scale: 1, pan: Offset.zero, nextScale: 0.01, anchor: anchor);
    expect(sMin, mmMinScale);
    final (sMax, _) = zoomAround(
        scale: 1, pan: Offset.zero, nextScale: 99, anchor: anchor);
    expect(sMax, mmMaxScale);
  });
}
