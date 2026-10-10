import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lifeharness/features/journal/domain/note_folder.dart';
import 'package:lifeharness/features/journal/presentation/note_local_import.dart';
import 'helpers.dart';

// V1.64 批2（工单 §11 过门点①②③）· 两枚弹层的独立文件（全 app/浮层用例拆分铁律）。
// 弹层只吃回调，不碰平台通道与 Provider＝真点真断言，无真异步 I/O。

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

  testWidgets('导入面板：默认目录档·主钮与说明随档换·进度行在场·汇总出人话提示',
      (t) async {
    final kinds = <String>[];
    await t.pumpWidget(_host((c) => showNoteLocalImportSheet(c, onRun: (k) async {
          kinds.add(k);
          return const LocalImportReport(added: 4, skipped: 1);
        })));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    expect(find.text('选择目录并导入'), findsOneWidget);
    expect(find.textContaining('子文件夹各成带「本地」角标节点'), findsOneWidget,
        reason: '目录档说明必须讲清层级还原（本轮改口的口径）');

    await t.tap(find.byKey(const ValueKey('ni-kind-file')));
    await t.pumpAndSettle();
    expect(find.text('选择文件并导入'), findsOneWidget);
    expect(find.textContaining('多选 .md 文件'), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('ni-go')));
    await t.pump();
    expect(find.byKey(const ValueKey('ni-progress')), findsOneWidget,
        reason: '长耗时动作必须有可见进度（工单 §3）');
    await t.pumpAndSettle();
    expect(kinds, ['file']);
    expect(await pollText(t, '已导入 4 条 · 跳过重复 1 条'), isTrue);
    await clearToasts(t);
  });

  testWidgets('导入面板：选择器取消＝不出汇总提示', (t) async {
    var shown = 0;
    await t.pumpWidget(_host((c) async {
      await showNoteLocalImportSheet(c, onRun: (k) async => null);
      shown++;
    }));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('ni-go')));
    await t.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    expect(shown, 1);
  });

  testWidgets('移除确认层：后果三行现算·取消不动手·确认才摘（拍板 H）', (t) async {
    var confirmed = 0;
    final folder = NoteFolder(
        id: 1,
        name: '外来笔记夹',
        source: 'local_dir',
        originPath: 'Download/外来笔记夹');
    Future<void> open(WidgetTester w) async {
      await w.tap(find.text('go'));
      await w.pumpAndSettle();
    }

    await t.pumpWidget(_host((c) => showNoteUnmountSheet(c,
        folder: folder,
        childCount: 3,
        keepCount: 7,
        onConfirm: () async => confirmed++)));
    await open(t);
    expect(find.text('移除挂载 · 外来笔记夹'), findsOneWidget);
    expect(find.text('本地'), findsOneWidget, reason: '来源角标随挂载类型换词');
    expect(find.text('Download/外来笔记夹 · 子夹 3 个'), findsOneWidget);
    expect(find.textContaining('只从文件树摘掉该挂载及其 3 个子夹'), findsOneWidget);
    expect(find.text('手机里的目录与文件不删除'), findsOneWidget);
    expect(find.textContaining('已导入的 7 条笔记保留在库'), findsOneWidget,
        reason: '条数必须现算进确认层（H 的承诺要看得见）');

    await t.tap(find.text('取消'));
    await t.pumpAndSettle();
    expect(confirmed, 0, reason: '长按只出弹层＝未确认不动手');

    await open(t);
    await t.tap(find.byKey(const ValueKey('nu-confirm')));
    await t.pumpAndSettle();
    expect(confirmed, 1);
  });

  testWidgets('导出目录挂载＝同族可移除（角标换「导出」·无子夹措辞）', (t) async {
    var confirmed = 0;
    await t.pumpWidget(_host((c) => showNoteUnmountSheet(c,
        folder: NoteFolder(id: 2, name: '笔记导出', source: 'export'),
        childCount: 0,
        keepCount: 0,
        onConfirm: () async => confirmed++)));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    expect(find.text('导出'), findsOneWidget);
    expect(find.text('移除挂载 · 笔记导出'), findsOneWidget);
    expect(find.textContaining('本机的挂载目录'), findsOneWidget,
        reason: '无 origin_path 时兜底人话，不露空串');
    expect(find.textContaining('只从文件树摘掉该挂载及其'), findsNothing);
    await t.tap(find.byKey(const ValueKey('nu-confirm')));
    await t.pumpAndSettle();
    expect(confirmed, 1);
  });
}
