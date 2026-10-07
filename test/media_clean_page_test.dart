/// R5c＋批②b U3/B-3：图片存储清理页 widget 验收（fake scanner 注入，禁真实 I/O）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/media/media_usage_scanner.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/settings/presentation/media_clean_page.dart';

import 'helpers.dart';

class _FakeScanner implements MediaUsageScanner {
  _FakeScanner(this.result);

  MediaScanResult result;
  final List<String> deleted = [];

  @override
  Future<MediaScanResult> scan() async => result;

  @override
  int deleteOrphans(List<String> paths) {
    deleted.addAll(paths);
    result = const MediaScanResult(orphans: [], totalFiles: 5);
    return paths.length;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('MediaUsageScanner.${invocation.memberName}');
}

void main() {
  Widget app(MediaUsageScanner scanner) => ProviderScope(
        overrides: [
          mediaScannerProvider.overrideWithValue(scanner),
        ],
        child: const MaterialApp(home: MediaCleanPage()),
      );

  // 内容寻址文件名（SHA256 前缀）＝真机形态：行主文案不许把这串露出来。
  const hashA =
      '3f9a2cb71e0d4a86b5c0f7d29a1e6b3c4d5f6a7b8c9d0e1f2a3b4c5d6e7f80911';
  final orphans = [
    MediaScanEntry(
        path: 'C:\\docs\\note_images\\$hashA.jpg',
        size: 1024,
        modified: DateTime(2026, 9, 12, 14, 3)),
    MediaScanEntry(
        path: r'C:\docs\book_covers\cover99.jpg',
        size: 2048,
        modified: null),
  ];

  testWidgets('U3 人话主文案：目录标签＋落盘时间，裸哈希退到副行「编号 8 位」',
      (tester) async {
    final fake = _FakeScanner(MediaScanResult(orphans: orphans, totalFiles: 5));
    await tester.pumpWidget(app(fake));
    await settle5(tester);

    expect(find.textContaining('未引用 2 / 共 5'), findsOneWidget);
    // 主行＝人话（笔记插图／书籍封面），取不到时间如实说「时间未知」。
    expect(find.text('笔记插图 · 09-12 14:03'), findsOneWidget);
    expect(find.text('书籍封面 · 时间未知'), findsOneWidget);
    // 副行＝体积 · 类型 · 编号短哈希（内容寻址名）或有语义的文件名。
    expect(find.textContaining('1.0 KB · JPG · 编号 3f9a2cb7'), findsOneWidget);
    // 真机 6078 走查抓的坑：`epub_b17-fi.jpg` 这类有语义的名字截前 8 位会彼此撞车，
    // 只有名字本身是 16 位以上十六进制哈希时才写「编号」。
    expect(find.textContaining('2.0 KB · JPG · cover99.jpg'), findsOneWidget);
    // 整屏文案里不得出现 20 位以上的裸哈希（完整串只许进预览底部）。
    expect(_allText(tester).any((t) => RegExp(r'[0-9a-f]{20,}').hasMatch(t)),
        isFalse,
        reason: _allText(tester).join(' | '));
    await clearToasts(tester);
  });

  testWidgets('逐行勾选 → 清理确认（公共版式）→ 删除并重扫', (tester) async {
    final fake = _FakeScanner(MediaScanResult(orphans: orphans, totalFiles: 5));
    await tester.pumpWidget(app(fake));
    await settle5(tester);

    expect(
        tester.widget<FilledButton>(find.byKey(const ValueKey('mc-delete'))).onPressed,
        isNull);
    expect(find.byKey(const ValueKey('mc-row-$hashA.jpg')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('mc-chk-$hashA.jpg')));
    await tester.pump();
    // Widget 之间是同一性比较，取 data 才判得出文案（写 `const Text(...)` 会假红）。
    expect(
        (tester.widget<FilledButton>(find.byKey(const ValueKey('mc-delete')))
                .child
            as Text)
            .data,
        '清理选中（1）');
    await tester.tap(find.byKey(const ValueKey('mc-delete')));
    await settle5(tester);
    // 确认版式全仓只一份（批六钉）＝公共原语 lhConfirm：多行后果＋d-confirm-ok。
    expect(find.textContaining('将删除 1 个文件 · 1.0 KB'), findsOneWidget);
    expect(find.textContaining('不进回收站'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('d-confirm-ok')));
    await settle5(tester);

    expect(fake.deleted, ['C:\\docs\\note_images\\$hashA.jpg']);
    await pollText(tester, '无未引用图片');
    await clearToasts(tester);
  });

  testWidgets('全选：一次勾满 ↔ 取消全选', (tester) async {
    // 2026-10-07 产品令「图片清理页面无全选按钮」——与云端清理屏（cc-all）同形补齐。
    final fake = _FakeScanner(MediaScanResult(orphans: orphans, totalFiles: 5));
    await tester.pumpWidget(app(fake));
    await settle5(tester);

    expect(find.text('全选'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mc-all')));
    await tester.pump();
    expect(
        (tester.widget<FilledButton>(find.byKey(const ValueKey('mc-delete')))
                .child
            as Text)
            .data,
        '清理选中（2）',
        reason: '全选＝两行都进选中集，底钮读数同步');
    expect(find.text('取消全选'), findsOneWidget);
    expect(
        tester
            .widget<Checkbox>(find.byKey(ValueKey('mc-chk-$hashA.jpg')))
            .value,
        isTrue);

    await tester.tap(find.byKey(const ValueKey('mc-all')));
    await tester.pump();
    expect(find.text('全选'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('mc-delete')))
            .onPressed,
        isNull,
        reason: '取消全选要真的清干净，不能留半截选中');
  });

  testWidgets('B-3 预览热区：点缩略图进共享查看件，可翻页、底部给完整路径',
      (tester) async {
    final fake = _FakeScanner(MediaScanResult(orphans: orphans, totalFiles: 5));
    await tester.pumpWidget(app(fake));
    await settle5(tester);

    await tester.tap(find.byKey(const ValueKey('mc-view-$hashA.jpg')));
    await settle5(tester);
    expect(find.byKey(const ValueKey('lb-pos')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('lb-pos'))).data, '1 / 2');
    expect(tester.widget<Text>(find.byKey(const ValueKey('lb-label'))).data,
        '笔记插图 · 09-12 14:03');
    // 完整哈希只在这里出现（技术明细下钻位）；路径给「目录/文件名」可读形态，
    // 不是 `/data/user/0/…` 绝对路径（真机 6078：尾部被省略号截掉＝看不见文件名）。
    final meta0 =
        tester.widget<Text>(find.byKey(const ValueKey('lb-meta'))).data!;
    expect(meta0, contains(hashA));
    expect(meta0, contains('note_images/'));
    expect(meta0, isNot(contains('C:\\')));
    await tester.tap(find.byKey(const ValueKey('lb-next')));
    await settle5(tester);
    expect(tester.widget<Text>(find.byKey(const ValueKey('lb-pos'))).data, '2 / 2');
    expect(
        tester.widget<Text>(find.byKey(const ValueKey('lb-meta'))).data,
        contains('book_covers/cover99.jpg'));
    expect(find.byKey(const ValueKey('lb-prev')), findsOneWidget);
    // 末张禁用「下一张」（到界不许空转）。
    expect(
        tester.widget<TextButton>(find.byKey(const ValueKey('lb-next'))).onPressed,
        isNull);
    await tester.tap(find.byKey(const ValueKey('lb-close')));
    await settle5(tester);
    expect(find.byKey(const ValueKey('lb-pos')), findsNothing);
    await clearToasts(tester);
  });

  testWidgets('无孤儿 → 显「无未引用图片」且列表为空', (tester) async {
    final fake = _FakeScanner(
        const MediaScanResult(orphans: [], totalFiles: 3));
    await tester.pumpWidget(app(fake));
    await settle5(tester);
    expect(find.text('无未引用图片'), findsOneWidget);
    expect(find.byKey(const ValueKey('mc-row-$hashA.jpg')), findsNothing);
    expect(find.byKey(const ValueKey('mc-all')), findsNothing,
        reason: '没东西可选时不摆一个点不动的钮');
    await clearToasts(tester);
  });
}

/// 页面全部可见文本（含 Text.rich 的 span），用于「不许露裸哈希」的整屏判定。
List<String> _allText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
    .where((s) => s.isNotEmpty)
    .toList(growable: false);
