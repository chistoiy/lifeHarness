import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema/media.dart' as md;
import 'package:lifeharness/features/media/data/media_repository.dart';
import 'package:lifeharness/features/media/domain/media_item.dart';
import 'package:lifeharness/features/media/domain/media_summary.dart';

/// 影音游批4b · 条目「一页总结」存储（`media_items.final_note` JSON 三键 · 零迁移）。
///
/// 独立文件＝全 app 点火类用例拆文件防 isolate 污染（AGENTS 门禁条）。
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

  Future<String> addItem() => repo.addItem(
    MediaItem(
      kind: MediaItem.kMovie,
      title: '测试条目',
      state: MediaItem.initialState(MediaItem.kMovie),
      progressWay: MediaItem.kWayPct,
      createdAt: 1,
      updatedAt: 1,
    ),
  );

  test('final_note 三键往返·非 JSON 旧行读成空不抛', () async {
    final id = await addItem();
    await repo.saveSummary(
      id,
      const MediaSummary(a: '诺兰把传记拍成惊悚片。', b: '听证会那段', c: '会推荐'),
    );
    final s = await repo.summaryOf(id);
    expect(s.a, '诺兰把传记拍成惊悚片。');
    expect(s.c, '会推荐');
    await db.update('media_items', {'final_note': '手改的裸文本'},
        where: 'id = ?', whereArgs: [id]);
    expect((await repo.summaryOf(id)).isEmpty, isTrue); // 读侧容错
  });

  test('全空保存＝列落 NULL（不写 "{}" 占位）', () async {
    final id = await addItem();
    await repo.saveSummary(id, const MediaSummary(a: 'x'));
    // 顺带钉「只改 final_note 与 updated_at」：写一次后其余列原样。
    final m = await repo.itemById(id);
    expect(m!.title, '测试条目');
    expect(m.state, '未看');
    expect(m.updatedAt, greaterThan(1), reason: 'updated_at 同场刷新');
    await repo.saveSummary(id, const MediaSummary());
    final raw =
        (await db.query('media_items', where: 'id = ?', whereArgs: [id]))
            .single['final_note'];
    expect(raw, isNull);
  });
}
