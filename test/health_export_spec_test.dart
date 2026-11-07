import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lifeharness/features/health/domain/health_export.dart';

/// 健康批6b · 流水导出规格（原型 `index-health.html` 的 `hExport` ＋需求 176 行）。
///
/// 四条判定：范围四档逐字、跨年取样、CSV/JSON 两种形态与预览同源、
/// 敏感实话进提示（文件名不放中文＝跨端兼容，实话落在提示与预览）。
void main() {
  final now = DateTime(2026, 10, 8, 15, 30, 12);
  HealthExportRow r(String date,
          {String kind = '喝水',
          String value = '1',
          String detail = '',
          String note = ''}) =>
      (date: date, kind: kind, value: value, detail: detail, note: note);

  group('范围与取样', () {
    test('范围四档逐字照原型（本机全部·近 30 天·近 90 天·按月份）', () {
      expect(healthScopeLabels(), ['本机全部', '近 30 天', '近 90 天', '按月份']);
      expect(healthScopeKey(3), 'month');
      expect(healthScopeLabel('d90'), '近 90 天');
      expect(kHealthExportFormats.map((f) => f.$2).toList(), ['CSV', 'JSON']);
    });

    test('近 30/90 天含今天往回数（29/89 天），边界日在框内', () {
      final rows = [r('2026-09-09'), r('2026-10-08')];
      expect(healthExportScope(rows: rows, scope: 'd30', now: now), hasLength(2),
          reason: '2026-09-09＝今天往回第 29 天，含');
      expect(healthExportScope(rows: [r('2026-09-08')], scope: 'd30', now: now), isEmpty);
      expect(
          healthExportScope(rows: [r('2026-07-11')], scope: 'd90', now: now), hasLength(1));
      expect(
          healthExportScope(rows: [r('2026-07-10')], scope: 'd90', now: now), isEmpty);
    });

    test('按月份＝前缀匹配；没选月份出空而不是全量（宁可少出，不许冒充范围）', () {
      final rows = [r('2026-09-30'), r('2026-10-01'), r('2026-10-08')];
      expect(healthExportScope(rows: rows, scope: 'month', now: now, month: '2026-10'),
          hasLength(2));
      expect(healthExportScope(rows: rows, scope: 'month', now: now), isEmpty);
    });

    test('月份滚轮 12 档旧→新、跨年回退到去年', () {
      final labels = healthMonthLabels(now);
      expect(labels.length, 12);
      expect(labels.first, '2025-11');
      expect(labels.last, '2026-10');
      expect(healthMonthLabels(DateTime(2026, 1, 5)).first, '2025-02');
      expect(healthMonthLabels(DateTime(2026, 12, 1)).last, '2026-12');
    });

    test('文件名 health_YYYYMMDD_HHmmss.格式（同日两次导出不互相覆盖）', () {
      expect(healthExportFileName(fmt: 'csv', now: now), 'health_20261008_153012.csv');
      expect(healthExportFileName(fmt: 'json', now: DateTime(2026, 10, 8, 15, 30, 13)),
          'health_20261008_153013.json');
    });
  });

  group('两种形态与预览同源', () {
    test('CSV 表头与预览字段行取同一份（预览说的是什么，文件里就是什么）', () {
      expect(healthCsvHeader, '日期,类型,读数,详情,备注');
      expect(healthFieldNote('csv'), '字段：$healthCsvHeader');
      expect(healthFieldNote('json'), healthJsonFieldNote);
    });

    test('CSV 行：RFC4180 转义（逗号/引号/换行才加引号，内部引号翻倍）', () {
      expect(healthCsvLine(r('2026-10-08', kind: '喝水', value: '3 杯')), '2026-10-08,喝水,3 杯,,');
      expect(
          healthCsvLine(r('2026-10-08', kind: '运动', note: '通勤, 跑步')),
          '2026-10-08,运动,1,,"通勤, 跑步"');
      expect(healthCsvLine(r('2026-10-08', kind: '身体', note: '他说"好"')),
          '2026-10-08,身体,1,,"他说""好"""');
    });

    test('JSON 键序＝字段说明那一行（导出文件要能被下游按约定读）', () {
      final e = healthJsonEntry(r('2026-10-08', kind: '睡眠', value: '480 分钟', detail: '入睡 23:00'));
      expect(e.keys.toList(), ['date', 'kind', 'value', 'detail', 'note']);
      expect(jsonEncode(e),
          '{"date":"2026-10-08","kind":"睡眠","value":"480 分钟","detail":"入睡 23:00","note":""}');
    });

    test('同一天多类按固定内序排（导出文件不能每次换序）', () {
      expect(exportKindOrder, ['喝水', '睡眠', '运动', '身体', '用药']);
    });
  });

  group('落盘与提示', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('lh_health_export_'));
    tearDown(() {
      // Windows 偶发句柄未放（刚写完的 CSV 还在索引器手里）：不留测试假红。
      try {
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('CSV 落盘：首行表头＋逐条一行，count 与文件行数一致', () async {
      final res = await writeHealthExportFile(
          dir: tmp.path,
          fmt: 'csv',
          rows: [r('2026-10-07', kind: '喝水', value: '2 杯'), r('2026-10-08', kind: '喝水', value: '3 杯')],
          now: now);
      expect(res.count, 2);
      expect(baseNameOf(res.path), 'health_20261008_153012.csv');
      final lines = File(res.path).readAsLinesSync();
      expect(lines.first, healthCsvHeader);
      expect(lines.length, 3);
    });

    test('JSON 落盘：空档出 []，有条目是合法数组（能直接 jsonDecode）', () async {
      final empty =
          await writeHealthExportFile(dir: tmp.path, fmt: 'json', rows: const [], now: now);
      expect(jsonDecode(File(empty.path).readAsStringSync()), isEmpty);

      final two = await writeHealthExportFile(
          dir: tmp.path,
          fmt: 'json',
          rows: [r('2026-10-07', kind: '喝水', value: '2 杯'), r('2026-10-08', kind: '用药', value: '已服', detail: '阿司匹林')],
          now: now);
      final decoded = jsonDecode(File(two.path).readAsStringSync()) as List;
      expect(decoded, hasLength(2));
      expect(decoded.last['kind'], '用药');
      expect(decoded.last['detail'], '阿司匹林');
    });

    test('完成提示四件实话：文件名＋条数与范围＋敏感记录＋真实落点路径', () {
      final tx = healthExportToast(
          path: 'x/health_20261008_153012.csv', count: 128, scope: 'd30');
      expect(tx, contains('health_20261008_153012.csv'));
      expect(tx, contains('近 30 天 128 条'));
      expect(tx, contains(healthExportSensitiveNote));
      expect(tx, contains('落点 x'),
          reason: '备份文件屏只扫 backup/ 与 exports/，导出件在 documents 根——给路径才是实话');
    });

    test('脚注与需求同句（数据仅存本机 · 无网络上传）', () {
      expect(healthLocalOnlyFootnote, '数据仅存本机 · 无网络上传');
    });
  });
}
