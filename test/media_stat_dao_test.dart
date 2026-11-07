import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema/media.dart' as md;
import 'package:lifeharness/features/media/data/media_repo_stat.dart';
import 'package:lifeharness/features/media/data/media_repository.dart';
import 'package:lifeharness/features/media/domain/media_item.dart';
import 'package:lifeharness/features/media/domain/media_session.dart';
import 'package:lifeharness/features/media/domain/media_stats.dart';

/// 影音游批7 · 统计与轨迹的**算面与取数口**（工单 §⚙ 第 1 项新增常驻件）。
///
/// 三条工装纪律：
/// - 期望值一律从种子数据**现算**（`fold ? minutes*speed : minutes` 这类算式在用例里重写一遍），
///   不借被测函数的输出自证；
/// - 用例内不读裸时钟：「今天」由 [today] 截到日，所有会话按它相对构造（避开跨月与 23:55–00:30 炸弹）；
/// - 表按现行完整形态建（`mediaSchemaStatements`），与真机 v39 同文。
void main() {
  sqfliteFfiInit();

  late Database db;
  late MediaRepository repo;

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day, 21, 30);
  DateTime day(int back, {int hour = 21, int minute = 0}) =>
      DateTime(today.year, today.month, today.day, hour, minute).subtract(Duration(days: back));

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in md.mediaSchemaStatements) {
      await db.execute(sql);
    }
    repo = MediaRepository(db);
  });
  tearDown(() => db.close());

  Future<MediaItem> addItem(
    String title, {
    String kind = MediaItem.kMovie,
    double myRating = 0,
    int durationMin = 0,
    int episodesTotal = 0,
    int seasonsCount = 0,
    int mainPct = 0,
    bool completed = false,
    int? endedAt,
    bool trashed = false,
  }) async {
    final x = MediaItem(
      id: 'x_$title',
      kind: kind,
      title: title,
      state: completed
          ? (kind == MediaItem.kGame ? '通关' : (kind == MediaItem.kSeries ? '追完' : '看完'))
          : '在看',
      progressWay: kind == MediaItem.kSeries ? MediaItem.kWayEp : MediaItem.kWayPct,
      durationMin: durationMin,
      episodesTotal: episodesTotal,
      seasonsCount: seasonsCount,
      mainPct: mainPct,
      myRating: myRating,
      completed: completed,
      endedAt: endedAt,
      createdAt: 1,
      updatedAt: 1,
    );
    await repo.addItem(x);
    if (trashed) await repo.softDelete([x.id]);
    return x;
  }

  Future<void> addSession(
    MediaItem x,
    DateTime start,
    int minutes, {
    double? speed,
    int? toPct,
    String? toText,
    bool running = false,
  }) =>
      db.insert(
        md.tMediaSessions,
        MediaSession(
          itemId: x.id,
          kind: x.kind,
          startedAt: start.millisecondsSinceEpoch,
          endedAt: running ? null : start.add(Duration(minutes: minutes)).millisecondsSinceEpoch,
          minutes: running ? 0 : minutes,
          speed: speed,
          toPct: toPct,
          toText: toText,
        ).toRow(),
      );

  /// 独立算子：真实与折算在用例侧各算一遍（不叫 billedMinutes，避免同源自证）。
  int realOf(MediaSession s) => s.minutes;
  int foldOf(MediaSession s) =>
      (s.minutes * (s.speed != null && s.speed! > 1 ? s.speed! : 1)).round();
  DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  group('取数口', () {
    test('进行中会话不进统计；软删条目的会话也不进（JOIN 在册）', () async {
      final keep = await addItem('在册片');
      final gone = await addItem('回收站片', trashed: true);
      await addSession(keep, day(1), 60);
      await addSession(keep, day(2), 30, running: true);
      await addSession(gone, day(3), 90);

      final rows = await repo.closedSessions();
      expect(rows.map((s) => s.itemId), [keep.id],
          reason: '只留在册条目的已结算会话：跑着的墙钟与回收站里的历史都不该进统计');
      expect(rows.single.minutes, 60);
    });

    test('单条目会话按日期升序（轨迹逐次柱直接吃这个序）', () async {
      final x = await addItem('排序片');
      await addSession(x, day(1), 30);
      await addSession(x, day(5), 45);
      await addSession(x, day(3), 60);
      final rows = await repo.closedSessionsOfItem(x.id);
      expect(rows.map((s) => s.minutes), [45, 60, 30]);
    });
  });

  group('统计算面', () {
    test('近 30 天＝30 格，逐格读数＝按日现算（真实口径）', () async {
      final x = await addItem('热力片');
      await addSession(x, day(0), 50);
      await addSession(x, day(0), 25);
      await addSession(x, day(4), 80);
      final r = mdsComputeStat(
        sessions: await repo.closedSessions(),
        items: await repo.items(),
        filter: const MdsStatFilter(),
        now: today,
      );
      expect(r.heat, hasLength(kMdsHeatDays));
      expect(r.heat.last.value, 75, reason: '今天两条＝50+25');
      expect(r.heat.last.count, 2);
      expect(r.heat[kMdsHeatDays - 5].value, 80);
      expect(r.heat.first.level, 0, reason: '最早的格子没记录＝虚线空格档');
      expect(r.heat.first.value, 0);
    });

    test('切折算＝逐条按倍速重算，且必然大于真实（刀1 靶点）', () async {
      final x = await addItem('倍速片');
      await addSession(x, day(0), 40, speed: 1.5);
      await addSession(x, day(0), 30, speed: 1);
      final sessions = await repo.closedSessions();
      final items = await repo.items();
      final realTotal = sessions.fold<int>(0, (t, s) => t + realOf(s));
      final foldTotal = sessions.fold<int>(0, (t, s) => t + foldOf(s));

      final a = mdsComputeStat(sessions: sessions, items: items, filter: const MdsStatFilter(), now: today);
      final b = mdsComputeStat(
          sessions: sessions, items: items, filter: const MdsStatFilter(fold: true), now: today);

      expect(foldTotal, greaterThan(realTotal), reason: '种子必须真含倍速行，否则这闸是空的');
      expect(a.totalMinutes, realTotal);
      expect(b.totalMinutes, foldTotal);
      expect(a.heat.last.value, realTotal);
      expect(b.heat.last.value, foldTotal);
      expect(b.heat.last.kindValues[x.kind], foldTotal);
    });

    test('强度分档单调：值大的档位不低于值小的（刀3 靶点）', () async {
      final x = await addItem('分档片');
      for (final (back, min) in [(1, 20), (2, 60), (3, 120), (4, 200)]) {
        await addSession(x, day(back), min);
      }
      final r = mdsComputeStat(
        sessions: await repo.closedSessions(),
        items: await repo.items(),
        filter: const MdsStatFilter(),
        now: today,
      );
      final withData = r.heat.where((c) => c.value > 0).toList();
      expect(withData.map((c) => c.level).toSet().length, greaterThan(1),
          reason: '分档必须真分出档，否则「恒 d1」的退化实现不会红');
      expect(withData.first.level, 3, reason: '热力按日期升序，最旧那天值最大＝顶档');
      expect(withData.last.level, 1);
      for (var i = 1; i < withData.length; i++) {
        expect(withData[i].level, lessThanOrEqualTo(withData[i - 1].level),
            reason: '值递减则档位不得递增（分位数切档的单调性）');
      }
    });

    test('时段五档合计＝全部会话读数；空档为 0 由 UI 侧写「—」', () async {
      final x = await addItem('时段片');
      await addSession(x, day(1, hour: 3), 30);
      await addSession(x, day(2, hour: 9), 40);
      await addSession(x, day(3, hour: 22), 50);
      final r = mdsComputeStat(
        sessions: await repo.closedSessions(),
        items: await repo.items(),
        filter: const MdsStatFilter(),
        now: today,
      );
      expect(r.hours, hasLength(5));
      expect(r.hours.fold<double>(0, (t, h) => t + h.value), 120);
      expect(r.hours.firstWhere((h) => h.key == 'dawn').value, 30);
      expect(r.hours.firstWhere((h) => h.key == 'am').value, 40);
      expect(r.hours.firstWhere((h) => h.key == 'pm').value, 0);
      expect(r.hours.firstWhere((h) => h.key == 'night').value, 50);
    });

    test('平均评分＝窗口内有记录条目的 my_rating 均值；没评分＝null 不编数', () async {
      final a = await addItem('评 8 分', myRating: 8);
      final b = await addItem('评 9 分', myRating: 9);
      final c = await addItem('没评分');
      await addSession(a, day(1), 60);
      await addSession(a, day(2), 60);
      await addSession(b, day(3), 60);
      await addSession(c, day(4), 60);
      final r = mdsComputeStat(
        sessions: await repo.closedSessions(),
        items: await repo.items(),
        filter: const MdsStatFilter(),
        now: today,
      );
      expect(r.ratingCount, 2, reason: '同一条两次阅读只算一次（按条目去重）');
      expect(r.ratingAvg, closeTo((8 + 9) / 2, 1e-9));

      final empty = mdsComputeStat(sessions: const [], items: const [], filter: const MdsStatFilter(), now: today);
      expect(empty.ratingAvg, isNull);
      expect(empty.kinds, isEmpty);
    });

    test('年×月×构成三重筛选＝与直查同值（互相交叠不吃错窗口）', () async {
      final x = await addItem('跨年片');
      final y = await addItem('另一类片', kind: MediaItem.kSeries, myRating: 7);
      await addSession(x, day(1), 60);
      await addSession(x, day(400), 90);
      await addSession(y, day(2), 45);

      final sessions = await repo.closedSessions();
      final items = await repo.items();
      final thisYear = today.year, thisMonth = today.month;
      final lastYear = day(400).year;

      double sum(int? year, int? month, String kind) => sessions
          .where((s) {
            final d = DateTime.fromMillisecondsSinceEpoch(s.startedAt);
            if (year != null && d.year != year) return false;
            if (month != null && d.month != month) return false;
            return kind == 'all' || s.kind == kind;
          })
          .fold<double>(0, (t, s) => t + s.minutes);

      final all = mdsComputeStat(sessions: sessions, items: items, filter: const MdsStatFilter(), now: today);
      expect(all.totalMinutes, sum(null, null, 'all'));
      expect(all.years, [thisYear, lastYear]);

      final byYear = mdsComputeStat(sessions: sessions, items: items, filter: MdsStatFilter(year: thisYear), now: today);
      expect(byYear.totalMinutes, sum(thisYear, null, 'all'));
      expect(byYear.trend, hasLength(12), reason: '选定年份＝12 根月柱');

      final byMonth = mdsComputeStat(
          sessions: sessions,
          items: items,
          filter: MdsStatFilter(year: thisYear, month: thisMonth),
          now: today);
      expect(byMonth.totalMinutes, sum(thisYear, thisMonth, 'all'));

      final byKind = mdsComputeStat(
          sessions: sessions,
          items: items,
          filter: const MdsStatFilter(kind: 'movie'),
          now: today);
      expect(byKind.totalMinutes, sum(null, null, 'movie'));
      expect(byKind.kindMinutes.keys, ['movie'], reason: '构成筛选下总时长卡只剩这一类');
      expect(byKind.kinds, hasLength(1));

      final lastYearOnly = mdsComputeStat(
          sessions: sessions, items: items, filter: MdsStatFilter(year: lastYear), now: today);
      expect(lastYearOnly.totalMinutes, sum(lastYear, null, 'all'));
    });

    test('类型构成百分比按当前度量归一（合计 99~101）；总时长卡恒为时长', () async {
      final m = await addItem('构成电影');
      final s = await addItem('构成剧集', kind: MediaItem.kSeries);
      await addSession(m, day(1), 100);
      await addSession(s, day(2), 100);
      await addSession(s, day(3), 100);
      final sessions = await repo.closedSessions();
      final items = await repo.items();
      final r = mdsComputeStat(sessions: sessions, items: items, filter: const MdsStatFilter(), now: today);
      expect(r.kinds.map((k) => k.pct).reduce((a, b) => a + b), inInclusiveRange(99, 101));
      expect(r.kinds.firstWhere((k) => k.kind == MediaItem.kSeries).value, 200);

      final cnt = mdsComputeStat(
          sessions: sessions,
          items: items,
          filter: const MdsStatFilter(metric: kMdsMetricCnt),
          now: today);
      expect(cnt.kinds.firstWhere((k) => k.kind == MediaItem.kMovie).value, 1,
          reason: '度量切次数＝按条数算，不再吃分钟');
      expect(cnt.totalMinutes, 300, reason: '跨 kind 总时长卡恒为时长，不随度量跳');
    });

    test('趋势：全部年份＝按年出柱；选定年份下无数据月 hasData=false（不画假点）', () async {
      final x = await addItem('趋势片');
      await addSession(x, day(1), 60);
      await addSession(x, day(400), 60);
      final sessions = await repo.closedSessions();
      final items = await repo.items();
      final r = mdsComputeStat(sessions: sessions, items: items, filter: const MdsStatFilter(), now: today);
      expect(r.trend, hasLength(2));
      expect(r.trend.every((b) => b.hasData), isTrue);

      final y = mdsComputeStat(
          sessions: sessions, items: items, filter: MdsStatFilter(year: today.year), now: today);
      expect(y.trend, hasLength(12));
      expect(y.trend.where((b) => !b.hasData).length, greaterThan(0), reason: '本月之外还有空月');
      expect(y.trend.firstWhere((b) => !b.hasData).value, 0);
    });
  });

  group('轨迹里程碑', () {
    test('电影三段＝开始/看过一半/看完；没填片长＝半程整行不出现', () async {
      final x = await addItem('三段片', durationMin: 120, completed: true, endedAt: day(1).millisecondsSinceEpoch);
      await addSession(x, day(5), 40);
      await addSession(x, day(1), 80);
      final miles = mdsMilestonesOf(x, await repo.closedSessionsOfItem(x.id));
      expect(miles.map((m) => m.label), ['开始观影', '看过一半', '看完']);
      expect(miles.first.date, dayOnly(day(5)));
      expect(miles[1].date, dayOnly(day(1)), reason: '累计 40→120 在这一条越过 60 分钟线');
      expect(miles.last.date, dayOnly(day(1)), reason: '完结档吃 ended_at');

      final noDur = await addItem('没片长');
      await addSession(noDur, day(2), 30);
      expect(mdsMilestonesOf(noDur, await repo.closedSessionsOfItem(noDur.id)).map((m) => m.label),
          ['开始观影'],
          reason: '总时长未知＝算不出过半，整行不出现而不是铺「未达成」占位');
    });

    test('剧集半程按进度快照解析；游戏通关吃 ended_at；音乐循环 100 未达＝不出现', () async {
      final s = await addItem('剧集半程', kind: MediaItem.kSeries, episodesTotal: 12, seasonsCount: 1);
      await addSession(s, day(3), 40, toText: 'S01E04');
      await addSession(s, day(1), 40, toText: 'S01E07');
      final ls = mdsMilestonesOf(s, await repo.closedSessionsOfItem(s.id));
      expect(ls.map((m) => m.label), ['开始追剧', '看到一半'], reason: '第 7 集 ≥ 12/2＝过半达成');
      expect(ls[1].date, dayOnly(day(1)));

      final g = await addItem('通关游戏',
          kind: MediaItem.kGame,
          mainPct: 100,
          completed: true,
          endedAt: day(0, hour: 10).millisecondsSinceEpoch);
      await addSession(g, day(2, hour: 14), 90, toPct: 60);
      expect(mdsMilestonesOf(g, await repo.closedSessionsOfItem(g.id)).map((m) => m.label),
          ['开始游玩', '主线半程', '通关']);

      final mu = await addItem('专辑', kind: MediaItem.kMusic);
      for (var i = 0; i < 6; i++) {
        await addSession(mu, day(i + 1, hour: 8), 20);
      }
      expect(mdsMilestonesOf(mu, await repo.closedSessionsOfItem(mu.id)).map((m) => m.label),
          ['开始听歌'], reason: '循环次数＝会话条数，6 条远不到 100＝整行不出现');

      final none = await addItem('没记录');
      expect(mdsMilestonesOf(none, const <MediaSession>[]), isEmpty);
    });

    test('轨迹时段合计＝真实耗时总和（倍速不改柱高，只出角标）', () async {
      final x = await addItem('轨迹时段');
      await addSession(x, day(1, hour: 22), 40, speed: 1.5);
      await addSession(x, day(2, hour: 8), 30);
      final hours = mdsTrackHours(await repo.closedSessionsOfItem(x.id));
      expect(hours.fold<double>(0, (t, h) => t + h.value), 70, reason: '恒吃真实耗时');
      expect(hours.firstWhere((h) => h.key == 'night').value, 40);
    });
  });
}
