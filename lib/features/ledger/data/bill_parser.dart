/// 账单 CSV 解析层（九·补4 · L14 步骤1-2；纯函数不触库，可单测）。
///
/// 表头前缀识别：支付宝「交易时间…交易分类…收/付款方式…交易订单号」；
/// 微信「交易时间…交易类型…支付方式…交易单号」。粘贴文本已在外部完成
/// 编码转换（UTF-8/GBK），此处只处理引号 CSV。
library;

import 'dart:convert' show LineSplitter, utf8;

import 'package:enough_convert/gbk.dart';
import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';

import '../../../core/logging/app_log.dart';

class BillRow {
  const BillRow({
    required this.date,
    required this.time,
    required this.counterparty,
    required this.product,
    required this.amt,
    required this.isIncome,
    required this.isRefund,
    required this.payMethod,
    required this.tradeNo,
    required this.rawCat,
    required this.status,
  });

  final String date; // YYYY-MM-DD
  final String time; // HH:MM
  final String counterparty;
  final String product;
  final double amt;
  final bool isIncome;
  final bool isRefund;

  /// 付款方式原文（账户匹配分组键）。
  final String payMethod;
  final String tradeNo;
  final String rawCat;
  final String status;
}

class BillParseResult {
  const BillParseResult({
    required this.platform,
    required this.rows,
    this.skipped = 0,
  });

  /// '支付宝' | '微信支付'
  final String platform;
  final List<BillRow> rows;

  /// 因「不计收支/跳过非支出」规则被过滤的条数。
  final int skipped;
}

/// 一行 CSV 拆字段（双引号包裹、`""` 转义）。
List<String> splitCsvLine(String line) {
  final out = <String>[];
  final buf = StringBuffer();
  var inQ = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (inQ) {
      if (ch == '"') {
        if (i + 1 < line.length && line[i + 1] == '"') {
          buf.write('"');
          i++;
        } else {
          inQ = false;
        }
      } else {
        buf.write(ch);
      }
    } else if (ch == '"') {
      inQ = true;
    } else if (ch == ',') {
      out.add(buf.toString().trim());
      buf.clear();
    } else {
      buf.write(ch);
    }
  }
  out.add(buf.toString().trim());
  return out;
}

/// 表头识别：返回 (平台, 列名→下标)。
(Map<String, int> col, String platform)? _detect(List<String> line) {
  final cells = line.map((c) => c.trim()).toList();
  if (!cells.contains('交易时间')) return null;
  final map = <String, int>{};
  for (var i = 0; i < cells.length; i++) {
    map[cells[i]] = i;
  }
  final isAlipay = map.containsKey('交易分类') &&
      (map.containsKey('收/付款方式') || map.containsKey('付款方式'));
  final isWx = map.containsKey('交易类型') && map.containsKey('支付方式');
  if (!isAlipay && !isWx) return null;
  return (map, isAlipay ? '支付宝' : '微信支付');
}

double _amtOf(String s) =>
    double.tryParse(s.replaceAll(RegExp(r'[¥￥,，\s]'), '')) ?? 0;

/// '2026-08-03 12:01:59' / '2026-08-03 12:01' → (date, time)。
(String, String) _dtOf(String s) {
  final p = s.trim().split(RegExp(r'\s+'));
  final d = (p.isNotEmpty ? p[0] : '').replaceAll(RegExp(r'[./]'), '-');
  final t = p.length > 1 ? p[1] : '';
  return (d.length >= 10 ? d.substring(0, 10) : d,
      t.length >= 5 ? t.substring(0, 5) : t);
}

/// 平台账单 CSV 文本 → 结构化行；识别失败返回 null。
/// [skipNonSpend] 开时过滤「代付/转入/提现/账户互转/还款」类非消费流水。
BillParseResult? parseBillText(String text, {bool skipNonSpend = true}) {
  final lines = const LineSplitter().convert(text);
  Map<String, int>? col;
  String? platform;
  final rows = <BillRow>[];
  var skipped = 0;
  for (final line in lines) {
    if (line.trim().isEmpty) continue;
    final cells = splitCsvLine(line);
    final det = _detect(cells);
    if (det != null) {
      col = det.$1;
      platform = det.$2;
      continue;
    }
    final cmap = col;
    final plat = platform;
    if (cmap == null || plat == null) continue; // 表头前的说明行
    final alipay = plat == '支付宝';
    String at(String name) {
      final i = cmap[name];
      return i == null || i >= cells.length ? '' : cells[i];
    }

    final (date, time) = _dtOf(at('交易时间'));
    if (date.isEmpty) continue;
    final amt = _amtOf(alipay ? at('金额') : at('金额(元)'));
    final flow = at('收/支');
    final counterparty = at('交易对方');
    final product = alipay ? at('商品说明') : at('商品');
    final rawCat = alipay ? at('交易分类') : at('交易类型');
    final status = alipay ? at('交易状态') : at('当前状态');
    var payM = alipay
        ? (at('收/付款方式').isNotEmpty ? at('收/付款方式') : at('付款方式'))
        : at('支付方式');
    // 支付宝「收/付款方式」常把主账户与活动/优惠用 & 拼接（如
    // 「招商银行信用卡(8663)&遇财神立减」「建设银行储蓄卡(1585)&建设银行立减金」），
    // 取 & 前的主账户，避免每个活动裂成一个新账户。
    payM = payM.split('&').first.trim();
    final tradeNo = alipay ? at('交易订单号') : at('交易单号');
    final isRefund = status.contains('退款') ||
        rawCat.contains('退款') ||
        counterparty.contains('退款') ||
        flow == '退款';
    if (!isRefund && skipNonSpend && _isNonSpend(rawCat, product, payM)) {
      skipped++;
      continue;
    }
    if (!isRefund && flow != '收入' && flow != '支出' && flow != '退款') {
      // 不计收支（理财转出转入等）不进账单。
      skipped++;
      continue;
    }
    if (amt <= 0 && !isRefund) {
      skipped++;
      continue;
    }
    rows.add(BillRow(
      date: date,
      time: time,
      counterparty: counterparty,
      product: product,
      amt: amt,
      isIncome: !isRefund && flow == '收入',
      isRefund: isRefund,
      payMethod: (payM.isEmpty || payM == '/') ? '未指定' : payM,
      tradeNo: tradeNo.trim(),
      rawCat: rawCat,
      status: status,
    ));
  }
  if (platform == null) {
    // 表头认不出＝这批一行都进不来，必须留痕（真机「导入无反应」类反馈看这里）。
    AppLog.add('账单解析：${lines.length} 行里未识别到支付宝/微信表头',
        level: LhLevel.warn);
    return null;
  }
  AppLog.addKey('账单解析：平台 $platform · 有效 ${rows.length} 条 · '
      '规则过滤 $skipped 条（共 ${lines.length} 行）');
  return BillParseResult(platform: platform, rows: rows, skipped: skipped);
}

bool _isNonSpend(String rawCat, String product, String payM) {
  const bad = ['代付', '转入', '转出', '提现', '充值', '还款', '账户', '中性'];
  final s = '$rawCat$product';
  return bad.any(s.contains);
}

/// 付款方式文本 → 账户类型推断（§3 导入账户建型口径）。
String guessAcctType(String payMethod) {
  final s = payMethod;
  if (s.contains('花呗') || s.contains('信用') || s.contains('透支')) {
    return 'credit';
  }
  if (s.contains('储蓄卡') || s.contains('借记卡') || RegExp(r'\(\d{4}\)').hasMatch(s)) {
    return 'debit';
  }
  if (s.contains('余额宝') || s.contains('零钱通') || s.contains('基金') || s.contains('理财')) {
    return 'invest';
  }
  if (s.contains('现金')) return 'cash';
  return 'ewallet'; // 余额/零钱等
}

/// 「付款方式」列聚合出的账户清单（步骤3 · 含收入到账方式，按笔数降序）。
/// 元素 = (付款方式原文, 笔数, 推断账户类型)。
List<(String, int, String)> aggBillAccounts(List<BillRow> rows) {
  final cnt = <String, int>{};
  for (final r in rows) {
    cnt[r.payMethod] = (cnt[r.payMethod] ?? 0) + 1;
  }
  final out = <(String, int, String)>[
    for (final e in cnt.entries) (e.key, e.value, guessAcctType(e.key)),
  ];
  out.sort((a, b) => b.$2.compareTo(a.$2));
  return out;
}

/// 分类自动映射（九·补4 步骤4「92% 命中 · 其余进其他可改」的命中层）：
/// 交易分类/类型原文 + 商品关键词 → 大类 id。
int mapBillCat(BillRow r) {
  if (r.isIncome) {
    final s = '${r.rawCat}${r.product}${r.counterparty}';
    if (s.contains('工资') || s.contains('薪酬')) return 201;
    if (s.contains('奖金') || s.contains('绩效')) return 202;
    if (s.contains('利息') || s.contains('收益') || s.contains('赎回')) {
      return 204;
    }
    if (s.contains('报销')) return 205;
    if (s.contains('红包')) return 206;
    return 207;
  }
  final s = '${r.rawCat}${r.product}';
  if (s.contains('餐饮') || s.contains('美食') || s.contains('外卖') || s.contains('餐') || s.contains('饮品') || s.contains('奶茶') || s.contains('咖啡') || s.contains('茶')) return 101;
  if (s.contains('交通') || s.contains('出行') || s.contains('打车') || s.contains('地铁') || s.contains('加油')) return 102;
  if (s.contains('购物') || s.contains('数码') || s.contains('服饰') || s.contains('日用') || s.contains('美妆') || s.contains('超市')) return 103;
  if (s.contains('住房') || s.contains('物业') || s.contains('水电') || s.contains('燃气') || s.contains('房租')) return 104;
  if (s.contains('娱乐') || s.contains('休闲') || s.contains('电影') || s.contains('游戏')) return 105;
  if (s.contains('运动') || s.contains('健身')) return 106;
  if (s.contains('教育') || s.contains('培训') || s.contains('书')) return 107;
  if (s.contains('医疗') || s.contains('健康') || s.contains('药')) return 108;
  if (s.contains('旅行') || s.contains('旅游') || s.contains('酒店') || s.contains('门票')) return 109;
  if (s.contains('人情') || s.contains('转账') || s.contains('红包') || s.contains('礼物')) return 110;
  if (s.contains('通讯') || s.contains('话费') || s.contains('流量') || s.contains('网络')) return 111;
  if (s.contains('宠物')) return 112;
  if (s.contains('订阅') || s.contains('会员') || s.contains('自动续费')) return 113;
  return 114;
}

/// Excel 1900 日期系统序列号 → DateTime（epoch 1899-12-30）。
DateTime excelSerialToDateTime(num serial) => DateTime(1899, 12, 30)
    .add(Duration(microseconds: (serial * 86400 * 1e6).round()));

/// 从账单文件字节解析（V1.51 文件式导入）。自动识别：
/// - `PK`(zip) → xlsx：spreadsheet_decoder 读表 + 归一化「交易时间」日期序列号，
///   再拼回 CSV 文本走 [parseBillText]（复用列映射/去重/过滤口径）；
/// - 其余 → csv：GBK / UTF-8(含 BOM) 解码后走 [parseBillText]。
/// 识别失败返回 null。
BillParseResult? parseBillFile(List<int> bytes, {bool skipNonSpend = true}) {
  if (bytes.length >= 2 && bytes[0] == 0x50 && bytes[1] == 0x4B) {
    return _parseXlsx(bytes, skipNonSpend: skipNonSpend);
  }
  return parseBillText(_decodeCsv(bytes), skipNonSpend: skipNonSpend);
}

/// csv 字节解码：UTF-8 BOM → 去 BOM；否则 UTF-8 严格优先、GBK 兜底
/// （GBK 几乎接受任意字节对不抛异常，故必须先试 UTF-8，否则 UTF-8 文件会被解成乱码）。
String _decodeCsv(List<int> bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return utf8.decode(bytes.sublist(3));
  }
  try {
    return utf8.decode(bytes);
  } catch (e) {
    // 支付宝/微信 CSV 多为 GBK：utf8 严格解码失败属常态路径，记 warn 供复盘。
    AppLog.add('账单 CSV utf8 解码失败，改按 GBK 重试：$e', level: LhLevel.warn);
    try {
      return gbk.decode(bytes);
    } catch (e2) {
      AppLog.add('账单 CSV utf8/GBK 均失败，容错解码（可能出乱码行）：$e2',
          level: LhLevel.warn);
      return utf8.decode(bytes, allowMalformed: true);
    }
  }
}

BillParseResult? _parseXlsx(List<int> bytes, {bool skipNonSpend = true}) {
  final SpreadsheetDecoder dec;
  try {
    dec = SpreadsheetDecoder.decodeBytes(bytes);
  } catch (e) {
    AppLog.add('账单 xlsx 解包失败（不是有效 Excel 容器）：$e',
        level: LhLevel.error);
    return null;
  }
  final sheet = dec.tables.values.isEmpty ? null : dec.tables.values.first;
  if (sheet == null) {
    AppLog.add('账单 xlsx 里没有可用工作表', level: LhLevel.warn);
    return null;
  }
  final rows = sheet.rows;
  int hdr = -1;
  for (var i = 0; i < rows.length && i < 40; i++) {
    if (rows[i].any((c) => (c?.toString() ?? '').trim() == '交易时间')) {
      hdr = i;
      break;
    }
  }
  if (hdr < 0) return null;
  final header = rows[hdr].map((c) => (c?.toString() ?? '').trim()).toList();
  final dtCol = header.indexOf('交易时间');
  final sb = StringBuffer();
  sb.writeln(header.map(_csvCell).join(','));
  for (var i = hdr + 1; i < rows.length; i++) {
    final r = rows[i];
    final cells = <String>[];
    for (var c = 0; c < header.length; c++) {
      var s = (c < r.length ? r[c]?.toString() : '') ?? '';
      if (c == dtCol) s = _normExcelDate(s);
      cells.add(_csvCell(s));
    }
    sb.writeln(cells.join(','));
  }
  return parseBillText(sb.toString(), skipNonSpend: skipNonSpend);
}

String _csvCell(String s) =>
    (s.contains(',') || s.contains('"')) ? '"${s.replaceAll('"', '""')}"' : s;

/// 交易时间列：Excel 数字序列号 → 'yyyy-MM-dd HH:mm:ss'；已是文本则原样。
String _normExcelDate(String raw) {
  final n = double.tryParse(raw.trim());
  if (n == null) return raw;
  final dt = excelSerialToDateTime(n);
  String two(int x) => x.toString().padLeft(2, '0');
  return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
      '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
}
