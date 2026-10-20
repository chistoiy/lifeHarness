import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/features/journal/domain/journal_entry.dart';
import 'package:lifeharness/features/journal/presentation/widgets/journal_layout_kit.dart';
import 'package:lifeharness/features/journal/presentation/widgets/journal_track_view.dart';

/// 日记改版批1b · 日期轨道**画面级**（工单 §6 第 2 条）。
///
/// 与 `journal_view_mode_test.dart` 的分工：那边钉数据折块（纯函数），
/// 这边钉「折出来的块真被画出来」＋「1b 的吸顶与左栏四档分层真的生效」。
/// 1b 的关键回归：pinned 头必须是 sliver——把单日块塞进 `SliverList.builder`
/// 会直接抛 `RenderRepaintBoundary expected RenderBox`（本批实伤，六条一起红）。

JournalEntry _e(
  DateTime day, {
  int? mood,
  String content = '正文',
  List<String> imgs = const [],
  int hour = 9,
  int minute = 30,
  bool starred = false,
  bool liked = false,
}) =>
    JournalEntry(
      day: day,
      mood: mood,
      starred: starred,
      liked: liked,
      // 图片靠正文 markdown 派生；`stripMdImages` 把图片换成 alt 文本（空 alt＝「图片」），
      // 所以正文断言用 textContaining，别用 find.text。
      content: '$content${imgs.isEmpty ? '' : '\n\n![](${imgs.map((x) => 'file://$x').join('|')})'}',
      createdAt: DateTime(day.year, day.month, day.day, hour, minute),
      updatedAt: DateTime(day.year, day.month, day.day, hour, minute),
    );

/// 把 blocks 平铺进 CustomScrollView（与 `trackScroll` 同构，剥掉图墙/工具栏）。
Widget _scene(List<JournalEntry> entries, {void Function(JournalEntry)? onOpen}) {
  final blocks = buildTrackBlocks(entries, moodColorOf: (_) => Colors.red);
  return MaterialApp(
    home: Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverMainAxisGroup(
              slivers: [
                for (final b in blocks)
                  ...trackBlockSlivers(
                    block: b,
                    onOpenEntry: onOpen ?? (_) {},
                  ),
              ],
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 96)),
        ],
      ),
    ),
  );
}

void main() {
  group('日期轨道渲染（批1b）', () {
    testWidgets('T1 一天一篇＝一块：日号出现一次、正文在', (tester) async {
      await tester.pumpWidget(_scene([
        _e(DateTime(2026, 10, 19), mood: 5, content: '十月十九'),
      ]));
      await tester.pumpAndSettle();
      expect(find.text('19'), findsOneWidget);
      expect(find.text('十月十九'), findsOneWidget);
    });

    testWidgets('T2 同日多篇只出一次日号（左栏不重复）', (tester) async {
      await tester.pumpWidget(_scene([
        _e(DateTime(2026, 10, 19), content: '早上那篇', hour: 8),
        _e(DateTime(2026, 10, 19), content: '晚上那篇', hour: 21),
      ]));
      await tester.pumpAndSettle();
      expect(find.text('19'), findsOneWidget);
      expect(find.text('早上那篇'), findsOneWidget);
      expect(find.text('晚上那篇'), findsOneWidget);
    });

    testWidgets('T3 跨日两块、新在上', (tester) async {
      await tester.pumpWidget(_scene([
        _e(DateTime(2026, 10, 19), content: '今天'),
        _e(DateTime(2026, 10, 18), content: '昨天'),
      ]));
      await tester.pumpAndSettle();
      expect(find.text('19'), findsOneWidget);
      expect(find.text('18'), findsOneWidget);
      expect(tester.getTopLeft(find.text('19')).dy,
          lessThan(tester.getTopLeft(find.text('18')).dy));
    });

    testWidgets('T4 吸顶：滚下去后首块日期块仍停在顶部（pinned 生效）', (tester) async {
      await tester.pumpWidget(_scene([
        for (var d = 19; d >= 12; d--) _e(DateTime(2026, 10, d), content: '第 $d 天'),
      ]));
      await tester.pumpAndSettle();
      final headY0 =
          tester.getTopLeft(find.byKey(const ValueKey('track-head-10-19'))).dy;

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -120));
      await tester.pumpAndSettle();
      final headY1 =
          tester.getTopLeft(find.byKey(const ValueKey('track-head-10-19'))).dy;

      // 往上滚了 120，但日期块被钉住：位移必须明显小于滚动量
      expect(headY0 - headY1, lessThan(40),
          reason: '首块日期块应被 pinned 钉住，不能跟着滚走 120px');
    });

    testWidgets('T5 吸顶头只铺左栏宽（不盖住右栏正文）', (tester) async {
      await tester.pumpWidget(_scene([
        _e(DateTime(2026, 10, 19), content: '第一天的正文'),
        _e(DateTime(2026, 10, 18), content: '第二天的正文'),
      ]));
      await tester.pumpAndSettle();
      final head =
          tester.getRect(find.byKey(const ValueKey('track-head-10-19')));
      // 左栏 64 + 间距 8 = 72；留 1px 容差
      expect(head.width, lessThanOrEqualTo(kTrackGutterW + kTrackGap + 1),
          reason: '吸顶头不能铺满整行，否则右栏正文被色带盖住');
    });

    testWidgets('T6 点条目回调带正确 entry', (tester) async {
      JournalEntry? opened;
      final target = _e(DateTime(2026, 10, 19), content: '点我');
      await tester.pumpWidget(_scene([target], onOpen: (e) => opened = e));
      await tester.pumpAndSettle();
      await tester.tap(find.text('点我'));
      await tester.pumpAndSettle();
      expect(opened?.id, target.id);
      expect(opened?.content, contains('点我'));
    });

    testWidgets('T7 空列表不抛异常', (tester) async {
      await tester.pumpWidget(_scene(const []));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('T8 正文最多两行（左栏不被长文撑宽）', (tester) async {
      await tester.pumpWidget(_scene([
        _e(DateTime(2026, 10, 19), content: '一' * 200),
      ]));
      await tester.pumpAndSettle();
      final t = tester.widget<Text>(find.text('一' * 200));
      expect(t.maxLines, kTrackBodyMaxLines);
      expect(t.overflow, TextOverflow.ellipsis);
    });

    testWidgets('T9 四档分层：日号 22px ＞ 月份/星期/时刻 10px', (tester) async {
      await tester.pumpWidget(_scene([
        _e(DateTime(2026, 10, 19), content: '带时刻', hour: 7, minute: 5),
      ]));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.text('19')).style?.fontSize,
          kTrackDayNoSize);
      // 月份标签：monthLabel 自带「月」字，不能再拼一次（否则「10月月」）
      expect(tester.widget<Text>(find.text('10月')).style?.fontSize,
          kTrackMetaSize);
      expect(tester.widget<Text>(find.text('周一')).style?.fontSize,
          kTrackMetaSize);
      expect(tester.widget<Text>(find.text('07:05')).style?.fontSize,
          kTrackMetaSize);
    });

    testWidgets('T10 收藏/点亮只读回显（星/心各一枚）', (tester) async {
      await tester.pumpWidget(_scene([
        _e(DateTime(2026, 10, 19), content: '两态都有', starred: true, liked: true),
      ]));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.star), findsOneWidget);
      expect(find.byIcon(Icons.favorite), findsOneWidget);
    });
  });
}
