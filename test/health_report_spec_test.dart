import 'package:flutter_test/flutter_test.dart';

import 'package:lifeharness/features/health/domain/health_models.dart';
import 'package:lifeharness/features/health/domain/health_report.dart';

/// 健康批3.5b · 检查报告规格单源（事实源＝`tools/health/v2_pages.html#p-report` ＋
/// `tools/health/v2_sheets.html` 的 `sheetHReportAdd`/`sheetHMetric` ＋ `v2_js.js` 的
/// `HK_LIB`/`rpRender`/`rpYear`/`rpToggle`/`rpa*`/`hmk*`）。
///
/// 这里钉的是**页面与两张弹层共用**的判据，屏上表现另由 `health_report_page_test` 与
/// `health_report_sheet_test` 管。五类必钉：
/// · 判档**边界值算正常**（原型 `m[1]<m[3]?'lo':(m[1]>m[4]?'hi':'ok')`）——把 `>` 改成 `>=`
///   这里当场红，参考范围 115~150 填 115 的人不该被判偏低；
/// · 月份轴而不是年份轴（原型 `r.d.slice(0,2)`），chips 序＝取数序、不额外排序；
/// · 统计三位吃**全量**、附件读数由 `files` 内容派生（原型的 `r.fmt` 是末次动作覆盖出来的
///   字符串，本实现按类型分开数＝偏离，登记工单 §3）；
/// · 滚轮量程按参考跨度自适应＋参考柱 1 一档（`hmkWheels` 原式），
///   「滚轮选不到中间值」是事实而不是 bug——5.2 归到 5 就红在这；
/// · 一切给用户的字符串从这里出（`rp*Tx`），弹层与页面不各拼一遍。
void main() {
  ReportBundle bundle(
      {int? id,
      String date = '2026-09-19',
      String name = '血常规',
      String? hospital = '市一院',
      List<String> files = const [],
      String kind = 'img',
      List<ReportMetric> metrics = const []}) {
    return ReportBundle(
      report: HealthReport(
          id: id,
          profileId: 1,
          date: date,
          name: name,
          hospital: hospital,
          files: files,
          kind: kind),
      metrics: metrics,
    );
  }

  ReportMetric m(String name, double? v, double? lo, double? hi, {String? unit = 'g/L'}) =>
      ReportMetric(name: name, value: v, refLo: lo, refHi: hi, unit: unit);

  group('项目库', () {
    test('十枚原序·单位与参考范围照原型原文', () {
      expect(hkLib.length, 10);
      expect(hkLib.map((e) => e.name).toList(), [
        '血红蛋白', '白细胞', '血小板', '总胆固醇', '低密度脂蛋白', //
        '甘油三酯', '空腹血糖', '糖化血红蛋白', '尿酸', '肌酐'
      ]);
      expect(hkLib[0].unit, 'g/L');
      expect(hkLib[1].unit, '×10⁹/L');
      expect(hkLib[8].unit, 'μmol/L');
      expect([hkLib[0].refLo, hkLib[0].refHi], [115.0, 150.0]);
      expect([hkLib[9].refLo, hkLib[9].refHi], [41.0, 81.0]);
    });

    test('自定义名不在库内＝查不到、单位回落空串', () {
      expect(hkFind('甲胎蛋白'), isNull);
      expect(hkUnitOf('甲胎蛋白'), '');
      expect(hkUnitOf('肌酐'), 'μmol/L');
    });
  });

  group('判档', () {
    test('边界值算正常：115/150 都判正常，出界才给旗', () {
      expect(hkFlagOf(115, 115, 150), HkFlag.normal, reason: '`<lo` 才偏低');
      expect(hkFlagOf(150, 115, 150), HkFlag.normal, reason: '`>hi` 才偏高');
      expect(hkFlagOf(114.9, 115, 150), HkFlag.low);
      expect(hkFlagOf(150.1, 115, 150), HkFlag.high);
    });

    test('缺数值或缺任一端参考＝none（不假装判过档）', () {
      expect(hkFlagOf(null, 115, 150), HkFlag.none);
      expect(hkFlagOf(120, null, 150), HkFlag.none);
      expect(hkFlagOf(120, 115, null), HkFlag.none);
      // 单边范围不当范围用：拿 0~null 去判会把所有值都判成「不偏高＝正常」。
      expect(hkFlagOfMetric(m('血红蛋白', 900, 115, null)), HkFlag.none);
    });

    test('四态文案与异常判定', () {
      expect(hkFlagTx(HkFlag.low), '偏低');
      expect(hkFlagTx(HkFlag.high), '偏高');
      expect(hkFlagTx(HkFlag.normal), '正常');
      expect(hkFlagTx(HkFlag.none), '—', reason: '没判过就出「—」，不写「未知」也不写 0');
      expect([hkIsAbnormal(HkFlag.low), hkIsAbnormal(HkFlag.high)], [true, true]);
      expect([hkIsAbnormal(HkFlag.normal), hkIsAbnormal(HkFlag.none)], [false, false]);
    });

    test('异常计数只数偏低偏高，角标两态', () {
      final ms = [
        m('血红蛋白', 100, 115, 150), // 偏低
        m('白细胞', 6.5, 3.5, 9.5, unit: '×10⁹/L'), // 正常
        m('肌酐', 95, 41, 81, unit: 'μmol/L'), // 偏高
        m('尿酸', null, 155, 357, unit: 'μmol/L'), // 未填＝none
      ];
      expect(hkAbnormal(ms), 2);
      expect(rpBadgeTx(2), '2 项异常');
      expect(rpBadgeTx(0), '全部正常');
    });
  });

  group('拼装体与月份轴', () {
    test('bundle 的读数＝检验项列表的读数（页面不再各取一次）', () {
      final b = bundle(metrics: [
        m('血红蛋白', 100, 115, 150),
        m('白细胞', 6.5, 3.5, 9.5, unit: '×10⁹/L'),
      ]);
      expect(b.metricCount, 2);
      expect(b.abnormalCount, 1);
      expect(b.flagOf(b.metrics.first), HkFlag.low);
    });

    test('归档月份取 date 的 MM；串太短原样回落（不抛）', () {
      expect(rpMonth('2026-09-19'), '09');
      expect(rpMonth('2026-12-01'), '12');
      expect(rpMonth('09-19'), '09-19');
    });

    test('chips＝「全部」∪ 出现过的月份，顺序跟着取数序', () {
      final bs = [
        bundle(date: '2026-09-19'),
        bundle(date: '2026-08-02'),
        bundle(date: '2026-09-05'),
      ];
      expect(rpMonthChips(bs), ['全部', '09', '08'], reason: '原型 `[全部].concat([...new Set(...)])`');
      expect(rpMonthChips(const []), ['全部']);
    });

    test('筛选与 chips 文案', () {
      final bs = [bundle(date: '2026-09-19', id: 1), bundle(date: '2026-08-02', id: 2)];
      expect(rpByMonth(bs, '全部'), bs);
      expect(rpByMonth(bs, '09').map((b) => b.report.id).toList(), [1]);
      expect(rpByMonth(bs, '07'), isEmpty);
      expect(rpMonthTx('全部'), '全部');
      expect(rpMonthTx('09'), '9 月', reason: '原型 `(+x)+\' 月\'` 去前导零');
      expect(rpMonthTx('12'), '12 月');
    });

    test('流水序＝最新在上，同日期按 id 倒排', () {
      final bs = [
        bundle(date: '2026-08-02', id: 1),
        bundle(date: '2026-09-19', id: 2),
        bundle(date: '2026-09-19', id: 3),
      ];
      expect(rpDesc(bs).map((b) => b.report.id).toList(), [3, 2, 1],
          reason: '偏离原型插入序：新传的报告排在底部会被当成没存上（登记工单 §3）');
    });
  });

  group('统计三位与附件读数', () {
    test('附件计数：有附件数附件，一张没落但记着 PDF 按 1 个记', () {
      expect(rpAttachCount(const HealthReport(
          profileId: 1, date: '2026-09-19', name: 'x', files: ['a.png', 'b.pdf'])), 2);
      expect(rpAttachCount(const HealthReport(
          profileId: 1, date: '2026-09-19', name: 'x', files: [], kind: 'pdf')), 1);
      expect(rpAttachCount(const HealthReport(profileId: 1, date: '2026-09-19', name: 'x')), 0);
    });

    test('kind 派生：全是 PDF 才记 pdf，混着或空都记 img', () {
      expect(rpKindOf(['a.pdf', 'b.PDF']), 'pdf', reason: '扩展名判据不分大小写');
      expect(rpKindOf(['a.pdf', 'b.png']), 'img');
      expect(rpKindOf(const []), 'img');
    });

    test('页顶三读数吃全量（月份筛选不该把它们跟着缩小）', () {
      final bs = [
        bundle(id: 1, date: '2026-09-19', files: ['a.png', 'b.png'], metrics: [
          m('血红蛋白', 100, 115, 150),
          m('白细胞', 6.5, 3.5, 9.5, unit: '×10⁹/L'),
        ]),
        bundle(id: 2, date: '2026-08-02', files: ['c.pdf'], kind: 'pdf', metrics: [
          m('肌酐', 95, 41, 81, unit: 'μmol/L'),
        ]),
      ];
      final stat = rpStatOf(bs);
      expect([stat.reports, stat.abnormal, stat.attachments], [2, 2, 3]);
      // 只看 8 月时三份读数一动不动，只有卡片少一张。
      final one = rpByMonth(bs, '08');
      expect(one.length, 1);
      expect(rpStatOf(one).attachments, 1);
    });

    test('附件读数按类型分开数（PDF 不计进「图片 ×N」）', () {
      expect(rpFmtTx(const HealthReport(profileId: 1, date: 'd', name: 'x')), '未附');
      expect(rpFmtTx(const HealthReport(profileId: 1, date: 'd', name: 'x', kind: 'pdf')), 'PDF',
          reason: '附件没落盘但类型记着 pdf：按 1 份 PDF 读');
      expect(
          rpFmtTx(const HealthReport(profileId: 1, date: 'd', name: 'x', files: ['a.png', 'b.png'])),
          '图片 ×2');
      expect(rpFmtTx(const HealthReport(profileId: 1, date: 'd', name: 'x', files: ['a.pdf'])), 'PDF');
      expect(
          rpFmtTx(
              const HealthReport(profileId: 1, date: 'd', name: 'x', files: ['a.pdf', 'b.png'])),
          'PDF · 图片 ×1');
      expect(
          rpFmtTx(
              const HealthReport(profileId: 1, date: 'd', name: 'x', files: ['a.pdf', 'b.pdf'])),
          'PDF ×2');
    });

    test('卡片副注四段·医院缺失落「—」', () {
      final b = bundle(hospital: null, files: ['a.png'], metrics: [m('血红蛋白', 120, 115, 150)]);
      expect(rpCardSub(b), '${b.report.date} · — · 图片 ×1 · 1 项');
    });
  });

  group('行文案', () {
    test('箭头两态与建议行缺值走「—」', () {
      expect(rpArrow(true), '⌄');
      expect(rpArrow(false), '›');
      expect(rpAdviceTx('一周后复查血脂'), '医生建议：一周后复查血脂');
      expect(rpAdviceTx(''), '医生建议：—');
      expect(rpAdviceTx(null), '医生建议：—');
    });

    test('空态与校验提示＝原型原话', () {
      expect(rpEmptyTx, '该档案暂无报告 · 点下方上传');
      expect(rpNoMetricTx, '尚未录入检验项');
      expect(rpNeedNameTx, '请填写报告名称');
      expect(rpNeedMetricNameTx, '请先选或填写项目名称');
      expect(rpDeletedTx, '已删除 · 图片随报告移除');
      expect(rpDelTx('血常规'), '删除 血常规 报告');
      expect(rpMetricAddedTx('血红蛋白'), '已加入 血红蛋白 · 报告标记重算');
      expect(rpTipHintTx, '选项目 · 填数值与参考范围后自动标记偏高偏低');
    });

    test('保存提示两半句：建档带项数、无项说「待录入检验项」', () {
      expect(rpSavedTx('血常规', 3), '已归档 血常规 · 3 项');
      expect(rpSavedTx('血常规', 0), '已归档 血常规 · 待录入检验项');
      expect(rpDraftTx(2), '附件 2 个 · 检验项需建档后逐条录入（参考范围决定偏高/偏低标记）');
      expect(rpMetricSub(const HealthReport(id: 1, profileId: 1, date: '2026-09-19', name: '血常规'), 4),
          '血常规 · 2026-09-19 · 已录 4 项');
    });

    test('检验项行：无值出「—」、无参考出「—」，数值不带尾零', () {
      expect(rpMetricValueTx(m('血红蛋白', 132.5, 115, 150)), '132.5 g/L');
      expect(rpMetricValueTx(m('血红蛋白', 108, 115, 150)), '108 g/L');
      expect(rpMetricValueTx(m('自定义', 6, null, null, unit: null)), '6');
      expect(rpMetricValueTx(m('自定义', null, 1, 2)), '—');
      expect(rpMetricRefTx(m('血红蛋白', 108, 115, 150)), '115 ~ 150');
      expect(rpMetricRefTx(m('自定义', 1, null, 2)), '—', reason: '缺任一端就不画半截范围');
    });

    test('缩略位上限：第 7 格起不给「＋」（原型 rpaPics 的 <6 判据）', () {
      expect(rpAttachMax, 6);
      expect([rpCanAddAttach(0), rpCanAddAttach(5), rpCanAddAttach(6)], [true, true, false]);
    });
  });

  group('数值与滚轮量程', () {
    test('hkNumTx：整数不写小数点，小数最多两位并去尾零', () {
      expect(hkNumTx(108), '108', reason: '检验单上的 108 不该写成 108.0');
      expect(hkNumTx(132.5), '132.5');
      expect(hkNumTx(3.14), '3.14');
      expect(hkNumTx(0.1), '0.1');
      expect(hkNumTx(5.2), '5.2');
    });

    test('hkNums 含首末档、step 非正回落 1、反向输入自动交换', () {
      expect(hkNums(0, 3, 1), [0, 1, 2, 3]);
      expect(hkNums(3, 0, 1), [0, 1, 2, 3], reason: 'from>to 不返回空表');
      expect(hkNums(0, 3, 0), [0, 1, 2, 3], reason: 'step<=0 当 1 一档');
      expect(hkNums(0, 10, 0.1).length, 101);
      expect(hkNums(0, 10, 0.1).last, 10.0, reason: '用 lo+i*st 而不是累加：误差不能摊进档位');
      expect(hkNums(0, 1, 0.1),
          [0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]);
    });

    test('数值柱按参考跨度自适应（总宽 >80 才 1 一档）', () {
      // 肌酐 41~81：跨度 40 → 两侧各放 45% → 23~99，宽度 76 ≤80 → 0.1 一档。
      final cr = hkValueRange(41, 81);
      expect(cr.first, 23.0);
      expect(cr.last, 99.0);
      expect(cr.length, 761);
      // 血红蛋白 115~150 同量级；自定义 0~400：跨度 400 → -180..580 夹到 0..580 → 1 一档。
      final open = hkValueRange(0, 400);
      expect([open.first, open.last], [0.0, 580.0]);
      expect(open.length, 581);
      expect(open[1], 1.0, reason: '这里必须是 1 一档，不然 0~400 铺出 5801 格滚不动');
    });

    test('参考柱量程＝max(20, round(hi*1.6))，缺参考按 400 兜底', () {
      expect(hkRefMax(150), 240);
      expect(hkRefMax(5.2), 20, reason: 'round(8.32)=8 <20 → 取下限 20');
      expect(hkRefMax(null), 640);
    });

    test('选中项目库＝数值柱收到 (lo-1, hi+1)·0.1 一档·默认档落参考中点', () {
      final w = hkWheelsFor(refLo: 115, refHi: 150);
      expect(w.val.count, 371, reason: '114~151 每 0.1 一档');
      expect(w.val.value, 132.5, reason: '最接近 (115+150)/2 的档');
      expect(w.refLo, 115.0);
      expect(w.refHi, 150.0);
      expect(w.val.labels.first, '114');
      expect(w.val.stepTx, '0.1');
    });

    test('参考柱 1 一档：5.2 归到 5（滚轮选不到中间值＝原型口径）', () {
      final w = hkWheelsFor(refLo: 0, refHi: 5.2);
      expect(w.refHi, 5.0, reason: '原型 `hNums(0, max(20, round(hi*1.6)), 1)` 就是整数档');
      expect(w.refLo, 0.0);
      expect(w.val.value, 2.6);
      expect(w.val.labels.length, 63);
    });

    test('自定义／刚开弹层＝数值柱铺自适应全量程、默认档取正中', () {
      final w = hkWheelsFor();
      expect(w.val.count, 581);
      expect(w.val.value, 291.0);
      expect([w.refLo, w.refHi], [0.0, 400.0]);
      expect(w.lo.count, 641, reason: '参考柱按 hkRefMax(null)=640 铺 0..640');
      expect(w.hi.index, 400);
    });
  });

  group('判档预览', () {
    test('齐项时的 tip 拼装（名称 数值 单位 · 参考 lo ~ hi 旗）', () {
      expect(rpTipTx(name: '血红蛋白', value: 100, lo: 115, hi: 150),
          '血红蛋白 100 g/L · 参考 115 ~ 150 偏低');
      expect(rpTipTx(name: '血红蛋白', value: 150, lo: 115, hi: 150),
          '血红蛋白 150 g/L · 参考 115 ~ 150 正常', reason: '边界值算正常，弹层预览与卡片同一判据');
      expect(rpTipTx(name: '自定义项', value: 6, lo: 0, hi: 10), '自定义项 6  · 参考 0 ~ 10 正常',
          reason: '库外名没有单位，trim 只收行尾、中间留一个空格位（与原型同形）');
    });
  });
}
