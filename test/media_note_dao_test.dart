import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/database/schema/media.dart' as md;
import 'package:lifeharness/features/media/data/media_repo_note.dart';
import 'package:lifeharness/features/media/data/media_repository.dart';
import 'package:lifeharness/features/media/domain/media_note.dart';

/// 影音游批5 数据层 · 笔记库＋名场面复习（工单执行面板第 1 项新增常驻测试）。
///
/// 三条工装口径：
/// - 表按 **v39 完整形态** 建（先重放 `migrations[37]` 建 v38 七表，再重放
///   `migrations[38]` 加复习三列），与真机老库升级路径同文；
/// - 期望值一律从种子数据与 `MediaNote.reviewGapsDays` **现算**，不写死计数与毫秒
///   （计划书 §7.5 提速第三条：观感写死自造假红）；
/// - 时间全部由用例注入（`now`/`createdAt`），模型与仓储内不读时钟。
void main() {
  sqfliteFfiInit();

  late Database db;
  late MediaRepository repo;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.migrations[37]!) {
      await db.execute(sql);
    }
    for (final sql in DbSchema.migrations[38]!) {
      await db.execute(sql);
    }
    repo = MediaRepository(db);
  });
  tearDown(() => db.close());

  const dayMs = 24 * 60 * 60 * 1000;
  final gaps = MediaNote.reviewGapsDays;

  Future<String> addItem(String title, {String kind = 'movie'}) async {
    final id = 'm_$title';
    await db.insert(md.tMediaItems, {
      'id': id,
      'kind': kind,
      'title': title,
      'state': '在看',
      'progress_way': 'pct',
      'created_at': 1,
      'updated_at': 1,
    });
    return id;
  }

  MediaNote note(
    String itemId,
    String body, {
    String kind = 'movie',
    String noteType = MediaNote.kScene,
    String? tag,
    String? thought,
    int? unitRef,
    int? atMin,
    bool starred = false,
    int createdAt = 0,
    List<String> imagePaths = const [],
    String? origin,
  }) => MediaNote(
    itemId: itemId,
    kind: kind,
    noteType: noteType,
    body: body,
    tag: tag,
    thought: thought,
    unitRef: unitRef,
    atMin: atMin,
    starred: starred,
    createdAt: createdAt,
    imagePaths: imagePaths,
    origin: origin,
  );

  Future<Map<String, Object?>> rowOf(int id) async =>
      (await db.query(md.tMediaNotes, where: 'id = ?', whereArgs: [id])).single;

  test('版本 39：38→39 段存在且就是复习三列＋到期索引（老库不升就没这列）', () {
    expect(DbSchema.version, 39);
    expect(DbSchema.migrations.containsKey(38), isTrue);
    final sql = DbSchema.migrations[38]!.join(' ');
    for (final col in ['review_stage', 'reviewed_at', 'next_review_at']) {
      expect(sql, contains('ADD COLUMN $col'), reason: '$col 没在迁移段里＝老库缺列');
    }
    expect(sql, contains('idx_mnote_due'));
    // 判重索引在 v39 段改成「仅在库行」局部唯一（删了能重记同一句）
    expect(sql, contains('DROP INDEX IF EXISTS idx_mnote_dedup'),
        reason: '未先摘旧全量唯一索引，软删行会永久占键');
  });

  test('PRAGMA：media_notes 三列齐且在册行读得出档位（fromMap 缺列回落 0/null）', () async {
    final cols = (await db.rawQuery('PRAGMA table_info(${md.tMediaNotes})'))
        .map((r) => '${r['name']}')
        .toSet();
    expect(
      cols,
      containsAll(<String>['review_stage', 'reviewed_at', 'next_review_at']),
    );
    final id = await repo.addNote(note('a', '名场面一'));
    final m = await repo.noteById(id!);
    expect(m!.reviewStage, 0);
    expect(m.reviewedAt, isNull);
    expect(m.nextReviewAt, isNotNull);
  });

  test('入账即排第一档：下次到期＝建档时刻＋首档天数（补记旧笔记按当时算，不蹭今天）', () async {
    final created = 1700000000000;
    final id = await repo.addNote(note('a', '昨夜那场雨', createdAt: created));
    final row = await rowOf(id!);
    expect(row['review_stage'], 0);
    expect(row['next_review_at'], created + gaps.first * dayMs,
        reason: '按 created 排期＝补记昨天的笔记不该今天才到期');
    // 还没到首档＝不进队列；到点即进（现算边界）
    expect(await repo.dueReviewCount(now: created + gaps.first * dayMs - 1), 0);
    expect(await repo.dueReviewCount(now: created + gaps.first * dayMs), 1);
  });

  test('空正文不落库（就地报错口径在数据层的同一道闸）；连点保存只落一条', () async {
    expect(await repo.addNote(note('a', '   ')), isNull);
    expect(await repo.noteCount(), 0);
    final first = await repo.addNote(note('a', '同一句话'));
    final second = await repo.addNote(note('a', '同一句话'));
    expect(second, first, reason: '判重命中＝返回既有行 id，不双落');
    expect(await repo.noteCount(), 1);
  });

  test('判重只认在库行：软删后同一句能重记（partial unique 只在 deleted_at IS NULL）', () async {
    final first = await repo.addNote(note('a', '删了再记', atMin: 12));
    await repo.deleteNote(first!);
    final again = await repo.addNote(note('a', '删了再记', atMin: 12));
    expect(again, isNotNull, reason: '撞旧索引会抛，这里必须落得下');
    expect(again, isNot(first));
    expect(await repo.noteCount(), 1, reason: '软删行不算在册');
  });

  test('判重键按条目＋子项＋时间点＋归一化正文：换时间点算两条，空白与大小写不算两条', () async {
    expect(
      MediaNote.dedupKey(itemId: 'a', body: '  Hello  World '),
      MediaNote.dedupKey(itemId: 'a', body: 'helloworld'),
    );
    expect(
      MediaNote.dedupKey(itemId: 'a', atMin: 1, body: 'x'),
      isNot(MediaNote.dedupKey(itemId: 'a', atMin: 2, body: 'x')),
    );
    expect(MediaNote.dedupKey(itemId: 'a', body: '  '), isEmpty);
    final a = await repo.addNote(note('a', '同一句', atMin: 5));
    final b = await repo.addNote(note('a', '同一句', atMin: 6));
    expect(b, isNot(a));
    expect(await repo.noteCount(), 2);
  });

  test('「记住了」逐档推进 1→3→7 后走完：next 落 NULL 且不再进队列', () async {
    final t0 = 1700000000000;
    final id = await repo.addNote(note('a', '要复习的名场面', createdAt: t0));
    var cur = (await repo.noteById(id!))!;
    expect(cur.reviewStage, 0);
    // 逐档：打卡时刻＝上一档的到期时刻，新到期＝打卡＋该档间隔（间隔取自模型）
    var due = t0 + gaps.first * dayMs;
    for (var i = 0; i < gaps.length; i++) {
      expect(await repo.dueReviewCount(now: due - 1), 0,
          reason: '第 $i 档到期前一毫秒不该进队列');
      expect(await repo.dueReviewCount(now: due), 1);
      cur = (await repo.markRemembered(id, now: due))!;
      expect(cur.reviewStage, i + 1, reason: '第 ${i + 1} 次记住要推一档（原地踏步＝刀2）');
      expect(cur.reviewedAt, due);
      // 打卡后按「新档」的间隔排期（首档 1 天已在入账时排掉，此处应走 3→7→走完）
      final nextGap = i + 1 < gaps.length ? gaps[i + 1] : null;
      expect(
        cur.nextReviewAt,
        nextGap == null ? isNull : due + nextGap * dayMs,
        reason: '第 ${i + 1} 次记住后应隔 ${nextGap ?? '不再'} 天再出',
      );
      if (nextGap == null) break;
      due = cur.nextReviewAt!;
    }
    expect(cur.isMastered, isTrue);
    expect(cur.nextReviewAt, isNull, reason: '走完三档＝不再排期');
    expect(await repo.dueReviewNotes(now: due + 365 * dayMs), isEmpty);
    // 再多点一次也不越界（clamp 守住档位数），且落库行同步
    final extra = await repo.markRemembered(id, now: due + 365 * dayMs);
    expect(extra!.reviewStage, MediaNote.masteredStage);
    expect(extra.nextReviewAt, isNull);
    final row = await rowOf(id);
    expect(row['review_stage'], MediaNote.masteredStage);
    expect(row['next_review_at'], isNull, reason: '档位要落库，不能只在内存里推');
  });

  test('到期队列＝筛过的笔记：软删行不出、按下次到期升序、角标读数与队列长度同口径', () async {
    final live = <int, int>{}; // id → 到期时刻
    for (var i = 0; i < 5; i++) {
      // 错开建档时刻，使到期时刻天然有序（现算，不写死毫秒）
      final id = await repo.addNote(
        note('a', '第 $i 条', createdAt: 1700000000000 + i * dayMs),
      );
      live[id!] = 1700000000000 + i * dayMs + gaps.first * dayMs;
    }
    final toDelete = live.keys.last;
    await repo.deleteNote(toDelete);
    final queue = await repo.dueReviewNotes(now: 1800000000000);
    expect(queue, hasLength(live.length - 1));
    expect(queue.map((n) => n.id), isNot(contains(toDelete)));
    final times = queue.map((n) => n.nextReviewAt!).toList();
    expect(times, orderedEquals(List.from(times)..sort()));
    expect(live.length - 1, 4, reason: '种子 5 条删 1 条＝队列 4（自检种子没跑偏）');
    // 角标与队列同一份 where：任何筛选组合下两者必相等
    for (final starred in [false, true]) {
      for (final kind in ['movie', 'series', null]) {
        expect(
          await repo.dueReviewCount(now: 1800000000000, kind: kind, starredOnly: starred),
          (await repo.dueReviewNotes(
            now: 1800000000000,
            kind: kind,
            starredOnly: starred,
          ))
              .length,
        );
      }
    }
  });

  test('六路筛选（kind/类型/条目/标星/标签/关键词）逐路生效且组合不放大', () async {
    final m1 = await addItem('沙丘 2');
    final m2 = await addItem('奥本海默', kind: 'series');
    final seeds = <MediaNote>[
      note(m1, '拳头砸在玻璃上', tag: '名场面', starred: true, atMin: 90),
      note(m1, '台词：不要想，去想', noteType: MediaNote.kLine, tag: '台词'),
      note(m2, '歌词片段', kind: 'series', noteType: MediaNote.kLyric, tag: '歌词'),
      note(m2, '长评正文', kind: 'series', noteType: MediaNote.kLong, tag: '名场面'),
      note(m1, '截图一张', noteType: MediaNote.kShot, imagePaths: ['/tmp/x.png']),
    ];
    final ids = <int>[];
    for (final s in seeds) {
      ids.add((await repo.addNote(s))!);
    }
    Future<Set<int>> idsWhere({
      String? kind,
      String? itemId,
      String? noteType,
      String? tag,
      String? query,
      bool starredOnly = false,
    }) async =>
        (await repo.notes(
          kind: kind,
          itemId: itemId,
          noteType: noteType,
          tag: tag,
          query: query,
          starredOnly: starredOnly,
        ))
            .map((n) => n.id!)
            .toSet();

    // 逐路
    expect(await idsWhere(kind: 'movie'), {ids[0], ids[1], ids[4]});
    expect(await idsWhere(itemId: m2), {ids[2], ids[3]});
    expect(await idsWhere(noteType: MediaNote.kLine), {ids[1]});
    expect(await idsWhere(tag: '名场面'), {ids[0], ids[3]});
    expect(await idsWhere(starredOnly: true), {ids[0]});
    expect(await idsWhere(query: '玻璃'), {ids[0]});
    expect(await idsWhere(query: '奥本海默'), {ids[2], ids[3]},
        reason: '关键词打条目名（走在册条目子查询）');
    // 组合：三路叠加结果必是单路结果的交集（不放大＝没有 OR 泄漏）
    final combo = await idsWhere(
        kind: 'series', noteType: MediaNote.kLong, tag: '名场面');
    expect(combo, {ids[3]});
    expect(
      combo.length,
      (await idsWhere(kind: 'series'))
          .intersection(await idsWhere(tag: '名场面'))
          .length,
    );
    // 四视图同口径：清单条数＝条目分面计数之和＝种子数
    final list = await repo.notes();
    expect(list, hasLength(seeds.length));
    final facet = await repo.noteItemFacet();
    expect(facet.fold<int>(0, (s, e) => s + e.count), list.length);
    expect(facet.first.count, 3, reason: '沙丘 2 三条笔记排前');
    // 选中一个条目时分面仍列全（否则条目 chips 选后就消失）
    expect(await repo.noteItemFacet(), hasLength(2));
    expect(await repo.notes(itemId: m2), hasLength(2));
    // 标签 chips 来源＝在册行 tag 去重排序（期望值现算自种子，不写死码位序）
    final expTags = <String>{
      ...seeds.map((s) => s.tag).whereType<String>(),
    }.toList()
      ..sort();
    expect(await repo.noteTags(), expTags);
    expect(expTags, hasLength(3), reason: '种子三枚标签（空标签不进 chips）');
  });

  test('删除走软删：笔记库与该条目时间线同帧不见，档位行仍在库（审计面留痕）', () async {
    final m = await addItem('沙丘 2');
    final a = (await repo.addNote(note(m, '留着', atMin: 10)))!;
    final b = (await repo.addNote(note(m, '删掉', atMin: 20)))!;
    expect(await repo.notesOfItem(m), hasLength(2));
    await repo.deleteNote(b);
    expect(await repo.notesOfItem(m).then((v) => v.map((n) => n.id).toSet()), {a});
    expect(await repo.notes().then((v) => v.map((n) => n.id).toSet()), {a});
    final raw = await db.query(
      md.tMediaNotes,
      where: 'id = ?',
      whereArgs: [b],
    );
    expect(raw.single['deleted_at'], isNotNull, reason: '软删不是物理删');
    expect(await repo.noteById(b), isNull);
    expect(await repo.markRemembered(b), isNull, reason: '软删行推不动档');
  });

  test('行内标星即时翻转；编辑只改该改的（未露字段不被洗掉）', () async {
    final m = await addItem('沙丘 2');
    final id = (await repo.addNote(
      note(m, '原正文', tag: '原标签', thought: '原批注', atMin: 44),
    ))!;
    await repo.setNoteStarred(id, true);
    expect((await repo.noteById(id))!.starred, isTrue);
    expect(await repo.notes(starredOnly: true), hasLength(1));
    await repo.setNoteStarred(id, false);
    expect((await repo.noteById(id))!.starred, isFalse);

    final cur = (await repo.noteById(id))!;
    final edited = cur.copyWith(
      body: '改过的正文',
      imagePaths: const ['/p/1.png', '/p/2.png'],
    );
    expect(await repo.updateNote(edited), isTrue);
    final back = (await repo.noteById(id))!;
    expect(back.body, '改过的正文');
    // 批3 教训的全字段透传：没在表单露出的列一个都不许被洗成空
    expect(back.tag, cur.tag);
    expect(back.thought, cur.thought);
    expect(back.atMin, cur.atMin);
    expect(back.itemId, cur.itemId);
    expect(back.kind, cur.kind);
    expect(back.noteType, cur.noteType);
    expect(back.origin, cur.origin);
    expect(back.createdAt, cur.createdAt);
    expect(back.reviewStage, cur.reviewStage);
    expect(back.nextReviewAt, cur.nextReviewAt);
    expect(back.imagePaths, ['/p/1.png', '/p/2.png']);
  });

  test('JSON 列与档位编解码成环：toRow→fromMap 一字段不丢，脏值读空并留痕不抛', () {
    final src = MediaNote(
      id: 7,
      itemId: 'a',
      kind: 'game',
      noteType: MediaNote.kShot,
      body: 'b',
      tag: 't',
      thought: 'th',
      unitRef: 3,
      atMin: 9,
      imagePaths: const ['x', 'y'],
      tags: const ['u'],
      starred: true,
      createdAt: 11,
      updatedAt: 12,
      deletedAt: 13,
      origin: MediaNote.kOriginSession,
      dedupHash: 'h',
      reviewStage: 2,
      reviewedAt: 14,
      nextReviewAt: 15,
    );
    final row = Map<String, Object?>.from(src.toRow())
      ..['id'] = src.id
      ..['created_at'] = src.createdAt
      ..['updated_at'] = src.updatedAt;
    final back = MediaNote.fromMap(row);
    expect(back.toRow(), src.toRow());
    expect(back.id, 7);
    expect(back.imagePaths, ['x', 'y']);
    expect(back.tags, ['u']);
    expect(back.isDeleted, isTrue);
    // 脏值容错（裸文本/非列表/坏 JSON 一律空列表，不抛）
    expect(MediaNote.fromMap({'image_paths': 'not json'}).imagePaths, isEmpty);
    expect(MediaNote.fromMap({'image_paths': '{"a":1}'}).imagePaths, isEmpty);
    expect(MediaNote.fromMap({'tags': '["a",1]'}).tags, ['a', '1']);
    // 档位工具：走完档不再给间隔，未走完逐档取值
    expect(MediaNote.gapDaysForStage(0), gaps[0]);
    expect(MediaNote.gapDaysForStage(MediaNote.masteredStage), isNull);
  });

  test('迁移守护：v38 形态老库跑 38→39 后三列齐、旧行档位 0 且未排期、软删行让出判重键', () async {
    // sqflite ffi 的 `:memory:` 按路径缓存＝同一个 handle，不能再开一库；
    // 把笔记表拆回 v38 形态（只重放提到本表的那批建表语句）再走 38→39 迁移。
    await db.execute('DROP TABLE IF EXISTS ${md.tMediaNotes}');
    for (final sql in DbSchema.migrations[37]!
        .where((s) => s.contains(md.tMediaNotes))) {
      await db.execute(sql);
    }
    final cols = (await db.rawQuery('PRAGMA table_info(${md.tMediaNotes})'))
        .map((r) => '${r['name']}')
        .toSet();
    expect(cols.contains('review_stage'), isFalse, reason: 'v38 形态本不该有复习列');
    final oldId = await db.insert(md.tMediaNotes, {
      'item_id': 'a',
      'kind': 'movie',
      'note_type': 'scene',
      'body': '老库笔记',
      'created_at': 1,
      'updated_at': 1,
      'dedup_hash': 'k1',
    });
    await db.insert(md.tMediaNotes, {
      'item_id': 'a',
      'kind': 'movie',
      'note_type': 'scene',
      'body': '老库软删笔记',
      'created_at': 1,
      'updated_at': 1,
      'deleted_at': 5,
      'dedup_hash': 'k2',
    });

    for (final sql in DbSchema.migrations[38]!) {
      await db.execute(sql);
    }
    final r = (await db.query(
      md.tMediaNotes,
      where: 'id = ?',
      whereArgs: [oldId],
    ))
        .single;
    expect(r['review_stage'], 0);
    expect(r['reviewed_at'], isNull);
    expect(r['next_review_at'], isNull, reason: '存量行不批量排期（档位由用户点出来的）');

    // 旧全量唯一索引若没摘掉，这里必抛（软删行永久占着 k2）
    await db.insert(md.tMediaNotes, {
      'item_id': 'a',
      'kind': 'movie',
      'note_type': 'scene',
      'body': '删了重记',
      'created_at': 2,
      'updated_at': 2,
      'dedup_hash': 'k2',
    });
    expect(
      await db.query(
        md.tMediaNotes,
        where: 'dedup_hash = ? AND deleted_at IS NULL',
        whereArgs: ['k2'],
      ),
      hasLength(1),
    );
    // 在库行之间仍然互斥（判重没被摘松）
    await expectLater(
      db.insert(md.tMediaNotes, {
        'item_id': 'a',
        'kind': 'movie',
        'note_type': 'scene',
        'body': '撞键',
        'created_at': 3,
        'updated_at': 3,
        'dedup_hash': 'k1',
      }),
      throwsA(anything),
    );
  });
}
