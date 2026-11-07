import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lifeharness/features/health/data/health_settings.dart';
import 'package:lifeharness/features/health/domain/health_calc.dart';
import 'package:lifeharness/features/health/domain/health_trend.dart';

/// 健康批6a · 趋势与周报规格单源（事实源＝`prototype/index-health.html` 的 `p-trends`＋`sheetHealthReport`，
/// JS 段 `HT_METRICS`／`hTrends`／`hMonthAvg`／`hTrendDay`／`hReport`——屏、弹层、复制文本三处都读这一件）。
///
/// 判据组（工单执行面板第 3 项「常驻用例」逐条钉死）：
/// · **缺记录日整格 null**（不补数）：热力出空格、曲线跳点、均值只吃有记录日——原型拿哈希补空槽一条不照抄；
/// · `trHeatLevel` 三档 `.72/.45/.18` ＋ -1 空格（刀1 靶：改成 `>=.5` 单一档这一组立刻红）；
/// · 四数据位三形态（体重/百分比类/量类各四枚，空段全出「—」）；
/// · 环比上期「上期无记录」出实话，不除零、不出 NaN；
/// · 周报六枚 tile＋同比五行**现算**（原型 `hrDiff` 五常量不抄）＋七日条＋结论句；
///   占比分母恒 7、日均分母只吃有记录日（刀2 靶：把 7 改成有记录天数这一组红）；
/// · **目标线只吃设置＋目标表读数**（刀3 靶：`ex` 折算摘掉改回写死 30 这一组红）。
void main() {
  // 固定参考日做纯函数入参——序列全部相对它构造，不落「今天减小时」的时间炸弹。
  final ref = DateTime(2026, 10, 8); // 周四
  String dk(int back) => dayKey(ref.subtract(Duration(days: back)));

  const goals = TrGoals(waterCups: 10, sleepHours: 8, weekExGoal: 3, bodyKg: 60);

  TrDay day({
    required String date,
    int? cups,
    int? sleepMin,
    int? exMin,
    double? kg,
    int? medPlanned,
    int? medTaken,
    List<int> paces = const <int>[],
  }) =>
      TrDay(
        date: date,
        cups: cups,
        sleepMin: sleepMin,
        exMin: exMin,
        kg: kg,
        medPlanned: medPlanned,
        medTaken: medTaken,
        paces: paces,
      );

  /// 全达标日：喝水满格＋睡满 8h＋运动过 10 分钟门槛 → 综合 100。
  TrDay fullDay(String date, {double kg = 60}) =>
      day(date: date, cups: 12, sleepMin: 480, exMin: 30, kg: kg, medPlanned: 2, medTaken: 2);
  /// 半达标日：睡 7h、没运动、水不足 → 综合 51（<80 不达标、>40 不算待改善）。
  TrDay halfDay(String date) =>
      day(date: date, cups: 4, sleepMin: 420, exMin: 0, medPlanned: 2, medTaken: 1);

  List<TrDay> week(TrDay Function(String date) f) =>
      [for (var i = 6; i >= 0; i--) f(dk(i))];

  group('六指标单源：名称/单位/形态/小数位', () {
    test('枚举顺序与六枚 label/unit 逐一对原型 `HT_METRICS`', () {
      expect(trMetricOrder, TrMetric.values, reason: '面板第 1 项：六枚顺序即 chips 顺序');
      expect(TrMetric.all.label, '综合达标');
      expect(TrMetric.water.label, '喝水');
      expect(TrMetric.sleep.label, '睡眠');
      expect(TrMetric.ex.label, '运动');
      expect(TrMetric.body.label, '体重');
      expect(TrMetric.drug.label, '用药');
      expect([for (final m in trMetricOrder) m.unit], ['%', '杯', 'h', '分钟', 'kg', '%']);
    });

    test('形态三分：综合/用药＝百分比，体重＝body，其余＝量类；体重与睡眠一位小数', () {
      expect(TrMetric.all.shape, TrShape.percent);
      expect(TrMetric.drug.shape, TrShape.percent);
      expect(TrMetric.body.shape, TrShape.body);
      expect(TrMetric.water.shape, TrShape.quantity);
      expect(TrMetric.sleep.shape, TrShape.quantity);
      expect(TrMetric.ex.shape, TrShape.quantity);
      expect(TrMetric.body.decimals, 1);
      expect(TrMetric.sleep.decimals, 1);
      expect(TrMetric.water.decimals, 0);
      expect(TrMetric.all.decimals, 0);
    });
  });

  group('单日读数：缺记录整格 null，综合分只在整日无记录时缺席', () {
    test('六枚 valueOf 各取各格', () {
      final d = day(
        date: dk(0),
        cups: 8,
        sleepMin: 450,
        exMin: 30,
        kg: 61.5,
        medPlanned: 2,
        medTaken: 1,
      );
      expect(d.valueOf(TrMetric.water, goals), 8);
      expect(d.valueOf(TrMetric.sleep, goals), 7.5);
      expect(d.valueOf(TrMetric.ex, goals), 30);
      expect(d.valueOf(TrMetric.body, goals), 61.5);
      expect(d.valueOf(TrMetric.drug, goals), 50);
      // 综合：w=0.8→32 + s=450/480→32.8125→约 33 + e=1→25 = 90
      expect(d.valueOf(TrMetric.all, goals), 90);
    });

    test('整日无记录＝recorded false，综合出 null、六枚全 null', () {
      final d = day(date: dk(1));
      expect(d.recorded, isFalse);
      expect(d.score(goals), isNull);
      for (final m in trMetricOrder) {
        expect(d.valueOf(m, goals), isNull, reason: '$m 缺记录不许出 0 假点');
      }
    });

    test('部分缺记录：分量按 0 吃进综合，但单指标仍出 null', () {
      final d = day(date: dk(2), cups: 10); // 只有喝水
      expect(d.recorded, isTrue);
      expect(d.valueOf(TrMetric.sleep, goals), isNull);
      expect(d.valueOf(TrMetric.body, goals), isNull);
      expect(d.valueOf(TrMetric.drug, goals), isNull);
      // w=1→40 + s=0 + e=0 = 40
      expect(d.score(goals), 40);
    });

    test('用药依从：无计划出 null（缺数据日不画 0 假点），有计划按已服/计划', () {
      expect(day(date: dk(0)).medRate, isNull);
      expect(day(date: dk(0), medPlanned: 0, medTaken: 0).medRate, isNull);
      expect(day(date: dk(0), medPlanned: 2, medTaken: 2).medRate, 100);
      expect(day(date: dk(0), medPlanned: 3, medTaken: 2).medRate, 67);
    });

    test('当日明细行：缺格出「—」、日期带周几', () {
      final tx = day(date: dk(0), cups: 5, exMin: 20).detailTx(goals);
      expect(tx, contains('${dk(0).substring(5)} ${dayWd(dk(0))}'));
      expect(tx, contains('喝水 5/10 杯'));
      expect(tx, contains('睡眠 —h'));
      expect(tx, contains('运动 20 分钟'));
      expect(tx, contains('体重 —kg'));
      expect(tx, contains('用药 —'));
    });
  });

  group('目标线（刀3 靶）：只吃设置与目标表读数', () {
    test('常量判据：综合 80、用药 100 是达标定义；体重未设＝null 不画虚线', () {
      expect(TrGoals.scoreGoalPct, 80);
      expect(TrGoals.drugGoalPct, 100);
      expect(goals.of(TrMetric.all), 80);
      expect(goals.of(TrMetric.drug), 100);
      expect(goals.of(TrMetric.body), 60);
      const noWeight = TrGoals(waterCups: 8, sleepHours: 8, weekExGoal: 3);
      expect(noWeight.of(TrMetric.body), isNull);
      expect(noWeight.goalTx(TrMetric.body), isNull, reason: '未设目标不出「目标 …」串');
    });

    test('运动日参考线＝周次数×10÷7 折算：3→4.3、5→7.1（写死 30 即红）', () {
      expect(goals.exDailyMinGoal, 4.3, reason: '3 次/周 → 30/7 ≈ 4.3 分钟/日');
      const five = TrGoals(waterCups: 10, sleepHours: 8, weekExGoal: 5);
      expect(five.exDailyMinGoal, 7.1);
      expect(five.of(TrMetric.ex), 7.1);
      expect(five.goalTx(TrMetric.ex), '目标 7 分钟', reason: '运动 decimals=0，读数取整');
      expect(goals.goalTx(TrMetric.ex), '目标 4 分钟', reason: '线位用 4.3 画，读数按 decimals=0 取整');
    });

    test('接线兑现：与 healthTrGoalsProvider 同源——三档读 HealthSettings、体重读 goals[weight_goal]', () async {
      SharedPreferences.setMockInitialValues({
        HealthSettings.kWaterGoal: 9,
        HealthSettings.kSleepGoal: 7,
        HealthSettings.kWeekExGoal: 4,
      });
      final st = HealthSettings(await SharedPreferences.getInstance());
      // 复刻 provider 的取值式（`health_providers.dart` healthTrGoalsProvider）
      final g = TrGoals(
        waterCups: st.waterGoal().toDouble(),
        sleepHours: st.sleepGoalHours().toDouble(),
        weekExGoal: st.weekExGoal(),
        bodyKg: const {'weight_goal': 58.5}['weight_goal'],
      );
      expect(g.of(TrMetric.water), 9, reason: '改喝水目标后目标线跟着走');
      expect(g.of(TrMetric.sleep), 7);
      expect(g.exDailyMinGoal, 5.7, reason: '4 次/周 → 40/7 ≈ 5.7');
      expect(g.of(TrMetric.body), 58.5, reason: '体重线来自 health_goal 表不是 prefs');
    });
  });

  group('热力分档（刀1 靶）：.72/.45/.18 三档＋ -1 空格', () {
    const s = (mn: 0.0, mx: 100.0);
    test('三档边界：73→3、72→3、61→2、45→2、18→1、17→0', () {
      expect(trHeatLevel(73, mn: s.mn, mx: s.mx), 3);
      expect(trHeatLevel(72, mn: s.mn, mx: s.mx), 3);
      expect(trHeatLevel(61, mn: s.mn, mx: s.mx), 2, reason: 'r=0.61 < .72 → 2 档（改成单一 .5 档这例红）');
      expect(trHeatLevel(60, mn: s.mn, mx: s.mx), 2);
      expect(trHeatLevel(45, mn: s.mn, mx: s.mx), 2);
      expect(trHeatLevel(18, mn: s.mn, mx: s.mx), 1);
      expect(trHeatLevel(17, mn: s.mn, mx: s.mx), 0);
      expect(trHeatLevel(0, mn: s.mn, mx: s.mx), 0);
    });

    test('null 出 -1 空格，不吃 0 档色；退化量程不除零', () {
      expect(trHeatLevel(null, mn: 0, mx: 100), -1);
      expect(trHeatLevel(5, mn: 5, mx: 5), 0,
          reason: '分母 clamp 到 0.0001 → r=(5-5)/0.0001=0，不 NaN；退化量程落最低档');
    });

    test('trScale：目标线与 1 参与上界，空集不炸', () {
      final cells = [TrCell(key: dk(0), label: 'x', v: 8), TrCell(key: dk(1), label: 'y', v: null)];
      expect(trScale(cells, 12), (mn: 0.0, mx: 12.0));
      expect(trScale(cells, null), (mn: 0.0, mx: 8.0));
      expect(trScale(const [], null), (mn: 0.0, mx: 1.0));
    });

    test('色阶文案：日视图与年视图（按月 · 前缀）', () {
      expect(trLegendTx(mn: 0, mx: 12, unit: '杯', year: false), '色阶 0 ~ 12.0杯');
      expect(trLegendTx(mn: 0, mx: 7.5, unit: 'h', year: true), '按月 · 色阶 0 ~ 7.5h');
      expect(trHeatTx(TrMetric.water, 7), '达标热力 · 喝水 · 近 7 天');
      expect(trHeatTx(TrMetric.sleep, 12), '达标热力 · 睡眠 · 近 12 个月');
    });
  });

  group('四数据位（trSlots 三形态）', () {
    test('体重＝期末/区间均值/区间变化/距目标，缺目标出「未设目标」', () {
      final slots = trSlots(m: TrMetric.body, vals: [61.0, 60.0, 62.5], g: goals);
      expect([for (final s in slots) s.label], ['期末 kg', '区间均值', '区间变化', '距目标']);
      expect(slots[0].value, '62.5');
      expect(slots[1].value, '61.2');
      expect(slots[2].value, '+1.5', reason: '期末 62.5 − 期初 61.0');
      expect(slots[3].value, '+2.5', reason: '62.5 − 目标 60');
      const noGoal = TrGoals(waterCups: 10, sleepHours: 8, weekExGoal: 3);
      expect(trSlots(m: TrMetric.body, vals: [61.0], g: noGoal)[3].value, '未设目标');
    });

    test('百分比类＝平均达标/达标天/峰值/待改善天（<40 判待改善）', () {
      final slots = trSlots(m: TrMetric.all, vals: [90, 51, 30, null, 100], g: goals);
      expect([for (final s in slots) s.label], ['平均达标', '达标天', '峰值', '待改善天']);
      expect(slots[0].value, '68%', reason: '(90+51+30+100)/4，null 不进分母');
      expect(slots[1].value, '2', reason: '>=80 的只有 90 与 100');
      expect(slots[2].value, '100%');
      expect(slots[3].value, '1', reason: '30 < 40');
    });

    test('量类＝合计/日均/达标天/单日峰值，日均分母只吃有记录日', () {
      final slots = trSlots(m: TrMetric.water, vals: [8, null, 12], g: goals);
      expect([for (final s in slots) s.label], ['合计 杯', '日均 杯', '达标天', '单日峰值']);
      expect(slots[0].value, '20');
      expect(slots[1].value, '10', reason: '20/2 个有记录日，除以 3（含空日）＝失真，这例钉偏离口径');
      expect(slots[2].value, '1', reason: '>=10 只有 12');
      expect(slots[3].value, '12');
    });

    test('空段四枚全「—」且 label 形态正确', () {
      final body = trSlots(m: TrMetric.body, vals: [null, null], g: goals);
      expect(body.map((s) => s.value), everyElement('—'));
      expect([for (final s in body) s.label], ['期末 kg', '区间均值', '区间变化', '距目标']);
    });
  });

  group('取样与分段：三档跨度、旧→新、环比两段', () {
    test('跨度文案与取数天数：周 14／月 60／年 731（两倍含上期）', () {
      expect(trRanges, [7, 30, 12]);
      expect(trRangeTx(7), '近 7 天');
      expect(trRangeTx(12), '近 12 个月');
      expect([trRangeShortTx(7), trRangeShortTx(30), trRangeShortTx(12)], ['周', '月', '年']);
      expect([for (final r in trRanges) trFetchDays(r)], [14, 60, 731]);
    });

    test('trDaysBack：旧→新含参考日；跨年月的键正确', () {
      final days = trDaysBack(ref, 7);
      expect(days.length, 7);
      expect(days.last, '2026-10-08');
      expect(days.first, '2026-10-02');
      expect(days, List<String>.from(days)..sort(), reason: '面板：取样序旧→新');
      expect(trDaysBack(DateTime(2026, 1, 3), 4), ['2025-12-31', '2026-01-01', '2026-01-02', '2026-01-03']);
      final months = trMonthsBack(DateTime(2026, 3), 4);
      expect(months, ['2025-12', '2026-01', '2026-02', '2026-03'], reason: '近 12 个月口径＝滚动窗口不是今年 1~12 月');
      expect(trMonthsBack(ref, 12).last, '2026-10');
    });

    test('trSplitDays：满段对半、不满段 prev 为空（新用户不拿短段外推）', () {
      final all = [for (final k in trDaysBack(ref, 14)) day(date: k)];
      final sp = trSplitDays(all, 7);
      expect(sp.cur.length, 7);
      expect(sp.prev.length, 7);
      expect(sp.prev.last.date, '2026-10-01');
      expect(sp.cur.last.date, '2026-10-08');
      final short = trSplitDays(all.sublist(9), 7);
      expect(short.cur.length, 5);
      expect(short.prev, isEmpty);
    });

    test('trSplitMonths：24 个月后 12 为当前期', () {
      final ms = trMonthsBack(ref, 24);
      final sp = trSplitMonths(ms);
      expect(sp.cur.length, 12);
      expect(sp.prev.length, 12);
      expect(sp.cur.last, '2026-10');
      expect(sp.prev.last, '2025-10');
      expect(trSplitMonths(ms.sublist(12)).prev, isEmpty);
    });

    test('日格缺记录出 null；月格按月均只吃有记录日，空格给实话', () {
      final days = [
        day(date: dk(9), cups: 4),
        day(date: dk(8), cups: 8),
        day(date: dk(7)), // 整日无记录
      ];
      final cells = trDayCells(days: days, m: TrMetric.water, g: goals);
      expect([for (final c in cells) c.v], [4, 8, null]);
      expect(cells[2].hasData, isFalse);

      final mk = dayKey(DateTime(ref.year, ref.month - 1, 15)).substring(0, 7); // 上月
      final mDays = [
        day(date: '$mk-01', cups: 4),
        day(date: '$mk-02', cups: 8),
        day(date: '$mk-03'),
      ];
      final mc = trMonthCells(days: mDays, months: [mk], m: TrMetric.water, g: goals);
      expect(mc.single.label, '${int.parse(mk.substring(5))}月');
      expect(mc.single.v, 6.0, reason: '(4+8)/2 有记录日；除以整月天数＝原型失真，登记偏离');
      final tx = trMonthDetailTx(mk, 6.0, TrMetric.water);
      expect(tx, contains('$mk 月均 6 杯'), reason: '杯 decimals=0');
      expect(tx, contains('日明细请切「月」'));
      expect(trMonthDetailTx(mk, null, TrMetric.water), '$mk 无记录 · 日明细请切「月」');
      expect(trMonthDetailTx(mk, 80.0, TrMetric.all), contains('约 24 天/月达标'));
    });
  });

  group('环比脚注（trCompareTx）', () {
    test('双段有记录：百分比差与日均同串', () {
      final tx = trCompareTx(cur: [8, 12], prev: [5, 5], m: TrMetric.water);
      expect(tx, '环比上期 +100.0% · 日均 10杯', reason: '(10−5)/5＝+100%');
    });

    test('上期无记录出实话，不除零不出 NaN', () {
      final tx = trCompareTx(cur: [8, 12], prev: [null, null], m: TrMetric.water);
      expect(tx, contains('环比上期 —（上期无记录）'));
      expect(tx, contains('日均 10杯'));
      expect(trCompareTx(cur: [0, 0], prev: [0], m: TrMetric.water), contains('上期无记录'),
          reason: '上期均值 0 也不能除——走同一实话分支');
    });
  });

  group('周报（刀2 靶）：六枚 tile、同比现算、占比分母恒 7', () {
    test('trWeekNo＝ISO 周号（周四定年）：跨年边界三条钉死', () {
      expect(trWeekNo(DateTime(2026, 1, 1)), 1);
      expect(trWeekNo(DateTime(2025, 12, 29)), 1, reason: '2025-12-29 属 2026 年第 1 周');
      expect(trWeekNo(DateTime(2026, 12, 31)), 53);
      expect(trWeekTx(ref), '第 41 周');
    });

    test('六枚 tile 口径与顺序：日均喝水/日均睡眠/运动次数/全达标天/期末体重/用药依从', () {
      final tw = week((d) => fullDay(d, kg: 61.0 + (int.parse(d.substring(8)) - 6) / 10));
      final lw = week((d) => halfDay(d));
      final r = trWeekReport(thisWeek: tw, lastWeek: lw, goals: goals, now: ref);
      expect([for (final t in r.tiles) t.name],
          ['日均喝水', '日均睡眠', '运动次数', '全达标天', '期末体重', '用药依从']);
      expect(r.tiles[0].value, '12.0 杯');
      expect(r.tiles[1].value, '8.0 h');
      expect(r.tiles[2].value, '7 次');
      expect(r.tiles[3].value, '100%', reason: '7/7 全达标；分母改成有记录天数＝刀2');
      expect(r.tiles[4].value, '61.2 kg', reason: '期末＝10-08 那天（61+(8-6)/10）');
      expect(r.tiles[5].value, '100%');
      expect(r.rangeTx, '10-02 ~ 10-08');
      expect(r.weekTx, '第 41 周');
    });

    test('占比分母恒 7：三天缺席不把「全达标天」抬成 100%', () {
      final sparse = week((d) => int.parse(d.substring(8)) % 2 == 1 ? fullDay(d) : day(date: d));
      // 10-03/05/07 三个奇数日里的 03、05、07 达标；02/04/06/08 空 → 3/7
      final r = trWeekReport(thisWeek: sparse, lastWeek: const <TrDay>[], goals: goals, now: ref);
      expect(r.tiles[3].value, '43%', reason: 'round(3/7*100)=43；分母若吃有记录日(3 天)会出 100%');
      expect(r.tiles[1].value, '8.0 h', reason: '日均睡眠分母只吃 3 个有记录日，不是 7');
      expect(r.tiles[0].value, '12.0 杯');
    });

    test('同比五行现算：上周无记录全出「—」且不 NaN；有上周时与对差一致', () {
      final tw = week((d) => fullDay(d, kg: 62));
      final noLast = trWeekReport(thisWeek: tw, lastWeek: const <TrDay>[], goals: goals, now: ref);
      expect(noLast.diffs.length, 5);
      expect([for (final x in noLast.diffs) x.name], ['日均睡眠', '日均喝水', '运动次数', '平均配速', '体重']);
      expect(noLast.diffs[2].delta, '+7 次', reason: '次数是计数不是均值：上周空段按 0 天对差，仍属现算');
      expect(noLast.verdictTx, contains('睡眠上周无记录'));

      final lw = week((d) => halfDay(d));
      final r = trWeekReport(thisWeek: tw, lastWeek: lw, goals: goals, now: ref);
      expect(r.diffs[0].delta, '+1.0 h', reason: '8.0 − 7.0（半达标日 420 分＝7.0h）');
      expect(r.diffs[1].delta, '+8.0 杯'); // 12 − 4
      expect(r.diffs[2].delta, '+7 次'); // 7 − 0（半周无 10 分钟以上运动）
      expect(r.diffs[4].delta, '—', reason: 'halfDay 无 kg → 上周期末取不到，出实话不外推');
    });

    test('配速差方向：更快＝好；无配速出「—」「持平」', () {
      final tw = week((d) => day(date: d, exMin: 30, paces: [300]));
      final slow = week((d) => day(date: d, exMin: 30, paces: [360]));
      final faster = trWeekReport(thisWeek: slow, lastWeek: tw, goals: goals, now: ref);
      expect(faster.diffs[3].delta, '+60″ /km');
      expect(faster.diffs[3].tag, '注意', reason: '配速变大＝更慢');
      final better = trWeekReport(thisWeek: tw, lastWeek: slow, goals: goals, now: ref);
      expect(better.diffs[3].delta, '-60″ /km');
      expect(better.diffs[3].tag, '好');
      final noPace = trWeekReport(thisWeek: week(fullDay), lastWeek: const <TrDay>[], goals: goals, now: ref);
      expect(noPace.diffs[3].delta, '—');
      expect(noPace.diffs[3].tag, '持平');
    });

    test('七日条＝七天各一条、缺记录日落 0；结论句含占比与不足杯数天数', () {
      final mix = week((d) {
        final dayNo = int.parse(d.substring(8));
        return dayNo.isOdd ? fullDay(d) : day(date: d, cups: 2, sleepMin: 300);
      });
      final r = trWeekReport(thisWeek: mix, lastWeek: const <TrDay>[], goals: goals, now: ref);
      expect(r.bars.length, 7);
      expect(r.bars.first.label, '10-02 ${dayWd('2026-10-02')}');
      expect(r.bars.first.score, 30, reason: '10-02 偶数日＝2 杯+300 分：w .2→8 + s 62.5%→21.875 → 29.875 → 30');
      expect(r.bars.last.score, 30, reason: '10-08 同为偶数日');
      expect(r.bars[1].score, 100, reason: '10-03 奇数日＝fullDay');
      expect(r.verdictTx, startsWith('本周 '));
      expect(r.verdictTx, contains('43% 的天数完成全部目标'), reason: '3/7 全达标（奇数日 3/5/7）');
      expect(r.verdictTx, contains('喝水有 4 天不足 10 杯'), reason: '偶数 4 天只有 2 杯');
    });

    test('全空周：tile 出 0/—、不 NaN、依从无计划出「—」', () {
      final r = trWeekReport(
          thisWeek: week((d) => day(date: d)),
          lastWeek: week((d) => day(date: d)),
          goals: goals,
          now: ref);
      expect(r.tiles.map((t) => t.value), ['0.0 杯', '0.0 h', '0 次', '0%', '—', '—']);
      expect(r.diffs.map((d) => d.delta), ['—', '—', '±0', '—', '—'],
          reason: '次数两周都是 0 → ±0 持平；其余四路无源出「—」');
      expect(r.bars.map((b) => b.score), everyElement(0.0));
      expect(r.copyText, isNot(contains('NaN')));
    });
  });

  group('复制文本（长图按钮本期不铺）', () {
    test('行式齐：标题/结论/六枚/同比段/七日条/尾注 = 23 行', () {
      final r = trWeekReport(thisWeek: week(fullDay), lastWeek: week(halfDay), goals: goals, now: ref);
      final lines = r.copyText.split('\n');
      expect(lines.first, 'LifeHarness 健康周报 · 第 41 周（10-02 ~ 10-08）');
      expect(lines[1], startsWith('结论：'));
      expect(lines.sublist(2, 8), [for (final t in r.tiles) '${t.name}：${t.value}']);
      expect(lines[8], '同比上周：');
      expect(lines.sublist(9, 14).length, 5);
      expect(lines[14], '每日达标：');
      expect(lines.sublist(15, 22).length, 7);
      expect(lines.last, '全部本机计算 · 无网络上传');
      expect(lines.length, 23);
      expect(r.copyText, isNot(contains('长图')));
    });
  });
}
