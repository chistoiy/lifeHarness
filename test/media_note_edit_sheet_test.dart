import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/host/event_bus.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/database/schema/core.dart' as core;
import 'package:lifeharness/features/journal/data/journal_dao.dart';
import 'package:lifeharness/features/journal/domain/journal_repository.dart';
import 'package:lifeharness/features/journal/presentation/journal_providers.dart';
import 'package:lifeharness/features/media/data/media_repo_note.dart';
import 'package:lifeharness/features/media/data/media_repository.dart';
import 'package:lifeharness/features/media/domain/media_item.dart';
import 'package:lifeharness/features/media/domain/media_note.dart';
import 'package:lifeharness/features/media/presentation/media_note_edit_sheet.dart';
import 'package:lifeharness/features/media/presentation/media_providers.dart';
import 'package:lifeharness/features/todo/data/todo_dao.dart';
import 'package:lifeharness/features/todo/domain/todo_repository.dart';
import 'package:lifeharness/features/todo/presentation/todo_providers.dart';

import 'helpers.dart';

/// 影音游批5 · 影音笔记唯一录入表单（原型 `m-sheet-note-edit` · 词典 LH-S35）。
///
/// 四条口径写在最近处：
/// - **一个表单面**：条目／类型／时间点／创建时间／附件／标签／正文／粘贴／识图／→日记／→待办
///   全在这一屏，两个入口（详情「＋ 记笔记」与计时「名场面」）不各造一套字段；
/// - 空正文＝**就地红字**（LH-K32），不借提示条——提示条会自己消失，用户回头看不到成因；
/// - 拍板④＝时间点与创建时间并排（两个「何时」挨着）；拍板⑤＝识图**置灰不隐藏**、
///   点击给一句实话；
/// - →日记／→待办＝L5 真写入（走 `shared/linkage` 出口，落库到别页能读到）。
///
/// 独立文件＝全 app 点火类用例拆文件防 isolate 污染（AGENTS 门禁条）。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late MediaRepository repo;
  late EventBus bus;
  late JournalRepository journalRepo;
  late TodoRepository todoRepo;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = MediaRepository(db);
    bus = EventBus();
    journalRepo = JournalRepository(JournalDao(db));
    todoRepo = TodoRepository(TodoDao(db), bus);
  });
  tearDown(() async {
    await bus.dispose();
    await db.close();
  });

  Future<String> addItem({String title = '沙丘 2', String kind = MediaItem.kMovie}) =>
      repo.addItem(MediaItem(
        kind: kind,
        title: title,
        state: MediaItem.initialState(kind),
        progressWay: MediaItem.defaultWay(kind),
        createdAt: 1,
        updatedAt: 1,
      ));

  /// 宿主页＋一枚开表单的钮：入口参数与真页一致（initialItemId/initialAtMin/origin）。
  Future<void> openForm(
    WidgetTester tester, {
    String? initialItemId,
    int? initialAtMin,
    String origin = MediaNote.kOriginManual,
  }) async {
    final container = ProviderContainer(
      overrides: [
        mediaRepositoryProvider.overrideWithValue(repo),
        journalRepositoryProvider.overrideWithValue(journalRepo),
        todoRepositoryProvider.overrideWithValue(todoRepo),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) => Scaffold(
            body: Center(
              child: Builder(builder: (bc) => ElevatedButton(
                    key: const ValueKey('host-open'),
                    onPressed: () => showMediaNoteEditSheet(
                      bc,
                      ref,
                      initialItemId: initialItemId,
                      initialAtMin: initialAtMin,
                      origin: origin,
                    ),
                    child: const Text('open'),
                  )),
            ),
          ),
        ),
      ),
    ));
    await settle5(tester);
    await tester.tap(find.byKey(const ValueKey('host-open')));
    await settle5(tester);
    expect(find.text('记一条影音笔记'), findsOneWidget);
  }

  Future<void> fill(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const ValueKey('mde-body')), text);
    await tester.pump(); // 让 onChanged 撤错的那次 setState 落帧
  }

  Future<void> save(WidgetTester tester) async {
    final btn = find.byKey(const ValueKey('mde-save'));
    await tester.ensureVisible(btn);
    await tester.tap(btn);
  }

  String? errOf(WidgetTester tester, Key key) =>
      tester.widget<TextField>(find.byKey(key)).decoration!.errorText;

  testWidgets('表单字段齐且两个「何时」并排（拍板④）', (tester) async {
    await useSurface(tester, const Size(420, 2000));
    final id = await addItem();
    await openForm(tester, initialItemId: id);
    // 类型五档一次看全（不做「点一下循环切」），每枚带该类色标（词典 LH-C18）
    for (final t in MediaNote.noteTypes) {
      expect(find.byKey(ValueKey('mde-type-$t')), findsOneWidget);
      expect(find.text(MediaNote.typeLabels[t]!), findsOneWidget);
      expect(
        (tester.widget<Container>(find.byKey(ValueKey('mde-type-accent-$t')))
                .decoration! as BoxDecoration)
            .color,
        mediaNoteTypeColor(t),
        reason: '$t 的 chip 色标与笔记库同源',
      );
    }
    for (final k in const ['mde-item', 'mde-at', 'mde-when', 'mde-tag', 'mde-body']) {
      expect(find.byKey(ValueKey(k)), findsOneWidget);
    }
    // 并排＝同一行内（y 中心一致，x 不同）
    final at = tester.getRect(find.byKey(const ValueKey('mde-at')));
    final when = tester.getRect(find.byKey(const ValueKey('mde-when')));
    expect(at.center.dy, when.center.dy, reason: '两个「何时」并排（拍板④）');
    expect(at.center.dx, lessThan(when.center.dx));
    // 条目从入口预置（不再点一次）
    expect(find.textContaining('沙丘 2'), findsWidgets);
  });

  testWidgets('识图置灰不隐藏，点它给一句实话（拍板⑤）', (tester) async {
    await useSurface(tester, const Size(420, 2000));
    final id = await addItem();
    await openForm(tester, initialItemId: id);
    expect(find.byKey(const ValueKey('mde-ocr')), findsOneWidget,
        reason: '能力未装＝置灰不摘钮（§九.4）');
    final opacity = tester.widget<Opacity>(find
        .ancestor(of: find.byKey(const ValueKey('mde-ocr')), matching: find.byType(Opacity))
        .first);
    expect(opacity.opacity, lessThan(1), reason: '置灰要看得出来是灰的');
    await tester.tap(find.byKey(const ValueKey('mde-ocr')));
    expect(await pollText(tester, '未安装识别库 · 可用「＋附件」与「粘贴文本」'), isTrue);
    await clearToasts(tester);
  });

  testWidgets('空正文＝就地红字且不落库，补输入即撤', (tester) async {
    await useSurface(tester, const Size(420, 2000));
    final id = await addItem();
    await openForm(tester, initialItemId: id);
    await save(tester);
    await settle5(tester);
    expect(errOf(tester, const ValueKey('mde-body')), '先写正文',
        reason: '文案照原型 #mdNoteErr，不另造口径');
    expect(await repo.noteCount(), 0, reason: '报错不许顺手落一行');
    expect(find.byType(SnackBar), findsNothing, reason: '不借道提示条');
    await fill(tester, '补一句');
    expect(errOf(tester, const ValueKey('mde-body')), isNull);
  });

  testWidgets('保存连点只落一条（防重入）', (tester) async {
    await useSurface(tester, const Size(420, 2000));
    final id = await addItem();
    await openForm(tester, initialItemId: id);
    await fill(tester, '保罗站在水面上的那一眼');
    final btn = find.byKey(const ValueKey('mde-save'));
    await tester.ensureVisible(btn);
    await tester.tap(btn);
    await tester.tap(btn); // 同帧再点一次＝真实连点场景
    await settle5(tester);
    await clearToasts(tester);
    expect(await repo.noteCount(), 1);
    final rows = await repo.notes();
    expect(rows.single.body, '保罗站在水面上的那一眼');
    expect(rows.single.origin, MediaNote.kOriginManual);
  });

  testWidgets('同一句再记一次给实话，不落第二行（判重）', (tester) async {
    await useSurface(tester, const Size(420, 2000));
    final id = await addItem();
    await openForm(tester, initialItemId: id);
    await fill(tester, '谁想控制一切');
    await save(tester);
    await settle5(tester);
    await clearToasts(tester);
    await openForm(tester, initialItemId: id);
    await fill(tester, '谁想控制一切');
    await save(tester);
    await settle5(tester);
    expect(await pollText(tester, '这条已经记过了 · 内容是同一句'), isTrue,
        reason: '判重命中不许谎报「已记入」');
    await clearToasts(tester);
    expect(await repo.noteCount(), 1);
  });

  testWidgets('计时入口＝时间点预置＋来源列落 session', (tester) async {
    await useSurface(tester, const Size(420, 2000));
    final id = await addItem();
    await openForm(tester,
        initialItemId: id,
        initialAtMin: 112,
        origin: MediaNote.kOriginSession);
    expect(
      tester.widget<TextField>(find.byKey(const ValueKey('mde-at'))).controller!.text,
      '1:52',
    );
    await fill(tester, '沙丘的热带雨林镜头');
    await save(tester);
    await settle5(tester);
    await clearToasts(tester);
    final n = (await repo.notes()).single;
    expect(n.origin, MediaNote.kOriginSession, reason: '「记一次」来源列要能追');
    expect(n.atMin, 112);
    expect(n.itemId, id);
    expect(n.kind, MediaItem.kMovie, reason: 'kind 随条目落，笔记库筛 kind 才不回落');
  });

  testWidgets('创建时间写成 2026-03-05＝按那天入账；乱写给实话不落脏值', (tester) async {
    await useSurface(tester, const Size(420, 2000));
    final id = await addItem();
    await openForm(tester, initialItemId: id);
    await fill(tester, '补记的那一句');
    await tester.enterText(find.byKey(const ValueKey('mde-when')), '2026-3-5');
    await save(tester);
    await settle5(tester);
    await clearToasts(tester);
    final n = (await repo.notes()).single;
    expect(DateTime.fromMillisecondsSinceEpoch(n.createdAt), DateTime(2026, 3, 5));

    await openForm(tester, initialItemId: id);
    await fill(tester, '另一句');
    await tester.enterText(find.byKey(const ValueKey('mde-when')), '2026-13-99');
    await save(tester);
    await settle5(tester);
    expect(await pollText(tester, '创建时间没看懂 · 用 2026-03-05 这种写法'), isTrue,
        reason: '越界值必须自己卡（Dart 会把它归成 2027-04-09）');
    await clearToasts(tester);
    expect(await repo.noteCount(), 1);
  });

  testWidgets('粘贴文本进正文（剪贴板走 mock，不发真异步 I/O）', (tester) async {
    await useSurface(tester, const Size(420, 2000));
    const pasted = '从别处抄来的一句';
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    // 剪贴板走 mock（真异步 channel 在 FakeAsync 下不返回＝既定坑）
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') return <String, String?>{'text': pasted};
      return null;
    });
    addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null));
    final id = await addItem();
    await openForm(tester, initialItemId: id);
    final paste = find.byKey(const ValueKey('mde-paste'));
    await tester.ensureVisible(paste);
    await tester.tap(paste);
    await settle5(tester);
    expect(
      tester.widget<TextField>(find.byKey(const ValueKey('mde-body'))).controller!.text,
      pasted,
    );
  });

  testWidgets('→日记＝真写进今日草稿，重复点给实话（L5）', (tester) async {
    await useSurface(tester, const Size(420, 2000));
    final id = await addItem();
    await openForm(tester, initialItemId: id);
    await fill(tester, '今天这段值得留进日记');
    final link = find.byKey(const ValueKey('mde-to-journal'));
    await tester.ensureVisible(link);
    await tester.tap(link);
    await settle5(tester);
    expect(await pollText(tester, '已插入今日日记草稿'), isTrue);
    final rows = await db.query(core.tJournal);
    expect(rows, hasLength(1));
    expect(rows.single['content'], contains('影音笔记 · 《沙丘 2》'));
    expect(rows.single['content'], contains('今天这段值得留进日记'));
    // 重复点＝实话，不重复插两段
    await tester.tap(link);
    await settle5(tester);
    expect(await pollText(tester, '这条已插入过今日日记'), isTrue);
    expect(await db.query(core.tJournal), hasLength(1));
    await clearToasts(tester);
  });

  testWidgets('→待办＝真生成一条无截止日任务（L5）', (tester) async {
    await useSurface(tester, const Size(420, 2000));
    final id = await addItem();
    await openForm(tester, initialItemId: id);
    await fill(tester, '把这段剪成短片');
    final link = find.byKey(const ValueKey('mde-to-todo'));
    await tester.ensureVisible(link);
    await tester.tap(link);
    await settle5(tester);
    expect(await pollText(tester, '已生成待办 · 去待办页可见'), isTrue);
    final rows = await db.query(core.tTodos);
    expect(rows, hasLength(1));
    expect(rows.single['title'], '把这段剪成短片');
    expect(rows.single['tag'], '影音游');
    expect(rows.single['due_at'], isNull, reason: 'L5 原口径＝无截止日');
    expect(rows.single['note'], contains('影音笔记 · 《沙丘 2》'));
    await clearToasts(tester);
    // 表单没关掉，保存仍可用
    await save(tester);
    await settle5(tester);
    await clearToasts(tester);
    expect((await repo.notes()).single.body, '把这段剪成短片');
  });

  test('时间点出端与反解同式（112 ↔ 1:52·「59 分」吃得回·看不懂给 null）', () {
    // 计时页把读数预填进表单＝出端产物，保存时走反解；两式不同＝时间点静默丢失
    expect(mediaNoteAtTx(112), '1:52');
    expect(mediaNoteParseAt(mediaNoteAtTx(112)), 112);
    expect(mediaNoteParseAt(mediaNoteAtTx(59)), 59, reason: '「59 分」这种出端写法必须吃得回去');
    expect(mediaNoteParseAt('1:52:14'), 112, reason: '时:分:秒取整分');
    expect(mediaNoteParseAt('112'), 112);
    expect(mediaNoteParseAt(''), isNull);
    expect(mediaNoteParseAt('1:ab'), isNull, reason: '看不懂＝不落值，不猜');
    expect(mediaNoteAtTx(null), '');
  });
}
