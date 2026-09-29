/// 小工具合集 · 日期计算域层（批2 · 原型 `dBoot` / `dCalcDiff` / `dCalcAdd` /
/// `dQuick` / `dFill` 同源，农历随日子模块引擎换算 = `shared/calendar/lunar.dart`）。
///
/// 时钟一律由参数注入（红线：用例禁时间炸弹，跨日窗口内也能稳定判定）。
library;

import '../../../shared/calendar/lunar.dart';

/// ISO 日期串（`YYYY-MM-DD`，原型 `iso`）。
String kitIsoDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// 解析 ISO 日期串（非法返回 null，对应原型 `isNaN` 分支）。
DateTime? kitParseIsoDate(String s) {
  final m = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(s.trim());
  if (m == null) return null;
  final y = int.parse(m.group(1)!), mo = int.parse(m.group(2)!), d = int.parse(m.group(3)!);
  if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
  try {
    return DateTime(y, mo, d);
  } catch (_) {
    return null;
  }
}

/// 周几中文（原型 `['日','一','二','三','四','五','六'][getDay()]`）。
String kitWeekdayLabel(DateTime d) =>
    const ['日', '一', '二', '三', '四', '五', '六'][d.weekday % 7];

/// 自然日差（b − a，先归一到零点，避免时分影响）。
int kitDayDiff(DateTime a, DateTime b) => DateTime(b.year, b.month, b.day)
    .difference(DateTime(a.year, a.month, a.day))
    .inDays;

/// 农历串（超出 1900~2100 历表范围时留空，不影响主文案）。
String kitLunarLabel(DateTime d) {
  try {
    return solarToLunar(d).toString();
  } catch (_) {
    return '';
  }
}

/// ① 两日期间隔文案（原型 `dCalcDiff`：「相差 N 天 ≈ X 周 · Y 个月 · 目标在后」）。
String kitDateDiffText(DateTime a, DateTime b) {
  final d = kitDayDiff(a, b);
  final ad = d.abs();
  final tail = d == 0 ? '（同一天）' : (d > 0 ? '目标在后' : '目标在前');
  return '相差 $ad 天 ≈ ${(ad / 7).toStringAsFixed(1)} 周 · '
      '${(ad / 30.44).toStringAsFixed(1)} 个月 · $tail';
}

/// ② 日期 ± 天数的结果。
class KitDateAddResult {
  const KitDateAddResult({
    required this.date,
    required this.offsetDays,
  });

  final DateTime date;

  /// 带符号偏移（正=往后，负=往前）。
  final int offsetDays;

  bool get isWeekend => date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;

  /// 界面主文案（原型 `dAdd`）。
  String get label =>
      '${kitIsoDate(date)} · 周${kitWeekdayLabel(date)}'
      '（${offsetDays > 0 ? '$offsetDays 天后' : '往前 ${-offsetDays} 天'}）'
      '${isWeekend ? ' · 落在周末' : ''}';

  /// 分享/复制串（原型 `KIT_SHARE_TXT`）。
  String shareFrom(DateTime from) =>
      '${kitIsoDate(from)} ${offsetDays > 0 ? '+' : '−'}${offsetDays.abs()} → ${kitIsoDate(date)}';

  /// 农历副文案（原型「农历随日子模块引擎换算」）。
  String get lunar => kitLunarLabel(date);
}

KitDateAddResult? kitDateAdd(DateTime from, int signedDays) {
  if (signedDays == 0) return null;
  final b = DateTime(from.year, from.month, from.day).add(Duration(days: signedDays));
  return KitDateAddResult(date: b, offsetDays: signedDays);
}

/// ③ 今天速览（原型 `dQuick`：已过天数 / 剩余天数 / 百分比 / 距元旦）。
String kitTodayQuick(DateTime now) {
  final y = DateTime(now.year, 12, 31);
  final rest = kitDayDiff(now, y);
  final days = kitDayDiff(DateTime(now.year, 1, 1), now) + 1;
  final pct = (days / 365 * 100).toStringAsFixed(1);
  return '今天是 ${kitIsoDate(now)} · 周${kitWeekdayLabel(now)}\n'
      '今年已过 $days 天 · 剩余 $rest 天（$pct%）· 距元旦 ${rest + 1} 天';
}

/// 快捷锚点（原型 `dFill` 的四种 kind）。
enum KitDateAnchor {
  today('今天'),
  newYear('元旦'),
  spring('春节'),
  christmas('圣诞');

  const KitDateAnchor(this.label);

  final String label;
}

/// 快捷锚点日期（元旦取「下一个元旦」；春节按历表取下一个农历正月初一，
/// 超出 1900~2100 范围回落次年春节常见日；圣诞取下一个 12-25）。
DateTime kitAnchorDate(KitDateAnchor kind, DateTime now) {
  switch (kind) {
    case KitDateAnchor.today:
      return DateTime(now.year, now.month, now.day);
    case KitDateAnchor.newYear:
      final thisNy = DateTime(now.year, 1, 1);
      return now.isAfter(thisNy) ? DateTime(now.year + 1, 1, 1) : thisNy;
    case KitDateAnchor.spring:
      for (var y = now.year; y <= now.year + 1; y++) {
        try {
          final d = lunarToSolar(y, 1, 1);
          if (!d.isBefore(DateTime(now.year, now.month, now.day))) return d;
        } catch (_) {
          return DateTime(now.year + 1, 2, 17);
        }
      }
      return DateTime(now.year + 1, 2, 17);
    case KitDateAnchor.christmas:
      final xmas = DateTime(now.year, 12, 25);
      return kitDayDiff(now, xmas) < 0 ? DateTime(now.year + 1, 12, 25) : xmas;
  }
}

/// 间隔结果 + 双端农历（②区结果卡副文案用）。
String kitDateDiffLunarText(DateTime a, DateTime b) =>
    '${kitIsoDate(a)}（${kitLunarLabel(a)}）→ ${kitIsoDate(b)}（${kitLunarLabel(b)}）';
