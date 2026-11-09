import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema/core.dart' as core;
import 'package:lifeharness/core/database/schema/media.dart' as md;
import 'package:lifeharness/features/media/data/media_repo_list.dart';
import 'package:lifeharness/features/media/data/media_repository.dart';
import 'package:lifeharness/features/media/domain/media_item.dart';

/// 批8b · 影音单数据层常驻闸（工单 §⚙ 第 3 项）：
/// pos 整段重写保序·软删成员随 join 消失·年度底稿＝本年窗口现算。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late MediaRepository repo;

  final now = DateTime.now();
  DateTime y(int back, {int hour = 12}) => now
      .subtract(Duration(days: back))
      .copyWith(hour: hour, minute: 0, second: 0, millisecond: 0, microsecond: 0);

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
  tearDown(() async {
    await db.close();
  });

  Future<MediaItem> addItem(String id,
      {String kind = MediaItem.kMovie,
      String state = '在看',
      int? endedAt,
      int dur = 100}) async {
    final x = MediaItem(
      id: id,
      kind: kind,
      title: id,
      state: state,
      progressWay: MediaItem.kWayPct,
      durationMin: dur,
      endedAt: endedAt,
      createdAt: 1,
      updatedAt: 1,
    );
    await repo.addItem(x);
    return x;
  }

  test('建单/改名/成员整段重写保序；软删成员随 join 消失（删条目不脏单）', () async {
    final a = await addItem('a');
    final b = await addItem('b', kind: MediaItem.kSeries);
    final c = await addItem('c', kind: MediaItem.kMusic);
    final id = await repo.createList('通勤看', MediaItem.kMovie);
    expect(id, greaterThan(0));
    var row = (await repo.listRows()).single;
    expect(row.name, '通勤看');
    expect(row.kindFilter, MediaItem.kMovie);
    expect(row.typeLabel, '片单');

    await repo.setMembers(id, [a.id, b.id, c.id]);
    expect((await repo.listMemberItems(id)).map((x) => x.id), [a.id, b.id, c.id]);
    // 重排＝换序写回；pos 从 0 连续（刀2 的落点：不写 pos 则原序不动）。
    await repo.setMembers(id, [c.id, a.id, b.id]);
    expect((await repo.listMemberItems(id)).map((x) => x.id), [c.id, a.id, b.id]);

    await repo.renameList(id, '改名后');
    expect((await repo.listRows()).single.name, '改名后');

    await repo.softDelete([a.id]);
    expect((await repo.listMemberItems(id)).map((x) => x.id), [c.id, b.id]);
    // listsHolding 只认在册成员关系（a 已软删，但关系行还在＝按 item 查仍给 id；
    // UI 侧勾选态吃 listMemberItems，不歧义）。
    expect(await repo.listsHolding(c.id), [id]);
    expect(await repo.listsHolding('zzz'), isEmpty);
  });

  test('混合单与空 kind_filter 都读成「混合单」（建后不换类型＝无迁移口）', () async {
    final id = await repo.createList('混着看', 'mix');
    final id2 = await db.insert(md.tMediaLists, {
      'name': '脏行',
      'kind_filter': '',
      'cover_style': 'desk',
      'created_at': 1,
    });
    final rows = await repo.listRows();
    expect(rows.map((r) => r.typeLabel), ['混合单', '混合单']);
    expect(rows.firstWhere((r) => r.id == id).isMix, isTrue);
    expect(id2, greaterThan(0));
  });

  test('年度底稿＝完结档 ∧ 本年窗口，达成日倒序·同日按 id；软删与非完结不入', () async {
    // 时间炸弹护栏（既定纪律）：开年 105 天内 y(100) 会跨出本年窗口，当日跳过。
    if (now.difference(DateTime(now.year)).inDays < 105) return;
    await addItem('早', state: '看完', endedAt: y(100).millisecondsSinceEpoch);
    await addItem('中', state: '追完', kind: MediaItem.kSeries,
        endedAt: y(50).millisecondsSinceEpoch);
    await addItem('晚', state: '通关', kind: MediaItem.kGame,
        endedAt: y(1).millisecondsSinceEpoch);
    await addItem('去年', state: '看完',
        endedAt: now.subtract(const Duration(days: 400)).millisecondsSinceEpoch);
    await addItem('没完', state: '在看', endedAt: y(2).millisecondsSinceEpoch);
    final gone = await addItem('删掉', state: '看完', endedAt: y(3).millisecondsSinceEpoch);
    await repo.softDelete([gone.id]);
    // 同日两枚验 id 稳定尾（a2 与 中 同一时刻：id 升序＝a2 在前）。
    await addItem('a2', state: '看完', endedAt: y(50).millisecondsSinceEpoch);

    final got = (await repo.yearDraftItems(now)).map((x) => x.id).toList();
    expect(got, ['晚', 'a2', '中', '早'],
        reason: '达成日倒序；同日（a2/中）按 id 升序稳定；去年/在看/软删都不入');
  });
}
