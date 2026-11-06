/// ICS 单向导出（RFC5545 子集）· 竞品补全清单 C04 · 批1 子批 A。
///
/// 纯序列化：不碰 DAO、不写文件、不发网络。调用方把日程/时间块/待办/重要日子
/// 映射成 [IcsItem] 即可；落盘与入口属子批 B（须过原型门）。
/// 口径：只做**导出**，不做 CalDAV / ICS 导入（后者会破零网络白名单，见补全清单 X09）。
library;

import '../../../shared/calendar/lunar.dart';

enum IcsRepeat { none, daily, weekly, monthly, solarYear, lunarYear }

class IcsItem {
  const IcsItem({
    required this.uid,
    required this.title,
    required this.start,
    this.end,
    this.note,
    this.location,
    this.repeat = IcsRepeat.none,
    this.lunarMonth,
    this.lunarDay,
    this.todo = false,
    this.done = false,
  });

  final String uid;
  final String title;
  final DateTime start;
  final DateTime? end;
  final String? note;
  final String? location;
  final IcsRepeat repeat;

  /// [IcsRepeat.lunarYear] 时的农历月日；缺失则该项跳过农历展开。
  final int? lunarMonth;
  final int? lunarDay;

  /// true → 输出 VTODO（待办），false → VEVENT。
  final bool todo;

  /// 子批B：已完成待办 → `STATUS:COMPLETED`（未完成为 NEEDS-ACTION）。
  final bool done;
}

String _two(int n) => n.toString().padLeft(2, '0');

String _stamp(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}${_two(d.month)}${_two(d.day)}'
    'T${_two(d.hour)}${_two(d.minute)}${_two(d.second)}';

/// RFC5545 TEXT 转义：反斜杠、分号、逗号、换行。
String _esc(String s) => s
    .replaceAll('\\', r'\\')
    .replaceAll(';', r'\;')
    .replaceAll(',', r'\,')
    .replaceAll('\r\n', r'\n')
    .replaceAll('\n', r'\n');

String? _rrule(IcsRepeat r) => switch (r) {
      IcsRepeat.daily => 'FREQ=DAILY',
      IcsRepeat.weekly => 'FREQ=WEEKLY',
      IcsRepeat.monthly => 'FREQ=MONTHLY',
      IcsRepeat.solarYear => 'FREQ=YEARLY',
      _ => null,
    };

/// 农历重复没有等价 RRULE（农历月日与公历不一一对应），改为逐年展开实例。
/// 每个实例是独立 VEVENT（UID 带年份后缀），能被系统日历/Thunderbird 直接读。
List<DateTime> lunarInstances(
  IcsItem item, {
  required DateTime now,
  int horizonYears = 3,
}) {
  final m = item.lunarMonth, d = item.lunarDay;
  if (item.repeat != IcsRepeat.lunarYear || m == null || d == null) {
    return <DateTime>[];
  }
  final out = <DateTime>[];
  for (var y = now.year; y < now.year + horizonYears; y++) {
    final solar = lunarToSolarInYear(y, m, d);
    if (solar != null) {
      out.add(DateTime(solar.year, solar.month, solar.day,
          item.start.hour, item.start.minute, item.start.second));
    }
  }
  return out;
}

/// 生成 .ics 全文（行尾 CRLF，符合 RFC5545）。
String buildIcs(
  List<IcsItem> items, {
  required DateTime now,
  String calendarName = 'LifeHarness',
  int horizonYears = 3,
}) {
  final lines = <String>[
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//LifeHarness//Calendar Export//ZH',
    'CALSCALE:GREGORIAN',
    'X-WR-CALNAME:${_esc(calendarName)}',
  ];
  final dtstamp = '${_stamp(now.toUtc())}Z';

  void emit(IcsItem e, DateTime start, {String? uidSuffix, String? rrule}) {
    final uid = '${e.uid}${uidSuffix ?? ''}@lifeharness.local';
    lines.add(e.todo ? 'BEGIN:VTODO' : 'BEGIN:VEVENT');
    lines.add('UID:$uid');
    lines.add('DTSTAMP:$dtstamp');
    lines.add('DTSTART:${_stamp(start)}');
    if (!e.todo) {
      lines.add('DTEND:${_stamp(e.end ?? start.add(const Duration(hours: 1)))}');
    }
    lines.add('SUMMARY:${_esc(e.title)}');
    if (e.note != null && e.note!.trim().isNotEmpty) {
      lines.add('DESCRIPTION:${_esc(e.note!)}');
    }
    if (e.location != null && e.location!.trim().isNotEmpty) {
      lines.add('LOCATION:${_esc(e.location!)}');
    }
    if (rrule != null) lines.add('RRULE:$rrule');
    if (e.todo) lines.add(e.done ? 'STATUS:COMPLETED' : 'STATUS:NEEDS-ACTION');
    lines.add(e.todo ? 'END:VTODO' : 'END:VEVENT');
  }

  for (final e in items) {
    if (e.repeat == IcsRepeat.lunarYear) {
      for (final dt in lunarInstances(e, now: now, horizonYears: horizonYears)) {
        emit(e, dt, uidSuffix: '-${dt.year}');
      }
      continue;
    }
    emit(e, e.start, rrule: _rrule(e.repeat));
  }
  lines.add('END:VCALENDAR');
  return '${lines.join('\r\n')}\r\n';
}
