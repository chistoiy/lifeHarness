import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/features/journal/domain/journal_entry.dart';
import 'package:lifeharness/features/journal/presentation/widgets/journal_wall.dart';

/// 日记改版批1a · 月历图墙**画面级**（工单 §1 执行面板「新增常驻」第三件）。
///
/// 纯逻辑（三态次序 / 7 倍数格数 / 月界偏移）在 `journal_view_mode_test.dart`；
/// 这里钉画面：7 列表头、无日记日不出格、有日记日实心、有图日带角标、点格回调日号。

JournalEntry _e(int day, {bool img = false, int? mood}) => JournalEntry(
      day: DateTime(2026, 10, day),
      mood: mood,
      content: img ? '有图\n\n![](file:///nope/x.jpg)' : '正文',
      createdAt: DateTime(2026, 10, day, 9, 30),
      updatedAt: DateTime(2026, 10, day, 9, 30),
    );

Future<void> _pumpWall(
  WidgetTester tester,
  Map<int, JournalEntry> byDay, {
  void Function(int)? onTap,
  DateTime? month,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: JournalWall(
          month: month ?? DateTime(2026, 10),
          byDayFirst: byDay,
          moodColorOf: (_) => const Color(0xFF6366F1),
          onTapDay: onTap ?? (_) {},
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('月历图墙渲染', () {
    testWidgets('V1 表头七个字齐全（周一开头）', (tester) async {
      await _pumpWall(tester, const {});
      for (final w in const ['一', '二', '三', '四', '五', '六', '日']) {
        expect(find.text(w), findsOneWidget, reason: '缺表头 $w');
      }
    });

    testWidgets('V2 2026-10（1 号周四）：1 号前四格空、31 天齐全', (tester) async {
      await _pumpWall(tester, const {});
      // 10 月 1 日是周四 ⇒ 周一起算偏移 3，前面三个空位不出格
      expect(find.byKey(const ValueKey('wall-day-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('wall-day-31')), findsOneWidget);
      // 1 号之前不存在「0 号」这种格
      expect(find.byKey(const ValueKey('wall-day-0')), findsNothing);
      expect(find.byKey(const ValueKey('wall-day-32')), findsNothing);
    });

    testWidgets('V3 写过但无图＝实心，没写＝不实心', (tester) async {
      await _pumpWall(tester, {5: _e(5)});
      Color? fillOf(String k) {
        final c = tester.widget<Container>(
          find.descendant(
            of: find.byKey(ValueKey(k)),
            matching: find.byType(Container),
          ),
        );
        return (c.decoration as BoxDecoration?)?.color;
      }

      expect(fillOf('wall-day-5'), isNotNull, reason: '写过那天要实心');
      expect(fillOf('wall-day-6'), isNull, reason: '没写那天不能实心');
    });

    testWidgets('V4 有图日多一枚右上角标（且与实心不互斥）', (tester) async {
      await _pumpWall(tester, {
        5: _e(5),
        6: _e(6, img: true),
      });
      final badge = find.byIcon(Icons.image_outlined);
      expect(badge, findsOneWidget, reason: '只有有图那格出角标');
      // 用「角标中心落在 6 号格矩形内」判定，别用距离阈值——格子只有 34×34、
      // 七等分后宽度约 34，任何像素阈值都很容易被分辨率改动弄红。
      final cell = tester.getRect(find.byKey(const ValueKey('wall-day-6')));
      final at = tester.getCenter(badge);
      expect(cell.contains(at), isTrue, reason: '角标应落在 6 号格内');
      expect(at.dx, greaterThan(cell.center.dx), reason: '角标应靠右');
      expect(at.dy, lessThan(cell.center.dy), reason: '角标应靠上');
    });

    testWidgets('V5 点格回调带日号（1~31，不是索引）', (tester) async {
      final tapped = <int>[];
      await _pumpWall(tester, {5: _e(5)}, onTap: tapped.add);
      await tester.tap(find.byKey(const ValueKey('wall-day-5')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('wall-day-20')));
      await tester.pumpAndSettle();
      expect(tapped, [5, 20]);
    });

    testWidgets('V6 空月份不抛异常（一行都没有的月份也要画出来）', (tester) async {
      await _pumpWall(tester, const {}, month: DateTime(2026, 2));
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('wall-day-28')), findsOneWidget);
      expect(find.byKey(const ValueKey('wall-day-29')), findsNothing);
    });

    testWidgets('V7 图例文案在位（不给说明用户猜不出实心含义）', (tester) async {
      await _pumpWall(tester, {5: _e(5)});
      expect(find.textContaining('实心＝当天写过'), findsOneWidget);
    });

    testWidgets('V8 标题显示年月（翻月后要知道自己在看哪个月）', (tester) async {
      await _pumpWall(tester, const {}, month: DateTime(2026, 10));
      expect(find.text('2026年10月'), findsOneWidget);
    });

    testWidgets('V9 不给 onMonthStep 时不出翻月钮（1a 旧调用点零改动）', (tester) async {
      await _pumpWall(tester, const {});
      expect(find.byKey(const ValueKey('wall-prev')), findsNothing);
      expect(find.byKey(const ValueKey('wall-next')), findsNothing);
    });

    testWidgets('V10 给了 onMonthStep：上一月可点、下一月可点（非本月时）', (tester) async {
      final steps = <int>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: JournalWall(
              // 用「上个月」当月面：下一月应当可点（还没回到本月）
              month: DateTime(2026, 9),
              byDayFirst: const {},
              onTapDay: (_) {},
              onMonthStep: steps.add,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('wall-prev')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('wall-next')));
      await tester.pumpAndSettle();
      expect(steps, [-1, 1]);
    });
  });
}
