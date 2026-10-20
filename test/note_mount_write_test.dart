import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/platform/saf_tree.dart';
import 'package:lifeharness/features/journal/data/note_dao.dart';
import 'package:lifeharness/features/journal/data/note_folder_dao.dart';
import 'package:lifeharness/features/journal/domain/note.dart';
import 'package:lifeharness/features/journal/presentation/note_local_import.dart';
import 'package:lifeharness/features/journal/presentation/note_mount_write.dart';

// V1.64 真机反馈批③（工单 交棒话术-20261011 §4·拍板「挂载即双向」）常驻件。
// 真 IO 全走注入缝：假原生复刻「同名追加 (2)」与「只读挂载 no_perm」两件事。

/// 假目录：taken＝目录里已有的文件名；writable＝拿没拿到写授权；written＝落盘内容台账。
Future<MountWriteResult> Function(
        {required String tree,
        required String relPath,
        required String name,
        required String text})
    fakeWrite(Set<String> taken,
        {bool writable = true,
        Map<String, String>? written,
        List<String>? relSeen}) =>
    ({required String tree,
      required String relPath,
      required String name,
      required String text}) async {
      if (!writable) return const MountWriteResult(code: 'no_perm');
      relSeen?.add(relPath);
      final dot = name.lastIndexOf('.');
      final base = dot > 0 ? name.substring(0, dot) : name;
      final ext = dot > 0 ? name.substring(dot) : '';
      var candidate = name, n = 1;
      while (taken.contains(candidate)) {
        n++;
        candidate = '$base($n)$ext';
      }
      taken.add(candidate);
      written?[candidate] = text;
      return MountWriteResult(
          code: 'ok',
          uri: 'content://doc/$candidate',
          name: candidate,
          localPath: relPath.isEmpty ? candidate : '$relPath/$candidate');
    };

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
  });
  tearDown(() async => db.close());

  Future<Note> mk(String title, {String? folder, String uri = '', String body = '正文'}) async {
    final now = DateTime.now();
    return notes.save(Note(
        title: title,
        content: body,
        kind: 'md',
        folder: folder,
        originUri: uri,
        createdAt: now,
        updatedAt: now));
  }

  Future<MountSyncResult> sync(Note n,
          {Set<String>? taken,
          bool writable = true,
          Map<String, String>? written,
          List<String>? relSeen,
          Future<String> Function(String uri, String content)? overwrite}) =>
      syncNoteToMount(
          saved: n,
          notes: notes,
          folders: folders,
          create: fakeWrite(taken ?? <String>{},
              writable: writable, written: written, relSeen: relSeen),
          overwrite: overwrite);

  /// 挂一个「本地导入的目录夹」（根＋一个子夹），与真机导入后的形状一致。
  Future<void> mountVault({String rootUri = 'content://tree/v1'}) async {
    const root = SafDoc(
        name: 'obsidian',
        uri: 'content://tree/v1',
        isDir: true,
        path: 'Download/obsidian',
        children: [
          SafDoc(name: '未命名', uri: 'content://tree/u1', isDir: true, children: [
            SafDoc(name: '已有的一篇.md', uri: 'content://doc/e1', isDir: false),
          ]),
        ]);
    await importLocalTree(
        notes: notes,
        folders: folders,
        root: root,
        readText: (uri) async => uri == 'content://doc/e1' ? '目录里本来就有的正文' : 'x');
  }

  group('① 新建即落盘', () {
    test('挂载根下的新笔记＝写文件并回填 URI 与实际文件名', () async {
      await mountVault();
      final n = await mk('会议记录', folder: 'obsidian');
      final written = <String, String>{};
      final r = await sync(n, taken: <String>{}, written: written);
      expect(r.outcome, MountSync.created);
      expect(written.keys, ['会议记录.md']);
      final back = (await notes.byId(n.id!))!;
      expect(back.originUri, 'content://doc/会议记录.md');
      expect(back.originPath, '会议记录.md');
      expect(back.srcHash, isNotEmpty, reason: '落盘后补内容哈希，重导同内容才算得出重复');
    });

    test('子夹下的新笔记＝relPath 走子夹相对路径（写进子目录不是根目录）', () async {
      await mountVault();
      final relSeen = <String>[];
      final r = await sync(await mk('新的一篇', folder: '未命名'),
          taken: <String>{}, relSeen: relSeen);
      expect(r.outcome, MountSync.created);
      expect(relSeen, ['未命名'], reason: '子夹的 origin_path 就是相对挂载根的路径');
    });

    test('同名第二篇＝文件名追加 (2)，两条笔记各自持自己的 URI', () async {
      await mountVault();
      final taken = <String>{};
      final a = await sync(await mk('灵感', folder: 'obsidian'), taken: taken);
      final b = await sync(await mk('灵感', folder: 'obsidian'), taken: taken);
      expect(a.outcome, MountSync.created);
      expect(b.outcome, MountSync.created);
      final nb = (await notes.byId((b.note)!.id!))!;
      expect(nb.originPath, '灵感(2).md');
      expect(nb.originUri, isNot((await notes.byId(a.note!.id!))!.originUri));
    });

    test('标题为空＝落「未命名笔记.md」不出空文件名', () async {
      await mountVault();
      final written = <String, String>{};
      await sync(await mk('   ', folder: 'obsidian'),
          taken: <String>{}, written: written);
      expect(written.keys, ['未命名笔记.md']);
    });
  });

  group('② 编辑覆写与失败可见', () {
    test('已有 URI 的条目（导入进来的那篇）＝覆写原文件，不新建', () async {
      await mountVault();
      final imported = (await notes.list(folder: '未命名')).single;
      expect(imported.originUri, 'content://doc/e1');
      final called = <String, String>{};
      final r = await sync(imported.copyWith(content: '改过的正文'),
          overwrite: (uri, content) async {
            called[uri] = content;
            return 'ok';
          });
      expect(r.outcome, MountSync.written);
      expect(called.keys, ['content://doc/e1'], reason: '必须写回原文件而不是另建一份');
      expect(called['content://doc/e1'], '改过的正文');
    });

    test('覆写 no_perm＝提示讲清「重新导入一次该目录」', () async {
      await mountVault();
      final imported = (await notes.list(folder: '未命名')).single;
      final r = await sync(imported,
          overwrite: (uri, content) async => 'no_perm');
      expect(r.outcome, MountSync.noPerm);
      expect(r.toastLine, contains('导入本地'));
      expect(r.toastLine, contains('再选它一次'));
    });

    test('覆写 missing＝改动仅存应用内', () async {
      await mountVault();
      final imported = (await notes.list(folder: '未命名')).single;
      final r = await sync(imported, overwrite: (uri, content) async => 'missing');
      expect(r.outcome, MountSync.failed);
      expect(r.toastLine, contains('仅存应用内'));
    });

    test('目录只有读权限＝no_perm，但应用内的保存照完成（绝不吞稿）', () async {
      await mountVault();
      final n = await mk('新的一篇', folder: 'obsidian', body: '没写出去也不能丢');
      final r = await sync(n, taken: <String>{}, writable: false);
      expect(r.outcome, MountSync.noPerm);
      final back = (await notes.byId(n.id!))!;
      expect(back.content, '没写出去也不能丢');
      expect(back.originUri, isEmpty, reason: '没落成文件就不该假装记住了 URI');
    });
  });

  group('③ 不该写的一律不打扰', () {
    test('手建夹／单文件挂标夹／导出夹／未归类＝都不写回', () async {
      await folders.create('手建夹');
      await folders.create('挂标夹', source: 'local_file');
      await folders.create('笔记导出', source: 'export', originUri: 'content://tree/x');
      var touched = 0;
      Future<String> boom(String uri, String content) async {
        touched++;
        return 'ok';
      }

      for (final f in ['手建夹', '挂标夹', '笔记导出', null]) {
        final r = await sync(await mk('甲$f', folder: f),
            taken: <String>{}, overwrite: boom);
        expect(r.outcome, MountSync.none, reason: '$f 不是本地导入的挂载夹');
      }
      expect(touched, 0);
    });

    test('挂载夹没有 origin_uri（异常数据）＝不写回也不抛', () async {
      await folders.create('空挂载', source: 'local_dir');
      final r = await sync(await mk('空挂载甲', folder: '空挂载'), taken: <String>{});
      expect(r.outcome, MountSync.none);
    });

    test('open_with 来源即便落在挂载夹下＝也不走挂载口（批1 回写口已负责，防一次保存写两遍）',
        () async {
      await mountVault();
      final now = DateTime.now();
      final viaOpen = await notes.save(Note(
          title: '从系统打开进来的',
          content: '正文',
          kind: 'md',
          folder: 'obsidian',
          source: 'open_with',
          originUri: 'content://doc/open1',
          openedAt: now,
          createdAt: now,
          updatedAt: now));
      var touched = 0;
      final r = await sync(viaOpen,
          taken: <String>{},
          overwrite: (uri, content) async {
            touched++;
            return 'ok';
          });
      expect(r.outcome, MountSync.none);
      expect(touched, 0, reason: '挂载口再写一遍＝同一次保存落两个文件/写两回');
    });
  });

  group('④ 重新授权与接线守护', () {
    test('重新导入同一目录＝刷新挂载锚点（老只读夹由此拿到写权限）', () async {
      await mountVault();
      final before = (await folders.byName('obsidian'))!;
      expect(before.originUri, 'content://tree/v1');
      const root2 = SafDoc(
          name: 'obsidian',
          uri: 'content://tree/v2',
          isDir: true,
          path: 'Download/obsidian');
      await importLocalTree(
          notes: notes,
          folders: folders,
          root: root2,
          readText: (uri) async => 'x');
      final after = (await folders.byName('obsidian'))!;
      expect(after.originUri, 'content://tree/v2',
          reason: 'URI 不刷新＝写回永远打在失效的旧授权上');
      expect(await folders.list(), hasLength(2), reason: '同名夹复用，不重复建');
    });

    test('落库点必须真调写回分派（源码守护·代码行原文）', () {
      final lines =
          File('lib/features/journal/presentation/note_edit_save.dart')
              .readAsStringSync()
              .split('\n')
              .where((l) => !l.trimLeft().startsWith('//'));
      expect(lines.where((l) => l.contains('syncNoteToMount(')), hasLength(1),
          reason: '摘掉这行＝「在已导入目录下建的笔记文件管理器看不到」原样复发');
    });

    test('原生与 Dart 缝一一对应：createInTree＋读|写授权', () {
      final kt = File(
              'android/app/src/main/kotlin/com/lifeharness/lifeharness/MainActivity.kt')
          .readAsStringSync();
      expect(kt, contains('"createInTree"'));
      expect(kt, contains('FLAG_GRANT_WRITE_URI_PERMISSION'),
          reason: '不申请写授权＝挂载即双向根本做不到');
      expect(kt, contains('DocumentsContract.createDocument'));
      expect(kt, isNot(contains('MANAGE_EXTERNAL_STORAGE')));
    });
  });
}
