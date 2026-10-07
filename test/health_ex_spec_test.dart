import 'package:flutter_test/flutter_test.dart';

import 'package:lifeharness/features/health/domain/health_calc.dart';
import 'package:lifeharness/features/health/domain/health_ex.dart';
import 'package:lifeharness/features/health/domain/health_models.dart';

/// 健康批4 · 运动域层规格（原型 `index-health.html` 的 `HT.exTypes`/`HT.distTypes`/
/// `hExMode`/`hExCalc`/`hRenderExLog` 三处 JS 的唯一实装对照）。
///
/// 六组判定＝执行面板第 3 项的清单：三模互算 27 组输入形态表（刀1 靶）／≥10 分钟周次数口径／
/// 配速三写法／无距离类型置灰／派生项跨模式不残留／计时回填与同日多条并存。
///
/// 独立文件（全 app/大页 pump 拆文件口径）；日期一律相对固定 `today` 构造。
void main() {
  const today = '2026-09-19';

  ExerciseRecord rec({
    int? id,
    String date = today,
    String type = '跑步',
    double? km,
    int min = 30,
    int? paceSec,
    int? kcal,
    String? note,
    String source = '手动',
    int? startedAt,
  }) =>
      ExerciseRecord(
          id: id,
          profileId: 1,
          date: date,
          type: type,
          distanceKm: km,
          durationMin: min,
          paceSec: paceSec,
          kcal: kcal,
          note: note,
          source: source,
          startedAt: startedAt);

  // ==================== 三模互算 27 组输入形态表（刀1 靶） ====================

  group('三模互算＝档位映射表', () {
    /// 每行：(档位, 输入 km/min/pace) → 期望输出 km/min/pace。
    /// 期望值全部由「知二算一」现推：30 分 @6′00″/km ＝ 5 km；5 km @6′00″ ＝ 30 分。
    const cases = <(ExMode, double?, int?, int?, double?, int?, int?)>[
      // pace 档（「按距离」＝填距离＋时长 → 算配速）
      (ExMode.pace, 5, 30, null, 5, 30, 360),
      (ExMode.pace, 10, 60, null, 10, 60, 360),
      (ExMode.pace, 2.5, 15, null, 2.5, 15, 360),
      (ExMode.pace, 3, 20, null, 3, 20, 400),
      (ExMode.pace, 7, 40, null, 7, 40, 343),
      (ExMode.pace, 0.5, 4, null, 0.5, 4, 480),
      (ExMode.pace, 21.1, 120, null, 21.1, 120, 341),
      (ExMode.pace, 5, 25, null, 5, 25, 300),
      (ExMode.pace, null, 30, null, null, 30, null),
      (ExMode.pace, 5, null, null, 5, null, null),
      (ExMode.pace, 0, 30, null, 0, 30, null),
      (ExMode.pace, null, null, null, null, null, null),
      // distance 档（「按时长」＝填时长＋配速 → 算距离）
      (ExMode.distance, null, 30, 360, 5, 30, 360),
      (ExMode.distance, null, 45, 400, 6.75, 45, 400),
      (ExMode.distance, null, 10, 300, 2, 10, 300),
      (ExMode.distance, null, 60, 330, 10.91, 60, 330),
      (ExMode.distance, null, 20, 0, null, 20, 0),
      (ExMode.distance, null, null, 360, null, null, 360),
      (ExMode.distance, null, 30, null, null, 30, null),
      // duration 档（「按配速」＝填距离＋配速 → 算时长）
      (ExMode.duration, 5, null, 360, 5, 30, 360),
      (ExMode.duration, 10, null, 400, 10, 67, 400),
      (ExMode.duration, 0.5, null, 480, 0.5, 4, 480),
      (ExMode.duration, 21.1, null, 341, 21.1, 120, 341),
      (ExMode.duration, 3, null, 0, 3, null, 0),
      (ExMode.duration, null, null, 300, null, null, 300),
      (ExMode.duration, 5, null, null, 5, null, null),
      (ExMode.duration, 0, null, 300, 0, 0, 300),
    ];

    for (final c in cases) {
      final (mode, kmIn, minIn, paceIn, kmOut, minOut, paceOut) = c;
      test('${mode.name} 档 · km=$kmIn min=$minIn pace=$paceIn', () {
        final got = exTriad(type: '跑步', mode: mode, km: kmIn, min: minIn, paceSec: paceIn);
        if (kmOut == null) {
          expect(got.km, isNull, reason: '${mode.name} 档距离算不出就留空，不写 0');
        } else {
          expect(got.km, closeTo(kmOut, 0.005));
        }
        expect(got.min, minOut, reason: '${mode.name} 档时长');
        expect(got.paceSec, paceOut, reason: '${mode.name} 档配速（秒/公里）');
      });
    }

    test('共 27 组输入形态（面板第 3 项的覆盖面）', () => expect(cases.length, 27));

    test('档位标签与只读列一一对应（seg 文案＝用户填的那两量）', () {
      expect(ExMode.pace.label, '按距离');
      expect(ExMode.distance.label, '按时长');
      expect(ExMode.duration.label, '按配速');
      expect(ExMode.pace.readOnlyField, 'pace');
      expect(ExMode.distance.readOnlyField, 'km');
      expect(ExMode.duration.readOnlyField, 'min');
      expect(exModeOf('distance'), ExMode.distance);
      expect(exModeOf(null), ExMode.pace, reason: '脏值/缺值回落到默认档，不抛');
    });

    test('派生项跨模式不残留（同一组输入换档 → 被算那列跟着变）', () {
      final a = exTriad(type: '跑步', mode: ExMode.pace, km: 5, min: 30);
      final b = exTriad(type: '跑步', mode: ExMode.distance, min: 30, paceSec: 360);
      expect(a.km, 5);
      expect(b.km, 5, reason: '按时长档：距离由 时长÷配速 现算，不是沿用上一次的输入');
      final c = exTriad(type: '跑步', mode: ExMode.duration, km: 5, paceSec: 360);
      expect(c.min, 30, reason: '按配速档：时长由 距离×配速 现算');
    });
  });

  // ==================== 无距离四类型（§五.4） ====================

  group('无距离类型', () {
    test('四类不计距离、四类计距离（判据单源）', () {
      expect(exTypes.length, 8);
      expect(exTypes.where(hasDistance).toList(), ['跑步', '骑行', '游泳', '步行']);
      for (final t in ['力量', '球类', '瑜伽', '其他']) {
        expect(hasDistance(t), isFalse, reason: '$t 只填时长');
      }
    });

    test('力量就算把距离递进来也折成 null（保存与回显同一条判据）', () {
      final got = exTriad(type: '力量', mode: ExMode.pace, km: 5, min: 40);
      expect(got.km, isNull);
      expect(got.paceSec, isNull);
      expect(got.min, 40);
    });

    test('回显行：无距离类只说「只需填时长」', () {
      expect(exCalcTx(type: '力量', mode: ExMode.pace, km: 5, min: 40),
          '该类型不计距离 · 只需填时长');
    });

    test('距离类三值闭合才出配速与估算消耗；缺一就提示', () {
      expect(exCalcTx(type: '跑步', mode: ExMode.pace, km: 5, min: 30),
          '三值闭合 · 均配速 6′00″ /km · 估算消耗 315 kcal');
      expect(exCalcTx(type: '跑步', mode: ExMode.pace, km: null, min: 30), '还需填一项');
      expect(exCalcTx(type: '跑步', mode: ExMode.pace, km: 5, min: 30, unit: 'mile'),
          '三值闭合 · 均配速 9′39″ /mile · 估算消耗 315 kcal');
    });

    test('估算消耗走 MET 表（§五.6）', () {
      expect(estKcal('跑步', 30), 315);
      expect(estKcal('瑜伽', 30), 102);
      expect(estKcal('表外项目', 30), 150, reason: '表外按「其他」5.0 兜底');
    });
  });

  // ==================== 配速三写法与单位 ====================

  group('配速读写', () {
    test('三种写法解析成同一秒数（§五.5）', () {
      expect(parsePaceSec("6'00\""), 360);
      expect(parsePaceSec('6:00'), 360);
      expect(parsePaceSec('600'), 360, reason: '单组数字＝末两位是秒，不是 600 分');
      expect(parsePaceSec('530'), 330);
      expect(parsePaceSec(''), isNull);
      expect(parsePaceSec('abc'), isNull);
    });

    test('展示跟着距离单位走（§五.10）：mile 档配速换算成每英里', () {
      expect(paceLabelFor(360, 'km'), '6′00″');
      expect(paceLabelFor(360, 'mile'), '9′39″', reason: '6 分/公里 ≈ 9.65 分/英里');
      expect(paceLabelFor(null, 'km'), '—');
      expect(paceLabelFor(0, 'km'), '—');
      expect(exDistUnitTx('km'), '/km');
      expect(exDistUnitTx('mile'), '/mile');
    });

    test('距离读数 mile 档换算，存储侧不动', () {
      expect(exKmTx(5, 'km'), '5.0');
      expect(exKmTx(5, 'mile'), '3.1');
    });
  });

  // ==================== 窗口 / 四数据位 / 周次数 ====================

  group('窗口与统计', () {
    final all = [
      rec(date: '2026-08-25', type: '跑步', km: 10, min: 55, kcal: 578),
      rec(date: '2026-09-13', type: '跑步', km: 5, min: 30, kcal: 300),
      rec(date: '2026-09-15', type: '骑行', km: 20, min: 60, kcal: 450),
      rec(date: '2026-09-18', type: '力量', min: 8, kcal: 40),
      rec(date: today, type: '步行', km: 3, min: 40, kcal: 168),
    ];

    test('本周＝含今天往回 7 天、本月＝30 天（两端都闭）', () {
      expect(exWindow(all, days: 7, today: today).map((e) => e.date).toList(),
          ['2026-09-13', '2026-09-15', '2026-09-18', today]);
      expect(exWindow(all, days: 30, today: today).length, 5);
      expect(exWindow(all, days: 7, today: '2026-09-30'), isEmpty,
          reason: '窗口右端封在 today，未来锚点不捞旧记录');
    });

    test('四数据位＝窗口条数/总时长/总距离/总消耗（次数≠有效次数）', () {
      final st = exStats(exWindow(all, days: 30, today: today));
      expect(st.count, 5);
      expect(st.totalMin, 193);
      expect(st.totalKm, closeTo(38, 0.001));
      expect(st.totalKcal, 1536);
    });

    test('周次数口径＝≥10 分钟才算一次（§五.9，与四数据位不同源）', () {
      final week = exWindow(all, days: 7, today: today);
      expect(week.length, 4, reason: '窗口内四条（含一条 8 分钟的力量）');
      expect(exWeekSessions(week), 3, reason: '8 分钟那次不计入周次数');
    });

    test('类型过滤：「全部」不筛，其余按类型；流水最新在上', () {
      final month = exWindow(all, days: 30, today: today);
      expect(exFiltered(month, exAllFilter).length, 5);
      expect(exFiltered(month, '跑步').map((e) => e.date).toList(), ['2026-08-25', '2026-09-13']);
      expect(exFiltered(month, '游泳'), isEmpty);
      expect(exFilterOptions().first, exAllFilter);
      expect(exFilterOptions().length, 9, reason: '「全部」＋八类');
      expect(exListDesc(month).first.date, today);
    });
  });

  // ==================== 配速趋势 ====================

  group('配速趋势', () {
    final mixed = [
      for (var i = 0; i < 15; i++)
        rec(
            date: '2026-09-${(i + 1).toString().padLeft(2, '0')}',
            type: i % 5 == 0 ? '力量' : '跑步',
            km: 5.0 + i,
            min: 30 + i),
    ];

    test('只取距离类，力量不进趋势', () {
      final t = exPaceTrend(mixed);
      expect(t.length, 12, reason: '15 条里 3 条力量 → 距离类 12 条');
      expect(t.every((e) => hasDistance(e.type)), isTrue);
      expect(t.first.date, '2026-09-02');
      expect(t.last.date, '2026-09-15');
    });

    test('超过 12 条只留最近 12 条（升序出）', () {
      final long = [
        for (var i = 1; i <= 16; i++)
          rec(date: '2026-09-${i.toString().padLeft(2, '0')}', km: 5, min: 30)
      ];
      final t = exPaceTrend(long);
      expect(t.length, 12);
      expect(t.first.date, '2026-09-05');
      expect(t.last.date, '2026-09-16');
    });

    test('没存配速就按 时长÷距离 现算（与落库回落同式）', () {
      final t = exPaceTrend(mixed);
      expect(exTrendPaceSec(t.first), 310, reason: '09-02＝31 分 / 6 公里');
      expect(exTrendPaceSec(rec(km: 5, min: 30, paceSec: 999)), 999,
          reason: '存了的读数优先，不重算覆盖');
    });

    test('不足 2 条＝不画线（一条点不叫趋势）', () {
      expect(exTrendEnough(exPaceTrend([rec(km: 5, min: 30)])), isFalse);
      expect(exTrendEnough(exPaceTrend(mixed)), isTrue);
      expect(exTrendEnough(exPaceTrend([rec(type: '力量', min: 30)])), isFalse);
    });

    test('最快/最慢：秒每公里越小越快', () {
      final trend = [rec(km: 5, min: 30), rec(date: '2026-09-18', km: 5, min: 20)];
      final s = exPaceSpread(trend);
      expect(s.fast, 240);
      expect(s.slow, 360);
      expect(exPaceSpread(const []).fast, isNull);
      expect(exPaceSpread(const []).slow, isNull);
    });
  });

  // ==================== 计时回填 / 流水文案 / 草稿 ====================

  group('计时与流水', () {
    test('计时秒折分钟：不足 1 分钟记 1 分钟（否则进不了周次数）', () {
      expect(exMinutesOf(0), 1);
      expect(exMinutesOf(20), 1);
      expect(exMinutesOf(59), 1);
      expect(exMinutesOf(60), 1);
      expect(exMinutesOf(90), 2);
      expect(exMinutesOf(3600), 60);
    });

    test('流水主行与副注（日期·星期·kcal·来源·备注）', () {
      final r = rec(date: today, type: '跑步', km: 5, min: 30, kcal: 315, source: '计时');
      expect(exRowMain(r, 'km'), '跑步 · 5.0 km · 30min');
      expect(exRowMain(r, 'mile'), '跑步 · 3.1 mile · 30min');
      expect(exRowMain(rec(date: today, type: '力量', min: 45), 'km'), '力量 · 45min');
      expect(exRowSub(r), contains('来源 计时'));
      expect(exRowSub(r), contains('315 kcal'));
      expect(exRowSub(r), isNot(contains('· ·')), reason: '空备注不留孤立分隔符');
      expect(exRowSub(rec(date: today, kcal: 0, note: '   ')), isNot(contains('kcal ·')));
    });

    test('草稿：无距离类把距离/配速折 null；计时来源与 startedAt 原样带上', () {
      final d = exDraft(
          profileId: 1,
          date: today,
          type: '瑜伽',
          mode: ExMode.pace,
          km: 3,
          min: 50,
          source: '计时',
          startedAt: 1234);
      expect(d.distanceKm, isNull);
      expect(d.paceSec, isNull);
      expect(d.durationMin, 50);
      expect(d.source, '计时');
      expect(d.startedAt, 1234);
    });

    test('同日多条并存（运动不按日期唯一，改哪条按 id 改）', () {
      final a = rec(id: 11, date: today, min: 30);
      final b = rec(id: 12, date: today, min: 45, type: '骑行');
      expect(a.date, b.date);
      expect(exListDesc([a, b]).map((e) => e.id).toList(), [12, 11]);
    });

    test('来源三档，「设备导入」灰位不可选（§九.6 只留字段）', () {
      expect(exSources, ['手动', '计时', '设备导入']);
      expect(exSourceEnabled('手动'), isTrue);
      expect(exSourceEnabled('计时'), isTrue);
      expect(exSourceEnabled('设备导入'), isFalse);
    });
  });
}
