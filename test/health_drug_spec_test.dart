import 'package:flutter_test/flutter_test.dart';

import 'package:lifeharness/features/health/domain/health_drug.dart';
import 'package:lifeharness/features/health/domain/health_models.dart';

/// 健康批5 · 用药规格单源（事实源＝`prototype/index-health.html` 的 `hMedPlan`/`hRenderMeds`/
/// `hRenderMedChips`/`hMedTap`/`hDrugSave`/`tgMedAll`——工作台卡、管理屏、录入弹层三处都读这一件，
/// 所以判据在这里钉死就够）。
///
/// 七组判定（工单执行面板第 3 项「常驻用例」）：
/// · **已服与有交代是两条判据**（刀1 靶）：计划位 `o`、依从率、热力达标都只认 `taken`，
///   `skipped` 只让漏服判跳过——把 `slotTaken` 换成 `slotSettled` 这一组立刻红；
/// · 归档档案**不进今日计划**，但流水照旧能读（删档案≠删历史，§五.8）；
/// · 热力三档带 `t>0` 守卫（刀2 靶）：没有计划的日子上空档而不是绿格；
/// · 漏服按「已过时刻 + 宽限」判，宽限档位来自设置 `missed_grace_min`；
/// · 档位表（96 格时刻／12 档剂量）就是可选集合，存量越界一律**就近归档**，跨零点那档不静默回落；
/// · chips 上限 5 枚，第 6 枚起收进「+n 全部」，n＝余下的枚数；
/// · 提示条原话逐字对原型，但**不吹没做的事**（排程在批8，文案只说开关状态）。
void main() {
  DrugPlan plan({
    int? id,
    String name = '钙片',
    String? spec,
    double dose = 1,
    List<String> times = const ['08:00', '20:00'],
    bool remind = false,
    String? endDate,
    bool archived = false,
  }) =>
      DrugPlan(
        id: id,
        profileId: 1,
        name: name,
        spec: spec,
        dose: dose,
        times: times,
        remind: remind,
        endDate: endDate,
        archived: archived,
      );

  DateTime at(int h, int m) => DateTime(2026, 9, 19, h, m);

  group('量程与档位：滚轮的档位集合就是可选集合', () {
    test('时刻表＝24 小时 × 4 刻共 96 档，08:00 在第 32 档（原型 hWheel 初始 index）', () {
      final opts = medTimeOptions();
      expect(opts.length, 96);
      expect(opts.first, '00:00');
      expect(opts.last, '23:45');
      expect(opts[32], medDefaultTime);
      expect(medSlotStepMin, 15);
    });

    test('存量时刻就近归档：08:07→08:00、08:08→08:15、23:59→00:00（跨零点不静默回落）', () {
      expect(medTimeIdx('08:00'), 32);
      expect(medTimeIdx('08:07'), 32, reason: '487 分＝32.47 档 → 四舍五入回 08:00');
      expect(medTimeIdx('08:08'), 33, reason: '488 分＝32.53 档 → 08:15');
      expect(medTimeIdx('09:30'), 38);
      // 刀口：这里若走「换算成字符串再 indexOf」，1440 归零算出 `0:00`，表里是 `00:00`，
      // 匹配不到就静默回落 08:00——23:59 那条会被归到早上。
      expect(medTimeIdx('23:59'), 0, reason: '23:59 归到 00:00 档，不是早上八点');
      expect(medTimeIdx(null), 32, reason: '读不到才回落默认档');
      expect(medTimeIdx('25:00'), 32, reason: '非法写法同回落，不抛');
    });

    test('剂量 0.5~6 片、半片一档共 12 档，新增默认 1 片＝index 1', () {
      expect(medDoseCount, 12);
      expect(medDoseLabels().first, '0.5');
      expect(medDoseLabels().last, '6');
      expect(medDoseLabels()[1], '1', reason: '整数不带小数点（原型 JS 数字直出）');
      expect(medDoseAt(0), 0.5);
      expect(medDoseAt(medDoseCount - 1), 6.0);
      expect(medDoseIdx(null), 1);
      expect(medDoseIdx(1.0), 1);
      expect(medDoseIdx(2.5), 4, reason: '(2.5-0.5)/0.5＝4 档');
      expect(medDoseIdx(0.2), 0, reason: '越下界夹紧第一档');
      expect(medDoseIdx(99), medDoseCount - 1, reason: '越上界夹紧末档，脏数据不炸量程');
    });

    test('宽限四档与读数（原型 hWheelPick([15,30,60,120])）', () {
      expect(medGraceOptions, [15, 30, 60, 120]);
      expect(medGraceTx(30), '超 30 分钟');
    });
  });

  group('今日计划：已服≠有交代（刀1 靶）', () {
    test('o 只认 taken，skipped 算「有交代」但不算已服', () {
      final d = plan(id: 7, times: const ['08:00', '20:00']);
      final logs = <int, Map<String, String>>{
        7: {'08:00': 'skipped', '20:00': 'taken'},
      };
      expect(mdPlan([d], logs), (t: 2, o: 1), reason: '换成 slotSettled 就变 2/2');
      expect(mdDrugDay(d, logs[7]!), (t: 2, o: 1));
      expect(mdPlanTx((t: 2, o: 1)), '1/2 次 · 今日');
    });

    test('计划位为 0 时读数出「—」，不出「0/0」（没计划≠一次没吃）', () {
      expect(mdPlanRead((t: 0, o: 0)), '—');
      expect(mdPlanRead((t: 0, o: 3)), '—', reason: '分母为零就不给比值读数');
      expect(mdPlanRead((t: 3, o: 0)), '0/3 次 · 今日');
      expect(mdRateTx(null), '—');
      expect(mdRateTx(75), '75%');
    });

    test('归档档案不进今日计划，也不进依从率分母', () {
      final live = plan(id: 1, times: const ['08:00']);
      final gone = plan(id: 2, name: '旧药', times: const ['20:00'], archived: true);
      final logs = <int, Map<String, String>>{
        1: {'08:00': 'taken'},
        2: {'20:00': 'taken'},
      };
      expect(mdActive([live, gone]).map((d) => d.id), [1]);
      expect(mdPlan([live, gone], logs), (t: 1, o: 1));
      expect(mdCompliance([live, gone], logs), 100.0);
      expect(mdCompliance([gone], logs), isNull,
          reason: '全是归档档案＝没有计划，依从率是「—」不是 0%');
    });
  });

  group('近 7 天热力：三档 + 无计划日不铺绿（刀2 靶）', () {
    test('mdHeatDay 的 t>0 守卫：t=0 的日子画空档，不画成「全部服用」', () {
      expect(mdHeatDay(t: 0, o: 0), MdHeat.none,
          reason: '摘掉 t>0 就变成 0>=0 成立＝满格绿，一支没开始的药看起来天天吃满');
      expect(mdHeatDay(t: 2, o: 2), MdHeat.full);
      expect(mdHeatDay(t: 2, o: 1), MdHeat.part);
      expect(mdHeatDay(t: 2, o: 0), MdHeat.none);
      expect(MdHeat.full.label, '全部服用');
      expect(MdHeat.part.label, '部分服用');
      expect(MdHeat.none.label, '未服用');
    });

    test('热力行旧→新七格，按单药取自己的打卡，别的药不串味', () {
      final d = plan(id: 5, times: const ['08:00', '20:00']);
      final days = mdDaysBack(at(10, 30), 7);
      expect(days.length, 7);
      expect(days.first, '2026-09-13', reason: '旧→新（原型 htDay(6-i)）');
      expect(days.last, '2026-09-19', reason: '最后一格＝今天');
      final byDay = <String, Map<int, Map<String, String>>>{
        '2026-09-18': {
          5: {'08:00': 'taken', '20:00': 'taken'},
          9: {'08:00': 'taken'}, // 另一支药，与这一行无关
        },
        '2026-09-19': {
          5: {'08:00': 'taken'},
        },
      };
      final row = mdHeatRow(drug: d, days: days, byDay: byDay);
      expect(row.map((x) => x.heat).toList(), [
        MdHeat.none,
        MdHeat.none,
        MdHeat.none,
        MdHeat.none,
        MdHeat.none,
        MdHeat.full,
        MdHeat.part,
      ]);
      expect(row[5], (day: '2026-09-18', t: 2, o: 2, heat: MdHeat.full));
      expect(row[6].o, 1, reason: '今天只服了一格');
    });
  });

  group('漏服：已过时刻 + 宽限，且既没服也没跳过', () {
    final d = plan(id: 3, times: const ['08:00', '12:00', '20:00']);

    test('当前分钟换算与三格各自判定', () {
      expect(mdNowMin(at(10, 5)), 605);
      expect(mdMissedOf(d, const {}, mdNowMin(at(10, 5)), graceMin: 30), 1,
          reason: '08:00 过了宽限，12:00/20:00 还没到');
      expect(mdMissedOf(d, const {}, mdNowMin(at(17, 0)), graceMin: 30), 2);
      expect(mdMissedOf(d, const {}, mdNowMin(at(23, 0)), graceMin: 30), 3);
      expect(mdMissedOf(d, const {}, mdNowMin(at(8, 20)), graceMin: 30), 0,
          reason: '宽限内不算漏（设置项 missed_grace_min 就作用在这里）');
    });

    test('已服与跳过都不算漏；合计只算在册档案', () {
      const settled = <String, String>{'08:00': 'taken', '12:00': 'skipped'};
      expect(mdMissedOf(d, settled, mdNowMin(at(23, 0)), graceMin: 30), 1,
          reason: '只剩 20:00 没交代；跳过那一格不再被叫成漏服');
      final other = plan(id: 4, name: '降压药', times: const ['09:00'], archived: true);
      expect(
          mdMissedTotal([d, other], <int, Map<String, String>>{3: const {}, 4: const {}}, 1380,
              graceMin: 30),
          3,
          reason: '归档档案不参与漏服合计（它已经不在卡列表里）');
    });

    test('徽标只在 n>0 时出现（摆一枚「今日漏服 0 次」＝把没发生的事说成发生了）', () {
      expect(mdMissedBadgeTx(0), isNull);
      expect(mdMissedBadgeTx(-1), isNull);
      expect(mdMissedBadgeTx(2), '今日漏服 2 次');
    });
  });

  group('槽位与 chips：至多五枚，余下的收进「+n 全部」', () {
    test('槽位序＝档案序 × 档案内时刻序，归档档案整支不进 chips', () {
      final a = plan(id: 1, times: const ['08:00', '20:00']);
      final b = plan(id: 2, name: '降压药', times: const ['21:00']);
      final c = plan(id: 3, name: '旧药', times: const ['07:00'], archived: true);
      final logs = <int, Map<String, String>>{
        1: {'08:00': 'taken'},
      };
      final slots = mdSlots([a, b, c], logs);
      expect(slots.map((s) => '${s.drugId}/${s.time}').toList(), ['1/08:00', '1/20:00', '2/21:00']);
      expect(slots.first.taken, isTrue);
      expect(mdSlotTx(slots.first), '08:00 钙片 · 已服');
      expect(mdSlotTx(slots[1]), '20:00 钙片 · 待服');
    });

    test('第六枚起折叠，n＝余下的枚数而不是总数', () {
      final slots = <MedSlot>[
        for (var i = 0; i < 6; i++)
          (drugId: 1, time: '0$i:00', name: '钙片', taken: false),
      ];
      expect(mdChipsShown(slots).length, medChipMax, reason: '原型 slice(0,5)');
      expect(mdChipsShown(slots).last.time, '04:00');
      expect(mdChipsMoreTx(slots.length), '+1 全部');
      expect(mdChipsMoreTx(5), isNull, reason: '刚好五枚不折叠');
      expect(mdChipsMoreTx(0), isNull);
      expect(mdChipsMoreTx(12), '+7 全部');
    });

    test('卡内时刻行文案（原型 ok?已服用 · 可撤销:待服用）', () {
      expect(mdSlotStateTx(true), '已服用 · 可撤销');
      expect(mdSlotStateTx(false), '待服用');
      expect(mdSlotBtnTx(true), '撤销');
      expect(mdSlotBtnTx(false), '打卡');
    });
  });

  group('卡面读数：空值不拿 0 或空串冒充', () {
    test('规格缺失显「—」，副信息按原型串', () {
      expect(mdSpecTx(null), '—');
      expect(mdSpecTx('  '), '—', reason: '空白串不算读数');
      expect(mdSpecTx('600mg'), '600mg');
      expect(mdCardSub(plan(spec: '600mg', dose: 0.5)), '600mg · 每次 0.5 片');
      expect(mdCardSub(plan()), '— · 每次 1 片', reason: '缺规格在卡上占一个「—」，不留空段');
      expect(mdCardSub(plan(endDate: '2026-10-19')), '— · 每次 1 片 · 疗程至 2026-10-19');
    });

    test('剂量单位行（原型 hdDoseU 原话）', () {
      expect(medUnit, '片');
      expect(mdDoseUnitTx(medUnit), '片 · 每次');
    });
  });

  group('总开关与症状关联', () {
    test('全开才算开：无档案＝关，有一枚关就是关', () {
      expect(mdRemindAllOn(const []), isFalse,
          reason: '没有在册档案时开关是关的（点了给一句实话，不谎报「已全部开启」）');
      final on = plan(id: 1, remind: true);
      final off = plan(id: 2, name: 'B', remind: false);
      final gone = plan(id: 3, name: 'C', remind: false, archived: true);
      expect(mdRemindAllOn([on]), isTrue);
      expect(mdRemindAllOn([on, off]), isFalse);
      expect(mdRemindAllOn([on, gone]), isTrue, reason: '归档档案不参与判定（它不在卡列表里）');
    });

    test('用药相关症状：0 条说「暂无」，不进单张卡（每卡挂同一个数＝假精确）', () {
      expect(mdSymLinkTx(0), '暂无用药相关症状');
      expect(mdSymLinkTx(3), '与用药相关症状 3 条');
    });
  });

  group('免打扰窗口从判据反推（写死字面量会在窗口改了之后继续谎报）', () {
    final day = at(12, 0);

    test('跨零点的 23:00–07:00：起止都由判据推出来', () {
      expect(mdDndTx(like23to7, day), '23:00 – 07:00');
    });

    test('不跨零点的窗口也推得对；无窗＝null，全天＝「全天」', () {
      expect(mdDndTx((t) => t.hour >= 0 && t.hour < 6, day), '00:00 – 06:00');
      expect(mdDndTx((t) => t.hour >= 9 && t.hour < 12, day), '09:00 – 12:00');
      expect(mdDndTx((t) => false, day), isNull, reason: '页面据此出「未设置免打扰时段」');
      expect(mdDndTx((t) => true, day), '全天');
    });

    test('四点边界探的是判据本身（22:59 不在窗内、23:00 起在、06:59 在、07:00 出）', () {
      expect(like23to7(at(22, 59)), isFalse);
      expect(like23to7(at(23, 0)), isTrue);
      expect(like23to7(at(6, 59)), isTrue);
      expect(like23to7(at(7, 0)), isFalse);
      expect(mdDndTx(like23to7, day), '23:00 – 07:00');
    });
  });

  group('录入弹层的两道校验（浏览器自带上限在这里得自己卡）', () {
    test('疗程日：留空放过，格式／月份／真实日历三道都拒', () {
      expect(medEndDateErr(''), isNull);
      expect(medEndDateErr('   '), isNull, reason: '留空＝不设置，不是错误');
      expect(medEndDateErr('2026-10-19'), isNull);
      expect(medEndDateErr('2026-2-3'), '疗程日期格式 yyyy-MM-dd', reason: '单位数月日不放行');
      expect(medEndDateErr('2026-13-01'), '疗程日期月份不合法');
      expect(medEndDateErr('2026-02-30'), '疗程日期不存在',
          reason: 'DateTime.tryParse 会把 2 月 30 日归一成 3 月 2 日，越界必须自己卡');
      expect(medEndDateErr('abc'), '疗程日期格式 yyyy-MM-dd');
    });

    test('时刻去重＋升序＋零填充归一，非法写法整条丢弃', () {
      expect(mdCleanTimes(['20:00', '08:00', '20:00']), ['08:00', '20:00']);
      expect(mdCleanTimes(['9:00', '09:00']), ['09:00'],
          reason: '库里混进 9:00 时打卡行的 key 对不上，写侧先归一成一种写法');
      expect(mdCleanTimes(['25:00', '08:00', 'x']), ['08:00'], reason: '非法时刻不进档案');
      expect(mdCleanTimes(const []), isEmpty);
      expect(mdCleanTimes(['23:45', '00:00']), ['00:00', '23:45'], reason: '归一后字典序＝时间序');
    });
  });

  group('提示条原话（改一个字都会被读成「功能变了」）', () {
    test('归档/打卡/提醒/建档四条与原型同文，其中不吹「已排程」', () {
      expect(medDelConfirmTx('钙片'), '删除「钙片」档案');
      expect(medDeletedTx, '已删除档案 · 历史打卡保留在流水');
      expect(medTapTx('08:00', '钙片', true), '08:00 · 钙片 打卡成功');
      expect(medTapTx('08:00', '钙片', false), '08:00 · 钙片 已撤销打卡');
      expect(medAddedTx('09:15'), '已加入 09:15');
      expect(medDupTimeTx, '该时刻已存在');
      expect(medNameRequiredTx, '请填写药品名称');
      expect(medSavedTx('钙片', true), '已建档 钙片 · 提醒已开启 · 排程随提醒中心上线生效',
          reason: '排程在批8 才接线，这句现在只说开关状态，不说「已排程到通知中心」');
      expect(medSavedTx('钙片', false), '已建档 钙片 · 未开启提醒');
      expect(medRemOnTx, '提醒已开启 · 排程随提醒中心上线生效');
      expect(medRemOffTx, '该药提醒已关闭');
      expect(medAllOnTx, '已全部开启提醒 · 排程随提醒中心上线生效');
      expect(medAllOffTx, '已全部关闭用药提醒');
      expect(medNoDrugTx, '还没有药品档案 · 先建档再开提醒');
      expect(medEmptyTx, '还没有药品档案 · 点下方「＋ 新增药品」');
      expect(medChipEmptyTx, '暂无用药计划 · 去「用药」建档');
      expect(medFootnoteTx, '处方药请遵医嘱 · 本模块只做记录与提醒，不提供用药建议');
    });
  });
}

/// 与 `NotificationService.inDndWindow` 同一条窗口规则的测试判据。
///
/// 域层不引 core（依赖方向），所以这里传函数进去探文案；页面对真判据的四点探针在
/// `health_med_page_test.dart`，两处任一改动都会被各自那一组抓住。
bool like23to7(DateTime t) => t.hour >= 23 || t.hour < 7;
