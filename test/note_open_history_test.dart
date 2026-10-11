import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/journal/data/note_dao.dart';
import 'package:lifeharness/features/journal/domain/note.dart';
import 'package:lifeharness/features/journal/domain/note_folder.dart';
import 'package:lifeharness/features/journal/presentation/note_open_history.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// V1.64 批4 · N-4「系统打开」历史件（工单 交棒话术-20261004 §18 面板＝本批唯一规格依据）。
// 纯件：三态判定／取数与清空语义／转入保留来源／DB v43 两路同段带列＋round-trip。
// 真库（in-memory sqlite）＋零平台通道（本批不动 android/**，回写口不在这里测）。

void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late NoteDao notes;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    notes = NoteDao(db);
  });
  tearDown(() async => db.close());

  final t0 = DateTime.now();

  Note openWith(String title,
      {String folder = kSystemOpenFolder,
      DateTime? wbAt,
      DateTime? openedAt,
      DateTime? updatedAt}) =>
      Note(
          title: title,
          content: '正文',
          kind: 'md',
          folder: folder,
          source: 'open_with',
          originPath: 'Download/$title.md',
          originUri: 'content://doc/$title',
          openedAt: openedAt ?? t0,
          wbAt: wbAt,
          createdAt: t0,
          updatedAt: updatedAt ?? t0);

  group('① DB v43（纯加列·两路同段带列·round-trip）', () {
    test('目标版本＝43', () => expect(DbSchema.version, 43));

    test('42→43 段真含 notes.wb_at 的 ALTER', () {
      expect(DbSchema.migrations[42], isNotNull,
          reason: '缺这行＝老库升级后没有该列，历史行三态直接崩（读 NULL 列）');
      expect(
          DbSchema.migrations[42]!
              .any((s) => s.contains('wb_at') && s.contains('ALTER TABLE')),
          isTrue);
    });

    test('基础 DDL 的 notes 建表段同批带列（新建库不靠迁移）', () {
      final ddl =
          DbSchema.createStatements.firstWhere((s) => s.contains('CREATE TABLE notes'));
      expect(ddl, contains('wb_at INTEGER'),
          reason: '只加迁移不加基础 DDL＝新装库有列、老库没列，两路不对齐（批2 立的口径）');
    });

    test('setWrittenAt 落库后读回＝拷贝点没漏（fromRow/toRow/copyWith）', () async {
      final n = await notes.save(openWith('甲'));
      expect(n.wbAt, isNull, reason: '刚导入＝从没回写过，默认必须为空');
      final at = t0.add(const Duration(minutes: 5));
      await notes.setWrittenAt(n.id!, at);
      final back = (await notes.byId(n.id!))!;
      expect(back.wbAt!.millisecondsSinceEpoch, at.millisecondsSinceEpoch,
          reason: '库里存得住、内存读不回＝copyWith/fromRow 漏字段（只有 round-trip 抓得到）');
      // copyWith 不许把 wbAt 丢掉（编辑保存走的就是这条链）
      expect(back.copyWith(title: '改名').wbAt, isNotNull);
    });

    test('wb_at 单列更新不许顺手刷 updated_at', () async {
      final n = await notes.save(openWith('甲'));
      final before = (await notes.byId(n.id!))!;
      await notes.setWrittenAt(n.id!, before.updatedAt.add(const Duration(hours: 1)));
      final after = (await notes.byId(n.id!))!;
      expect(after.updatedAt.millisecondsSinceEpoch,
          before.updatedAt.millisecondsSinceEpoch,
          reason: '刷了它就没有「回写后又改了正文」这回事——三态会永远显示已回写');
    });
  });

  group('② 三态判定（原型 OF_ST 同词）', () {
    test('回写时间不早于最后修改＝已回写原文件', () {
      final u = t0.add(const Duration(minutes: 3));
      expect(
          noteHistStateOf(openWith('甲', updatedAt: u, wbAt: u)),
          NoteHistState.written,
          reason: '边界 wb_at==updated_at 算已回写（同一次保存里回写就在保存之后）');
      expect(
          noteHistStateOf(
              openWith('乙', updatedAt: u, wbAt: u.add(const Duration(seconds: 1)))),
          NoteHistState.written);
    });

    test('回写后又改了正文＝退回仅应用内（摘掉 wb_at 判定＝本例红＝刀①）', () {
      final wb = t0.add(const Duration(minutes: 1));
      expect(
          noteHistStateOf(openWith('甲',
              wbAt: wb, updatedAt: wb.add(const Duration(minutes: 2)))),
          NoteHistState.app,
          reason: '回写成功只弹 toast 不落库时推不出这条，故批4 加列——判定摘掉＝谎报');
      expect(noteHistStateOf(openWith('乙')), NoteHistState.app,
          reason: '从没回写过＝仅应用内');
    });

    test('归属已改到别的夹＝已转正式目录（优先于回写判定）', () {
      expect(
          noteHistStateOf(openWith('甲',
              folder: '方法论', wbAt: t0, updatedAt: t0.add(const Duration(days: 1)))),
          NoteHistState.moved);
    });

    test('三态词表与原型一致·仅应用内带小注', () {
      expect(noteHistLabel(NoteHistState.written), '已回写原文件');
      expect(noteHistLabel(NoteHistState.app), '仅应用内');
      expect(noteHistLabel(NoteHistState.moved), '已转正式目录');
      expect(noteHistHint(NoteHistState.app), '原文件不在 · 改动仅存应用内');
      expect(noteHistHint(NoteHistState.written), isNull);
      expect(noteHistHint(NoteHistState.moved), isNull);
    });

    test('标题为空＝回退到来源文件名去扩展名（不出现空白行）', () {
      expect(
          noteHistTitle(Note(
              title: '  ',
              content: 'x',
              originPath: 'Download/甲.md',
              createdAt: t0,
              updatedAt: t0)),
          '甲');
      expect(noteHistTitle(openWith('  ')), '未命名进件',
          reason: '来源名也是空白＝给人话，不画一行空白（列表里出现空行是最难查的缺陷）');
      expect(noteHistTitle(openWith('有题')), '有题');
    });
  });

  group('③ 取数、转入与清空（产品裁定的语义）', () {
    test('历史列表＝在册的 open_with 行·按最近打开倒序·软删不参与', () async {
      await notes.save(openWith('早', openedAt: t0.subtract(const Duration(days: 2))));
      await notes.save(openWith('晚', openedAt: t0));
      final keep = await notes.save(openWith('删我', openedAt: t0));
      await notes.save(Note(
          title: '普通笔记',
          content: 'x',
          folder: '灵感',
          createdAt: t0,
          updatedAt: t0));
      await notes.softDelete(keep.id!);
      final list = await openHistNotes(notes);
      expect(list.map((e) => e.title), ['晚', '早'],
          reason: '回收站行不许混进历史（E 批红线），非进件来源也不在列');
    });

    test('转入＝只改归属，来源标保留（＝「已转正式目录」态的唯一依据）', () async {
      final n = await notes.save(openWith('甲'));
      await notes.setFolderMany([n.id!], '方法论');
      final back = (await notes.byId(n.id!))!;
      expect(back.source, 'open_with',
          reason: '清掉来源＝这行从历史里消失且再也判不出 moved，还违拍板 B「来源不随编辑消失」');
      expect(noteHistStateOf(back), NoteHistState.moved);
    });

    test('清空＝只软删仍在临时夹的进件，已转入的一行不动', () async {
      final inTmp1 = await notes.save(openWith('甲'));
      final inTmp2 = await notes.save(openWith('乙'));
      final moved = await notes.save(openWith('丙', folder: '方法论'));
      final normal = await notes.save(Note(
          title: '普通',
          content: 'x',
          folder: kSystemOpenFolder,
          createdAt: t0,
          updatedAt: t0));
      expect(openHistPending(await openHistNotes(notes)).length, 2);
      expect(await openHistClear(notes), 2,
          reason: '条数只算进件；摘掉「仍在临时夹」这层过滤＝连已转入的一起删＝刀②红');
      expect((await notes.byId(inTmp1.id!))!.deletedAt, isNotNull);
      expect((await notes.byId(inTmp2.id!))!.deletedAt, isNotNull);
      expect((await notes.byId(moved.id!))!.deletedAt, isNull,
          reason: '原型原话「已转入的笔记不受影响」＝这条是承诺不是措辞');
      expect((await notes.byId(normal.id!))!.deletedAt, isNull,
          reason: '非 open_with 来源一律不许被这个按钮碰');
    });

    test('临时夹本来就空＝清空回 0 条不出假动作', () async {
      expect(await openHistClear(notes), 0);
    });
  });

  group('④ 接线在册（源码守护·代码行原文）', () {
    test('树顶固定行在场·该夹从树节点排除·计数与列表同一份读数', () {
      final src = File(
              'lib/features/journal/presentation/widgets/note_tree_drawer.dart')
          .readAsStringSync()
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(src, contains("keyName: 'nt-sysopen'"),
          reason: '固定行被摘＝N-4 没有入口（拍板 F 要求就在树上这一行）');
      expect(src, contains("badgeSource: 'temp'"), reason: '「临时」标不许漏');
      expect(src, contains('count: hist.length'),
          reason: '计数必须来自 openHistFrom(同一份 notesProvider)，另写 SQL＝两处数不一致');
      expect(src, contains('onTap: () => _openHist(hist)'),
          reason: '点它必须开半屏（原型 nohOpen），不是切目录');
      expect(src, contains('nodes.where((x) => x.name != kSystemOpenFolder)'),
          reason: '不在下方排除＝同一夹出现两处（固定行＋普通节点）＝刀③');
    });

    test('回写成功必须落 wb_at（不然三态永远两态）', () {
      final src = File(
              'lib/features/journal/presentation/note_edit_save.dart')
          .readAsStringSync()
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(src, contains("if (wb == 'ok')"),
          reason: '只在失败分支出声＝成功没落库，历史行分不清已回写/仅应用内');
      expect(src, contains('setWrittenAt('));
    });

    test('「临时」标取主题档，不新增硬编码色值（〇B 棘轮）', () {
      final src = File(
              'lib/features/journal/presentation/note_local_import.dart')
          .readAsStringSync();
      expect(src, contains("'temp': '临时'"));
      expect(src, contains('colorScheme.onSurfaceVariant'),
          reason: '新色值要走人审钉基线；本批用 token＝棘轮零新增');
    });
  });
}
