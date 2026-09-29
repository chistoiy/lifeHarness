import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/features/kits/domain/kit_wheel.dart';

/// V1.47 批2 · 轮盘抽签域层用例（原型 `wheelParsePaste` / `wheelGo` / 约束口径）。
void main() {
  KitWheelSet set(List<(String, int)> xs, {String id = 'w1', String name = '日常'}) =>
      KitWheelSet(
        id: id,
        name: name,
        items: [for (final x in xs) KitWheelItem(x.$1, x.$2)],
      );

  group('1 · 数据自愈（原型 wheelSets）', () {
    test('空数据建默认 6 项套', () {
      final d = kitWheelDecode(const {});
      expect(d.sets.length, 1);
      expect(d.curId, 'w1');
      expect(d.sets.first.items.length, 6);
      expect(d.sets.first.items.map((e) => e.text).toList(),
          ['写日记', '跑步 5km', '阅读 30 分钟', '吃顿好的', '看部电影', '发呆时间']);
    });

    test('cur 指向不存在的套 → 回落首套；sets 为空 → 重建', () {
      final d = kitWheelDecode({
        'cur': 'nope',
        'sets': [
          {'id': 'a', 'name': 'A', 'items': []},
          {'id': 'b', 'name': 'B', 'items': []},
        ],
      });
      expect(d.curId, 'a');
      final e = kitWheelDecode({
        'cur': 'x',
        'sets': const <Object>[],
      });
      expect(e.sets.single.id, 'w1');
    });

    test('编解码往返保留套、权重与历史', () {
      final src = [
        KitWheelSet(
          id: 'w1',
          name: '日常',
          items: const [KitWheelItem('写日记', 3), KitWheelItem('跑步', 1)],
          history: const [KitWheelResult('写日记', 1700000000000)],
        ),
      ];
      final back = kitWheelDecode(kitWheelEncode(src, 'w1'));
      expect(back.sets.single.items.map((e) => e.weight).toList(), [3, 1]);
      expect(back.sets.single.history.single.option, '写日记');
      expect(back.curId, 'w1');
    });

    test('损坏 JSON 字段按缺失处理（不炸界面）', () {
      final d = kitWheelDecode({
        'cur': 123,
        'sets': [
          {'id': 'a', 'name': 'A', 'items': '坏了'},
        ],
      });
      expect(d.sets.single.items, isEmpty);
    });
  });

  group('2 · 约束（2~12 项 · 8 套 · 权重 1~9 · 名称 12 字）', () {
    test('权重与名称钳制', () {
      expect(kitWheelClampWeight(0), 1);
      expect(kitWheelClampWeight(99), 9);
      expect(kitWheelClampText('一二三四五六七八九十甲乙丙丁'), '一二三四五六七八九十甲乙');
    });

    test('配色按项数截取（2~12）', () {
      expect(kitWheelColors(1).length, 2);
      expect(kitWheelColors(5).length, 5);
      expect(kitWheelColors(30).length, 12);
    });

    test('常量登记与原型一致', () {
      expect(kKitWheelMinItems, 2);
      expect(kKitWheelMaxItems, 12);
      expect(kKitWheelMaxSets, 8);
      expect(kKitWheelMaxHistory, 12);
    });
  });

  group('3 · 批量粘贴解析', () {
    test('换行/逗号/顿号/分号分隔，中英文冒号取权重', () {
      final l = kitWheelParsePaste('可乐:3\n健身:1、阅读:2，打游戏；散步');
      expect(l.map((e) => e.text).toList(), ['可乐', '健身', '阅读', '打游戏', '散步']);
      expect(l.map((e) => e.weight).toList(), [3, 1, 2, 1, 1]);
    });

    test('空行忽略；权重越界钳到 1~9', () {
      final l = kitWheelParsePaste('\n\n 甲:99 \n乙:0');
      expect(l.map((e) => e.text).toList(), ['甲', '乙']);
      expect(l.map((e) => e.weight).toList(), [9, 1]);
    });

    test('追加：满 12 项拒绝，超出上限部分丢弃', () {
      final full = [for (var i = 0; i < 12; i++) KitWheelItem('项$i', 1)];
      final r0 = kitWheelAppend(full, kitWheelParsePaste('甲,乙'));
      expect(r0.added, isEmpty);
      expect(r0.skipped, 2);
      final ten = full.take(10).toList();
      final r1 = kitWheelAppend(ten, kitWheelParsePaste('甲,乙,丙,丁'));
      expect(r1.added.length, 2);
      expect(r1.skipped, 2);
    });
  });

  group('4 · 扇区与落点', () {
    test('扇区角度按权重占比，末段收在 360°', () {
      final ss = kitWheelSectors(set([('甲', 3), ('乙', 1)]));
      expect(ss.length, 2);
      expect(ss[0].start, 0);
      expect(ss[0].end, 270);
      expect(ss[1].start, 270);
      expect(ss[1].end, closeTo(360, 1e-9));
      expect(kitWheelSectors(set(const <(String, int)>[])), isEmpty);
    });

    test('占比取整（原型 Math.round）', () {
      final s = set([('甲', 3), ('乙', 1)]);
      expect(s.totalWeight, 4);
      expect(s.percentOf(0), 75);
      expect(s.percentOf(1), 25);
      expect(s.percentOf(9), 0);
    });

    test('随机源决定命中项（权重区间边界）', () {
      final s = set([('甲', 3), ('乙', 1)]);
      expect(kitWheelSpin(s, currentRotation: 0, rand01: 0.0).index, 0);
      expect(kitWheelSpin(s, currentRotation: 0, rand01: 0.999).index, 1);
      // r 恰好落在甲的右端点（0.75×4−3=0）→ 原型同口径判给甲。
      expect(kitWheelSpin(s, currentRotation: 0, rand01: 0.75).index, 0);
      expect(kitWheelSpin(s, currentRotation: 0, rand01: 0.76).index, 1);
    });

    test('旋转角把命中的扇区中线停在顶部指针，且至少多转三圈', () {
      final s = set([('甲', 3), ('乙', 1)]);
      final r = kitWheelSpin(s, currentRotation: 0, rand01: 0.0);
      // 甲中线 = 135°，需再转 225° → 0 + 1080 + 225。
      expect(r.rotateTo, closeTo(1305, 1e-6));
      final after = ((r.rotateTo + 135) % 360);
      expect(after, closeTo(0, 1e-6)); // 中线落到正上方
      final r2 = kitWheelSpin(s, currentRotation: 400, rand01: 0.9);
      expect(r2.rotateTo, greaterThan(400 + 1080 - 1e-9));
    });

    test('历史压入表头并截断 12 条', () {
      var h = <KitWheelResult>[];
      for (var i = 0; i < 15; i++) {
        h = kitWheelPushHistory(h, KitWheelResult('项$i', i));
      }
      expect(h.length, kKitWheelMaxHistory);
      expect(h.first.option, '项14');
      expect(h.last.option, '项3');
    });
  });
}
