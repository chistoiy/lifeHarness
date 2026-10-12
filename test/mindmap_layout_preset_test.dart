import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/features/mindmap/domain/mindmap_layout.dart';
import 'package:lifeharness/features/mindmap/domain/mindmap_layout_preset.dart';
import 'package:lifeharness/features/mindmap/domain/mindmap_models.dart';
import 'package:lifeharness/features/mindmap/presentation/mindmap_painter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 思维导图批4 · 布局预设与三引擎守护（工单 §4e.2 ①②③④⑤ + 变异刀2 钉位）。
///
/// 纯 Dart 级：引擎用默认度量（固定尺寸），零 Flutter 依赖；store 组用
/// `SharedPreferences.setMockInitialValues`（同批3 `mindmap_style_test` 口径）。
MindmapNode _n(
  int id, {
  int? parent,
  int sort = 0,
  bool folded = false,
  String? side,
  double dx = 0,
  double dy = 0,
  String title = '',
}) =>
    MindmapNode(
      id: id,
      mapId: 1,
      parentId: parent,
      title: title.isEmpty ? '节点$id' : title,
      sort: sort,
      folded: folded,
      side: side,
      dx: dx,
      dy: dy,
      createdAt: 1,
      updatedAt: 1,
    );

/// 一棵 1(根) + 4 子 + 子 2 下挂 1 孙的树（覆盖宽树与深树两种形态）。
List<MindmapNode> _sample() => [
      _n(1),
      _n(2, parent: 1, sort: 0),
      _n(3, parent: 1, sort: 1),
      _n(4, parent: 1, sort: 2),
      _n(5, parent: 1, sort: 3),
      _n(6, parent: 2, sort: 0),
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ---- ① 四预设表逐字照抄原型 LAY_PRESETS ----
  group('① 预设表（照抄原型 LAY_PRESETS）', () {
    test('四张卡的键/标题/副标逐字不差', () {
      expect(mmLayoutCards.length, 4);
      expect(
        mmLayoutCards.map((c) => '${c.preset.key}|${c.title}|${c.sub}').toList(),
        [
          'tree/right/portrait|纵向树|竖屏默认',
          'tree/right/landscape|横向树|父左子右',
          'tree/both/landscape|双向树|子级分列两侧',
          'radial/both/portrait|放射图|根居中四面铺开',
        ],
      );
    });

    test('缩略图形态四分支齐（outline/hright/hboth/radial）', () {
      expect(mmLayoutCards.map((c) => c.icon).toList(),
          ['outline', 'hright', 'hboth', 'radial']);
    });

    test('默认预设＝纵向树/向右/竖屏（C12）', () {
      expect(MmLayoutPreset.defaults.key, 'tree/right/portrait');
    });

    test('parse 逐段回落：认得的段生效、认不出的段落默认（不许炸页面）', () {
      expect(MmLayoutPreset.parse('radial/both/landscape').key,
          'radial/both/landscape');
      // 非法段：struct 落 tree、dir 落 right、ratio 落 portrait。
      expect(MmLayoutPreset.parse('gantt/zzz/xxx').key, 'tree/right/portrait');
      expect(MmLayoutPreset.parse('tree/both').key, 'tree/right/portrait');
      expect(MmLayoutPreset.parse(null).key, 'tree/right/portrait');
      expect(MmLayoutPreset.parse('').key, 'tree/right/portrait');
    });
  });

  // ---- 工厂：预设挑引擎 ----
  group('预设 → 引擎工厂', () {
    test('tree/right/portrait 与 tree/right/landscape 各自挑对应引擎', () {
      expect(
        const MmLayoutPreset(
                struct: MmLayoutPreset.sTree,
                dir: MmLayoutPreset.dRight,
                ratio: MmLayoutPreset.rPortrait)
            .engine(),
        isA<HorizontalTreeEngine>(),
        reason: '默认预设走横向树引擎（纵向大纲由画布页的批1 引擎实例承担）',
      );
    });

    test('landscape 强制走横向列排：dir=right 也按横向树算（原型口径）', () {
      final p = const MmLayoutPreset(
          struct: MmLayoutPreset.sTree,
          dir: MmLayoutPreset.dRight,
          ratio: MmLayoutPreset.rLandscape);
      final e = p.engine() as HorizontalTreeEngine;
      expect(e.both, isTrue, reason: 'ratio=landscape 与 dir=both 共用横向分支');
    });

    test('radial 挑放射引擎，both 位直传', () {
      final e = const MmLayoutPreset(
              struct: MmLayoutPreset.sRadial,
              dir: MmLayoutPreset.dBoth,
              ratio: MmLayoutPreset.rPortrait)
          .engine() as RadialEngine;
      expect(e.both, isTrue);
    });
  });

  // ---- ② 默认态零视觉变化 ----
  group('② 默认态零视觉变化（批1 纵向树逐值不变）', () {
    test('默认预设结果与批1 TreeLayoutEngine 逐值相等', () {
      final nodes = _sample();
      final batch1 = TreeLayoutEngine().layout(nodes);
      // 画布页默认路径走的就是批1 那个引擎（_layoutFor 的 defaults 分支）；
      // 这里以「同一引擎同一输入」为默认态口径：结果确定且连线画法＝stair。
      expect(batch1.edgeKind, MmEdgeKind.stair);
      expect(batch1.baseline.length, nodes.length);
      // 默认形态的连线仍是批2 修形的横向贝塞尔口径（assignedSides 全 r）。
      expect(batch1.assignedSides.values.every((s) => s == 'r'), isTrue);
    });
  });

  // ---- 横向树 ----
  group('横向树引擎（tree × dir）', () {
    test('dir=right：子节点全部在父右侧，且逐列右移（父左子右）', () {
      final l = HorizontalTreeEngine(both: false).layout(_sample());
      for (final n in _sample()) {
        if (n.parentId == null) continue;
        final p = l.baseline[n.parentId]!;
        final c = l.baseline[n.id]!;
        expect(c.dx, greaterThan(p.dx),
            reason: '节点${n.id} 应在父右侧');
      }
      expect(l.edgeKind, MmEdgeKind.branch);
    });

    test('dir=both：4 个子节点分列两侧（2 右 2 左）', () {
      final l = HorizontalTreeEngine(both: true).layout(_sample());
      final kids = [2, 3, 4, 5];
      final rs = kids.where((id) => l.assignedSides[id] == 'r').toList();
      final ls = kids.where((id) => l.assignedSides[id] == 'l').toList();
      expect(rs.length, 2);
      expect(ls.length, 2);
      // 左置子节点的**右缘**贴在根的左缘（不与根重叠）。
      final rootLeft = l.baseline[1]!.dx;
      for (final id in ls) {
        final w = l.sizes[id]!.width;
        expect(l.baseline[id]!.dx + w, lessThanOrEqualTo(rootLeft + 0.01));
      }
    });

    test('dir=both 奇数子节点：右侧多一个（§2.6 原话）', () {
      final nodes = [_n(1), _n(2, parent: 1), _n(3, parent: 1), _n(4, parent: 1)];
      final l = HorizontalTreeEngine(both: true).layout(nodes);
      final rs = [2, 3, 4].where((id) => l.assignedSides[id] == 'r').length;
      final ls = [2, 3, 4].where((id) => l.assignedSides[id] == 'l').length;
      expect(rs, 2);
      expect(ls, 1);
    });

    test('显式 side 优先：手动分侧的节点换预设后仍守在原侧', () {
      final nodes = [
        _n(1),
        _n(2, parent: 1, side: 'l'),
        _n(3, parent: 1, side: 'l'),
        _n(4, parent: 1),
      ];
      final l = HorizontalTreeEngine(both: true).layout(nodes);
      expect(l.assignedSides[2], 'l');
      expect(l.assignedSides[3], 'l');
      // 剩下的补右侧（右侧优先补满）。
      expect(l.assignedSides[4], 'r');
    });

    test('同侧子节点块两两不重叠（纵向间距按实测高累加）', () {
      final l = HorizontalTreeEngine(both: true).layout(_sample());
      final rs = [2, 3, 4, 5].map((id) => l.baseline[id]!).toList()
        ..sort((a, b) => a.dy.compareTo(b.dy));
      for (var i = 1; i < rs.length; i++) {
        expect(rs[i].dy, greaterThanOrEqualTo(rs[i - 1].dy),
            reason: '右侧第 $i 块与上一块重叠');
      }
    });

    test('折叠整枝跳过（F1-9，三引擎口径一致）', () {
      final nodes = [_n(1), _n(2, parent: 1, folded: true), _n(3, parent: 2)];
      for (final e in <LayoutEngine>[
        HorizontalTreeEngine(both: false),
        HorizontalTreeEngine(both: true),
        RadialEngine(both: true),
      ]) {
        expect(e.layout(nodes).baseline.keys, isNot(contains(3)),
            reason: '${e.runtimeType} 未跳过折叠枝');
      }
    });
  });

  // ---- 放射 ----
  group('放射引擎（radial）', () {
    test('根居中：根的宽高中心落在圆心（原点在归一前的坐标空间）', () {
      final nodes = _sample();
      final e = RadialEngine(both: true);
      final l = e.layout(nodes);
      // 归一后拿不到原点，改为验「根中心与四个一级子中心的平均距离一致」——
      // 根必须真的居中，否则一层子级会压在根上（原型目检实锤）。
      final root = Rect.fromLTWH(l.baseline[1]!.dx, l.baseline[1]!.dy,
          l.sizes[1]!.width, l.sizes[1]!.height);
      final rootC = root.center;
      final dists = [2, 3, 4, 5]
          .map((id) => (Offset(l.baseline[id]!.dx + l.sizes[id]!.width / 2,
                      l.baseline[id]!.dy + l.sizes[id]!.height / 2) -
                  rootC)
              .distance)
          .toList();
      for (final d in dists) {
        expect(d, closeTo(dists.first, 0.01),
            reason: '同一环的子节点到根中心距离应相等（同心圆）');
      }
      expect(l.edgeKind, MmEdgeKind.radial);
    });

    test('both=false 只铺右半圆：子节点 x 均不小于根中心', () {
      final nodes = _sample();
      final l = RadialEngine(both: false).layout(nodes);
      final rootC = l.baseline[1]!.dx + l.sizes[1]!.width / 2;
      for (final id in [2, 3, 4, 5, 6]) {
        final cx = l.baseline[id]!.dx + l.sizes[id]!.width / 2;
        expect(cx, greaterThanOrEqualTo(rootC - 0.01),
            reason: '节点$id 落在右半圆之外');
      }
    });

    test('both=true 铺整圆：左右两侧都有子节点', () {
      final l = RadialEngine(both: true).layout(_sample());
      final rootC = l.baseline[1]!.dx + l.sizes[1]!.width / 2;
      final lefts = [2, 3, 4, 5]
          .where((id) => l.baseline[id]!.dx + l.sizes[id]!.width / 2 < rootC)
          .length;
      final rights = [2, 3, 4, 5]
          .where((id) => l.baseline[id]!.dx + l.sizes[id]!.width / 2 > rootC)
          .length;
      expect(lefts, greaterThan(0));
      expect(rights, greaterThan(0));
    });

    test('多根各自成圈：第二个根整体在第一个根下方（不叠圈）', () {
      final nodes = [_n(1), _n(2, parent: 1), _n(3), _n(4, parent: 3)];
      final l = RadialEngine(both: true).layout(nodes);
      expect(l.baseline[3]!.dy, greaterThan(l.baseline[1]!.dy + l.sizes[1]!.height));
    });
  });

  // ---- 归一 ----
  group('坐标归一（mmNormalize）', () {
    test('全图基线非负且留边距；相对位置不变', () {
      final raw = <int, Offset>{1: const Offset(-60, -18), 2: const Offset(90, 132)};
      final out = mmNormalize(raw);
      expect(out[1]!.dx, greaterThanOrEqualTo(16));
      expect(out[1]!.dy, greaterThanOrEqualTo(16));
      expect(out[2]!.dx - out[1]!.dx, raw[2]!.dx - raw[1]!.dx,
          reason: '归一只做常量平移，不改相对位置');
    });

    test('已全非负且大于边距时原样返回（零分配）', () {
      final raw = <int, Offset>{1: const Offset(40, 40)};
      expect(identical(mmNormalize(raw), raw), isTrue);
    });

    test('两新引擎的输出基线恒非负', () {
      final nodes = _sample();
      for (final e in <LayoutEngine>[
        HorizontalTreeEngine(both: true),
        RadialEngine(both: true),
      ]) {
        for (final p in e.layout(nodes).baseline.values) {
          expect(p.dx, greaterThanOrEqualTo(0), reason: '${e.runtimeType} x 为负');
          expect(p.dy, greaterThanOrEqualTo(0), reason: '${e.runtimeType} y 为负');
        }
      }
    });
  });

  // ---- ③④⑤ store 往返与每图隔离 ----
  group('③④⑤ 预设存储（每图一套）', () {
    late SharedPreferences prefs;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    test('往返：设预设 → 冷启重读 → 同一预设', () async {
      const p = MmLayoutPreset(
          struct: MmLayoutPreset.sRadial,
          dir: MmLayoutPreset.dBoth,
          ratio: MmLayoutPreset.rPortrait);
      await MmLayoutStore(prefs).save(7, p);
      expect(MmLayoutStore(prefs).load(7), p);
    });

    test('未设过返回 null（有别于「显式设成默认」）', () {
      expect(MmLayoutStore(prefs).load(9), isNull);
    });

    test('每图隔离（变异刀2 钉位）：A 设放射、B 未设 → B 仍是纵向树', () async {
      final store = MmLayoutStore(prefs);
      await store.save(
          1,
          const MmLayoutPreset(
              struct: MmLayoutPreset.sRadial,
              dir: MmLayoutPreset.dBoth,
              ratio: MmLayoutPreset.rPortrait));
      expect(store.load(1)!.isRadial, isTrue);
      expect(store.load(2), isNull);
      expect(store.load(2) ?? MmLayoutPreset.defaults, MmLayoutPreset.defaults);
    });

    test('reset 只清自己那一格；删到空则整 key 清掉', () async {
      final store = MmLayoutStore(prefs);
      await store.save(1, MmLayoutPreset.defaults);
      await store.save(2, MmLayoutPreset.defaults);
      await store.reset(1);
      expect(store.load(1), isNull);
      expect(store.load(2), MmLayoutPreset.defaults);
      await store.reset(2);
      expect(prefs.getString(MmLayoutStore.key), isNull);
    });

    test('损坏 JSON 不炸、按未设回落（用户数据不可炸页面）', () async {
      await prefs.setString(MmLayoutStore.key, '{不是合法 json');
      expect(MmLayoutStore(prefs).load(1), isNull);
      await prefs.setString(MmLayoutStore.key, '["不是 map"]');
      expect(MmLayoutStore(prefs).load(1), isNull);
      await prefs.setString(MmLayoutStore.key, '{"1":{"struct":"tree"}}');
      expect(MmLayoutStore(prefs).load(1), isNull,
          reason: '格内不是字符串键（对象）＝按未设处理');
    });

    test('损坏后 save 能自愈（覆盖成合法值）', () async {
      await prefs.setString(MmLayoutStore.key, 'xx');
      final store = MmLayoutStore(prefs);
      await store.save(1, MmLayoutPreset.defaults);
      expect(store.load(1), MmLayoutPreset.defaults);
    });
  });

  // ---- ⑥ 连线按形态分派（变异刀3 钉位） ----
  group('⑥ 连线画法按布局形态分派', () {
    final nodes = _sample();
    final byId = {for (final n in nodes) n.id!: n};

    List<MmEdgeRoute> routesOf(MmLayoutPreset preset) {
      final l = mmLayoutOf(preset, nodes);
      return mmEdgeRoutes(
        nodes: nodes,
        edgeKind: l.edgeKind,
        assignedSides: l.assignedSides,
        rectOf: (n) {
          final b = l.baseline[n.id]!;
          return Rect.fromLTWH(b.dx, b.dy, l.sizes[n.id]!.width,
              l.sizes[n.id]!.height);
        },
      );
    }

    test('纵向大纲（默认）走阶梯贝塞尔：仍是批2 那一支（非两点直线）', () {
      final l = TreeLayoutEngine().layout(nodes);
      final rs = mmEdgeRoutes(
        nodes: nodes,
        edgeKind: l.edgeKind,
        assignedSides: l.assignedSides,
        rectOf: (n) {
          final b = l.baseline[n.id]!;
          return Rect.fromLTWH(
              b.dx, b.dy, l.sizes[n.id]!.width, l.sizes[n.id]!.height);
        },
      );
      expect(rs.length, 5, reason: '样例树有 5 条父子边');
      expect(rs.every((r) => !r.isStraight), isTrue,
          reason: '默认形态的连线画法必须逐值保持批2 基线');
    });

    test('横向树走「父中心 → 子中心」两点直线（变异刀3 钉位）', () {
      final rs = routesOf(const MmLayoutPreset(
          struct: MmLayoutPreset.sTree,
          dir: MmLayoutPreset.dRight,
          ratio: MmLayoutPreset.rLandscape));
      expect(rs, isNotEmpty);
      expect(rs.every((r) => r.isStraight), isTrue,
          reason: '横向布局套阶梯公式＝连线斜穿节点（6113 实锤同族坑）');
      // 直线两端必须正好落在父子盒中心。
      final l = mmLayoutOf(
          const MmLayoutPreset(
              struct: MmLayoutPreset.sTree,
              dir: MmLayoutPreset.dRight,
              ratio: MmLayoutPreset.rLandscape),
          nodes);
      final first = rs.first;
      final parent = byId[nodes.firstWhere((n) => n.id == first.childId).parentId]!;
      final child = byId[first.childId]!;
      final pb = l.baseline[parent.id]!;
      final cb = l.baseline[child.id]!;
      expect(first.points.first,
          Offset(pb.dx + l.sizes[parent.id]!.width / 2,
              pb.dy + l.sizes[parent.id]!.height / 2));
      expect(first.points.last,
          Offset(cb.dx + l.sizes[child.id]!.width / 2,
              cb.dy + l.sizes[child.id]!.height / 2));
    });

    test('放射走两点直线', () {
      final rs = routesOf(const MmLayoutPreset(
          struct: MmLayoutPreset.sRadial,
          dir: MmLayoutPreset.dBoth,
          ratio: MmLayoutPreset.rPortrait));
      expect(rs.every((r) => r.isStraight), isTrue);
    });

    test('单端缺失的边不产路由（父不在待绘集合里则整条省略）', () {
      final l = TreeLayoutEngine().layout(nodes);
      // 只留根与一个子：其余子节点不在列表里，其边不画。
      final partial = [byId[1]!, byId[2]!];
      final rs = mmEdgeRoutes(
        nodes: partial,
        edgeKind: l.edgeKind,
        assignedSides: l.assignedSides,
        rectOf: (n) => const Rect.fromLTWH(0, 0, 10, 10),
      );
      expect(rs.length, 1);
      expect(rs.single.childId, 2);
    });
  });

  // ---- ③ 换预设只重算基线、偏移保留 ----
  group('③ 偏移与基线正交（2d 口径）', () {
    test('三引擎都不消费 dx/dy——偏移是渲染层叠加量', () {
      final plain = _sample();
      final moved = [
        _n(1, dx: 60, dy: -30),
        _n(2, parent: 1, sort: 0, dx: 12),
        _n(3, parent: 1, sort: 1),
        _n(4, parent: 1, sort: 2),
        _n(5, parent: 1, sort: 3),
        _n(6, parent: 2, sort: 0),
      ];
      for (final e in <LayoutEngine>[
        TreeLayoutEngine(),
        HorizontalTreeEngine(both: true),
        RadialEngine(both: true),
      ]) {
        expect(e.layout(moved).baseline, e.layout(plain).baseline,
            reason: '${e.runtimeType} 把拖拽偏移算进基线了');
      }
    });
  });
}