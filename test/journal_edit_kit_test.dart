import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/features/journal/domain/diary_edit_kit.dart';
import 'package:lifeharness/features/journal/domain/journal_entry.dart';
import 'package:lifeharness/features/journal/presentation/widgets/diary_mood_rail.dart';
import 'package:lifeharness/features/journal/presentation/widgets/diary_toolbar.dart';

/// 日记改版批2 · 编辑页组件「纯逻辑 + 画面」两截（工单 §4d ①②⑤⑥）。
///
/// 纯逻辑（心情组主轨/更多/取消/额外两枚、保存三态文案、头部星期全称）走 `test()`
///     ——这些判据页面里全是字符串拼接，拼错了只有真机看得出，必须脱离 widget 树钉住。
/// 画面（心情 rail 是**可横滚**单选组而非等分铺满、选中出右上小叉、⋮ 折叠低频、长按 400ms 出提示）
///     走 `testWidgets()` 直接 pump 两个组件，不经过整页（整页依赖 provider，代价大且易挂）。
void main() {
  group('K · 心情单选组（纯逻辑）', () {
    test('K1 主轨 5 枚与库内序号同序（下标+1 就是落库值）', () {
      expect(kMoodMain, hasLength(kMoodMainCount));
      for (var i = 0; i < kMoodMain.length; i++) {
        expect(kMoodMain[i].$1, i + 1);
        expect(kMoodMain[i].$2, kJournalMoods[i].$1, reason: '主轨表情必须就是库内第 $i 档');
      }
    });

    test('K2 表情 ↔ 序号互转；更多行两枚库内无序号', () {
      expect(diaryMoodIndex('😄'), 1);
      expect(diaryMoodIndex('😡'), 7);
      expect(diaryMoodIndex('😍'), isNull, reason: '更多行多出来的两枚不能冒充已记录');
      expect(diaryMoodEmoji(2), '😌');
      expect(diaryMoodEmoji(null), isNull);
      expect(diaryMoodEmoji(0), isNull, reason: '越界不给「第 0 档」这种假值');
    });

    test('K3 选中态按表情字符比（序号比会整行不亮——批2 原型踩过）', () {
      expect(moodSelected(2, '😌'), isTrue);
      expect(moodSelected(2, '😄'), isFalse);
      expect(moodSelected(null, '😌'), isFalse);
      expect(moodSelected(2, '😍'), isFalse, reason: '额外两枚不参与选中');
    });

    test('K4 点同一枚＝取消；点别的＝切过去；额外两枚点了不改库内值', () {
      expect(moodToggled(2, '😌'), isNull);
      expect(moodToggled(null, '😌'), 2);
      expect(moodToggled(3, '😌'), 2);
      expect(moodToggled(3, '😍'), 3, reason: '额外两枚只改视觉回显');
    });
  });

  group('S · 保存三态（纯逻辑）', () {
    test('S1 三态提示文案逐字对齐原型「syncSaveState / saveDiary」', () {
      expect(diarySaveHint(DiarySaveState.clean), '草稿已自动保存');
      expect(diarySaveHint(DiarySaveState.dirty), '有未保存修改');
      expect(diarySaveHint(DiarySaveState.saving), '保存中…');
    });

    test('S2 只有 dirty 时保存钮全亮，clean/saving 降透明（原型 .45）', () {
      expect(diarySaveDimmed(DiarySaveState.clean), isTrue);
      expect(diarySaveDimmed(DiarySaveState.dirty), isFalse);
      expect(diarySaveDimmed(DiarySaveState.saving), isTrue);
    });
  });

  group('H · 头部日期（纯逻辑）', () {
    test('H1 当年＝MM-DD＋星期全称（批2 起不用「周五」简称）', () {
      // 2026-10-19 是周一
      expect(diaryHeadDate(DateTime(2026, 10, 19), now: DateTime(2026, 10, 19)),
          '10-19 星期一');
      expect(diaryHeadDate(DateTime(2026, 10, 17), now: DateTime(2026, 10, 19)),
          '10-17 星期六');
    });

    test('H2 跨年补年份（补到日，不再只补到月）', () {
      expect(diaryHeadDate(DateTime(2025, 9, 19), now: DateTime(2026, 10, 19)),
          '2025-09-19 星期五');
    });
  });

  group('画面 · 心情 rail', () {
    Future<void> pumpRail(WidgetTester tester,
        {int? mood, bool moreOpen = false, void Function(String)? onMood}) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DiaryMoodRail(
            mood: mood,
            moreOpen: moreOpen,
            onMood: onMood ?? (_) {},
            onToggleMore: () {},
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('R1 主轨是**横向可滚**列表，不是等分铺满', (tester) async {
      await pumpRail(tester);
      final rail = find.byKey(const ValueKey('diary-mood-rail'));
      expect(rail, findsOneWidget);
      expect(tester.widget<ListView>(rail).scrollDirection, Axis.horizontal);
      for (var i = 1; i <= kMoodMainCount; i++) {
        expect(find.byKey(ValueKey('mood-main-$i')), findsOneWidget);
      }
    });

    testWidgets('R2 未展开时第二行不存在；展开才出「更多」六枚', (tester) async {
      await pumpRail(tester);
      expect(find.byKey(const ValueKey('diary-mood-more-row')), findsNothing);
      await pumpRail(tester, moreOpen: true);
      expect(find.byKey(const ValueKey('diary-mood-more-row')), findsOneWidget);
      expect(find.byKey(const ValueKey('mood-extra-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('mood-extra-1')), findsOneWidget);
    });

    testWidgets('R3 选中枚出右上小叉；点它＝取消（与再点一次同入口）', (tester) async {
      final hits = <String>[];
      await pumpRail(tester, mood: 2, onMood: hits.add);
      expect(find.byKey(const ValueKey('diary-mood-clear')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('diary-mood-clear')));
      await tester.pump();
      expect(hits, ['😌']);

      await pumpRail(tester, mood: null);
      expect(find.byKey(const ValueKey('diary-mood-clear')), findsNothing,
          reason: '没有选中态就不该出小叉');
    });

    testWidgets('R4 点一枚回传表情字符（不是序号）', (tester) async {
      final hits = <String>[];
      await pumpRail(tester, onMood: hits.add);
      await tester.tap(find.byKey(const ValueKey('mood-main-3')));
      await tester.pump();
      expect(hits, ['😐']);
    });
  });

  group('画面 · 工具栏', () {
    Future<void> pumpBar(WidgetTester tester,
        {void Function(String)? onAct}) async {
      String tag(String k) => k;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DiaryToolbar(
            onBold: () => onAct?.call(tag('bold')),
            onTask: () => onAct?.call(tag('task')),
            onUl: () => onAct?.call(tag('ul')),
            onQuote: () => onAct?.call(tag('quote')),
            onGallery: () => onAct?.call(tag('album')),
            onCamera: () => onAct?.call(tag('camera')),
            onVoice: () => onAct?.call(tag('voice')),
            onMmCard: () => onAct?.call(tag('mm')),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('T1 主栏 Top5＝加粗/待办/相册/拍照/语音；列表·引用·导图卡不在主栏', (tester) async {
      await pumpBar(tester);
      for (final k in const ['bold', 'task', 'album', 'camera', 'voice']) {
        expect(find.byKey(ValueKey('diary-tb-$k')), findsOneWidget, reason: '缺 $k');
      }
      for (final k in const ['ul', 'quote', 'mm']) {
        expect(find.byKey(ValueKey('diary-tb-$k')), findsNothing, reason: '$k 该收进 ⋮');
      }
    });

    testWidgets('T2 点 ⋮ 展开低频行：无序列表/引用块/导图卡片，再点收起', (tester) async {
      await pumpBar(tester);
      expect(find.byKey(const ValueKey('diary-tb-more-row')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('diary-tb-more')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('diary-tb-more-row')), findsOneWidget);
      for (final k in const ['ul', 'quote', 'mm']) {
        expect(find.byKey(ValueKey('diary-tb-$k')), findsOneWidget);
      }
      await tester.tap(find.byKey(const ValueKey('diary-tb-more')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('diary-tb-ul')), findsNothing);
    });

    testWidgets('T3 短按＝执行动作、不出提示；长按 400ms＝只出提示、不执行', (tester) async {
      final acts = <String>[];
      await pumpBar(tester, onAct: acts.add);

      await tester.tap(find.byKey(const ValueKey('diary-tb-bold')));
      await tester.pumpAndSettle();
      expect(acts, ['bold']);
      expect(find.byKey(const ValueKey('diary-tip-bold')), findsNothing,
          reason: '短按不该闪提示');

      final g = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey('diary-tb-task'))));
      await tester.pump(const Duration(milliseconds: 450));
      expect(find.byKey(const ValueKey('diary-tip-task')), findsOneWidget,
          reason: '长按 400ms 该出提示');
      await g.up();
      await tester.pumpAndSettle();
      expect(acts, ['bold'], reason: '长按的语义是"问这是什么"，不能顺带执行');
    });
  });
}
