import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/features/calendar/domain/cal_event.dart';
import 'package:lifeharness/features/calendar/presentation/calendar_page.dart';

/// F2-1/C1（时间模块批1 · 冻结口径）同日多态圆点优先级：
/// **计时中 > 计划中 > 已完成**（line 30 旧表述「计时中>完成>计划」作废）。
/// 三态混合取最高；用例逐一覆盖两两混合与三态全混合。
void main() {
  const accent = Color(0xFF6366F1);
  const red = Color(0xFFF43F5E);
  const green = Color(0xFF34D399);
  final d = DateTime(2026, 9, 19);

  CalEvent ev(EventStatus s) => CalEvent(title: 'e', start: d, status: s);

  test('单态：进行中红 / 计划中主题色 / 已完成绿 / 无事件 null', () {
    expect(CalendarPage.dotColorFor([ev(EventStatus.active)], accent), red);
    expect(CalendarPage.dotColorFor([ev(EventStatus.planning)], accent), accent);
    expect(CalendarPage.dotColorFor([ev(EventStatus.done)], accent), green);
    expect(CalendarPage.dotColorFor([], accent), isNull);
  });

  test('两两混合取高：计划压完成 · 进行压计划 · 进行压完成（C1）', () {
    expect(
        CalendarPage.dotColorFor([ev(EventStatus.done), ev(EventStatus.planning)], accent),
        accent);
    expect(
        CalendarPage.dotColorFor([ev(EventStatus.planning), ev(EventStatus.active)], accent),
        red);
    expect(
        CalendarPage.dotColorFor([ev(EventStatus.done), ev(EventStatus.active)], accent),
        red);
  });

  test('三态全混合取最高=计时中红（C1 用例主判据）', () {
    expect(
        CalendarPage.dotColorFor(
            [ev(EventStatus.done), ev(EventStatus.planning), ev(EventStatus.active)],
            accent),
        red);
  });

  test('计划中优先级高于已完成：仅含完成+计划的日子不得判绿（旧 line30 口径回归护栏）',
      () {
    final c = CalendarPage.dotColorFor([ev(EventStatus.done), ev(EventStatus.planning)], accent);
    expect(c, isNot(green));
  });
}
