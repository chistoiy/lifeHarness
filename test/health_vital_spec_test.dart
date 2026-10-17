import 'package:flutter_test/flutter_test.dart';

import 'package:lifeharness/features/health/domain/health_models.dart';
import 'package:lifeharness/features/health/domain/health_vital.dart';

/// 健康批2.5 · 体征五类规格与派生（纯函数，不碰库）。
///
/// 四条判定（工单 §0 与计划 §11.3.1）：
/// · **参考区间只有一个出处**——规格表只带单位/时段/档位，区间读 `vitalRef`；血氧的 999 是
///   「无上限」哨兵，文案必须走「参考 ≥95」而不是把 999 印给用户；
/// · **主值＝该类第一字段**（血压取收缩压），判级和统计都只看它；
/// · **没有基线就不编「较基线」**（回落参考区间）；
/// · 无记录（主值 null）＝「—」且不计入异常，别把空读成 0。
void main() {
  HealthVital bp(int sys, int dia, {int? hr, String? slot}) => HealthVital(
        profileId: 1,
        date: '2026-10-08',
        time: '07:10',
        kind: 'bp',
        sys: sys,
        dia: dia,
        hr: hr,
        slot: slot ?? '晨起空腹',
      );

  group('规格表（原型 VT 的转写）', () {
    test('五类顺序·名称·单位与原型一致', () {
      expect(vitalOrder, ['bp', 'hr', 'spo2', 'glu', 'temp']);
      expect(vitalOrder.map((k) => vitalSpecs[k]!.name), ['血压', '心率', '血氧', '血糖', '体温']);
      expect(vitalOrder.map((k) => vitalSpecs[k]!.unit), ['mmHg', '次/分', '%', 'mmol/L', '℃']);
    });

    test('血压三列（收缩/舒张/伴生心率），其余单列；步长只由该类主值决定小数位', () {
      final fields = vitalSpecs['bp']!.fields;
      expect(fields.map((f) => f.col), ['sys', 'dia', 'hr']);
      expect(fields.map((f) => f.label), ['收缩压', '舒张压', '心率']);
      expect(vitalSpecs['bp']!.decimals, 0);
      expect(vitalSpecs['glu']!.decimals, 1);
      expect(vitalSpecs['temp']!.decimals, 1);
      expect(vitalSpecs['hr']!.fields.single.col, 'val');
      expect(vitalSpecs['spo2']!.fields.single.col, 'val');
    });

    test('测量时段照抄原型；血糖那行换题注', () {
      expect(vitalSpecs['bp']!.slots, ['晨起空腹', '上午', '午后', '晚间', '睡前', '运动后']);
      expect(vitalSpecs['hr']!.slots, ['晨起静息', '日间', '晚间', '运动后']);
      expect(vitalSpecs['spo2']!.slots, ['晨起', '日间', '晚间']);
      expect(vitalSpecs['glu']!.slots, ['空腹', '餐后2h', '随机', '夜间']);
      expect(vitalSpecs['temp']!.slots, ['晨起', '日间', '晚间', '复测']);
      expect(vitalSpecs['glu']!.slotLabel, '血糖时段 · 饮食情况见备注');
      expect(vitalSpecs['bp']!.slotLabel, '测量时段');
    });

    test('档位含端点且无浮点毛刺（0.1 步长靠计数取档，不是累加）', () {
      final sys = vitalSpecs['bp']!.fields.first.values;
      expect(sys.length, 131);
      expect(sys.first, 70.0);
      expect(sys.last, 200.0);
      final glu = vitalSpecs['glu']!.fields.first.values;
      expect(glu.length, 193);
      expect(glu.first, 2.8);
      expect(glu.last, 22.0, reason: '2.8 + 192×0.1 的累加误差会被 toStringAsFixed(2) 抹平');
      expect(vitalSpecs['temp']!.fields.first.values.length, 71);
    });
  });

  group('参考区间只读 vitalRef（展示文案另有一层「无上限」折算）', () {
    test('血压/心率/血糖/体温出「参考 a ~ b 单位」', () {
      expect(vitalSpecs['bp']!.refLabel, '参考 90 ~ 139 mmHg');
      expect(vitalSpecs['hr']!.refLabel, '参考 55 ~ 95 次/分');
      expect(vitalSpecs['glu']!.refLabel, '参考 3.9 ~ 6.1 mmol/L');
      expect(vitalSpecs['temp']!.refLabel, '参考 36 ~ 37.2 ℃');
    });

    test('血氧上限 999＝无上限哨兵，文案只写下限', () {
      expect(vitalSpecs['spo2']!.refLabel, '参考 ≥95 %');
    });
  });

  group('读数派生（主值·文本·判级）', () {
    test('主值＝第一字段：血压取收缩压，心率指标取 val', () {
      expect(bp(120, 80, hr: 62).primary, 120);
      expect(const HealthVital(profileId: 1, date: '2026-10-08', time: '07:15', kind: 'hr', val: 62).primary, 62);
    });

    test('血压文本两值、其余按步长定小数；缺失出「—」不补 0', () {
      expect(bp(120, 80).valueText, '120/80');
      expect(const HealthVital(profileId: 1, date: '2026-10-08', time: '06:50', kind: 'glu', val: 5.6).valueText, '5.6');
      expect(const HealthVital(profileId: 1, date: '2026-10-08', time: '06:50', kind: 'glu', val: 6).valueText, '6.0');
      expect(const HealthVital(profileId: 1, date: '2026-10-08', time: '07:00', kind: 'bp').valueText, '—');
    });

    test('判级：区间内 normal、越界 low/high、无值 null（未记录不判成正常）', () {
      expect(bp(120, 80).flag, 'normal');
      expect(bp(89, 60).flag, 'low');
      expect(bp(140, 90).flag, 'high');
      expect(const HealthVital(profileId: 1, date: '2026-10-08', time: '21:10', kind: 'spo2', val: 94).flag, 'low');
      expect(const HealthVital(profileId: 1, date: '2026-10-08', time: '21:10', kind: 'spo2', val: 100).flag, 'normal',
          reason: '血氧 100 不撞 999 上限');
      expect(const HealthVital(profileId: 1, date: '2026-10-08', time: '21:10', kind: 'spo2').flag, isNull);
    });

    test('迷你柱：按展示上限定高并夹在 12%~100%，无值＝0', () {
      expect(bp(139, 80).barFrac(), closeTo(139 / (139 * 1.15), 0.001));
      expect(bp(200, 120).barFrac(), 1.0);
      expect(bp(70, 40).barFrac(), greaterThanOrEqualTo(0.12));
      expect(const HealthVital(profileId: 1, date: '2026-10-08', time: '07:00', kind: 'bp').barFrac(), 0);
    });
  });

  group('副注 vtDelta：有基线比值，没基线回落参考区间', () {
    const withBase = HealthProfile(id: 1, name: '本人', rel: '本人', restSys: 118, restDia: 72, restHr: 62);
    const noBase = HealthProfile(id: 1, name: '本人', rel: '本人');

    test('血压较基线两值·正负都带符号', () {
      expect(bp(120, 71).deltaText(withBase), '较基线 +2 / -1');
      expect(bp(110, 75).deltaText(withBase), '较基线 -8 / +3');
    });

    test('心率较静息（四舍五入到整）', () {
      const v = HealthVital(profileId: 1, date: '2026-10-08', time: '07:15', kind: 'hr', val: 65.4);
      expect(v.deltaText(withBase), '较静息 +3');
    });

    test('基线缺失（建表种子的三值全空）→ 回落参考区间，不编造 118/72', () {
      expect(bp(120, 80).deltaText(noBase), '参考 90 ~ 139 mmHg');
      expect(bp(120, 80).deltaText(null), '参考 90 ~ 139 mmHg');
      const v = HealthVital(profileId: 1, date: '2026-10-08', time: '07:15', kind: 'hr', val: 65);
      expect(v.deltaText(noBase), '参考 55 ~ 95 次/分');
    });

    test('血氧/血糖/体温永远比参考区间', () {
      const v = HealthVital(profileId: 1, date: '2026-10-08', time: '06:50', kind: 'glu', val: 5.6);
      expect(v.deltaText(const HealthProfile(id: 1, name: '本人', rel: '本人', restSys: 118, restDia: 72, restHr: 62)),
          '参考 3.9 ~ 6.1 mmol/L');
    });
  });

  group('统计', () {
    test('均值按该类小数位取整；空表 null（UI 显「—」）', () {
      expect(vitalMean([bp(120, 80), bp(121, 82)], 0), 121);
      expect(vitalMean([bp(120, 80), bp(120, 82)], 0), 120);
      expect(
          vitalMean(
              const [
                HealthVital(profileId: 1, date: '2026-10-08', time: '06:50', kind: 'glu', val: 5.6),
                HealthVital(profileId: 1, date: '2026-10-08', time: '09:30', kind: 'glu', val: 5.8),
              ],
              1),
          5.7);
      expect(vitalMean(const [], 0), isNull);
    });

    test('异常条数只数越界的，主值缺失不计', () {
      expect(
          vitalAbnormalCount([bp(140, 90), bp(120, 80), const HealthVital(profileId: 1, date: '2026-10-08', time: '07:00', kind: 'bp')]),
          1);
    });
  });

  test('行映射：toRow 的列名与建表一致，fromRow 回读不丢字段', () {
    const v = HealthVital(
        id: 7, profileId: 2, date: '2026-10-07', time: '20:40', kind: 'bp',
        sys: 138, dia: 86, hr: 74, slot: '晚间', note: '服药后 2 小时测');
    expect(v.toRow(), {
      'profile_id': 2, 'date': '2026-10-07', 'time': '20:40', 'kind': 'bp',
      'sys': 138, 'dia': 86, 'hr': 74, 'val': null, 'slot': '晚间',
      'diet_note': null, 'note': '服药后 2 小时测',
    });
    final back = HealthVital.fromRow({...v.toRow(), 'id': 7});
    expect(back.id, 7);
    expect(back.valueText, '138/86');
    expect(back.deltaText(null), '参考 90 ~ 139 mmHg');
  });
}
