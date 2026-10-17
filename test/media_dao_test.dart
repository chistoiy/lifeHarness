import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema/media.dart' as md;
import 'package:lifeharness/features/media/data/media_repository.dart';
import 'package:lifeharness/features/media/domain/media_item.dart';

/// 影音游批2 · 仓储数据面（工单执行面板第 1 项受影响测试）。
///
/// 独立文件＝全 app 点火类用例拆文件防 isolate 污染（AGENTS 门禁条）。
/// 屏面在 `media_shelf_test.dart` / `media_add_sheet_test.dart`。
void main() {
  sqfliteFfiInit();

  late Database db;
  late MediaRepository repo;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in md.mediaSchemaStatements) {
      await db.execute(sql);
    }
    repo = MediaRepository(db);
  });
  tearDown(() => db.close());

  MediaItem item(
    String title, {
    String kind = MediaItem.kMovie,
    String? state,
    String? way,
    String? progressTo,
    int mainPct = 0,
    int episodesTotal = 0,
    int tracksCount = 0,
    int playthroughs = 0,
    List<String> tags = const [],
  }) => MediaItem(
    kind: kind,
    title: title,
    state: state ?? MediaItem.initialState(kind),
    progressWay: way ?? MediaItem.defaultWay(kind),
    progressTo: progressTo,
    mainPct: mainPct,
    episodesTotal: episodesTotal,
    tracksCount: tracksCount,
    playthroughs: playthroughs,
    tags: tags,
    createdAt: 1,
    updatedAt: 1,
  );

  test('新增两条电影＝在册两条；TEXT 主键由仓储生成且不重', () async {
    final a = await repo.addItem(item('沙丘 2'));
    final b = await repo.addItem(item('奥本海默'));
    expect(a.startsWith('m'), isTrue, reason: 'id 是 TEXT 主键（§2.1）');
    expect(a, isNot(b));
    final list = await repo.items();
    expect(list, hasLength(2));
    expect(list.map((x) => x.title), containsAll(['沙丘 2', '奥本海默']));
    final counts = await repo.kindCounts();
    expect(counts['movie'], 2);
    expect(counts['all'], 2);
  });

  test('在册读取的唯一口径＝deleted_at IS NULL（刀1：摘掉这条谓词本例即红）', () async {
    final keep = await repo.addItem(item('活着'));
    final gone = await repo.addItem(item('要删的那部'));
    await repo.softDelete([gone]);
    final list = await repo.items();
    expect(list.map((x) => x.id), [keep], reason: '软删行不得出现在架面');
    final raw = await db.query(
      md.tMediaItems,
      columns: ['deleted_at'],
      where: 'id = ?',
      whereArgs: [gone],
    );
    expect(raw.single['deleted_at'], isNotNull, reason: '删除＝打标不物理删');
    // 计数与俯瞰同口径：都不能带上软删行
    expect((await repo.kindCounts())['movie'], 1);
    expect((await repo.recentPerKind()).map((x) => x.id), [keep]);
  });

  test('改分区：完结档同步 completed；非完结档回落 0', () async {
    final id = await repo.addItem(item('漫长的季节', kind: MediaItem.kSeries));
    await repo.moveState(id, MediaItem.kSeries, '追完');
    var row = (await db.query(
      md.tMediaItems,
      where: 'id = ?',
      whereArgs: [id],
    )).single;
    expect(row['state'], '追完');
    expect(row['completed'], 1, reason: '追完＝完结标记，统计侧吃这一列');
    await repo.moveState(id, MediaItem.kSeries, '在追');
    row = (await db.query(
      md.tMediaItems,
      where: 'id = ?',
      whereArgs: [id],
    )).single;
    expect(row['completed'], 0);
  });

  test('批量移动：全部类型视图给语义档，逐条按各自 kind 落值，归并标签绝不入库', () async {
    final m = await repo.addItem(item('电影A'));
    final s = await repo.addItem(item('剧集B', kind: MediaItem.kSeries));
    final g = await repo.addItem(item('游戏C', kind: MediaItem.kGame));
    final mu = await repo.addItem(item('专辑D', kind: MediaItem.kMusic));
    final n = await repo.bulkMove([m, s, g, mu], '在看/追/玩', 'all');
    expect(n, 4);
    final states = {
      for (final r in await db.query(md.tMediaItems)) '${r['title']}': '${r['state']}',
    };
    expect(states['电影A'], '在看');
    expect(states['剧集B'], '在追');
    expect(states['游戏C'], '在玩');
    expect(states['专辑D'], '在听');
    expect(
      states.values,
      isNot(contains('在看/追/玩')),
      reason: '归并标签是筛选档不是分区值，写进 state 列＝脏数据',
    );
  });

  test('批量移动：目标档与某条目 kind 无对应值时跳过该条（不硬塞）', () async {
    final m = await repo.addItem(item('电影A'));
    final s = await repo.addItem(item('剧集B', kind: MediaItem.kSeries));
    // 「通关」只有游戏有；电影/剧集两条都应跳过
    expect(await repo.bulkMove([m, s], '通关', 'all'), 0);
    final rows = await db.query(md.tMediaItems);
    expect(rows.map((r) => r['state']), everyElement('未看'));
  });

  test('批量加标签＝追加去重，已有该标签不双写', () async {
    final a = await repo.addItem(item('带标签的', tags: ['通勤']));
    final b = await repo.addItem(item('空标签的'));
    expect(await repo.bulkAddTags([a, b], '通勤'), 1, reason: '已有的一条不重复加');
    expect(await repo.bulkAddTags([a, b], '周末'), 2);
    final tags = {
      for (final r in await db.query(md.tMediaItems)) '${r['title']}': '${r['tags']}',
    };
    expect(tags['带标签的'], '通勤,周末');
    expect(tags['空标签的'], '通勤,周末');
  });

  test('音乐循环次数＝会话条数（表里不存列，派生回填，不写死）', () async {
    final id = await repo.addItem(item('范特西', kind: MediaItem.kMusic));
    for (var i = 0; i < 3; i++) {
      await db.insert(md.tMediaSessions, {
        'item_id': id,
        'kind': MediaItem.kMusic,
        'started_at': 1000 + i,
        'minutes': 40,
      });
    }
    final list = await repo.items();
    expect(list.single.listenLoops, 3);
    expect(list.single.metaLine, contains('循环 3 次'));
    // 会话表为空时读 0，不编数
    await db.delete(md.tMediaSessions);
    expect((await repo.items()).single.listenLoops, isNull);
    expect((await repo.items()).single.metaLine, contains('循环 0 次'));
  });

  test('桌面俯瞰＝四类各取最近一条（记录页影音游 tab 用）', () async {
    await repo.addItem(item('老电影'));
    await db.update(
      md.tMediaItems,
      {'last_activity_at': 5000},
      where: 'title = ?',
      whereArgs: ['老电影'],
    );
    await repo.addItem(item('新电影'));
    await db.update(
      md.tMediaItems,
      {'last_activity_at': 9000},
      where: 'title = ?',
      whereArgs: ['新电影'],
    );
    final g = await repo.addItem(item('游戏C', kind: MediaItem.kGame));
    expect(g, isNotEmpty);
    await repo.addItem(item('软删的游戏', kind: MediaItem.kGame));
    final all = await db.query(md.tMediaItems, where: 'title = ?', whereArgs: ['软删的游戏']);
    await repo.softDelete(['${all.single['id']}']);
    final recent = await repo.recentPerKind();
    expect(recent.map((x) => x.title), ['新电影', '游戏C'],
        reason: '每类只留最近一条，且软删那条不算');
    expect(recent.map((x) => x.kind), [MediaItem.kMovie, MediaItem.kGame]);
  });

  test('关键词命中片名/主创/发行/标签四域；分区 chip 只在该 kind 取值域内生效', () async {
    await repo.addItem(item('星际穿越', state: '在看'));// creator 缺省＝未知
    await db.update(
      md.tMediaItems,
      {'creator': '诺兰', 'tags': '科幻'},
      where: 'title = ?',
      whereArgs: ['星际穿越'],
    );
    await repo.addItem(item('奥本海默'));
    expect((await repo.items(query: '诺兰')).map((x) => x.title), ['星际穿越']);
    expect((await repo.items(query: '科幻')).length, 1);
    expect((await repo.items(stateGroup: '在看/追/玩', kind: 'all')).length, 1);
    expect(await repo.items(stateGroup: '在追', kind: MediaItem.kMovie), isEmpty,
        reason: '「在追」不是电影分区＝筛出空，不该串到别的类');
  });

  test('排序：recent 按最近活动倒序、rating 优先我的评分、name 是码位序', () async {
    final a = await repo.addItem(item('甲', state: '在看'));
    final b = await repo.addItem(item('乙', state: '在看'));
    await db.update(
      md.tMediaItems,
      {'last_activity_at': 100, 'created_at': 100},
      where: 'id = ?',
      whereArgs: [a],
    );
    await db.update(
      md.tMediaItems,
      {'last_activity_at': 200, 'created_at': 200},
      where: 'id = ?',
      whereArgs: [b],
    );
    expect((await repo.items(sort: 'recent')).map((x) => x.title), ['乙', '甲']);
    await db.update(
      md.tMediaItems,
      {'my_rating': 9.5},
      where: 'id = ?',
      whereArgs: [a],
    );
    expect((await repo.items(sort: 'rating')).first.title, '甲');
    expect((await repo.items(sort: '非法值随便传')).length, 2,
        reason: '非白名单排序键回落 recent，不吃外部拼接');
    // name 档实测口径＝码位序（NOCASE 只折叠 ASCII）：拉丁标题按字母排，
    // 中文标题不保证拼音序——这条是能力边界，出处见仓储 `_orderBy` 注释。
    await repo.addItem(item('Oppenheimer'));
    await repo.addItem(item('Dune'));
    final names = (await repo.items(sort: 'name')).map((x) => x.title).toList();
    expect(names.indexOf('Dune') < names.indexOf('Oppenheimer'), isTrue);
    expect(names.indexOf('甲') < names.indexOf('乙'), isFalse,
        reason: '甲 U+7532 > 乙 U+4E59＝码位序把乙排在前面（不是拼音序，别当缺陷改）');
  });
}
