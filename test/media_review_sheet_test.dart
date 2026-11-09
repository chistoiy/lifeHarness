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
import 'package:lifeharness/features/media/presentation/media_notes_page.dart';
import 'package:lifeharness/features/media/presentation/media_providers.dart';

import 'helpers.dart';

/// 影音游批5 · 名场面复习卡（原型 `m-review` · 词典 LH-S36 · 工单 §1.2）。
///
/// 三条口径写在最近处：
/// - 队列与角标**同一份筛选**（屏侧不自己数）：进屏「剩 N 条」＝复习钮角标数＝到期行数；
/// - 记住了＝逐档推进（1→3→7 天，走完三档清排期）；**跳过＝不落库**，
///   只从本轮内存队列摘掉（下次进屏仍按排期出）；
/// - 正面只有正文，**背面才是出处与批注**（正面漏了出处＝没有翻面，批5 原型面自纠过同一条）；
///   卡角一枚不写字的小箭头当翻面线索（拍板⑥）。
///
/// 宿主用真的笔记库屏（复习弹层的两个入口都在那），弹层行为按真实路径走。
/// 独立文件＝全 app 点火类用例拆文件防 isolate 污染（AGENTS 门禁条）。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  const day = 24 * 60 * 60 * 1000;
  late Database db;
  late MediaRepository repo;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    // v39 完整形态（基础 DDL 冻结在 v38，复习三列由 createStatements 尾部补）
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = MediaRepository(db);
  });
  tearDown(() => db.close());

  Future<String> addItem({String title = '沙丘 2', String kind = MediaItem.kMovie}) =>
      repo.addItem(MediaItem(
        kind: kind,
        title: title,
        state: MediaItem.initialState(kind),
        progressWay: MediaItem.defaultWay(kind),
        createdAt: 1,
        updatedAt: 1,
      ));

  /// 记一条「已到期」的笔记：两天前建档 ⇒ 首档（+1 天）已过。
  Future<int?> addDue(String itemId, String kind,
          {required String body, int ageDays = 2, String? thought}) =>
      repo.addNote(MediaNote(
        itemId: itemId,
        kind: kind,
        noteType: MediaNote.kScene,
        body: body,
        thought: thought,
        atMin: 112,
        createdAt: DateTime.now().millisecondsSinceEpoch - ageDays * day,
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

  /// 从笔记库屏打开复习弹层（队列模式）。
  Future<void> openReview(WidgetTester tester) async {
    await tester.tap(find.byKey(MediaNotesPage.kReview));
    await settle5(tester);
    expect(find.byKey(const ValueKey('mdr-sheet')), findsOneWidget);
  }

  Future<MediaNote?> row(int? id) => id == null ? repo.noteById(0) : repo.noteById(id);

  /// 只在复习弹层内找（笔记库卡片在弹层后面画同一句正文，全树 find.text 会数成两个）。
  Finder inSheet(Finder f) => find.descendant(
      of: find.byKey(const ValueKey('mdr-sheet')), matching: f);

  String leftTx(WidgetTester t) =>
      t.widget<Text>(find.byKey(const ValueKey('mdr-left'))).data!;

  testWidgets('队列与角标同源：进屏「剩 N 条」＝角标数＝到期行数', (tester) async {
    await useSurface(tester, const Size(420, 1400));
    final movie = await addItem();
    await addDue(movie, MediaItem.kMovie, body: '到期一');
    await addDue(movie, MediaItem.kMovie, body: '到期二', ageDays: 5);
    await addDue(movie, MediaItem.kMovie, body: '还没到期', ageDays: 0);
    final c = await pumpNotes(tester);
    expect(tester.widget<Text>(find.descendant(
      of: find.byKey(const ValueKey('mdn-review-badge')),
      matching: find.byType(Text),
    )).data, '2');
    expect(await c.read(mediaDueCountProvider.future), 2);
    await openReview(tester);
    expect(leftTx(tester), '剩 2 条', reason: '队列长度与角标一个口径');
  });

  testWidgets('正面不出出处与条目名，翻面才出（卡角小箭头不写字）', (tester) async {
    await useSurface(tester, const Size(420, 1400));
    final movie = await addItem();
    // a 到期早于 b ⇒ 先看带批注的那条，推档后看没批注的那条
    await addDue(movie, MediaItem.kMovie,
        body: '保罗站在水面上的那一眼', thought: '这句是全片的轴', ageDays: 5);
    await addDue(movie, MediaItem.kMovie, body: '没写批注的那条', ageDays: 2);
    await pumpNotes(tester);
    await openReview(tester);
    expect(inSheet(find.text('保罗站在水面上的那一眼')), findsOneWidget);
    expect(find.descendant(
        of: find.byKey(const ValueKey('mdr-front')),
        matching: find.textContaining('沙丘 2')), findsNothing,
        reason: '背面信息漏在正面＝没有翻面');
    expect(inSheet(find.textContaining('这句是全片的轴')), findsNothing);
    // 翻面线索＝卡角箭头，不写教学文案
    expect(find.byKey(const ValueKey('mdr-corner')), findsOneWidget);
    expect(find.textContaining('翻面'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('mdr-card')));
    await settle5(tester);
    expect(find.textContaining('电影 · 《沙丘 2》'), findsOneWidget);
    expect(inSheet(find.textContaining('1:52')), findsOneWidget);
    expect(inSheet(find.text('这句是全片的轴')), findsOneWidget);
    expect(find.byKey(const ValueKey('mdr-no-thought')), findsNothing);
    // 下一条没写批注＝背面给一句实话，不留空白
    await tester.tap(find.byKey(const ValueKey('mdr-remember')));
    await settle5(tester);
    expect(inSheet(find.text('没写批注的那条')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('mdr-card')));
    await settle5(tester);
    expect(find.byKey(const ValueKey('mdr-no-thought')), findsOneWidget);
    expect(find.text('未写批注'), findsOneWidget);
  });

  testWidgets('档位派生 1/3/7 且「记住了」逐档推进（走完三档清排期）', (tester) async {
    await useSurface(tester, const Size(420, 1400));
    final movie = await addItem();
    final first = await addDue(movie, MediaItem.kMovie, body: '第一档');
    await pumpNotes(tester);
    await openReview(tester);
    final scheme = Theme.of(
        tester.element(find.byKey(const ValueKey('mdr-stages'))))
        .colorScheme;
    // 当前档高亮＝第 0 档（1 天）；三档 chips 都在但不许点跳档（只读行）
    Color chipColor(int gap) => ((tester
            .widget<Container>(find.byKey(ValueKey('mdr-stage-$gap')))
            .decoration!) as BoxDecoration)
        .color!;
    expect(chipColor(1), scheme.primary.withValues(alpha: .16));
    expect(chipColor(3) == scheme.primary.withValues(alpha: .16), isFalse);
    expect(find.byKey(const ValueKey('mdr-stage-mastered')), findsNothing);

    final now = DateTime.now().millisecondsSinceEpoch;
    await tester.tap(find.byKey(const ValueKey('mdr-remember')));
    await settle5(tester);
    await clearToasts(tester);
    final after = await row(first);
    expect(after!.reviewStage, 1, reason: '记住了＝推一档');
    expect(after.reviewedAt, isNotNull);
    expect(after.nextReviewAt! - now, closeTo(3 * day, 5 * 1000),
        reason: '新档按 3 天排（1→3→7）');
    // 队列只有这一条 ⇒ 推档后本轮见底＝虚线空态
    expect(find.byKey(const ValueKey('mdr-empty')), findsOneWidget);
    expect(find.text('今天没有到期的复习'), findsOneWidget);
    // 角标随推档退场（该条下次到期在 3 天后）
    expect(find.byKey(const ValueKey('mdn-review-badge')), findsNothing);

    // 手工把一行摆到最后一档且仍到期：走完＝清排期，之后不再进队列
    final last = await addDue(movie, MediaItem.kMovie, body: '最后一档', ageDays: 4);
    await db.update(md.tMediaNotes, {'review_stage': 2, 'next_review_at': now - day},
        where: 'id = ?', whereArgs: [last]);
    await tester.tapAt(const Offset(6, 6)); // 先收起当前弹层（角标已退，队列见底）
    await settle5(tester);
    await tester.tap(find.byKey(MediaNotesPage.kReview));
    await settle5(tester);
    expect(inSheet(find.text('最后一档')), findsOneWidget);
    expect(find.byKey(const ValueKey('mdr-stage-mastered')), findsNothing,
        reason: '第 2 档（7 天）还没走完，不该显示已走完');
    expect(chipColor(7), scheme.primary.withValues(alpha: .16));
    await tester.tap(find.byKey(const ValueKey('mdr-remember')));
    await settle5(tester);
    final done = await row(last);
    expect(done!.reviewStage, MediaNote.masteredStage);
    expect(done.nextReviewAt, isNull, reason: '走完三档＝清排期（copyWith 的 null 当「不改」，必须走哨兵）');
    expect(await repo.dueReviewCount(), 0, reason: '走完三档＝不再排队');
    // 本轮队列随之见底（推档后摘出），再进屏也不会把它带回来
    expect(find.byKey(const ValueKey('mdr-empty')), findsOneWidget);
    await tester.tapAt(const Offset(6, 6));
    await settle5(tester);
    await tester.tap(find.byKey(MediaNotesPage.kReview));
    await settle5(tester);
    expect(find.text('今天没有到期的复习'), findsOneWidget);
  });

  testWidgets('跳过＝不落库（只摘本轮内存队列）', (tester) async {
    await useSurface(tester, const Size(420, 1400));
    final movie = await addItem();
    // 到期时刻：a 早于 b ⇒ 队列顺序 [a, b]（队列按 next_review_at 升序）
    final a = await addDue(movie, MediaItem.kMovie, body: '先跳这条', ageDays: 5);
    final b = await addDue(movie, MediaItem.kMovie, body: '再看这条', ageDays: 2);
    await pumpNotes(tester);
    await openReview(tester);
    expect(inSheet(find.text('先跳这条')), findsOneWidget);
    final before = await row(a);
    await tester.tap(find.byKey(const ValueKey('mdr-skip')));
    await settle5(tester);
    expect(inSheet(find.text('再看这条')), findsOneWidget, reason: '跳过＝下一条');
    expect(leftTx(tester), '剩 1 条');
    final after = await row(a);
    expect(after!.reviewStage, before!.reviewStage, reason: '跳过不许改档位');
    expect(after.nextReviewAt, before.nextReviewAt, reason: '跳过不许改排期');
    expect(after.updatedAt, before.updatedAt, reason: '跳过不许动行');
    // 下一轮进屏它仍会出现（本轮摘除≠永久不再复习＝拍板③）
    await tester.tap(find.byKey(const ValueKey('mdr-remember')));
    await settle5(tester);
    await tester.tapAt(const Offset(6, 6));
    await settle5(tester);
    await tester.tap(find.byKey(MediaNotesPage.kReview));
    await settle5(tester);
    expect(inSheet(find.text('先跳这条')), findsOneWidget);
    expect(b, isNotNull);
  });

  testWidgets('单条模式＝只翻面不改动（无队列条数、无档位动作）', (tester) async {
    await useSurface(tester, const Size(420, 1400));
    final movie = await addItem();
    final id = await addDue(movie, MediaItem.kMovie, body: '从卡面点进来的那句');
    final c = await pumpNotes(tester);
    c.read(mediaNoteViewProvider.notifier).state = 'card';
    await settle5(tester);
    await tester.tap(find.byKey(ValueKey('mdn-card-$id')));
    await settle5(tester);
    expect(find.text('复习卡'), findsOneWidget);
    expect(find.text('名场面复习'), findsNothing);
    expect(find.text('单条'), findsOneWidget,
        reason: '原型 #mRevPos 位置槽在单条模式写「单条」＝不蹭档位的可见交代');
    expect(find.byKey(const ValueKey('mdr-stages')), findsNothing);
    expect(find.byKey(const ValueKey('mdr-remember')), findsNothing);
    expect(find.byKey(const ValueKey('mdr-skip')), findsNothing);
    final before = await row(id);
    await tester.tap(find.byKey(const ValueKey('mdr-card')));
    await settle5(tester);
    expect(find.textContaining('电影 · 《沙丘 2》'), findsOneWidget);
    final after = await row(id);
    expect(after!.reviewStage, before!.reviewStage);
    expect(after.nextReviewAt, before.nextReviewAt);
  });

  testWidgets('队列吃笔记库那六路筛选（筛到游戏就只复习游戏的）', (tester) async {
    await useSurface(tester, const Size(420, 1400));
    final movie = await addItem();
    final game = await addItem(title: '艾尔登法环', kind: MediaItem.kGame);
    await addDue(movie, MediaItem.kMovie, body: '电影里的到期句');
    await addDue(game, MediaItem.kGame, body: '游戏里的到期句', ageDays: 3);
    final c = await pumpNotes(tester);
    c.read(mediaNoteFilterProvider.notifier).state =
        nfKind(kMediaNoteFilterAll, MediaItem.kGame);
    await settle5(tester);
    await openReview(tester);
    expect(leftTx(tester), '剩 1 条');
    expect(inSheet(find.text('游戏里的到期句')), findsOneWidget);
    expect(inSheet(find.text('电影里的到期句')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('mdr-card')));
    await settle5(tester);
    expect(find.textContaining('游戏 · 《艾尔登法环》'), findsOneWidget);
  });
}
