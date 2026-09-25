import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/days/data/days_repository.dart';
import 'package:lifeharness/features/days/domain/day_models.dart';

/// 批1 · 日子仓储（CRUD/归档闭环/准备事项转链/提醒派生同步/去年今日）。
/// 独立文件防 isolate 污染。
void main() {
  sqfliteFfiInit();

  late Database db;
  late DaysRepository repo;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = DaysRepository(db);
  });

  tearDown(() => db.close());

  DayEntry sample({
    int? id,
    String title = '妈妈生日',
    DayRepeat repeat = DayRepeat.lunar,
    List<DayPrep> preps = const [],
    bool pinned = false,
    bool archived = false,
  }) =>
      DayEntry(
        id: id,
        title: title,
        iconId: 'cake',
        colorKey: 'rose',
        category: '生日',
        repeat: repeat,
        targetDate: repeat == DayRepeat.once || repeat == DayRepeat.solarYear
            ? DateTime(2025, 10, 17)
            : null,
        lunarMonth: 8,
        lunarDay: 27,
        remOffsets: const [30, 7, 0],
        pinned: pinned,
        archived: archived,
        preps: preps,
      );

  test('schema v20：版本与迁移登记', () {
    expect(DbSchema.version, greaterThanOrEqualTo(20));
    expect(DbSchema.migrations[19], containsAll(DbSchema.daysSchemaStatements));
  });

  group('日子 CRUD 与归档闭环', () {
    test('新建含准备事项 → loadAll 组装回来', () async {
      final id = await repo.addDay(sample(preps: const [
        DayPrep(dayId: 0, text: '订蛋糕'),
        DayPrep(dayId: 0, text: '挑礼物', done: true),
      ]));
      final d = await repo.loadAll();
      final day = d.days.single;
      expect(day.id, id);
      expect(day.title, '妈妈生日');
      expect(day.repeat, DayRepeat.lunar);
      expect(day.remOffsets, [30, 7, 0]);
      expect(day.preps.map((p) => p.text), ['订蛋糕', '挑礼物']);
      expect(day.preps[1].done, isTrue);
    });

    test('updateDay 整组替换 preps：同文本保留 todo_id 链', () async {
      final id = await repo.addDay(sample(preps: const [
        DayPrep(dayId: 0, text: '订蛋糕'),
      ]));
      var d = await repo.loadAll();
      final prep = d.days.single.preps.single;
      await repo.setPrepTodo(prep.id!, 777);
      await repo.updateDay(sample(id: id, preps: const [
        DayPrep(dayId: 0, text: '订蛋糕'),
        DayPrep(dayId: 0, text: '订包厢'),
      ]));
      d = await repo.loadAll();
      expect(d.days.single.preps.length, 2);
      expect(d.days.single.preps.firstWhere((p) => p.text == '订蛋糕').todoId, 777);
    });

    test('归档→恢复→彻底删除（preps 级联不留孤）', () async {
      final id = await repo.addDay(sample(preps: const [
        DayPrep(dayId: 0, text: 'x'),
      ]));
      await repo.setArchived(id, true);
      var d = await repo.loadAll();
      expect(d.days.single.archived, isTrue);
      expect(d.active, isEmpty);
      await repo.setArchived(id, false);
      d = await repo.loadAll();
      expect(d.active.length, 1);
      await repo.purgeDay(id);
      d = await repo.loadAll();
      expect(d.days, isEmpty);
      final orphans = await db.query(DbSchema.tDayPreps);
      expect(orphans, isEmpty);
    });

    test('置顶持久化且 loadAll 置顶在前', () async {
      final a = await repo.addDay(sample(title: 'A'));
      await repo.addDay(sample(title: 'B'));
      await repo.setPinned(a, true);
      final d = await repo.loadAll();
      expect(d.days.first.title, 'A');
      expect(d.days.first.pinned, isTrue);
    });
  });

  group('提醒中心', () {
    test('证件手动建档 → 改提醒日（snooze 优先，不动原到期日）→ 已处理保留审计', () async {
      final id = await repo.addCertReminder(
          title: '护照', due: DateTime(2026, 11, 5), tip: '约 10 个工作日');
      var d = await repo.loadAll();
      var r = d.reminders.single;
      expect(r.kind, 'cert');
      expect(r.effectiveDate, DateTime(2026, 11, 5));
      await repo.setSnooze(id, DateTime(2026, 12, 1), 9);
      d = await repo.loadAll();
      r = d.reminders.single;
      expect(r.dueDate, DateTime(2026, 11, 5)); // 原始到期日留痕
      expect(r.effectiveDate, DateTime(2026, 12, 1));
      expect(r.snoozeHour, 9);
      await repo.markHandled(id);
      d = await repo.loadAll();
      expect(d.unhandled, isEmpty);
      expect(d.reminders.single.handledAt, isNotNull); // 行仍在＝静默归档留审计
    });

    test('订阅派生：周期账单自动生成/推进重置/停用清除', () async {
      final recurId = await db.insert(DbSchema.tLedgerRecur, {
        'bk': 1, 'name': '视频会员', 'amt': 25.0, 'cat_id': null, 'sub': null,
        'account_id': 1, 'freq': '每月', 'next_date': '2026-09-28', 'active': 1,
      });
      var d = await repo.loadAll();
      var sub = d.reminders.single;
      expect((sub.kind, sub.title, sub.sourceKey),
          ('sub', '视频会员', 'recur:$recurId'));
      expect(sub.effectiveDate, DateTime(2026, 9, 28));

      await repo.markHandled(sub.id!);
      // 源推进 next_date → 新周期撤销已处理
      await db.update(DbSchema.tLedgerRecur, {'next_date': '2026-10-28'},
          where: 'id = ?', whereArgs: [recurId]);
      d = await repo.loadAll();
      expect(d.reminders.single.handled, isFalse);
      expect(d.reminders.single.effectiveDate, DateTime(2026, 10, 28));

      // 停用 → 派生行连带删除
      await db.update(DbSchema.tLedgerRecur, {'active': 0},
          where: 'id = ?', whereArgs: [recurId]);
      d = await repo.loadAll();
      expect(d.reminders, isEmpty);
    });

    test('保修派生在 item_profiles 建表前静默跳过（批2 自动生效）', () async {
      final d = await repo.loadAll();
      expect(d.reminders.where((r) => r.kind == 'warranty'), isEmpty);
    });
  });

  group('去年今日（只读日记投影）', () {
    test('同 MM-DD 历史年命中、今年与异日排除', () async {
      Future<void> j(DateTime d, String text) => db.insert(DbSchema.tJournal, {
            'entry_date': d.millisecondsSinceEpoch,
            'content': text,
            'created_at': d.millisecondsSinceEpoch,
            'updated_at': d.millisecondsSinceEpoch,
          });
      await j(DateTime(2025, 9, 19), '去年今天');
      await j(DateTime(2024, 9, 19), '前年今天');
      await j(DateTime(2026, 9, 19), '今年');
      await j(DateTime(2025, 9, 20), '异日');
      final out = await repo.anniversaryEntries(9, 19, 2026);
      expect(out.map((e) => e.text), ['去年今天', '前年今天']);
      expect(out.first.date.year, 2025);
    });
  });
}
