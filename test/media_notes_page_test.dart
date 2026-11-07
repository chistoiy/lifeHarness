import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/database/schema/media.dart' as md;
import 'package:lifeharness/features/media/data/media_repo_note.dart';
import 'package:lifeharness/features/media/data/media_repository.dart';
import 'package:lifeharness/features/media/domain/media_item.dart';
import 'package:lifeharness/features/media/domain/media_note.dart';
import 'package:lifeharness/features/media/presentation/media_note_edit_sheet.dart'
    show mediaNoteTypeColor;
import 'package:lifeharness/features/media/presentation/media_notes_page.dart';
import 'package:lifeharness/features/media/presentation/media_providers.dart';
import 'package:lifeharness/shared/widgets/ui_kit.dart' show EmptyDashRow;

import 'helpers.dart';

/// 影音游批5 · 影音笔记库屏（原型 `m-notes` · 词典 LH-C18 · 工单 §⚙ 第 3 项）。
///
/// 屏侧承重口径写在最近处（每条对应一个用例，改动必先过这一屏）：
/// - **四视图吃同一份筛选结果**：切卡片／行／按条目／截图墙，计数行的数字不许漂
///   （＝变异刀 3 钉的那条：谁要是给某个视图另写一条查询，这里必红）；
/// - 六路筛选收在一枚筛选钮后面（拍板①），默认视图＝按条目（拍板②）；
/// - 行内标星就地翻、删除走确认式且**软删**——库内行不物理消失，
///   但笔记库与该条目名场面时间线同帧不见（同一个 `mediaTick` 出口）。
///
/// 独立文件＝全 app 点火类用例拆文件防 isolate 污染（AGENTS 门禁条）。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late MediaRepository repo;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    // 建表走全量 createStatements：mediaSchemaStatements 是冻结在 v38 形态的基础 DDL，
    // 批5 的复习三列由 createStatements 尾部补齐（＝D1 迁移守护同一条坑）。
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = MediaRepository(db);
  });
  tearDown(() => db.close());

  Future<String> addItem(String title, String kind) => repo.addItem(
        MediaItem(
          kind: kind,
          title: title,
          state: MediaItem.initialState(kind),
          progressWay: MediaItem.defaultWay(kind),
          createdAt: 1,
          updatedAt: 1,
        ),
      );

  Future<int?> addNote(
    String itemId,
    String kind, {
    required String type,
    required String body,
    String? tag,
    bool starred = false,
    int? atMin,
    int createdAt = 1,
  }) =>
      repo.addNote(MediaNote(
        itemId: itemId,
        kind: kind,
        noteType: type,
        body: body,
        tag: tag,
        starred: starred,
        atMin: atMin,
        createdAt: createdAt,
      ));

  Future<ProviderContainer> pumpNotes(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [mediaRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: const MediaNotesPage()),
    ));
    await settle5(tester);
    return container;
  }

  /// 计数行读数（原型同式 `$n 条 · 标星 m`）——四视图比的就是这个数。
  /// 键挂在外层 Padding，文本是它的后代（取 Text 要走 descendant）。
  String countTx(WidgetTester tester) => tester
      .widget<Text>(find.descendant(
          of: find.byKey(MediaNotesPage.kCount), matching: find.byType(Text)))
      .data!;

  int countOf(WidgetTester tester) => int.parse(countTx(tester).split(' 条').first);

  /// 复习角标读数（同样：键在 Container 上，数字是它的 Text 子项）。
  Finder badgeTx(WidgetTester tester) => find.descendant(
      of: find.byKey(const ValueKey('mdn-review-badge')),
      matching: find.byType(Text));

  Future<void> setFilter(
    WidgetTester tester,
    ProviderContainer c,
    MediaNoteFilter f,
  ) async {
    c.read(mediaNoteFilterProvider.notifier).state = f;
    await settle5(tester);
  }

  /// 该视图**实际画出来的笔记数**（计数行说了 6 条，画面就得有 6 条）：
  /// 卡片／按条目画 `mdn-card-*`，行视图画 `mdn-row-*`，截图墙画 `mdn-wall-*`。
  int drawnCount(WidgetTester tester, String view) {
    final prefix = switch (view) {
      'list' => 'mdn-row-',
      'wall' => 'mdn-wall-',
      _ => 'mdn-card-',
    };
    return find
        .byWidgetPredicate((w) =>
            w.key is ValueKey &&
            (w.key as ValueKey).value.toString().startsWith(prefix))
        .evaluate()
        .length;
  }

  /// 依次切四档视图，各取一次「计数行读数」与「实画条数」。
  Future<List<(int, int)>> countsAcrossViews(WidgetTester tester) async {
    final out = <(int, int)>[];
    for (final (k, _) in MediaNotesPage.views) {
      await tester.tap(find.byKey(ValueKey('mdn-view-$k')));
      await settle5(tester);
      out.add((countOf(tester), drawnCount(tester, k)));
    }
    return out;
  }

  /// 卡片面左侧色标（竖条＝ClipRRect 上的叠层，键 `mdn-accent-<id>`；
  /// 写进 `Border(left: …)` 会与圆角互斥并在 paint 阶段炸卡，故取色只看这一条）。
  Color cardAccent(WidgetTester tester, int id) => tester
      .widget<ColoredBox>(find.byKey(ValueKey('mdn-accent-$id')))
      .color;

  testWidgets('默认视图＝按条目（拍板②），分组标题带每组计数', (tester) async {
    await useSurface(tester, const Size(420, 1000));
    final movie = await addItem('沙丘 2', MediaItem.kMovie);
    await addNote(movie, MediaItem.kMovie,
        type: MediaNote.kScene, body: '保罗站在水面上的那一眼');
    await addNote(movie, MediaItem.kMovie, type: MediaNote.kLine, body: '谁想控制一切');
    await pumpNotes(tester);
    expect(find.byKey(ValueKey('mdn-group-$movie')), findsOneWidget);
    expect(find.text('《沙丘 2》 · 2 条'), findsOneWidget);
    // 分组档不带行内动作（原型同形：动作在卡片/行视图给）
    expect(find.byKey(const ValueKey('mdn-view-byitem')), findsOneWidget);
    expect(countTx(tester), '2 条 · 标星 0', reason: '计数行与原型同式（条数＋其中标星数）');
  });

  testWidgets('六路筛选组合后，四视图计数一致（刀 3 靶：一份数据四种画法）', (tester) async {
    // 视口垫高：懒构建 ListView 视口外的子项不建，实画条数会假少
    await useSurface(tester, const Size(420, 2400));
    final movie = await addItem('沙丘 2', MediaItem.kMovie);
    final game = await addItem('艾尔登法环', MediaItem.kGame);
    // 本地种子表＝期望值的唯一来源（不拿仓储自己数一遍当对照）
    final seed = <({String item, String kind, String type, String? tag, bool star, String body})>[
      (item: movie, kind: MediaItem.kMovie, type: MediaNote.kScene, tag: '高光', star: true, body: '水面上的那一眼'),
      (item: movie, kind: MediaItem.kMovie, type: MediaNote.kLine, tag: '高光', star: false, body: '谁想控制一切'),
      (item: movie, kind: MediaItem.kMovie, type: MediaNote.kLyric, tag: null, star: false, body: '啊这旋律'),
      (item: movie, kind: MediaItem.kMovie, type: MediaNote.kLong, tag: '摄影', star: true, body: '沙漠拍成了海'),
      (item: game, kind: MediaItem.kGame, type: MediaNote.kScene, tag: '高光', star: false, body: '史东贝利亚的龙'),
      (item: game, kind: MediaItem.kGame, type: MediaNote.kShot, tag: null, star: false, body: '雾林夜景截图'),
    ];
    for (final n in seed) {
      await addNote(n.item, n.kind,
          type: n.type, body: n.body, tag: n.tag, starred: n.star);
    }
    final c = await pumpNotes(tester);

    final cases = <(MediaNoteFilter, int, String)>[
      (kMediaNoteFilterAll, 6, '不筛'),
      (nfType(kMediaNoteFilterAll, MediaNote.kScene), 2, '只看名场面'),
      (nfKind(kMediaNoteFilterAll, MediaItem.kGame), 2, '只看游戏'),
      (nfItem(kMediaNoteFilterAll, movie), 4, '只看沙丘 2'),
      (nfTag(kMediaNoteFilterAll, '高光'), 3, '只看标签高光'),
      (nfStarred(kMediaNoteFilterAll, true), 2, '只看标星'),
      (nfQuery(kMediaNoteFilterAll, '龙'), 1, '关键词命中条目内正文'),
      // 组合路：类型＋类别＋标星（三路同时生效才是「一份 where」）
      (
        nfStarred(nfType(nfKind(kMediaNoteFilterAll, MediaItem.kMovie), MediaNote.kScene), true),
        1,
        '电影＋名场面＋标星',
      ),
    ];
    for (final (f, want, why) in cases) {
      await setFilter(tester, c, f);
      final got = await countsAcrossViews(tester);
      expect(got.map((e) => e.$1).toList(), List.filled(4, want),
          reason: '$why：四档视图计数行应一致（实得 ${got.map((e) => e.$1).toList()}）');
      expect(got.map((e) => e.$2).toList(), List.filled(4, want),
          reason: '$why：实画条数必须＝计数行读数——某个视图另写一条查询，这里必红（刀 3）');
      // 与本地种子表现算的条数对齐（防「筛错了但四视图一致」的假绿）
      final local = seed.where((n) =>
          (f.type == null || n.type == f.type) &&
          (f.kind == null || n.kind == f.kind) &&
          (f.itemId == null || n.item == f.itemId) &&
          (f.tag == null || n.tag == f.tag) &&
          (!f.starred || n.star) &&
          (f.query.trim().isEmpty || n.body.contains(f.query.trim())));
      expect(want, local.length, reason: '$why：面板期望值与种子表现算不符');
    }
  });

  testWidgets('筛选钮带激活计数＋已选摘要行＋清空（拍板①）', (tester) async {
    await useSurface(tester, const Size(420, 1200));
    final movie = await addItem('沙丘 2', MediaItem.kMovie);
    await addNote(movie, MediaItem.kMovie,
        type: MediaNote.kScene, body: '水面上', tag: '高光');
    await addNote(movie, MediaItem.kMovie, type: MediaNote.kLine, body: '另一句');
    final c = await pumpNotes(tester);
    expect(find.text('筛选'), findsOneWidget);
    expect(find.byKey(MediaNotesPage.kSummary),
        findsOneWidget,
        reason: '未加筛选也要有一句实话，不留空位');
    expect(tester.widget<Text>(find.byKey(MediaNotesPage.kSummary)).data,
        '未加筛选 · 看在册全部笔记');
    expect(find.byKey(const ValueKey('mdn-clear')), findsNothing,
        reason: '零条件时不给「清空」摆设');

    // 面板内选两路 → 应用：钮计数、摘要行随动
    await tester.tap(find.byKey(MediaNotesPage.kFilterBtn));
    await settle5(tester);
    expect(find.text('筛选影音笔记'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mdn-f-类型-名场面')));
    await settle5(tester);
    await tester.tap(find.byKey(const ValueKey('mdn-f-标签-高光')));
    await settle5(tester);
    await tester.tap(find.byKey(const ValueKey('mdn-filter-apply')));
    await settle5(tester);
    expect(find.text('筛选 · 2'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(MediaNotesPage.kSummary)).data,
        '已选：名场面 · 高光');
    expect(countOf(tester), 1);

    // 取消＝草稿不落屏（面板改的是草稿）
    await tester.tap(find.byKey(MediaNotesPage.kFilterBtn));
    await settle5(tester);
    await tester.tap(find.byKey(const ValueKey('mdn-f-类型-长评')));
    await tester.tap(find.byKey(const ValueKey('mdn-filter-cancel')));
    await settle5(tester);
    expect(find.text('筛选 · 2'), findsOneWidget, reason: '取消不该改屏');

    await tester.tap(find.byKey(const ValueKey('mdn-clear')));
    await settle5(tester);
    expect(find.text('筛选'), findsOneWidget);
    expect(countOf(tester), 2);
    expect(c.read(mediaNoteFilterProvider), kMediaNoteFilterAll);
  });

  testWidgets('五类色标按 type 落对（词典 LH-C18 的 Flutter 落面）', (tester) async {
    await useSurface(tester, const Size(420, 1400));
    final movie = await addItem('沙丘 2', MediaItem.kMovie);
    final ids = <String, int>{};
    for (final t in MediaNote.noteTypes) {
      ids[t] = (await addNote(movie, MediaItem.kMovie,
              type: t, body: '内容·$t', createdAt: 100 + MediaNote.noteTypes.indexOf(t)))!;
    }
    final c = await pumpNotes(tester);
    c.read(mediaNoteViewProvider.notifier).state = 'card';
    await settle5(tester);
    final seen = <Color>{};
    for (final t in MediaNote.noteTypes) {
      final accent = cardAccent(tester, ids[t]!);
      expect(accent, mediaNoteTypeColor(t), reason: '$t 的色标应与词典同源');
      seen.add(accent);
    }
    expect(seen.length, MediaNote.noteTypes.length,
        reason: '五类色标互不相同，否则色标等于没标');
    expect(
      {for (final t in MediaNote.noteTypes) mediaNoteTypeColor(t)}.length,
      MediaNote.noteTypes.length,
    );
    // 卡片头部那行是「类型 · 条目名」拼成的一句，取文本要看得到类名（非精确匹配）
    expect(
      find.textContaining(MediaNote.typeLabels[MediaNote.kLyric]!),
      findsWidgets,
    );
  });

  testWidgets('行内标星即时翻转：就地变、不跳页不开弹层', (tester) async {
    await useSurface(tester, const Size(420, 1200));
    final movie = await addItem('沙丘 2', MediaItem.kMovie);
    final id = (await addNote(movie, MediaItem.kMovie,
        type: MediaNote.kScene, body: '水面上', createdAt: 5))!;
    final c = await pumpNotes(tester);
    c.read(mediaNoteViewProvider.notifier).state = 'card';
    await settle5(tester);
    expect(find.byIcon(Icons.star_border), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('mdn-star-$id')));
    await settle5(tester);
    expect(find.byIcon(Icons.star), findsOneWidget, reason: '点一下即实心');
    expect(countTx(tester), contains('标星 1'), reason: '标星数就地跟（同一条记录的两面）');
    expect(find.byKey(const ValueKey('mdn-sheet')), findsNothing,
        reason: '标星是就地动作，不许开弹层');
    expect(find.byKey(const ValueKey('mde-body')), findsNothing,
        reason: '标星不许把录入表单带出来');
    final row = await db.query(md.tMediaNotes, where: 'id = ?', whereArgs: [id]);
    expect(row.single['starred'], 1);
    // 再点一下关回去（同一枚钮两态，不做「只能标不能去」）
    await tester.tap(find.byKey(ValueKey('mdn-star-$id')));
    await settle5(tester);
    expect(find.byIcon(Icons.star_border), findsOneWidget);
  });

  testWidgets('删除＝确认式且软删；笔记库与条目时间线同帧不见', (tester) async {
    await useSurface(tester, const Size(420, 1200));
    final movie = await addItem('沙丘 2', MediaItem.kMovie);
    final keep = (await addNote(movie, MediaItem.kMovie,
        type: MediaNote.kLine, body: '留下那句', createdAt: 3))!;
    final gone = (await addNote(movie, MediaItem.kMovie,
        type: MediaNote.kScene, body: '删掉那句', createdAt: 4))!;
    final c = await pumpNotes(tester);
    c.read(mediaNoteViewProvider.notifier).state = 'card';
    await settle5(tester);

    await tester.tap(find.byKey(ValueKey('mdn-del-$gone')));
    await settle5(tester);
    expect(find.textContaining('删掉这条影音笔记'), findsOneWidget,
        reason: '删除先确认（LH-S31）');
    await tester.tap(find.byKey(const ValueKey('d-confirm-cancel')));
    await settle5(tester);
    expect(find.byKey(ValueKey('mdn-card-$gone')), findsOneWidget,
        reason: '取消＝不删');

    await tester.tap(find.byKey(ValueKey('mdn-del-$gone')));
    await settle5(tester);
    await tester.tap(find.byKey(const ValueKey('d-confirm-ok')));
    await clearToasts(tester);
    expect(find.byKey(ValueKey('mdn-card-$gone')), findsNothing);
    expect(find.byKey(ValueKey('mdn-card-$keep')), findsOneWidget);
    expect(countOf(tester), 1);

    // 软删＝行还在、带 deleted_at（审计面留痕），但读取出口一律不见
    final raw = await db.query(md.tMediaNotes, where: 'id = ?', whereArgs: [gone]);
    expect(raw.single['deleted_at'], isNotNull, reason: '不许物理删行');
    expect(await repo.notesOfItem(movie), hasLength(1),
        reason: '条目名场面时间线走同一出口＝同帧消失');
    expect(await repo.noteById(gone), isNull);
  });

  testWidgets('空态两档分话术：库里零笔记 vs 当前筛选零命中', (tester) async {
    await useSurface(tester, const Size(420, 1000));
    final c = await pumpNotes(tester);
    expect(find.text('还没有影音笔记 · 点右上＋记一条'), findsOneWidget);
    // 零笔记档＝虚线行也是补录入口（点开表单）
    await tester.tap(find.byKey(const ValueKey('mdn-empty')));
    await settle5(tester);
    expect(find.text('记一条影音笔记'), findsOneWidget);
    await tester.tapAt(const Offset(6, 6)); // 遮罩收起（表单底部钮在滚动区外，不靠点它关）
    await settle5(tester);
    expect(find.text('记一条影音笔记'), findsNothing);

    final movie = await addItem('沙丘 2', MediaItem.kMovie);
    await addNote(movie, MediaItem.kMovie,
        type: MediaNote.kScene, body: '水面上', createdAt: 2);
    // 测试直接写库＝应用侧的 mediaTick 不会自己动；补一次重取（等价保存后的 _bump）
    c.read(mediaTickProvider.notifier).state++;
    await settle5(tester);
    await setFilter(tester, c, nfQuery(kMediaNoteFilterAll, '查无此句'));
    expect(find.text('当前筛选没有笔记'), findsOneWidget,
        reason: '有笔记但筛空了≠没笔记，两句话术不许混');
    expect(find.text('还没有影音笔记 · 点右上＋记一条'), findsNothing);
    // 筛空档的虚线行不给补录入口（不是「没记过」）
    expect(
      tester.widget<EmptyDashRow>(find.byKey(const ValueKey('mdn-empty'))).onTap,
      isNull,
    );
  });

  testWidgets('复习角标＝吃同一份筛选的到期数（屏侧不自己数）', (tester) async {
    await useSurface(tester, const Size(420, 1200));
    final movie = await addItem('沙丘 2', MediaItem.kMovie);
    final game = await addItem('艾尔登法环', MediaItem.kGame);
    final now = DateTime.now().millisecondsSinceEpoch;
    const day = 24 * 60 * 60 * 1000;
    // 两天前建档＝已过 1 天档（到期）；刚建档的还没到期
    await addNote(movie, MediaItem.kMovie,
        type: MediaNote.kScene, body: '到期一', createdAt: now - 2 * day);
    await addNote(game, MediaItem.kGame,
        type: MediaNote.kLine, body: '到期二', createdAt: now - 3 * day);
    await addNote(movie, MediaItem.kMovie,
        type: MediaNote.kLong, body: '还没到期', createdAt: now);
    final c = await pumpNotes(tester);
    expect(find.byKey(const ValueKey('mdn-review-badge')), findsOneWidget);
    expect(tester.widget<Text>(badgeTx(tester)).data,
        '2');
    // 筛到游戏＝队列口径随筛选变（与笔记库同一份 where），角标跟着变 1
    await setFilter(tester, c, nfKind(kMediaNoteFilterAll, MediaItem.kGame));
    expect(tester.widget<Text>(badgeTx(tester)).data,
        '1');
    // 全部到期都筛没了＝角标退场，不留 0 角标
    await setFilter(tester, c, nfQuery(kMediaNoteFilterAll, '还没到期'));
    expect(find.byKey(const ValueKey('mdn-review-badge')), findsNothing);
  });

  testWidgets('截图墙档：无附件行如实给「无截图」，不画假缩略图', (tester) async {
    await useSurface(tester, const Size(420, 1200));
    final movie = await addItem('沙丘 2', MediaItem.kMovie);
    final noShot = (await addNote(movie, MediaItem.kMovie,
        type: MediaNote.kScene, body: '只有文字', createdAt: 2))!;
    final c = await pumpNotes(tester);
    c.read(mediaNoteViewProvider.notifier).state = 'wall';
    await settle5(tester);
    expect(find.byKey(ValueKey('mdn-wall-$noShot')), findsOneWidget);
    expect(find.text('无截图'), findsOneWidget);
    expect(find.byType(Image), findsNothing, reason: '没有附件就不该有图片节点');
  });
}
