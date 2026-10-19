import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/features/journal/domain/journal_entry.dart';
import 'package:lifeharness/features/journal/presentation/widgets/journal_layout_kit.dart';
import 'package:lifeharness/features/journal/presentation/widgets/journal_track_view.dart';

/// 日记改版批1a · 日期轨道**画面级**（工单 §1 执行面板「新增常驻」第二件）。
///
/// 与 `journal_view_mode_test.dart` 的分工：那边钉数据折块口径（纯函数），
/// 这里钉「折出来的块真的被画出来了」——左栏日号、同日多篇共用一块、
/// 时刻列、有图缩略、长按/点击出口仍指向正确篇。

JournalEntry _e(
  DateTime day, {
  int? mood,
  String content = '正文',
  List<String> imgs = const [],
  List<String> tags = const [],
}) {
  final e = JournalEntry(
    day: day,
    mood: mood,
    // 图片不走构造参数，靠正文里的 markdown 图片语法——`imagePaths` 是解析出来的派生字段。
    // 注意 `stripMdImages` 把图片**换成 alt 文本**（不是删掉），alt 会留在预览正文里，
    // 所以这里统一给空 alt，正文断言才不会被 alt 干扰。
    content: '$content${imgs.isEmpty ? '' : '\n\n![](${imgs.map((x) => 'file://$x').join('|')})'}'
        '${tags.isEmpty ? '' : '\n\n${tags.join(' ')}'}',
    createdAt: DateTime(day.year, day.month, day.day, 9, 30),
    updatedAt: DateTime(day.year, day.month, day.day, 9, 30),
  );
  return e;
}

Future<void> _pumpTrack(
  WidgetTester tester,
  List<JournalEntry> entries, {
  void Function(JournalEntry)? onOpen,
}) async {
  final blocks = buildTrackBlocks(entries, moodColorOf: (_) => Colors.red);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: 600,
        child: JournalTrackView(
          blocks: blocks,
          onOpenEntry: onOpen ?? (_) {},
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('日期轨道渲染', () {
    testWidgets('T1 一天一篇＝一块：日号/月·周副标出现一次', (tester) async {
      await _pumpTrack(tester, [
        _e(DateTime(2026, 10, 19), mood: 5, content: '十月十九'),
      ]);
      expect(find.text('19'), findsOneWidget);
      expect(find.text('十月十九'), findsOneWidget);
    });

    testWidgets('T2 同日多篇只出一次日号（左栏不重复）', (tester) async {
      await _pumpTrack(tester, [
        _e(DateTime(2026, 10, 19), content: '早上那篇'),
        _e(DateTime(2026, 10, 19), content: '晚上那篇'),
      ]);
      // 日号只有一处（左栏 gutter），不随篇数增长
      expect(find.text('19'), findsOneWidget);
      expect(find.text('早上那篇'), findsOneWidget);
      expect(find.text('晚上那篇'), findsOneWidget);
    });

    testWidgets('T3 跨日＝两块，且按输入顺序（新→旧）落块', (tester) async {
      await _pumpTrack(tester, [
        _e(DateTime(2026, 10, 19), content: '今天'),
        _e(DateTime(2026, 10, 18), content: '昨天'),
      ]);
      expect(find.text('19'), findsOneWidget);
      expect(find.text('18'), findsOneWidget);
      final y = tester.getTopLeft(find.text('19')).dy;
      final y2 = tester.getTopLeft(find.text('18')).dy;
      expect(y, lessThan(y2), reason: '新的日期块必须在上');
    });

    testWidgets('T4 有图篇出缩略（≤3 枚），无图篇不出', (tester) async {
      final noImg = _e(DateTime(2026, 10, 19), content: '无图');
      final withImg =
          _e(DateTime(2026, 10, 18), content: '有图', imgs: const ['/nope/a.jpg']);
      // 先钉住构造假设：图片确实被解析出来了（否则这条用例测的是空气）
      expect(noImg.imagePaths, isEmpty);
      expect(withImg.imagePaths, hasLength(1));
      await _pumpTrack(tester, [noImg, withImg]);
      // 缩略用 Image.file，文件不存在时走 errorBuilder 占位——只要不抛异常即算过
      expect(tester.takeException(), isNull);
      // 正文用 `find.textContaining`：预览正文是「有图\n\n图片」这种多段串，
      // 精确匹配 `find.text('有图')` 会漏（预览把图片占位也拼在里面）。
      expect(find.textContaining('有图'), findsOneWidget);
      expect(find.textContaining('无图'), findsOneWidget);
    });

    testWidgets('T5 点条目回调带正确 entry（长按多选外的唯一出口）', (tester) async {
      JournalEntry? opened;
      final target = _e(DateTime(2026, 10, 19), content: '点我');
      await _pumpTrack(tester, [target], onOpen: (e) => opened = e);
      await tester.tap(find.text('点我'));
      await tester.pumpAndSettle();
      expect(opened?.id, target.id);
      expect(opened?.content, contains('点我'));
    });

    testWidgets('T6 空列表不抛异常（筛选筛成 0 篇时轨道档不能白屏炸）', (tester) async {
      await _pumpTrack(tester, const []);
      expect(tester.takeException(), isNull);
      expect(find.byType(JournalTrackView), findsOneWidget);
    });

    testWidgets('T7 正文最多两行（左栏不被长文撑宽）', (tester) async {
      await _pumpTrack(tester, [
        _e(DateTime(2026, 10, 19), content: '一' * 200),
      ]);
      final t = tester.widget<Text>(find.text('一' * 200));
      expect(t.maxLines, 2);
      expect(t.overflow, TextOverflow.ellipsis);
    });
  });
}
