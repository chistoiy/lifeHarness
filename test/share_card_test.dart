import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/logging/app_log.dart';
import 'package:lifeharness/shared/widgets/share_card.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'helpers.dart';

/// V1.57 A 批 · 分享长图公共通道（拍板记录 §五~§六）。
/// 钉三件事：① 文件名 sanitize；② 渲染失败走 warn 日志且回执不谎报成功；
/// ③ 站点级：点「保存图片」后 toast 含真实 share 路径且不是「模拟」。
/// 注意：写盘是真异步 I/O，一律包在 tester.runAsync 里（FakeAsync 下永不返回）。

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.dir);
  final String dir;
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}

final _model = ShareCardModel(
  file: '决算-Mac/Book*1?"<>| ',
  eyebrow: 'LifeHarness · 物品决算',
  title: 'MacBook 决算报告',
  line: '已归档 · 2024-03-01 建档 · 2026-08-30 冻结',
  big: '¥ 3.21',
  unit: '/天',
  tiles: const [
    ShareCardTile('总投入', '¥8,999'),
    ShareCardTile('持有', '913 天'),
    ShareCardTile('净持有', '¥8,120'),
  ],
  sections: const [
    ShareCardSection(head: '决算口径', rows: [
      ShareCardRow('残值回收', '¥879'),
      ShareCardRow('真实日均', '¥3.21/天'),
    ]),
    ShareCardSection(head: '备注', rows: [
      ShareCardRow('这段没有右值，应输出整段文本行'),
    ]),
  ],
);

Future<ui.Image> _decode(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  return frame.image;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const dirName = 'lh_share_card_test_docs';
  final docsDir = Directory('${Directory.systemTemp.path}/$dirName');
  final savedFile = File(
      '${docsDir.path}${Platform.pathSeparator}share${Platform.pathSeparator}'
      '决算-MacBook1.png');
  late PathProviderPlatform prevProvider;

  setUpAll(() async {
    if (docsDir.existsSync()) docsDir.deleteSync(recursive: true);
  });
  setUp(() {
    prevProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProvider(docsDir.path);
  });
  tearDown(() {
    PathProviderPlatform.instance = prevProvider;
  });

  group('sanitize 与文字版', () {
    test('① 文件名清洗去 \\/:*?"<>| 与首尾空格', () {
      expect(sanitizeShareName(r'决算-Mac/Book*1?"<>| '), '决算-MacBook1');
      expect(sanitizeShareName('a:b?c*d'), 'abcd');
      expect(sanitizeShareName('  普通名字  '), '普通名字');
    });

    test('文字版＝标题·大数字+单位·口径·〔段名〕+行（值空为整段文本行）', () {
      final t = _model.copyText;
      expect(t.split('\n'), [
        'MacBook 决算报告',
        '¥ 3.21 /天',
        '已归档 · 2024-03-01 建档 · 2026-08-30 冻结',
        '',
        '〔决算口径〕',
        '残值回收：¥879',
        '真实日均：¥3.21/天',
        '',
        '〔备注〕',
        '这段没有右值，应输出整段文本行',
      ]);
    });

    test('站点假 toast 字样已摘净（六处逐字核）', () {
      for (final (path, banned) in [
        ('../lib/features/items/presentation/item_stats_page.dart', '统计卡已生成分享长图'),
        ('../lib/features/items/presentation/item_settle_page.dart', '决算长图已生成'),
        ('../lib/features/days/presentation/day_detail_page.dart', '倒数日分享卡已生成'),
        ('../lib/features/ledger/presentation/ledger_yearly_page.dart', '已生成年度分享图（模拟）'),
        ('../lib/features/habit/presentation/habit_auto_sheets.dart', '已保存到相册'),
      ]) {
        final src = File('test/$path').readAsStringSync();
        expect(src.contains(banned), isFalse,
            reason: '$path 仍残留假承诺「$banned」');
      }
    });
  });

  group('captureShareCard', () {
    test('② 预览层未就绪 → 返回 null 且落 warn 日志', () async {
      final before = AppLog.lines.length;
      final path = await captureShareCard(GlobalKey(), name: 'x');
      expect(path, isNull);
      final warns = AppLog.lines
          .skip(before)
          .where((l) => l.level == LhLevel.warn)
          .toList();
      expect(warns, isNotEmpty);
      expect(warns.first.text, contains('分享长图生成失败'));
      // 排空 AppLog 节流 Timer。
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });

    testWidgets('③ 保存图片落 share/ 真实路径 · 1080 宽 · toast 非模拟', (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 900));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (ctx) => Center(
                child: ElevatedButton(
                  onPressed: () => showShareCardSheet(ctx, _model),
                  child: const Text('open'),
                ),
              )),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sc-sheet')), findsOneWidget);
      expect(find.text('分享长图'), findsOneWidget);
      expect(find.text('预览'), findsOneWidget);

      // 光栅回调要真事件循环持续驱动，runAsync 内混 pump（widget_tester 允许）
      // + 真实延时推进整条 保存→落盘→关弹层→toast 链。
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('sc-save')));
        for (var i = 0;
            i < 40 &&
                !(savedFile.existsSync() && savedFile.lengthSync() > 1000);
            i++) {
          await tester.pump(const Duration(milliseconds: 30));
          await Future<void>.delayed(const Duration(milliseconds: 30));
        }
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
      });

      expect(savedFile.existsSync(), isTrue,
          reason: '未落盘到 <docs>/share/ · AppLog 尾部：'
              '${AppLog.lines.reversed.take(3).map((l) => l.formatted).join(' || ')}');
      final bytes = savedFile.readAsBytesSync();
      expect(bytes.length, greaterThan(1000));
      final img = await tester.runAsync(() => _decode(bytes));
      expect(img!.width, 1080);

      // 保存成功应先关弹层，再 toast 真实路径（toast 是长句，用包含匹配轮询）。
      for (var i = 0;
          i < 15 &&
              find.textContaining('分享长图已保存：').evaluate().isEmpty;
          i++) {
        await tester.pump(const Duration(milliseconds: 80));
      }
      expect(find.textContaining('分享长图已保存：'), findsOneWidget);
      expect(find.byKey(const ValueKey('sc-sheet')), findsNothing);
      expect(find.textContaining('模拟'), findsNothing);
      expect(find.textContaining('相册'), findsNothing);
      await drainLogTimer(tester);
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('复制文字版 → 「文字版已复制」（toast 在 await Clipboard 之后才出现，即链路走通）',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(420, 900));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (ctx) => Center(
                child: ElevatedButton(
                  onPressed: () => showShareCardSheet(ctx, _model),
                  child: const Text('open'),
                ),
              )),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      // 不 mock 整条 flutter/platform 通道（会炸 Title/SystemSound 报文）；
      // Clipboard.setData 无处理器时静默应答，toast 出现即证明 await 已过。
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('sc-copy')));
        for (var i = 0; i < 12 && find.text('文字版已复制').evaluate().isEmpty; i++) {
          await tester.pump(const Duration(milliseconds: 40));
          await Future<void>.delayed(const Duration(milliseconds: 40));
        }
      });
      expect(find.text('文字版已复制'), findsOneWidget);
      await clearToasts(tester);
      await drainLogTimer(tester);
      await tester.binding.setSurfaceSize(null);
    });
  });
}
