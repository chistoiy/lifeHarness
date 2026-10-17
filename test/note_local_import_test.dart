import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/platform/saf_tree.dart';
import 'package:lifeharness/features/journal/data/note_dao.dart';
import 'package:lifeharness/features/journal/data/note_folder_dao.dart';
import 'package:lifeharness/features/journal/domain/note.dart';
import 'package:lifeharness/features/journal/domain/note_folder.dart';
import 'package:lifeharness/features/journal/presentation/note_local_import.dart';

// V1.64 批2（工单 交棒话术-20261004 §12 面板）常驻件：N-1 目录/文件导入＋N-1c 挂载移除。
// 纯数据/服务层，无 pump（不占全 app 用例的拆分铁律面）；SAF 真 IO 全走注入缝。

/// 演示目录树：/Download/外来笔记夹/{外来总览.md, 会议记录/{协议草稿.md, 复盘意见.md}, 摘录/任务拆分.md}
/// ＋ 干扰项（.txt 走打开方式不收·.png 不收·隐藏夹整支不收·空夹也要挂出来）。
SafDoc demoTree() => const SafDoc(
      name: '外来笔记夹',
      uri: 'content://tree/root',
      isDir: true,
      path: 'Download/外来笔记夹',
      children: [
        SafDoc(
            name: '外来总览.md',
            uri: 'content://doc/overview',
            isDir: false,
            path: 'Download/外来笔记夹/外来总览.md'),
        SafDoc(name: '会议记录', uri: 'content://tree/meet', isDir: true, children: [
          SafDoc(name: '协议草稿.md', uri: 'content://doc/a', isDir: false),
          SafDoc(name: '复盘意见.md', uri: 'content://doc/b', isDir: false),
          SafDoc(name: '会议录音.txt', uri: 'content://doc/t', isDir: false),
          SafDoc(name: '白板.png', uri: 'content://doc/p', isDir: false),
        ]),
        SafDoc(name: '摘录', uri: 'content://tree/quote', isDir: true, children: [
          SafDoc(name: '任务拆分.markdown', uri: 'content://doc/c', isDir: false),
        ]),
        SafDoc(name: '空夹', uri: 'content://tree/empty', isDir: true),
        SafDoc(name: '.obsidian', uri: 'content://tree/hidden', isDir: true, children: [
          SafDoc(name: '设置.md', uri: 'content://doc/h', isDir: false),
        ]),
      ],
    );

Map<String, String> demoBodies() => {
      'content://doc/overview': '# 外来总览\n正文甲',
      'content://doc/a': '## 协议草稿\n正文乙',
      'content://doc/b': '## 复盘意见\n正文丙',
      'content://doc/c': '任务拆分\n正文丁',
      'content://doc/t': '这不是 markdown',
      'content://doc/p': 'png 二进制',
      'content://doc/h': '隐藏夹里的设置',
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

  Future<LocalImportReport> impTree({
    SafDoc? root,
    Future<String?> Function(String uri)? readText,
  }) =>
      importLocalTree(
          notes: notes,
          folders: folders,
          root: root ?? demoTree(),
          readText: readText ?? ((uri) async => demoBodies()[uri]));

  Future<NoteFolder?> folderOf(String name) => folders.byName(name);

  group('① schema v42（挂载三列＋内容哈希列）', () {
    test('版本 42·41→42 段真含四列 ALTER＋索引·基础 DDL 同段带列', () {
      expect(DbSchema.version, 43,
          reason: '批4（notes.wb_at）又升一级；41→42 段必须仍在册');
      expect(DbSchema.migrations.containsKey(41), isTrue,
          reason: '缺这段＝老库升级没有挂载列（新装有、老库没有）');
      final seg = DbSchema.migrations[41]!.join(' ');
      for (final col in [
        'ALTER TABLE note_folders ADD COLUMN source',
        'ALTER TABLE note_folders ADD COLUMN origin_path',
        'ALTER TABLE note_folders ADD COLUMN origin_uri',
        'ALTER TABLE notes ADD COLUMN src_hash',
      ]) {
        expect(seg, contains(col), reason: '$col 不在 41→42 段');
      }
      final folderDdl = DbSchema.createStatements
          .firstWhere((s) => s.contains('CREATE TABLE IF NOT EXISTS note_folders'));
      for (final col in ['source', 'origin_path', 'origin_uri']) {
        expect(folderDdl, contains(col), reason: 'note_folders 基础 DDL 缺 $col');
      }
      final notesDdl = DbSchema.createStatements
          .firstWhere((s) => s.contains('CREATE TABLE notes'));
      expect(notesDdl, contains('src_hash'));
    });

    test('NoteFolder 三列 round-trip＋isMount 判定（手建夹不算挂载）', () async {
      final made = await folders.create('手建夹');
      expect(made.isMount, isFalse);
      final mount = await folders.create('挂载夹',
          source: 'local_dir', originUri: 'content://tree/x', originPath: 'Download/x');
      expect(mount.isMount, isTrue);
      final back = (await folderOf('挂载夹'))!;
      expect(back.source, 'local_dir');
      expect(back.originUri, 'content://tree/x');
      expect(back.originPath, 'Download/x');
      expect(back.isMount, isTrue);
      expect((await folderOf('手建夹'))!.source, '');
    });
  });

  group('② 目录档＝层级还原（工单 §11·产品 2026-10-11 定）', () {
    test('根夹＋子夹各成挂载节点·parent 串对·来源三列落值', () async {
      final r = await impTree();
      expect(r.added, 4, reason: '四篇 md（txt/png/隐藏夹都不收）');
      expect(r.folders, 4, reason: '根＋会议记录＋摘录＋空夹');
      final root = (await folderOf('外来笔记夹'))!;
      expect(root.parentId, isNull);
      expect(root.source, 'local_dir');
      expect(root.originUri, 'content://tree/root');
      final meet = (await folderOf('会议记录'))!;
      expect(meet.parentId, root.id, reason: '子夹必须挂在根夹下（层级还原）');
      expect(meet.source, 'local_dir');
      expect((await folderOf('空夹'))!.isMount, isTrue,
          reason: '空子夹也是磁盘层级的一部分');
    });

    test('笔记按子夹归位·来源标 local_dir·相对路径与 URI 落值', () async {
      await impTree();
      final inMeet = await notes.list(folder: '会议记录');
      expect(inMeet.map((n) => n.title).toSet(), {'协议草稿', '复盘意见'});
      final one = inMeet.first;
      expect(one.source, 'local_dir');
      expect(one.kind, 'md');
      expect(one.originPath, '会议记录/${one.title}.md');
      expect(one.originUri, startsWith('content://doc/'));
      expect(one.srcHash, isNotEmpty);
      expect((await notes.list(folder: '摘录')).single.title, '任务拆分',
          reason: 'markdown 扩展名同族·标题去后缀');
    });

    test('只收 .md/.markdown：txt 与图片与隐藏项一律不进', () async {
      await impTree();
      final all = await notes.list();
      expect(all.map((n) => n.title).toSet(),
          {'外来总览', '协议草稿', '复盘意见', '任务拆分'});
      expect(await folderOf('.obsidian'), isNull, reason: '隐藏夹整支不挂');
    });

    test('二次导入＝全判重跳过·节点不重复建（幂等）', () async {
      final a = await impTree();
      final before = (await notes.list()).length;
      final b = await impTree();
      expect(b.added, 0);
      expect(b.skipped, a.added);
      expect((await notes.list()).length, before, reason: '不堆副本');
      expect(await db.query(DbSchema.tNoteFolders), hasLength(4),
          reason: '同名夹复用＝树不会被同一目录挂出两份');
    });

    test('回收站行不参与判重（E 批红线）：软删一篇后重导＝只补那一篇', () async {
      await impTree();
      final gone = (await notes.list(folder: '摘录')).single;
      await notes.softDelete(gone.id!);
      final r = await impTree();
      expect(r.added, 1);
      expect(r.skipped, 3);
    });

    test('读不出正文＝计入可见「读取失败」汇总，不静默吞', () async {
      final r = await impTree(readText: (uri) async => throw Exception('授权失效'));
      expect(r.unread, 4);
      expect(r.line, contains('读取失败 4 条'));
      expect(await notes.list(), isEmpty);
    });

    test('同名手建夹复用并升挂为挂载（不重复建夹）', () async {
      await folders.create('会议记录');
      await impTree();
      final meet = (await folderOf('会议记录'))!;
      expect(meet.source, 'local_dir', reason: '导入命中同名夹＝升挂，树上才出「本地」标');
      expect(await db.query(DbSchema.tNoteFolders, where: "name = '会议记录'"),
          hasLength(1));
    });
  });

  group('③ 文件档（单/多文件·拍板 E）', () {
    test('落当前目录并给该夹挂 local_file 标', () async {
      await folders.create('灵感');
      final r = await importLocalFiles(
          notes: notes,
          folders: folders,
          docs: const [
            SafDoc(name: '引文摘抄.md', uri: 'content://doc/a', isDir: false),
            SafDoc(name: '译注备忘.md', uri: 'content://doc/b', isDir: false),
          ],
          currentFolder: '灵感',
          readText: (uri) async => '正文 $uri');
      expect(r.added, 2);
      expect((await folderOf('灵感'))!.source, 'local_file');
      expect((await notes.list(folder: '灵感')).every((n) => n.source == 'local_file'),
          isTrue);
    });

    test('未选当前目录＝落未归类（folder 空）·不挂任何标', () async {
      await importLocalFiles(
          notes: notes,
          folders: folders,
          docs: const [SafDoc(name: '速记.md', uri: 'content://doc/z', isDir: false)],
          readText: (uri) async => 'z');
      final n = (await notes.list()).single;
      expect(n.folder, isNull);
      expect(await folderOf('速记'), isNull, reason: '文件档不建独立节点（工单 §1.2）');
    });
  });

  group('④ 挂载移除 N-1c（拍板 H＝保留在库）', () {
    test('移除＝摘挂载行连子夹·库内笔记一行不少·归属名保留', () async {
      await impTree();
      final root = (await folderOf('外来笔记夹'))!;
      final before = (await notes.list()).length;
      final removed =
          await unmountFolder(folders: folders, notes: notes, folder: root);
      expect(removed, 4, reason: '根＋三子夹整体摘掉');
      expect(await db.query(DbSchema.tNoteFolders), isEmpty);
      expect((await notes.list()).length, before, reason: 'H＝笔记保留在库');
      expect((await notes.list(folder: '会议记录')).length, 2,
          reason: '归属名不动＝重导时仍按内容判重不复制');
    });

    test('确认层读数现算：子夹数与保留条数（不写死）', () async {
      await impTree();
      final root = (await folderOf('外来笔记夹'))!;
      expect(await folders.subtreeIds(root.id!), hasLength(4));
      expect(await mountNoteCount(folders, notes, root.id!), 4);
      final quote = (await folderOf('摘录'))!;
      expect(await mountNoteCount(folders, notes, quote.id!), 1);
    });

    test('守卫：固定「系统打开」夹与手建夹都拒绝移除（返回 false 不静默成功）', () async {
      await folders.create(kSystemOpenFolder,
          source: 'local_dir', originUri: 'content://tree/s');
      expect(await folders.unmount((await folderOf(kSystemOpenFolder))!.id!), isFalse);
      await folders.create('手建夹');
      expect(await folders.unmount((await folderOf('手建夹'))!.id!), isFalse);
      expect(await folderOf('手建夹'), isNotNull);
    });

    test('移除后重导＝节点重建·笔记仍判重不复制（可逆性自证）', () async {
      await impTree();
      final before = (await notes.list()).length;
      await unmountFolder(
          folders: folders, notes: notes, folder: (await folderOf('外来笔记夹'))!);
      final r = await impTree();
      expect(r.added, 0);
      expect(r.skipped, 4);
      expect((await notes.list()).length, before);
      expect((await folderOf('外来笔记夹'))!.isMount, isTrue);
    });
  });

  group('⑤ 挂标自动回落与接线守护', () {
    test('local_file 夹：有本地来源笔记时在册，清空后回落（不再画「本地」）', () async {
      await folders.create('灵感');
      await importLocalFiles(
          notes: notes,
          folders: folders,
          docs: const [SafDoc(name: '甲.md', uri: 'content://doc/1', isDir: false)],
          currentFolder: '灵感',
          readText: (uri) async => '甲');
      expect(await notes.foldersHoldingLocalNotes(), contains('灵感'));
      for (final n in await notes.list(folder: '灵感')) {
        await notes.purge(n.id!);
      }
      expect(await notes.foldersHoldingLocalNotes(), isNot(contains('灵感')),
          reason: '回收站/清空后不该继续挂着「本地」标');
    });

    test('树抽屉接线在场（源码守护·代码行原文）：导入入口＋长按分派＋角标', () async {
      final src = File('lib/features/journal/presentation/widgets/note_tree_drawer.dart')
          .readAsStringSync()
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(src, contains("'导入本地 · 目录或文件'"), reason: 'N-1 入口被摘＝功能没有门');
      // 断言必须跟被守护代码的**现行形态**：批2（6c50401）把 T-E 就地化时这处分派从
      // 单行 `if (...) return _unmount(node);` 改成了块形式，测试串没同步＝此后一直红
      // （本批路过抓到）。同款分派另有底部条 `_renameOrUnmount` 一处，故只断在场不数次数。
      expect(src, contains('''
    if (node.folder.isMount) {
      _unmount(node);
      return;
    }'''), reason: '长按分派被摘＝挂载节点再也摘不掉');
      expect(src, contains('MountBadge(source: badgeSource)'),
          reason: '角标被摘＝「本地/导出」标全树消失');
      expect(src, contains('importLocalTree('));
      expect(src, contains('importLocalFiles('));
    });

    test('原生通道四枚在册（Kotlin 侧方法名与 Dart 缝同名）', () async {
      final kt = File(
              'android/app/src/main/kotlin/com/lifeharness/lifeharness/MainActivity.kt')
          .readAsStringSync();
      for (final m in ['pickTree', 'pickFiles', 'listTree', 'readDoc']) {
        expect(kt, contains('"$m"'), reason: '原生分派缺 $m＝导入点了必然抛');
      }
      expect(kt, contains('takePersistableUriPermission'),
          reason: '不取持久化授权＝重启后挂载读不到（工单 §3 红线）');
      expect(kt, isNot(contains('MANAGE_EXTERNAL_STORAGE')));
    });
  });

  group('⑥ 树计数与列表同源（真机反馈 2026-10-11·工单 交棒话术-20261011 §3）', () {
    test('目录里的一篇＋应用内新建的一篇＝树上计 2，列表也必须见 2', () async {
      const root = SafDoc(
          name: 'obsidian',
          uri: 'content://tree/o',
          isDir: true,
          children: [
            SafDoc(name: '未命名', uri: 'content://tree/u', isDir: true, children: [
              SafDoc(name: '外来的一篇.md', uri: 'content://doc/x', isDir: false),
            ]),
          ]);
      await importLocalTree(
          notes: notes,
          folders: folders,
          root: root,
          readText: (uri) async => '目录里本来就有的正文');
      final now = DateTime.now();
      await notes.save(Note(
          title: '我手动加的',
          content: '手输正文',
          folder: '未命名',
          createdAt: now,
          updatedAt: now));
      final counts = await notes.folderCounts();
      expect(counts['未命名'], 2, reason: '导入的那篇必须归到子夹名下');
      expect((await notes.list(folder: '未命名')).length, counts['未命名'],
          reason: '树上计数与列表条数不同源＝产品报的「计 2 只见 1」；'
              '两条查询的过滤条件（archived/deleted_at/folder）必须逐字一致');
      expect(await notes.trash(), isEmpty, reason: '那条不该躺在回收站里');
    });
  });
}
