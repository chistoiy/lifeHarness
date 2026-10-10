import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/platform/open_intent.dart';
import 'package:lifeharness/features/journal/data/note_dao.dart';
import 'package:lifeharness/features/journal/data/note_folder_dao.dart';
import 'package:lifeharness/features/journal/domain/note.dart';
import 'package:lifeharness/features/journal/domain/note_folder.dart';
import 'package:lifeharness/features/journal/presentation/note_open_with.dart';

// V1.64 批1（工单 交棒话术-20261004 §2 N-3/N-4 · 拍板 C/F/G）常驻件。
// 纯数据/服务层＋源码守护：无 pump（不占全 app 级拆分铁律的隔离面）；
// 真磁盘与通道 IO 全走注入缝（noteOpenReadContent / noteWriteBack）。

void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late NoteDao notes;
  late NoteFolderDao folders;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    notes = NoteDao(db);
    folders = NoteFolderDao(db);
    noteOpenReadContent = (path) async => '# 正文来自 $path';
    noteWriteBack = (uri, content) async => 'ok';
  });
  tearDown(() async => db.close());

  Future<int> idOfFolder(String name) async =>
      (await folders.list()).firstWhere((f) => f.name == name).id!;

  group('① schema v41（notes 来源四列）', () {
    test('版本 41·40→41 段真含四列 ALTER·基础 DDL 新装也带列', () {
      expect(DbSchema.version, 42,
          reason: '批2（挂载三列＋src_hash）又升一级；40→41 段必须仍在册');
      expect(DbSchema.migrations.containsKey(40), isTrue,
          reason: '缺这段＝老库升级没有来源列（新装有老库没有）');
      final seg = DbSchema.migrations[40]!.join(' ');
      for (final col in ['source', 'origin_path', 'origin_uri', 'opened_at']) {
        expect(seg, contains('ADD COLUMN $col'), reason: '$col 不在 40→41 段');
      }
      final create = DbSchema.createStatements
          .firstWhere((s) => s.contains('CREATE TABLE $DbSchema.tNotes') ||
              s.contains('CREATE TABLE notes'));
      for (final col in ['source', 'origin_path', 'origin_uri', 'opened_at']) {
        expect(create, contains(col), reason: '基础 DDL 缺 $col（新装库会读不到列）');
      }
    });

    test('Note 四列 round-trip（toRow→fromRow 等值）', () async {
      final now = DateTime.now();
      final n = Note(
          title: '甲',
          content: 'c',
          kind: 'md',
          folder: '乙',
          source: 'open_with',
          originPath: '甲.md',
          originUri: 'content://x/1',
          openedAt: now,
          createdAt: now,
          updatedAt: now);
      final saved = await notes.save(n);
      final back = await notes.byId(saved.id!);
      expect(back!.source, 'open_with');
      expect(back.originPath, '甲.md');
      expect(back.originUri, 'content://x/1');
      expect(back.openedAt!.millisecondsSinceEpoch,
          now.millisecondsSinceEpoch);
    });
  });

  group('② importOpenedNote（N-3/N-4 · 拍板 C/F）', () {
    Future<NoteOpenResult> imp({String fileName = '会议纪要.md', String uri = 'content://a/1'}) =>
        importOpenedNote(
            notes: notes,
            folders: folders,
            path: '/cache/lh_open/$fileName',
            fileName: fileName,
            uri: uri);

    test('首开＝建条＋归集「系统打开」夹＋来源/URI/时间落值', () async {
      final r = await imp();
      expect(r.outcome, NoteOpenOutcome.created);
      final n = r.note!;
      expect(n.kind, 'md');
      expect(n.folder, kSystemOpenFolder);
      expect(n.source, 'open_with');
      expect(n.originUri, 'content://a/1');
      expect(n.title, '会议纪要');
      expect(n.openedAt, isNotNull);
      expect(await folders.list(),
          contains(predicate<NoteFolder>((f) => f.name == kSystemOpenFolder)));
      expect(await notes.list(folder: kSystemOpenFolder), hasLength(1));
    });

    test('同名（同 URI）二次打开＝覆盖更新不堆副本', () async {
      final a = await imp();
      noteOpenReadContent = (path) async => '# 新正文 v2';
      final b = await imp(fileName: '会议纪要.md');
      expect(b.outcome, NoteOpenOutcome.updated);
      expect(b.note!.id, a.note!.id, reason: '更新必须钉在原行（拍板 C）');
      expect(await notes.list(folder: kSystemOpenFolder), hasLength(1));
      expect((await notes.byId(a.note!.id!))!.content, '# 新正文 v2');
    });

    test('回收站行不参与判重（E 批红线）：软删后同 URI 再开＝新建在册', () async {
      final a = await imp();
      await notes.softDelete(a.note!.id!);
      final b = await imp();
      expect(b.outcome, NoteOpenOutcome.created);
      expect(b.note!.id, isNot(a.note!.id));
      expect(await notes.list(folder: kSystemOpenFolder), hasLength(1));
    });

    test('读失败＝failed 不建条不建夹', () async {
      noteOpenReadContent = (path) async => throw Exception('盘读失败');
      final r = await imp();
      expect(r.outcome, NoteOpenOutcome.failed);
      expect(r.note, isNull);
      expect(await folders.list(), isEmpty);
    });

    test('固定「系统打开」夹删除被 DAO 守卫吞掉（历史列表载体不丢）', () async {
      await imp();
      final id = await idOfFolder(kSystemOpenFolder);
      await folders.deleteTree(id);
      expect(await folders.list(),
          contains(predicate<NoteFolder>((f) => f.name == kSystemOpenFolder)));
      expect(await notes.list(folder: kSystemOpenFolder), hasLength(1));
    });
  });

  group('③ 回写分派（拍板 G · 变异刀②靶点）', () {
    test('仅 open_with＋带 URI 才回写；其余来源/空 URI 不打扰', () async {
      final calls = <String>[];
      noteWriteBack = (uri, content) async {
        calls.add(uri);
        return 'ok';
      };
      expect(
          await noteWriteBackGuard(
              source: 'open_with', originUri: 'content://a/1', content: 'x'),
          'ok');
      expect(await noteWriteBackGuard(source: '', originUri: 'content://a/1', content: 'x'),
          isNull);
      expect(await noteWriteBackGuard(source: 'local_dir', originUri: 'p', content: 'x'),
          isNull);
      expect(await noteWriteBackGuard(source: 'open_with', originUri: '', content: 'x'),
          isNull);
      expect(calls, ['content://a/1']);
    });

    test('编辑页落库点必须真调回写守卫（源码守护·代码行原文）', () async {
      final src =
          (  _readFile('lib/features/journal/presentation/note_edit_save.dart'))
              .split('\n');
      final codeLines = src
          .where((l) => !l.trimLeft().startsWith('//'))
          .where((l) => l.contains('noteWriteBackGuard('));
      expect(codeLines, hasLength(1),
          reason: '_persist 里的回写分派被摘＝本批核心承诺（保存回写原文件）失效');
    });

    test('组合根分派在场（app.dart 三行接线源码守护）', () async {
      final src = ( _readFile('lib/app.dart')).split('\n');
      final code = src.where((l) => !l.trimLeft().startsWith('//')).join('\n');
      expect(code, contains('classifyOpenIntent('));
      expect(code, contains('kOpenUnsupportedToast'));
      expect(code, contains('noteOpenConsume('));
      expect(code, contains('handleOpenWithEpub('));
    });
  });

  group('④ 通道 takeOpenFile（三态泛化回归）', () {
    const channel = MethodChannel('lh/intents');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    testWidgets('null=无待处理；kind ""=拒收；map=解析四字段', (t) async {
      Object? reply;
      messenger.setMockMethodCallHandler(channel, (call) async => reply);
      expect(await takeOpenFile(), isNull);
      reply = {'kind': ''};
      expect((await takeOpenFile())!.kind, '');
      reply = {
        'kind': 'note',
        'path': '/cache/lh_open/x.md',
        'name': 'x.md',
        'uri': 'content://a/2'
      };
      final f = (await takeOpenFile())!;
      expect(f.kind, 'note');
      expect(f.uri, 'content://a/2');
      expect(classifyOpenIntent(null), isNull);
      expect(classifyOpenIntent(f), 'note');
      messenger.setMockMethodCallHandler(channel, null);
    });
  });
}

// 源码守护读文件（定式同 entry_retire_test：读工作树源码文本断代码行原文）。
String _readFile(String rel) => File(rel).readAsStringSync();
