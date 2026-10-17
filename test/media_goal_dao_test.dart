import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema/core.dart' as core;
import 'package:lifeharness/core/database/schema/media.dart' as md;
import 'package:lifeharness/features/media/data/media_repo_goal.dart';
import 'package:lifeharness/features/media/data/media_repo_session.dart';
import 'package:lifeharness/features/media/data/media_repository.dart';
import 'package:lifeharness/features/media/domain/media_goal.dart';
import 'package:lifeharness/features/media/domain/media_item.dart';
import 'package:lifeharness/features/media/domain/media_note.dart';
import 'package:lifeharness/features/media/domain/media_session.dart';
import 'package:lifeharness/features/media/presentation/media_providers.dart';

/// 批8a · media_goals 建表（v39→v40）＋目标读写＋设置 KV 回落的常驻闸（工单 §⚙ 第 3 项）。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late MediaRepository repo;

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day, 20);
  DateTime day(int back, {int hour = 10}) =>
      DateTime(today.year, today.month, today.day, hour)
          .subtract(Duration(days: back));

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in md.mediaSchemaStatements) {
      await db.execute(sql);
    }
    await db.execute(
      'CREATE TABLE IF NOT EXISTS ${core.tSettings} (key TEXT PRIMARY KEY, value TEXT)',
    );
    repo = MediaRepository(db);
  });
  tearDown(() => db.close());

  Future<void> addScene(DateTime created, {bool deleted = false}) =>
      db.insert(md.tMediaNotes, {
        'item_id': 'x1',
        'kind': MediaItem.kMovie,
        'note_type': MediaNote.kScene,
        'body': '名场面 $created',
        'created_at': created.millisecondsSinceEpoch,
        'updated_at': created.millisecondsSinceEpoch,
        'deleted_at': deleted ? created.millisecondsSinceEpoch : null,
      });

  test('media_goals 未设＝零行；setGoal 覆盖写；clearGoal 删行回虚线', () async {
    expect(await repo.goalRows(), isEmpty);
    await repo.setGoal('movieMin', 'min', 80);
    var rows = await repo.goalRows();
    expect(rows.length, 1);
    expect(rows.single.target, 80);
    expect(rows.single.unit, 'min');
    expect(rows.single.updatedAt, isNotNull);
    await repo.setGoal('movieMin', 'min', 100);
    rows = await repo.goalRows();
    expect(rows.length, 1, reason: '同指标覆盖写，不堆历史行');
    expect(rows.single.target, 100);
    expect(await repo.clearGoal('movieMin'), 1);
    expect(await repo.goalRows(), isEmpty);
  });

  test('六路定义齐（行序＝kMdsGoalDefs 固定）；游玩滚轮存 0.1h 整数', () async {
    expect(kMdsGoalDefs.map((d) => d.k),
        ['movieMin', 'musicH', 'gameH', 'doneN', 'dayN', 'sceneN']);
    // 滚轮档对齐原型 mGoalItems：观影 10~300 步 10、听歌 1~48、天数 1~7。
    expect(mdsGoalWheelLabels('movieMin').first, '10');
    expect(mdsGoalWheelLabels('movieMin').last, '300');
    expect(mdsGoalWheelLabels('dayN').length, 7);
    expect(mdsGoalWheelLabels('gameH').first, '5', reason: '0.5h 存 5（0.1h 刻度）');
    expect(mdsGoalWheelDisplay('gameH').first, '0.5');
    expect(mdsGoalStoreValue('gameH', 0), 5);
    final g = MediaGoal(metric: 'gameH', unit: 'h', target: 36);
    expect(mdsGoalTargetText(g), '3.6 h');
  });

  test('六路读数现算：日/周一起/月窗各不误；影音天数去重；恒吃真实分钟', () {
    MediaSession s(String kind, DateTime start, int min, {double? speed}) =>
        MediaSession(
          itemId: 'x_$kind',
          kind: kind,
          startedAt: start.millisecondsSinceEpoch,
          endedAt: start.add(Duration(minutes: min)).millisecondsSinceEpoch,
          minutes: min,
          speed: speed,
        );
    final base = day(0, hour: 12);
    final weekStart =
        base.subtract(Duration(days: base.weekday - 1));
    // 今天＝周三凌晨实测踩坑：base 是「周一起+0 天 12:00」不是日历今天，今天两条要显式落今天。
    final reads = mdsComputeGoalReads(
      sessions: [
        s(MediaItem.kMovie, DateTime(base.year, base.month, base.day, 9), 50),
        s(MediaItem.kSeries, DateTime(base.year, base.month, base.day, 14), 30),
        s(MediaItem.kMovie, weekStart.subtract(const Duration(days: 1)), 999),
        s(MediaItem.kMusic, weekStart, 120, speed: 2.0),
        s(MediaItem.kGame, day(2), 90),
        s(MediaItem.kGame, weekStart.subtract(const Duration(days: 30)), 9999),
      ],
      items: const [],
      sceneNotesThisMonth: 0,
      now: base,
    );
    expect(reads['movieMin'], 80, reason: '今晨零点起 movie+series 真实分钟（昨日 999 不吃）');
    expect(reads['musicH'], 2.0,
        reason: '恒吃真实＝4.0 是折算值；本周一起算（刀1 摘窗口＝11199/60 独红）');
    expect(reads['gameH'], closeTo(1.5, 1e-9));
    expect(reads['dayN'], 3,
        reason: '今天＋昨天（游戏 90）＋周一起（听歌）＝3 个去重日历日');
  });

  test('看完数＝完结档且达成日在本年；去年完结与软删都不入', () {
    MediaItem x(String id, String state, int? ended, {bool gone = false}) =>
        MediaItem(
          id: id,
          kind: MediaItem.kMovie,
          title: id,
          state: state,
          progressWay: MediaItem.kWayPct,
          endedAt: ended,
          createdAt: 1,
          updatedAt: 1,
          deletedAt: gone ? 1 : null,
        );
    final reads = mdsComputeGoalReads(
      sessions: const [],
      items: [
        x('a', '看完', DateTime.now().millisecondsSinceEpoch),
        x('b', '追完', DateTime.now().millisecondsSinceEpoch),
        x('c', '通关', DateTime.now().millisecondsSinceEpoch),
        x('d', '看完', DateTime.now().subtract(Duration(days: 400)).millisecondsSinceEpoch),
        x('e', '搁置', DateTime.now().millisecondsSinceEpoch),
      ],
      sceneNotesThisMonth: 0,
      now: DateTime.now(),
    );
    expect(reads['doneN'], 3, reason: '看完/追完/通关且本年＝3；去年达成与未完结合不计');
    // 软删过滤在取数口（mediaAllItems），算面只忠实在册份——这里验算面不误收 null endedAt。
    expect(
        mdsComputeGoalReads(
                sessions: const [],
                items: [x('f', '看完', null)],
                sceneNotesThisMonth: 0,
                now: DateTime.now())
            ['doneN'],
        0);
  });

  test('sceneNotesBetween 只吃本月在册行；软删与上月不入（铁口径⑥）', () async {
    await addScene(day(1));
    await addScene(day(0, hour: 1));
    await addScene(day(40));
    await addScene(day(2), deleted: true);
    final got = await repo.sceneNotesBetween(
        DateTime(now.year, now.month), DateTime(now.year, now.month + 1));
    expect(got, 2);
  });

  test('hasSessionOnDay：只认已结算会话；进行中不算今天计时过', () async {
    // 一律用**当下相对**时刻（生产与本件同吃 DateTime.now 这只钟），不混 UTC 锚（凌晨实测坑）。
    final t = DateTime.now();
    final midnight = DateTime(t.year, t.month, t.day);
    Future<void> sess(DateTime start, {bool closed = true}) =>
        db.insert(md.tMediaSessions, {
          'item_id': 'x1',
          'kind': MediaItem.kMovie,
          'started_at': start.millisecondsSinceEpoch,
          'ended_at': closed
              ? start.add(const Duration(minutes: 10)).millisecondsSinceEpoch
              : null,
          'minutes': closed ? 10 : 0,
          'source': 'timer',
        });
    // 今天 00:00 起、不晚于当下的时刻：用「本分钟起点」保证 ended/started 都已发生。
    final nowAligned = DateTime(t.year, t.month, t.day, t.hour, t.minute);
    await sess(nowAligned, closed: false);
    expect(await repo.hasSessionOnDay(midnight), isFalse,
        reason: '进行中（ended NULL）不算今天计时过');
    await sess(nowAligned.subtract(const Duration(minutes: 1)));
    expect(await repo.hasSessionOnDay(midnight), isTrue);
    expect(await repo.hasSessionOnDay(midnight.subtract(const Duration(days: 3))),
        isFalse);
  });

  test('lastSessionToMin＝最近一条已结算的终点（无会话/无终点＝null 不编 0）', () async {
    expect(await repo.lastSessionToMin('x1'), isNull);
    Future<void> sess(int started, int? ended, int? toMin) =>
        db.insert(md.tMediaSessions, {
          'item_id': 'x1',
          'kind': MediaItem.kMovie,
          'started_at': started,
          'ended_at': ended,
          'minutes': 10,
          'to_min': toMin,
          'source': 'timer',
        });
    await sess(1000, 2000, 12);
    await sess(5000, 6000, 44);
    await sess(7000, null, null);
    expect(await repo.lastSessionToMin('x1'), 44);
  });

  test('minLiveCreatedAt 不吃软删行（newPos=tail 落位基准）', () async {
    Future<void> item(String id, int created, {bool gone = false}) =>
        db.insert(md.tMediaItems, {
          'id': id,
          'kind': MediaItem.kMovie,
          'title': id,
          'state': '未看',
          'progress_way': MediaItem.kWayPct,
          'created_at': created,
          'updated_at': created,
          'deleted_at': gone ? 1 : null,
        });
    expect(await repo.minLiveCreatedAt(), isNull);
    await item('a', 500);
    await item('b', 300, gone: true);
    await item('c', 700);
    expect(await repo.minLiveCreatedAt(), 500);
  });

  test('kvAllMedia 只回 media.* 前缀；mediaKvSafe 缺表缺键都回落默认', () async {
    await repo.setKv('media.newPos', 'tail');
    await repo.setKv('read.something', 'x');
    final map = await repo.kvAllMedia();
    expect(map.keys, ['media.newPos']);
    expect(await mediaKvSafe(repo, 'media.newPos', 'head'), 'tail');
    expect(await mediaKvSafe(repo, 'media.speedFold', 'false'), 'false');
    await db.execute('DROP TABLE ${core.tSettings}');
    expect(await repo.kvAllMedia(), isEmpty);
    expect(await mediaKvSafe(repo, 'media.defaultView', 'desk'), 'desk',
        reason: '表没了也不炸＝老测试库与回落口径');
  });

  test('goalRows 按建行序返回（屏面行序另吃 kMdsGoalDefs 固定序）', () async {
    await repo.setGoal('sceneN', '条', 5);
    await repo.setGoal('movieMin', 'min', 30);
    final rows = await repo.goalRows();
    expect(rows.map((g) => g.metric).toList(), ['sceneN', 'movieMin']);
  });
}
