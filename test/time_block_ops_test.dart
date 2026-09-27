import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/features/calendar/domain/block_ops.dart';
import 'package:lifeharness/features/calendar/domain/time_block.dart';

/// V1.52 时间模块纯操作层用例（收口规则 / 拆分合并 / 空隙 / 聚合）。
/// 规则出处：`prototype/index.html` p-calendar（time52patch*.js 已 31/31 绿）。
void main() {
  final day = DateTime(2026, 9, 19);
  TimeBlock blk(int s, int e, {String cat = '工作', String? note, String src = kSrcMark, int? id}) =>
      TimeBlock(
          id: id ?? s,
          day: day,
          startMin: s,
          endMin: e,
          catName: cat,
          note: note ?? cat,
          source: src);

  group('计时块 effEnd / durationMin', () {
    test('计时中块结束随当前时刻推进', () {
      final b = blk(540, 540, src: kSrcTiming);
      expect(b.isTiming, isTrue);
      expect(b.effEnd(DateTime(2026, 9, 19, 9, 50)), 590);
      expect(b.durationMin(DateTime(2026, 9, 19, 9, 50)), 50);
    });

    test('普通块不受当前时刻影响', () {
      final b = blk(540, 585);
      expect(b.effEnd(DateTime(2026, 9, 19, 23, 59)), 585);
    });

    test('当前时刻早于起始时钳回起始（不产生负耗时）', () {
      final b = blk(600, 600, src: kSrcTiming);
      expect(b.effEnd(DateTime(2026, 9, 19, 8, 0)), 600);
      expect(b.durationMin(DateTime(2026, 9, 19, 8, 0)), 0);
    });
  });

  group('closeMinuteForAdd · 未结束事件被后续事件自动关闭', () {
    final a = blk(600, 600, src: kSrcTiming); // a 从 10:00 起计时

    test('新段起始晚于 a → 收口到新段起始', () {
      expect(closeMinuteForAdd(timing: a, bStart: 630, nowMin: 700), 630);
    });

    test('新段起始=当前 → 收口到当前', () {
      expect(closeMinuteForAdd(timing: a, bStart: 700, nowMin: 700), 700);
    });

    test('收口不早于 a 自身起始', () {
      expect(closeMinuteForAdd(timing: a, bStart: 600, nowMin: 550), 600);
    });

    test('新段起始更早（纯补录）→ 不收口', () {
      expect(closeMinuteForAdd(timing: a, bStart: 540, nowMin: 700), isNull);
    });
  });

  group('addRejected · 补录越界', () {
    final a = blk(600, 600, src: kSrcTiming);

    test('补录跨过计时块起点被拒', () {
      expect(addRejected(timing: a, bStart: 540, bEnd: 660), isTrue);
    });

    test('补录完全早于计时块起点放行', () {
      expect(addRejected(timing: a, bStart: 480, bEnd: 540), isFalse);
    });

    test('起始不早于计时块时不由该规则拦截（走收口）', () {
      expect(addRejected(timing: a, bStart: 600, bEnd: 660), isFalse);
    });
  });

  group('splitHalf · 对半拆分', () {
    test('10:00-11:00 拆成两段等长', () {
      final parts = splitHalf(blk(600, 660))!;
      expect(parts.length, 2);
      expect([parts[0].startMin, parts[0].endMin], [600, 630]);
      expect([parts[1].startMin, parts[1].endMin], [630, 660]);
      expect(parts[1].id, isNull, reason: '第二段是新增行');
    });

    test('不足 2 分钟不可拆', () {
      expect(splitHalf(blk(600, 601)), isNull);
    });

    test('计时中块按当前时刻拆', () {
      final b = blk(600, 600, src: kSrcTiming);
      final parts = splitHalf(b, DateTime(2026, 9, 19, 10, 30))!;
      expect([parts[0].startMin, parts[0].endMin], [600, 615]);
      expect([parts[1].startMin, parts[1].endMin], [615, 630]);
    });
  });

  group('neighborOf / mergePair · 合并仅限相邻', () {
    final target = blk(600, 660, cat: '工作', id: 1);
    final prevNear = blk(570, 600, cat: '餐饮', id: 2);
    final prevFar = blk(300, 330, cat: '餐饮', id: 3);
    final nextNear = blk(660, 700, cat: '学习', id: 4);
    final timing = blk(700, 700, cat: '娱乐', id: 5, src: kSrcTiming);

    test('上/下相邻（间隙≤30 分）可合并', () {
      final day1 = [prevNear, target, nextNear, timing];
      expect(neighborOf(day1, target, -1)?.id, 2);
      expect(neighborOf(day1, target, 1)?.id, 4);
    });

    test('间隙超 30 分钟视为不相邻', () {
      final day2 = [prevFar, target];
      expect(neighborOf(day2, target, -1), isNull);
    });

    test('计时中块不参与合并', () {
      final day3 = [target, timing];
      expect(neighborOf(day3, target, 1)?.id, isNot(5));
      expect(neighborOf(day3, target, 1), isNull);
    });

    test('合并取并集区间并转回普通块', () {
      final m = mergePair(target, nextNear);
      expect([m.startMin, m.endMin], [600, 700]);
      expect(m.source, kSrcMark);
      expect(m.catName, '工作', reason: '分类取更早那段');
    });
  });

  group('freeGaps · 轴视图空隙', () {
    test('块之间的空档按最小 15 分钟筛出', () {
      final gaps = freeGaps([blk(540, 600), blk(700, 760)]);
      expect(gaps, [
        [0, 540],
        [600, 700],
        [760, 1440]
      ]);
    });

    test('小于阈值的缝隙不生成补录条', () {
      final gaps = freeGaps([blk(540, 600), blk(610, 700)]);
      expect(gaps.any((g) => g[0] == 600), isFalse);
    });

    test('无块时整段可点', () {
      expect(freeGaps([]), [
        [0, 1440]
      ]);
    });

    test('计时中块按已耗时结束空隙', () {
      final b = blk(600, 600, src: kSrcTiming);
      final gaps = freeGaps([b], now: DateTime(2026, 9, 19, 10, 30));
      expect(gaps.last, [630, 1440]);
    });
  });

  group('聚合与环比', () {
    test('minutesByCat 含计时中已耗时', () {
      final m = minutesByCat(
          [blk(540, 585, cat: '工作'), blk(600, 600, cat: '娱乐', src: kSrcTiming)],
          DateTime(2026, 9, 19, 10, 20));
      expect(m['工作'], 45);
      expect(m['娱乐'], 20);
      expect(totalMinutes(m.keys.map((k) => blk(0, m[k]!, cat: k))), 65);
    });

    test('deltaPct 上期为 0 时不可比', () {
      expect(deltaPct(60, 30), 100);
      expect(deltaPct(60, 0), isNull);
      expect(deltaPct(30, 60), -50);
    });

    test('fmtMin 跨天回绕 · fmtDur 天/时/分', () {
      expect(fmtMin(1470), '00:30');
      expect(fmtDur(90), '1 时 30 分');
      expect(fmtDur(120), '2 时');
      expect(fmtDur(45), '45 分');
      expect(fmtDur(0), '0 分');
      expect(fmtDur(1500), '1 天 1 时', reason: '年档大数必须带天档');
      expect(fmtDur(1440), '1 天');
    });
  });
}
