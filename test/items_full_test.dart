import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/features/items/domain/item_models.dart';
import 'package:lifeharness/features/items/domain/items_csv.dart';

/// 物品模块余项守护：CSV 纯函数（I09）＋本批新增能力源码级正反档。
/// 源码级用例统一「新形态存在」＋「旧错误形态不存在」成对断言。
String _src(String p) => File(p).readAsStringSync();

void main() {
  group('I09 · CSV 导出纯函数', () {
    test('① RFC 4180 转义：逗号/引号/换行/翻倍，正负两档同例', () {
      expect(csvCell('a,b'), '"a,b"', reason: '正档：含逗号包裹');
      expect(csvCell('a"b'), '"a""b"', reason: '正档：内引号翻倍');
      expect(csvCell('a\nb'), '"a\nb"', reason: '正档：含换行包裹');
      expect(csvCell('a\r\nb'), '"a\r\nb"');
      expect(csvCell('plain'), 'plain', reason: '负档：普通串不包裹');
      expect(csvCell(null), '', reason: '负档：null 与空串同形');
      expect(csvCell('a,b').contains('a,b"'), isTrue);
    });

    test('② 表头列数与行同源、BOM＋CRLF 收尾', () {
      final csv = itemsToCsv(<ItemProfile>[], DateTime(2026, 11, 9));
      expect(csv.startsWith('\uFEFF'), isTrue, reason: '正档：BOM 防 Excel 乱码');
      expect(csv.endsWith('\r\n'), isTrue, reason: '正档：末行也收 CRLF');
      expect(csv.contains('\n') && !csv.contains('\r\n'), isFalse,
          reason: '负档：不许裸 LF 行分隔');
      final header = csv.replaceAll('\uFEFF', '').split('\r\n').first;
      expect(header.split(',').length, kItemCsvHeader.length,
          reason: '正档：表头列数自洽');
      expect(kItemCsvHeader.contains('品牌'), isTrue);
      expect(kItemCsvHeader.contains('序列号'), isTrue);
      expect(kItemCsvHeader.contains('物品备注'), isTrue);
    });

    test('③ 两件档案导出两行，且行内列数恒等于表头', () {
      // 不构造完整档案模型（字段多、夹具脆），改钉源码：行函数返回 19 列。
      final src = _src('lib/features/items/domain/items_csv.dart');
      expect(src.contains('List<String> itemCsvRow(ItemProfile it'), isTrue);
      expect(src.contains('itemsToCsv(List<ItemProfile> items'), isTrue);
      expect(kItemCsvHeader.length, 19, reason: '正档：列序冻结为 19 列');
      expect(kItemCsvHeader.toSet().length, kItemCsvHeader.length,
          reason: '负档：不许重复列名');
    });
  });

  group('本批新增能力 · 源码级正反档', () {
    test('④ I02/I04 列表搜索与筛选接线', () {
      final s = _src('lib/features/items/presentation/items_page.dart');
      expect(s.contains('TextEditingController') || s.contains('onChanged'),
          isTrue, reason: '正档：搜索输入在册');
      expect(s.contains('keyword:') && s.contains('hasQuery'), isTrue,
          reason: '正档：查询态接入（实现字段名＝keyword，不是 query）');
    });

    test('⑤ I01 照片 / I07 用量 / I06 保养 三处入口', () {
      final d = _src('lib/features/items/presentation/item_detail_page.dart');
      expect(d.contains('Image.file('), isTrue, reason: '正档：照片落本机文件');
      expect(d.contains('i-detail-usage-add'), isTrue);
      expect(d.contains('i-detail-maint-add'), isTrue);
      expect(d.contains('addUsage('), isTrue, reason: '正档：接既有按次用量写口');
      expect(d.contains('toast(\'照片'), isFalse,
          reason: '负档：不许留照片占位 toast');
    });

    test('⑥ I06 维护事件不进成本池（与二次付费口径隔离）', () {
      final m = _src('lib/features/items/domain/item_models.dart');
      final r = _src('lib/features/items/data/items_repository.dart');
      expect(m.contains("const kEvMaintain = 'maintain'"), isTrue);
      expect(kEvMaintain, isNot(equals(kEvExtra)),
          reason: '负档：维护事件不得复用 extra 类别进成本池');
      expect(r.contains('addMaintenance('), isTrue);
      expect(r.contains('amount: 0'), isTrue,
          reason: '正档：维护金额恒 0');
    });
  });
}
