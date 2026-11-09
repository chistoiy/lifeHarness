/// 交互整改批二常驻用例（T5 按压反馈 · T6 触控热区 · T7 错误人话化）。
///
/// 口径来源＝`docs/handoff/交互整改开发计划-20261003.md` 批二行：
///  - T5：`PillChip`/`HPick`/`MoodRow` 三原语统一「按下微缩」帧反馈（scale 非 splash）；
///  - T6：热区外扩——MoodRow 44dp、缩略图删除角标 36dp、眼睛钮 44dp、习惯打卡钮 44dp
///    （后两处为跨模块组件，按「源码守护钉数值」形态常驻，改动即红）；
///  - T7：`humanizeError` 人话映射（认不出原样返回，不编造）＋`AppToast.showError`
///    时长下限 3.2s＋技术细节走日志双通道。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/logging/app_log.dart';
import 'package:lifeharness/shared/widgets/image_attach.dart';
import 'package:lifeharness/shared/widgets/ui_kit.dart';

import 'helpers.dart';

/// 按下并保持（不抬起）：startGesture 后必须 pump 一帧，指针事件才送达引擎。
Future<TestGesture> pressDown(WidgetTester t, Finder f) async {
  final g = await t.startGesture(t.getCenter(f));
  await t.pump();
  return g;
}

/// 按压反馈是否生效＝Pressable 的 AnimatedScale 是否处于非静止值。
/// 读 widget 属性而非渲染矩阵：动画中的 Transform 元素不重建（只换图层），
/// 读 storage 会拿到静止帧的 1.0（PillChip 侥幸能读到，HPick/MoodRow 不能）。
bool _pressScaled(Type widgetType) {
  final scales = find
      .descendant(
          of: find.byType(widgetType),
          matching: find.descendant(
              of: find.byType(Pressable), matching: find.byType(AnimatedScale)))
      .evaluate()
      .map((e) => (e.widget as AnimatedScale).scale);
  return scales.any((v) => v < 1);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('T5 按压反馈（三原语统一 scale）', () {
    Future<void> mount(WidgetTester t, Widget child) => t.pumpWidget(
        MaterialApp(home: Scaffold(body: Center(child: child))));

    testWidgets('PillChip：按下缩放生效、抬起复原，且点击回调照常', (t) async {
      var taps = 0;
      await mount(
          t, PillChip(label: '亮', selected: false, onTap: () => taps++));
      final down = await pressDown(t, find.byType(PillChip));
      await t.pump(const Duration(milliseconds: 60));
      expect(_pressScaled(PillChip), isTrue,
          reason: '无按压帧反馈＝T5 要治的『点了不像能点』');
      await down.up();
      await t.pump(); // 送达移除事件（_down 复位）
      await t.pump(const Duration(milliseconds: 300)); // 跑完回弹动画
      expect(_pressScaled(PillChip), isFalse, reason: '抬起必须复原');
      await t.tap(find.byType(PillChip));
      // 一次按下-抬起本身就构成 tap（2＝press 那次 ＋ 显式 tap 那次）：
      // 证明 Pressable 的 Listener 只观察、不与 GestureDetector 抢竞技场。
      expect(taps, 2, reason: 'Listener 不得吞点击');
    });

    testWidgets('HPick 点选与横滑共存：按压反馈生效、fling 仍能滚动', (t) async {
      var changes = 0;
      await mount(
        t,
        SizedBox(
          width: 320,
          child: HPick(
              items: List.generate(8, (i) => 'L$i'),
              index: 0,
              itemWidth: 76,
              onChanged: (_) => changes++),
        ),
      );
      final first = find.byKey(const ValueKey('hopt-L1'));
      final g = await pressDown(t, first);
      await t.pump(const Duration(milliseconds: 60));
      expect(_pressScaled(HPick), isTrue, reason: '选项按压必须有反馈');
      await g.up();
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(first);
      expect(changes, greaterThanOrEqualTo(1));
      await t.fling(find.byType(ListView), const Offset(-200, 0), 1800);
      for (var i = 0; i < 30; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(t.state<ScrollableState>(find.byType(Scrollable)).position.pixels,
          greaterThan(0),
          reason: 'Pressable 只观察指针，不得干扰惯性滚动（R3-9 同面）');
    });

    testWidgets('MoodRow：反馈生效且点选回调按序', (t) async {
      final picked = <int>[];
      await mount(
          t,
          MoodRow(
              emojis: const ['😀', '😅', '😴'],
              onPick: picked.add));
      final g =
          await pressDown(t, find.byKey(const ValueKey('mood-1')));
      await t.pump(const Duration(milliseconds: 60));
      expect(_pressScaled(MoodRow), isTrue,
          reason: '心情表情按下必须有帧反馈');
      await g.up();
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.byKey(const ValueKey('mood-2')));
      expect(picked, [1, 2]);
    });
  });

  group('T6 触控热区', () {
    testWidgets('MoodRow 表情热区 ≥44dp（视觉仍 24dp 表情）', (t) async {
      await t.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Center(
                  child: MoodRow(
                      emojis: const ['😀', '😅', ''], onPick: (_) {})))));
      final size = t.getSize(find.byKey(const ValueKey('mood-0')));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    });

    testWidgets('缩略图删除角标热区 ≥36dp（视觉仍 20dp 圆）', (t) async {
      await t.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Center(
                  child: ImageSquareCard(
                      path: 'nonexistent-for-test.png',
                      fg: Colors.black,
                      onDelete: () {},
                      delKey: const ValueKey('probe-del'))))));
      final size = t.getSize(find.byKey(const ValueKey('probe-del')));
      expect(size.width, greaterThanOrEqualTo(36));
      expect(size.height, greaterThanOrEqualTo(36));
    });

    test('眼睛钮/习惯打卡钮热区数值常驻钉（跨模块组件，源码守护形态）', () {
      final eye = File(
              'lib/features/settings/presentation/widgets/sync_service_edit_sheet.dart')
          .readAsStringSync();
      expect(eye, contains('minWidth: 44, minHeight: 44'),
          reason: '眼睛钮热区回落到 ≈18dp＝T6 缺陷复发');
      expect(eye, contains('padding: const EdgeInsets.all(4)'),
          reason: 'padding 归零会把 44dp 约束压扁');
      final habit = File(
              'lib/features/habit/presentation/widgets/habit_tile_row.dart')
          .readAsStringSync();
      expect(habit, contains('minWidth: 44, minHeight: 44'),
          reason: '打卡钮 32dp 嵌行内＝T6 缺陷复发');
      expect(habit, contains('behavior: HitTestBehavior.opaque'),
          reason: '热区外扩后空白处必须可命中');
    });
  });

  group('T7 错误人话化', () {
    test('humanizeError 分类映射＋认不出原样返回（不编造）', () {
      expect(humanizeError(const SocketException('failed host lookup')),
          contains('网络连接不上'));
      expect(humanizeError(TimeoutException('deadline exceeded')),
          contains('请求超时'));
      expect(humanizeError(Exception('OS Error: No space left on device')),
          contains('存储空间不足'));
      expect(humanizeError(Exception('HttpException: status 404')),
          contains('404'));
      expect(humanizeError(Exception('HttpException: status 503')),
          contains('服务端出错'));
      // 兜底口径：认不出的异常原样给（细节本就给用户看的那一类）。
      expect(humanizeError(Exception('口令不正确')), 'Exception: 口令不正确');
    });

    testWidgets('AppToast.showError：人话句＋「详情见日志」＋时长 3.2s，原文进日志',
        (t) async {
      AppLog.reset();
      await t.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Builder(builder: (context) => Center(
                    child: TextButton(
                        onPressed: () => AppToast.showError(context,
                            const SocketException('connection refused'),
                            prefix: '同步失败'),
                        child: const Text('go')),
                  )))));
      await t.tap(find.text('go'));
      await t.pump();
      final bar =
          t.widget<SnackBar>(find.descendant(of: find.byType(Scaffold), matching: find.byType(SnackBar)).first);
      expect((bar.content as Text).data, '同步失败：网络连接不上，检查网络或代理后重试 · 详情见日志');
      expect(bar.duration, const Duration(milliseconds: 3200),
          reason: '错误类时长 <3s 读不完（T7 判据）');
      expect(bar.action, isNull, reason: '普通失败条不得带 action（永挂教训）');
      expect(AppLog.lines.any((l) =>
          l.level.name == 'warn' && l.text.contains('connection refused')),
          isTrue,
          reason: '技术细节必须留日志页（双通道口径）');
      await t.pump(const Duration(milliseconds: 3300));
      await drainLogTimer(t);
    });

    test(r'三个已整改点不得再把裸 $e 拼进提示条（防回潮守护）', () {
      for (final path in [
        'lib/core/ai/ai_review.dart',
        'lib/features/settings/presentation/widgets/sync_progress_sheet.dart',
        'lib/features/settings/presentation/log_page.dart',
      ]) {
        final src = File(path).readAsStringSync();
        final raw = RegExp(r'AppToast[.]show[(][^)]*[\$]e').hasMatch(src);
        expect(raw, isFalse, reason: '$path 又出现裸异常进提示条');
        expect(src, contains('AppToast.showError'),
            reason: '$path 的失败条应走 showError 统一出口');
      }
    });
  });
}
