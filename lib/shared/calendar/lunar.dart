/// 农历换算（1900–2100 标准历表 · 公历↔农历互转）。
///
/// 需求 V1.42 模块11：「每年（农历）· 自动逐年换算公历」。工程无农历依赖，
/// 且应用离线红线禁网络请求，故以经典压缩历表纯 Dart 实现。
/// 治理 V1.47 批0：自 `features/days/domain/` 提升至 `shared/calendar/`——
/// 日子（每年农历重复）与小工具「日期计算」两处共用一份历表，守架构红线 R1
/// （feature 不得互相 import；跨模块共用能力一律经 `shared/`，照 weather 先例）。
/// 表格式：每项 17 bit——低 4 位=闰几月（0 无闰），bit4–15=正月…腊月大小月
/// （1=30 天 0=29 天），bit16=闰月是否 30 天。
/// 回归锚点（test/days_lunar_test.dart）：春节 2023-01-22 / 2024-02-10 /
/// 2025-01-29 / 2026-02-17 / 2027-02-06；中秋 2024-09-17 / 2025-10-06 /
/// 2026-09-25；闰月 2023 闰二、2025 闰六、2028 闰五。
library;

/// 农历日期（month 1~12；isLeap=是否闰月；day 1~30）。
class LunarDate {
  const LunarDate(this.year, this.month, this.day, {this.isLeap = false});

  final int year;
  final int month;
  final int day;
  final bool isLeap;

  /// 中文串（如「闰六月」「八月廿七」「腊月初一」）。
  String get monthName => '${isLeap ? '闰' : ''}${_monthNames[month - 1]}';
  String get dayName => _dayNames[day - 1];

  @override
  String toString() => '$monthName$dayName';

  @override
  bool operator ==(Object other) =>
      other is LunarDate &&
      other.year == year &&
      other.month == month &&
      other.day == day &&
      other.isLeap == isLeap;

  @override
  int get hashCode => Object.hash(year, month, day, isLeap);
}

const _monthNames = [
  '正月', '二月', '三月', '四月', '五月', '六月',
  '七月', '八月', '九月', '十月', '冬月', '腊月'
];

const _dayNames = [
  '初一', '初二', '初三', '初四', '初五', '初六', '初七', '初八', '初九', '初十',
  '十一', '十二', '十三', '十四', '十五', '十六', '十七', '十八', '十九', '二十',
  '廿一', '廿二', '廿三', '廿四', '廿五', '廿六', '廿七', '廿八', '廿九', '三十'
];

/// 农历年份越出历表（1900–2100）时抛出的错误。
RangeError lunarRangeError(int year) => RangeError.range(
    year, 1900, 2100, '农历年份', '农历年份越出历表 1900–2100');

int _leapMonth(int y) => _lunarInfo[y - 1900] & 0xf;

int _leapDays(int y) {
  if (_leapMonth(y) == 0) return 0;
  return (_lunarInfo[y - 1900] & 0x10000) != 0 ? 30 : 29;
}

/// 平月 month（1~12）天数。
int lunarMonthDays(int y, int month) =>
    ((_lunarInfo[y - 1900] >> (16 - month)) & 0x1) != 0 ? 30 : 29;

/// 农历年总天数（含闰月）。
int lunarYearDays(int y) {
  var sum = 348; // 12 * 29
  for (var i = 0x8000; i > 0x8; i >>= 1) {
    if ((_lunarInfo[y - 1900] & i) != 0) sum++;
  }
  return sum + _leapDays(y);
}

final DateTime _base = DateTime(1900, 1, 31); // 农历 1900 正月初一

/// 公历 → 农历（时间部分忽略，按自然日）。
LunarDate solarToLunar(DateTime solar) {
  final d = DateTime(solar.year, solar.month, solar.day);
  var offset = d.difference(_base).inDays;
  if (offset < 0) throw lunarRangeError(d.year - 1);
  var year = 1900;
  while (year <= 2100) {
    final days = lunarYearDays(year);
    if (offset < days) break;
    offset -= days;
    year++;
  }
  if (year > 2100) throw lunarRangeError(year);
  final leap = _leapMonth(year);
  var isLeap = false;
  var month = 1;
  for (; month <= 12; month++) {
    // 闰月排在同名平月之后
    final cur = isLeap ? _leapDays(year) : lunarMonthDays(year, month);
    if (offset < cur) break;
    offset -= cur;
    if (leap != 0 && month == leap && !isLeap) {
      isLeap = true;
      month--; // 下一轮循环重新处理同月号的闰月
    } else {
      isLeap = false;
    }
  }
  return LunarDate(year, month, offset + 1, isLeap: isLeap);
}

/// 农历 → 公历。带闰歧义时（源数据只存月/日号，如「八月廿七」）优先取**平月**，
/// 该年此月无平月同名者（历史数据）才取闰月。
DateTime lunarToSolar(int year, int month, int day) {
  final leap = _leapMonth(year);
  // 先数到目标平月月初
  var offset = 0;
  for (var m = 1; m < month; m++) {
    offset += lunarMonthDays(year, m);
    if (leap == m) offset += _leapDays(year);
  }
  // 目标月本身：平月优先；平月天数容不下 day 且该年恰有同号闰月时顺延闰月
  final plain = lunarMonthDays(year, month);
  var isLeap = false;
  if (day > plain && leap == month) {
    offset += plain;
    isLeap = true;
  } else if (plain == 0 && leap == month) {
    isLeap = true;
  }
  final inMonth = day > (isLeap ? _leapDays(year) : plain)
      ? (isLeap ? _leapDays(year) : plain)
      : day; // 三十不存在时收敛到当月末
  offset += inMonth - 1;
  // 加回 year 年初相对 base 的偏移
  var daysBefore = 0;
  for (var y = 1900; y < year; y++) {
    daysBefore += lunarYearDays(y);
  }
  return _base.add(Duration(days: daysBefore + offset));
}

/// 农历某月/日在公历 year 年的日期（平月优先，自动逐年换算用；year 越界返回 null）。
DateTime? lunarToSolarInYear(int year, int month, int day) {
  if (year < 1900 || year > 2100) return null;
  try {
    return lunarToSolar(year, month, day);
  } catch (_) {
    return null;
  }
}

/// 月/日号 → 中文（滚轮选择与标签展示共用）。
String lunarLabel(int month, int day) =>
    '${_monthNames[month - 1]}${_dayNames[day - 1]}';

const List<int> _lunarInfo = [
  0x04bd8, 0x04ae0, 0x0a570, 0x054d5, 0x0d260, 0x0d950, 0x16554, 0x056a0,
  0x09ad0, 0x055d2, // 1900–1909
  0x04ae0, 0x0a5b6, 0x0a4d0, 0x0d250, 0x1d255, 0x0b540, 0x0d6a0, 0x0ada2,
  0x095b0, 0x14977, // 1910–1919
  0x04970, 0x0a4b0, 0x0b4b5, 0x06a50, 0x06d40, 0x1ab54, 0x02b60, 0x09570,
  0x052f2, 0x04970, // 1920–1929
  0x06566, 0x0d4a0, 0x0ea50, 0x06e95, 0x05ad0, 0x02b60, 0x186e3, 0x092e0,
  0x1c8d7, 0x0c950, // 1930–1939
  0x0d4a0, 0x1d8a6, 0x0b550, 0x056a0, 0x1a5b4, 0x025d0, 0x092d0, 0x0d2b2,
  0x0a950, 0x0b557, // 1940–1949
  0x06ca0, 0x0b550, 0x15355, 0x04da0, 0x0a5b0, 0x14573, 0x052b0, 0x0a9a8,
  0x0e950, 0x06aa0, // 1950–1959
  0x0aea6, 0x0ab50, 0x04b60, 0x0aae4, 0x0a570, 0x05260, 0x0f263, 0x0d950,
  0x05b57, 0x056a0, // 1960–1969
  0x096d0, 0x04dd5, 0x04ad0, 0x0a4d0, 0x0d4d4, 0x0d250, 0x0d558, 0x0b540,
  0x0b6a0, 0x195a6, // 1970–1979
  0x095b0, 0x049b0, 0x0a974, 0x0a4b0, 0x0b27a, 0x06a50, 0x06d40, 0x0af46,
  0x0ab60, 0x09570, // 1980–1989
  0x04af5, 0x04970, 0x064b0, 0x074a3, 0x0ea50, 0x06b58, 0x055c0, 0x0ab60,
  0x096d5, 0x092e0, // 1990–1999
  0x0c960, 0x0d954, 0x0d4a0, 0x0da50, 0x07552, 0x056a0, 0x0abb7, 0x025d0,
  0x092d0, 0x0cab5, // 2000–2009
  0x0a950, 0x0b4a0, 0x0baa4, 0x0ad50, 0x055d9, 0x04ba0, 0x0a5b0, 0x15176,
  0x052b0, 0x0a930, // 2010–2019
  0x07954, 0x06aa0, 0x0ad50, 0x05b52, 0x04b60, 0x0a6e6, 0x0a4e0, 0x0d260,
  0x0ea65, 0x0d530, // 2020–2029
  0x05aa0, 0x076a3, 0x096d0, 0x04afb, 0x04ad0, 0x0a4d0, 0x1d0b6, 0x0d250,
  0x0d520, 0x0dd45, // 2030–2039
  0x0b5a0, 0x056d0, 0x055b2, 0x049b0, 0x0a577, 0x0a4b0, 0x0aa50, 0x1b255,
  0x06d20, 0x0ada0, // 2040–2049
  0x14b63, 0x09370, 0x049f8, 0x04970, 0x064b0, 0x168a6, 0x0ea50, 0x06b20,
  0x1a6c4, 0x0aae0, // 2050–2059
  0x0a2e0, 0x0d2e3, 0x0c960, 0x0d557, 0x0d4a0, 0x0da50, 0x05d55, 0x056a0,
  0x0a6d0, 0x055d4, // 2060–2069
  0x052d0, 0x0a9b8, 0x0a950, 0x0b4a0, 0x0b6a6, 0x0ad50, 0x055a0, 0x0aba4,
  0x0a5b0, 0x052b0, // 2070–2079
  0x0b273, 0x06930, 0x07337, 0x06aa0, 0x0ad50, 0x14b55, 0x04b60, 0x0a570,
  0x054e4, 0x0d160, // 2080–2089
  0x0e968, 0x0d520, 0x0daa0, 0x16aa6, 0x056d0, 0x04ae0, 0x0a9d4, 0x0a2d0,
  0x0d150, 0x0f252, // 2090–2099
  0x0d520, // 2100
];
