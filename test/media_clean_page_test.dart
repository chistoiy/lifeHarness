/// R5c：图片存储清理页 widget 验收（fake scanner 注入，禁真实 I/O）。
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

  final orphans = [
    MediaScanEntry(
        path: r'C:\docs\note_images\orphan1.jpg', size: 1024, modified: null),
    MediaScanEntry(
        path: r'C:\docs\note_images\orphan2.jpg', size: 2048, modified: null),
  ];

  testWidgets('扫描汇总 + 逐行勾选 + 清理确认 → 删除并重扫', (tester) async {
    final fake = _FakeScanner(
        MediaScanResult(orphans: orphans, totalFiles: 5));
    await tester.pumpWidget(app(fake));
    await settle5(tester);

    expect(find.byKey(const ValueKey('mc-summary')), findsOneWidget);
    expect(find.textContaining('未引用 2 / 共 5'), findsOneWidget);
    expect(find.byKey(const ValueKey('mc-row-orphan1.jpg')), findsOneWidget);
    expect(find.byKey(const ValueKey('mc-row-orphan2.jpg')), findsOneWidget);

    // 未勾选 → 按钮禁用。
    expect(
        tester.widget<FilledButton>(
                find.byKey(const ValueKey('mc-delete')))
            .onPressed,
        isNull);

    await tester.tap(find.byKey(const ValueKey('mc-row-orphan1.jpg')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('mc-delete')));
    await tester.pump();
    expect(find.text('将删除 1 个文件 · 1.0 KB，不可恢复。'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mc-confirm')));
    await tester.pump();

    expect(fake.deleted, [r'C:\docs\note_images\orphan1.jpg']);
    await pollText(tester, '无未引用图片');
    await clearToasts(tester);
  });

  testWidgets('无孤儿 → 显「无未引用图片」且列表为空', (tester) async {
    final fake = _FakeScanner(
        const MediaScanResult(orphans: [], totalFiles: 3));
    await tester.pumpWidget(app(fake));
    await settle5(tester);
    expect(find.text('无未引用图片'), findsOneWidget);
    expect(find.byKey(const ValueKey('mc-row-orphan1.jpg')), findsNothing);
  });
}
