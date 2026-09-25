import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/goals/data/goals_repository.dart';
import 'package:lifeharness/features/goals/domain/goal_models.dart';

/// 批3 · 目标 OKR 仓储（CRUD/上限/回填留痕/自动汇聚回写/归档冻结/复制清零
/// 重编号/复盘归档链/Try→下季草稿/周期归档幂等）。独立文件防 isolate 污染。
void main() {
  sqfliteFfiInit();

  final now = DateTime(2026, 9, 19);
  late Database db;
  late GoalsRepository repo;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = GoalsRepository(db);
  });

  tearDown(() => db.close());

  GoalKr k(String label, {double tgt = 1, double cur = 0, String unit = '项',
          KrSource src = KrSource.manual, int? id}) =>
      GoalKr(
          goalId: 0,
          id: id,
          label: label,
          target: tgt,
          unit: unit,
          source: src,
          cur: cur);

  Future<int> seedGoal(String title, String period, List<GoalKr> krs,
      {int sort = 0}) async {
    final id = await db.insert(DbSchema.tGoals, {
      'title': title,
      'period': period,
      'sort': sort,
      'created_at': now.millisecondsSinceEpoch,
      'updated_at': now.millisecondsSinceEpoch,
    });
    for (final kr in krs) {
      await db.insert(DbSchema.tGoalKrs, {
        'goal_id': id,
        'label': kr.label,
        'target': kr.target,
        'unit': kr.unit,
        'src': kr.source.wire,
        'cur': kr.cur,
      });
    }
    return id;
  }

  group('目标/KR CRUD', () {
    test('addGoal 落库组装；第 6 个返 null（超限）', () async {
      for (var i = 1; i <= 5; i++) {
        final id = await repo.addGoal(Goal(
            title: 'O$i 目标',
            period: '2026 Q3',
            sort: i - 1,
            krs: [k('KR甲', tgt: 4), k('KR乙', tgt: 2)]));
        expect(id, isNotNull);
      }
      final overflow = await repo.addGoal(Goal(
          title: 'O6 目标', period: '2026 Q3', krs: [k('a'), k('b')]));
      expect(overflow, isNull);
      final d = await repo.loadAll(now: now);
      expect(d.inPeriod('2026 Q3').length, 5);
      expect(d.inPeriod('2026 Q3').first.krs.length, 2);
    });

    test('updateGoal 整组替换：同 id 保留回填留痕，新行入库', () async {
      final gid = await repo.addGoal(Goal(
          title: 'O1 原', period: '2026 Q3', krs: [k('KR甲', tgt: 5), k('KR乙')]));
      var d = await repo.loadAll(now: now);
      final kr1 = d.goals.first.krs.first;
      await repo.bumpKr(kr1.id!, 3, note: '手动回填');
      d = await repo.loadAll(now: now);
      final keep = d.goals.first.krs.first;
      await repo.updateGoal(d.goals.first.copyWith(
          title: 'O1 改',
          krs: [
            GoalKr(
                id: keep.id,
                goalId: gid!,
                label: 'KR甲改名',
                target: keep.target,
                unit: keep.unit,
                source: keep.source,
                cur: keep.cur),
            k('KR丙 新增', tgt: 2, cur: 1),
          ]));
      d = await repo.loadAll(now: now);
      final g = d.goals.first;
      expect(g.title, 'O1 改');
      expect(g.krs.map((x) => x.label), ['KR甲改名', 'KR丙 新增']);
      // 留痕保留（仅追加）：甲有手动回填；新行 cur>0 记建档初值
      expect(g.krs[0].updates.map((u) => u.kind), ['manual']);
      expect(g.krs[1].updates.map((u) => u.note), ['建档初值']);
      expect(g.krs[0].cur, 3);
    });

    test('bumpKr 写 kr_updates 手动留痕并更新 cur', () async {
      final gid = await repo.addGoal(
          Goal(title: 'O1', period: '2026 Q3', krs: [k('KR甲', tgt: 4)]));
      final d0 = await repo.loadAll(now: now);
      final krId = d0.goals.first.krs.first.id!;
      await repo.bumpKr(krId, 2);
      final d = await repo.loadAll(now: now);
      final kr = d.goals.first.krs.first;
      expect(kr.cur, 2);
      expect(kr.progressPct, 50);
      expect(kr.updates.single.kind, 'manual');
      expect(kr.updates.single.note, '手动回填');
      expect(gid, greaterThan(0));
    });

    test('removeGoal 连删 KR 与留痕', () async {
      final gid = await repo.addGoal(
          Goal(title: 'O1', period: '2026 Q3', krs: [k('a'), k('b')]));
      final d0 = await repo.loadAll(now: now);
      await repo.bumpKr(d0.goals.first.krs.first.id!, 1);
      await repo.removeGoal(gid!);
      expect(await db.query(DbSchema.tGoals), isEmpty);
      expect(await db.query(DbSchema.tGoalKrs), isEmpty);
      expect(await db.query(DbSchema.tKrUpdates), isEmpty);
    });
  });

  group('自动汇聚（载入实算 + 回写 + auto 留痕）', () {
    Future<void> seedSources() async {
      final inQ3 = DateTime(2026, 9, 10).millisecondsSinceEpoch;
      final outQ3 = DateTime(2026, 6, 10).millisecondsSinceEpoch;
      await db.insert(DbSchema.tTodos,
          {'title': '甲', 'done': 1, 'created_at': inQ3, 'updated_at': inQ3});
      await db.insert(DbSchema.tTodos,
          {'title': '乙', 'done': 1, 'created_at': inQ3, 'updated_at': inQ3});
      await db.insert(DbSchema.tTodos,
          {'title': '丙', 'done': 0, 'created_at': inQ3, 'updated_at': inQ3});
      await db.insert(DbSchema.tTodos,
          {'title': '丁', 'done': 1, 'created_at': outQ3, 'updated_at': outQ3});
      await db.insert(DbSchema.tBooks, {
        'id': 'b1',
        'title': '书一',
        'state': '已读',
        'ended_at': inQ3,
        'created_at': inQ3,
        'updated_at': inQ3
      });
      await db.insert(DbSchema.tBooks, {
        'id': 'b2',
        'title': '书二',
        'state': '在读',
        'ended_at': inQ3,
        'created_at': inQ3,
        'updated_at': inQ3
      });
      await db.insert(DbSchema.tJournal,
          {'entry_date': inQ3, 'content': 'x', 'created_at': inQ3, 'updated_at': inQ3});
      await db.insert(DbSchema.tJournal,
          {'entry_date': outQ3, 'content': 'y', 'created_at': outQ3, 'updated_at': outQ3});
      await db.insert(DbSchema.tHabitEntries, {
        'habit_id': 'h1',
        'day': '2026-09-01',
        'checked': 1,
        'origin': 'manual',
        'created_at': inQ3,
        'updated_at': inQ3,
      });
      await db.insert(DbSchema.tHabitEntries, {
        'habit_id': 'h1',
        'day': '2026-09-02',
        'checked': 1,
        'origin': 'manual',
        'created_at': inQ3,
        'updated_at': inQ3,
      });
      await db.insert(DbSchema.tHabitEntries, {
        'habit_id': 'h2',
        'day': '2026-09-02',
        'checked': 1,
        'origin': 'manual',
        'created_at': inQ3,
        'updated_at': inQ3,
      });
      await db.insert(DbSchema.tHabitEntries, {
        'habit_id': 'h2',
        'day': '2026-09-03',
        'checked': 0,
        'origin': 'manual',
        'created_at': inQ3,
        'updated_at': inQ3,
      });
      await db.insert(DbSchema.tLedgerTxns,
          {'kind': 'income', 'amt': 1000, 'account_id': 1, 'date': '2026-09-05', 'bk': 0, 'created_at': inQ3});
      await db.insert(DbSchema.tLedgerTxns,
          {'kind': 'expense', 'amt': 400, 'account_id': 1, 'date': '2026-09-06', 'bk': 0, 'created_at': inQ3});
    }

    test('五源 cur 实算回写 + auto 留痕', () async {
      await seedSources();
      await seedGoal('O1 汇聚', '2026 Q3', [
        k('待办', tgt: 4, cur: 99, src: KrSource.todo),
        k('阅读', tgt: 6, src: KrSource.read),
        k('日记', tgt: 5, src: KrSource.journal),
        k('习惯', tgt: 3, src: KrSource.habit),
        k('结余', tgt: 50, unit: '%', src: KrSource.ledger),
        k('手动', tgt: 2, cur: 1),
      ]);
      final d = await repo.loadAll(now: now);
      final krs = d.goals.first.krs;
      expect(krs[0].cur, 2); // todo：仅 Q3 窗内 done=1 两条
      expect(krs[1].cur, 1); // read：已读本数
      expect(krs[2].cur, 1); // journal：篇数落窗
      expect(krs[3].cur, 3); // habit：(habit,day) 去重
      expect(krs[4].cur, 60); // ledger：(1000-400)/1000*100
      expect(krs[5].cur, 1); // manual 不动
      // 回写库
      final row = (await db.query(DbSchema.tGoalKrs,
          where: 'src = ?', whereArgs: ['todo']))
          .first;
      expect(row['cur'], 2);
      // auto 留痕
      final autos = await db.query(DbSchema.tKrUpdates,
          where: "kind = 'auto'");
      expect(autos.length, 5);
      expect(autos.first['note'], '待办完成数 · 自动汇聚');
      // 二次载入幂等（值未再变化不再留痕）
      await repo.loadAll(now: now);
      expect((await db.query(DbSchema.tKrUpdates, where: "kind = 'auto'")).length,
          5);
    });

    test('归档周期冻结不重算', () async {
      await seedSources();
      await seedGoal('O1 冻结', '2026 Q3', [k('待办', tgt: 4, cur: 7, src: KrSource.todo)]);
      await repo.setPeriodArchived('2026 Q3', true);
      final d = await repo.loadAll(now: now);
      expect(d.goals.first.krs.first.cur, 7); // 冻结在归档时点
      expect(d.isArchived('2026 Q3'), isTrue);
      expect(await db.query(DbSchema.tKrUpdates, where: "kind = 'auto'"), isEmpty);
    });
  });

  group('复制清零', () {
    test('copyGoals：清零 + O 重编号 + 上限截断；无 O 前缀标题不改', () async {
      await seedGoal('O1 上期甲', '2026 Q2',
          [k('a', tgt: 4, cur: 4), k('b', cur: 1)],
          sort: 0);
      await seedGoal('坚持输出', '2026 Q2', [k('c', cur: 2)], sort: 1);
      await seedGoal('O9 占位', '2026 Q3', [k('x', cur: 5)], sort: 2);
      final n = await repo.copyGoals('2026 Q2', '2026 Q3');
      expect(n, 2);
      final d = await repo.loadAll(now: now);
      final q3 = d.inPeriod('2026 Q3');
      expect(q3.length, 3); // 1 原有 + 2 复制
      final titles = q3.map((g) => g.title).toSet();
      expect(titles, containsAll(['O2 上期甲', '坚持输出', 'O9 占位'])); // 重编号从已有数+1 起
      final copied = q3.firstWhere((g) => g.title == 'O2 上期甲');
      expect(copied.krs.every((x) => x.cur == 0), isTrue); // 进度清零
      expect(copied.krs.map((x) => x.target), [4, 1]); // 目标/单位保留
      expect(q3.firstWhere((g) => g.title == '坚持输出').krs.single.cur, 0);
      // 上限截断：Q3 已 3 个 → 再复制 Q2(2 个) 全进（3+2=5 恰满）
      expect(await repo.copyGoals('2026 Q2', '2026 Q3'), 2);
      expect((await repo.loadAll(now: now)).inPeriod('2026 Q3').length, 5);
      // 满 5 后再复制 0 条
      expect(await repo.copyGoals('2026 Q2', '2026 Q3'), 0);
    });

    test('copySingleGoal：清零复制；目标周期满 5 返 null', () async {
      final gid = await seedGoal('O1 单复', '2026 Q2', [k('a', cur: 3, tgt: 5)]);
      final nid = await repo.copySingleGoal(gid, '2026 Q3');
      expect(nid, isNotNull);
      final d = await repo.loadAll(now: now);
      final copy = d.goals.firstWhere((g) => g.id == nid);
      expect(copy.title, 'O1 单复'); // 单目标复制不改编号（原型 goalCopy）
      expect(copy.krs.single.cur, 0);
      for (var i = 2; i <= 5; i++) {
        await seedGoal('O$i 满', '2026 Q3', [k('x')]);
      }
      expect(await repo.copySingleGoal(gid, '2026 Q3'), isNull);
    });
  });

  group('复盘与周期归档', () {
    test('saveReview 草稿 → 归档 → 再更新保持 archived；period 唯一', () async {
      await repo.saveReview(
          const GoalReview(period: '2026 Q3', keep: 'k1'), asArchived: false);
      var d = await repo.loadAll(now: now);
      expect(d.reviewFor('2026 Q3')!.archived, isFalse);
      await repo.saveReview(
          const GoalReview(period: '2026 Q3', keep: 'k2', trial: 't'),
          asArchived: true);
      d = await repo.loadAll(now: now);
      expect(d.reviewFor('2026 Q3')!.archived, isTrue);
      expect(d.reviewFor('2026 Q3')!.keep, 'k2');
      await repo.saveReview(
          const GoalReview(period: '2026 Q3', keep: 'k3', archived: true),
          asArchived: false);
      d = await repo.loadAll(now: now);
      expect(d.reviewFor('2026 Q3')!.archived, isTrue); // 归档不回退
      expect(d.reviews.length, 1);
    });

    test('tryToNextDraft：标题编号 + Try 首行截 18 字；空/超限返 null', () async {
      await seedGoal('O1 已有', '2026 Q4', [k('x')]);
      final id = await repo.tryToNextDraft('2026 Q3', '把入睡绑定日记打卡；后面这条不该进来');
      expect(id, isNotNull);
      final d = await repo.loadAll(now: now);
      final draft = d.goals.firstWhere((g) => g.id == id);
      expect(draft.period, '2026 Q4');
      expect(draft.title, 'O2 由 2026 Q3 复盘 Try 生成'); // 已有 1 个 → O2
      expect(draft.krs.single.label, '把入睡绑定日记打卡');
      expect(draft.krs.single.target, 1);
      // 超 18 字截断加省略号（无分隔符整句即首行）
      final long = '一二三四五六七八九十甲乙丙丁戊己庚辛壬癸子丑寅卯';
      final id2 = await repo.tryToNextDraft('2026 Q3', long);
      final draft2 =
          (await repo.loadAll(now: now)).goals.firstWhere((g) => g.id == id2);
      expect(draft2.krs.single.label, '${long.substring(0, 18)}…');
      // Q4 满 5 后超限返 null；空句返 null
      await seedGoal('占位丁', '2026 Q4', [k('y')]);
      await seedGoal('占位戊', '2026 Q4', [k('z')]);
      expect(await repo.tryToNextDraft('2026 Q3', '再来一条改法'), isNull);
      expect(await repo.tryToNextDraft('2026 Q3', ' ；。 '), isNull);
    });

    test('setPeriodArchived 幂等（replace 冲突），可恢复', () async {
      await repo.setPeriodArchived('2026 Q1', true);
      await repo.setPeriodArchived('2026 Q1', true);
      expect(await db.query(DbSchema.tGoalPeriods), hasLength(1));
      var d = await repo.loadAll(now: now);
      expect(d.isArchived('2026 Q1'), isTrue);
      await repo.setPeriodArchived('2026 Q1', false);
      d = await repo.loadAll(now: now);
      expect(d.isArchived('2026 Q1'), isFalse);
    });
  });
}
