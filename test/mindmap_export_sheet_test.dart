import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/features/mindmap/presentation/mindmap_export_actions.dart';

/// 批2 F4-5 · 导出弹层行为（工单 §4c.3 ②）。
/// 轻 widget（单弹层 pump），独立文件防套件互踩。
void main() {
  testWidgets('默认态：格式 HTML、正文开关关（§4.10 隐私硬口径）、xmind 置灰',
      (tester) async {
    MmExportChoice? got;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (ctx) {
        return Center(
          child: TextButton(
            onPressed: () async {
              got = await showMmExportSheet(ctx);
            },
            child: const Text('open'),
          ),
        );
      }),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('mm-export-body-sw'))).value,
        isFalse, reason: '正文默认关＝弹层初态（变异刀1 钉点）');
    // xmind 置灰：OnBackPressed 不触发？直接点它不改变选择
    await tester.tap(find.byKey(const ValueKey('mm-export-fmt-xmind')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('mm-export-go')));
    await tester.pumpAndSettle();
    expect(got, isNotNull);
    expect(got!.format, 'html', reason: 'xmind 置灰＝点它不换格式');
    expect(got!.includeBody, isFalse);
    expect(got!.landscape, isFalse);
  });

  testWidgets('选 md＋开正文＋开横向＝选项如实带出', (tester) async {
    MmExportChoice? got;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (ctx) {
        return Center(
          child: TextButton(
            onPressed: () async {
              got = await showMmExportSheet(ctx);
            },
            child: const Text('open'),
          ),
        );
      }),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mm-export-fmt-md')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('mm-export-body-sw')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('mm-export-landscape-sw')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('mm-export-go')));
    await tester.pumpAndSettle();

    expect(got!.format, 'md');
    expect(got!.includeBody, isTrue);
    expect(got!.landscape, isTrue);
  });

  testWidgets('选 PNG：两开关置灰不可开（画布像素快照无正文/横向语义）',
      (tester) async {
    MmExportChoice? got;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (ctx) {
        return Center(
          child: TextButton(
            onPressed: () async {
              got = await showMmExportSheet(ctx);
            },
            child: const Text('open'),
          ),
        );
      }),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mm-export-fmt-png')));
    await tester.pump();
    // 开关 disabled：onChanged=null → 点击无效
    final sw = tester.widget<SwitchListTile>(
        find.byKey(const ValueKey('mm-export-body-sw')));
    expect(sw.onChanged, isNull, reason: 'PNG 态正文开关必须 disabled');
    final sw2 = tester.widget<SwitchListTile>(
        find.byKey(const ValueKey('mm-export-landscape-sw')));
    expect(sw2.onChanged, isNull);
    await tester.tap(find.byKey(const ValueKey('mm-export-go')));
    await tester.pumpAndSettle();
    expect(got!.format, 'png');
    expect(got!.includeBody, isFalse, reason: '即便此前误开过，PNG 选项也强制关');
    expect(got!.landscape, isFalse);
  });
}
