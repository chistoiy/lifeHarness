import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/features/journal/presentation/note_export.dart';

import 'helpers.dart';

// V1.64 批3 · 「导出为本地目录」半屏（原型 sheetNoteExport/nxScChg/nxDo）。
// 独立文件＝全 app/浮层用例拆分铁律；弹层只吃回调，不碰平台通道与 Provider。

Widget _host(void Function(BuildContext) launch) => MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (c) => TextButton(
              onPressed: () => launch(c), child: const Text('go')),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('导出面板：默认「全部笔记」·主钮与说明随档换·进度行在场·汇总出人话',
      (t) async {
    final scopes = <String>[];
    await t.pumpWidget(_host((c) => showNoteExportSheet(c,
        hasCurrentFolder: true,
        folderLabel: '灵感',
        onRun: (s) async {
          scopes.add(s);
          return const NoteExportReport(exported: 6, assets: 3);
        })));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    expect(find.text('选择目录并导出'), findsOneWidget);
    expect(find.textContaining('导出全部笔记'), findsOneWidget,
        reason: '默认档＝原型 `let nxSc=\'all\'`');

    await t.tap(find.byKey(const ValueKey('nx-sc-cur')));
    await t.pumpAndSettle();
    expect(find.textContaining('只导「灵感」里的笔记'), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('nx-go')));
    await t.pump();
    expect(find.byKey(const ValueKey('nx-progress')), findsOneWidget,
        reason: '长耗时动作必须有可见进度（工单 §3 红线）');
    await t.pumpAndSettle();
    expect(scopes, ['灵感'], reason: '当前目录档要把所选夹名交给服务（DAO 按 folder 过滤）');
    expect(await pollText(t, '已导出 6 篇 · 附件 3 张'), isTrue);
    await clearToasts(t);
  });

  testWidgets('未点选文件夹＝「当前目录」点了拒切换并出一句实话（原型 nxScChg）', (t) async {
    var ran = 0;
    await t.pumpWidget(_host((c) => showNoteExportSheet(c,
        hasCurrentFolder: false,
        folderLabel: '',
        onRun: (s) async {
          ran++;
          return const NoteExportReport(exported: 1);
        })));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('nx-sc-cur')));
    await t.pumpAndSettle();
    expect(await pollText(t, '先在树中点选文件夹，或改选「全部笔记」'), isTrue);
    expect(find.textContaining('导出全部笔记'), findsOneWidget,
        reason: '拒点＝档位必须留在「全部笔记」，否则切过去导出个空包更迷惑');

    await t.tap(find.byKey(const ValueKey('nx-go')));
    await t.pumpAndSettle();
    expect(ran, 1, reason: '主钮照走当前档');
    await clearToasts(t);
  });

  testWidgets('选择器取消＝不出汇总；整批没落成（no_perm）也必须出声', (t) async {
    await t.pumpWidget(_host((c) => showNoteExportSheet(c,
        hasCurrentFolder: false,
        folderLabel: '',
        onRun: (s) async => null)));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('nx-go')));
    await t.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing, reason: '用户在系统选择器里取消＝不提示');

    await t.pumpWidget(_host((c) => showNoteExportSheet(c,
        hasCurrentFolder: false,
        folderLabel: '',
        onRun: (s) async => const NoteExportReport(errorCode: 'no_perm'))));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('nx-go')));
    await t.pumpAndSettle();
    expect(await pollText(t, '这个目录只有读取权限 · 没能导出'), isTrue,
        reason: '「点了没反应」是本系列红线；0 篇/没权限这类结果一律出声');
    await clearToasts(t);
  });

  test('导出件在树上的入口＝底条第五枚 nt-bt-export（源码守护·代码行原文）', () {
    final src = File(
            'lib/features/journal/presentation/widgets/note_tree_drawer.dart')
        .readAsStringSync();
    expect(src, contains("key: const ValueKey('nt-bt-export')"),
        reason: '原型底条一直有这枚（ntBtExport），dart 侧不许丢入口');
    expect(src, contains('onPressed: _exportLocal'));
    expect(src, contains('exportNotesToTree('));
    expect(src, contains('safPickTree()'), reason: '取目标目录必须走 SAF 树选择器（红线）');
  });
}
