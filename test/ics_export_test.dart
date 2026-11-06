import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/features/calendar/domain/ics_export.dart';

final _now = DateTime(2026, 11, 6, 9, 0);

IcsItem _item({
  String uid = 'e1',
  String title = '复盘会',
  IcsRepeat repeat = IcsRepeat.none,
  bool todo = false,
  int? lunarMonth,
  int? lunarDay,
  String? note,
}) =>
    IcsItem(
      uid: uid,
      title: title,
      start: DateTime(2026, 11, 7, 14, 0),
      end: DateTime(2026, 11, 7, 15, 30),
      repeat: repeat,
      todo: todo,
      lunarMonth: lunarMonth,
      lunarDay: lunarDay,
      note: note,
    );

void main() {
  group('C04 ICS 序列化', () {
    test('单事件 VEVENT 字段齐、行尾 CRLF', () {
      final ics = buildIcs([_item(note: '带,分号;和反斜杠\\')], now: _now);
      expect(ics, contains('BEGIN:VCALENDAR'));
      expect(ics, contains('BEGIN:VEVENT'));
      expect(ics, contains('UID:e1@lifeharness.local'));
      expect(ics, contains('DTSTART:20261107T140000'));
      expect(ics, contains('DTEND:20261107T153000'));
      expect(ics, contains('SUMMARY:复盘会'));
      expect(ics, contains(r'DESCRIPTION:带\,分号\;和反斜杠\\'));
      expect(ics, endsWith('END:VCALENDAR\r\n'));
      expect(ics, isNot(contains('BEGIN:VEVENT\n')));
    });

    test('公历每年重复出 RRULE，待办出 VTODO', () {
      final ics = buildIcs([
        _item(repeat: IcsRepeat.solarYear),
        _item(uid: 't1', title: '交报表', todo: true),
      ], now: _now);
      expect(ics, contains('RRULE:FREQ=YEARLY'));
      expect(ics, contains('BEGIN:VTODO'));
      expect(ics, contains('STATUS:NEEDS-ACTION'));
      expect(ics.indexOf('BEGIN:VTODO'), greaterThan(ics.indexOf('BEGIN:VEVENT')));
    });

    test('农历重复无 RRULE，逐年展开成不同公历实例', () {
      final item = _item(repeat: IcsRepeat.lunarYear, lunarMonth: 1, lunarDay: 1);
      final ics = buildIcs([item], now: _now);
      final instances = lunarInstances(item, now: _now);
      expect(instances.length, 3, reason: '未来 3 年各一实例');
      expect(instances.map((d) => d.year).toSet().length, 3);
      expect(ics, isNot(contains('RRULE:FREQ=YEARLY')),
          reason: '农历不能用公历 YEARLY 规则糊弄');
      for (final d in instances) {
        expect(ics, contains('DTSTART:${d.year.toString().padLeft(4, '0')}'
            '${d.month.toString().padLeft(2, '0')}'
            '${d.day.toString().padLeft(2, '0')}T140000'));
      }
      expect('UID:e1-'.allMatches(ics).length, 3);
    });

    test('缺农历月日时跳过展开，不产空事件', () {
      final ics =
          buildIcs([_item(repeat: IcsRepeat.lunarYear)], now: _now);
      expect(ics, isNot(contains('BEGIN:VEVENT')));
    });
  });
}
