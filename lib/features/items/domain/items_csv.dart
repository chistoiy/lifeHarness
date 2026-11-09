/// 物品档案 CSV 导出（竞品补全 I09 的纯函数层）。
///
/// 为什么单独成文件：导出是「同一份档案快照的另一种序列化」，口径全在这里、
/// UI 只负责把字符串送出去（剪贴板/文件），单测不必起整机、不依赖 dart:io
/// 或分享插件；与 items_filter.dart 同属 domain 层可判定逻辑。
library;

import 'item_calc.dart';
import 'item_models.dart';

/// CSV 表头（顺序即列序；与 ItemsRepository._row 的档案列同源语义）。
/// 末尾两列是只读派生：持有天数 / 当前日均（冻结档案留空）。
const kItemCsvHeader = <String>[
  'ID',
  '名称',
  '分类',
  '品牌',
  '序列号',
  '购入日期',
  '购入价',
  '成本池',
  '状态',
  '计费方式',
  '计划次数',
  '单位',
  '已用次数',
  '保修至',
  '物品备注',
  '照片',
  '来源',
  '持有天数',
  '当前日均',
];

/// RFC 4180 单元格转义：含逗号 / 引号 / CR / LF 时用双引号包裹，
/// 且内部双引号翻倍。null 与空串同形（导出侧不区分「没填」与「空」）。
String csvCell(Object? v) {
  final s = v == null ? '' : v.toString();
  if (s.contains(',') || s.contains('"') || s.contains('\r') || s.contains('\n')) {
    return '"${s.replaceAll('"', '""')}"';
  }
  return s;
}

/// 单件档案 → 一行 CSV 字段（顺序严格对齐 [kItemCsvHeader]）。
/// 金额统一两位小数（对账/迁移口径）；成本池走 [poolOf] 净值而非购入价，
/// 冻结档案无当前日均 → 留空（不是 0，0 会被误读成「免费持有」）。
List<String> itemCsvRow(ItemProfile it, DateTime now) => <String>[
      '${it.id ?? ''}',
      it.name,
      it.category,
      it.brand ?? '',
      it.serial ?? '',
      it.buyDate,
      it.price.toStringAsFixed(2),
      poolOf(it).toStringAsFixed(2),
      it.status,
      it.mode.wire,
      it.planUnits == null ? '' : it.planUnits!.toStringAsFixed(0),
      it.unit,
      usedTotal(it).toStringAsFixed(0),
      it.warranty ?? '',
      it.note ?? '',
      it.photo ?? '',
      it.source,
      '${daysHeld(it.buyDate, now)}',
      it.billing ? (costPerDay(it, now) ?? 0).toStringAsFixed(2) : '',
    ];

/// 全量档案 → CSV 文本。
/// - 带 UTF-8 BOM（Excel 中文不乱码）；
/// - 行分隔 CRLF（RFC 4180），每行（含末行）以 CRLF 收尾；
/// - [now] 走与列表/详情同一个时间源缝，派生列口径一致。
String itemsToCsv(List<ItemProfile> items, DateTime now) {
  final rows = <String>[
    kItemCsvHeader.map((e) => csvCell(e)).join(','),
    for (final it in items) itemCsvRow(it, now).map((e) => csvCell(e)).join(','),
  ];
  return '\uFEFF${rows.join('\r\n')}\r\n';
}
