import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/journal/data/note_dao.dart';
import 'package:lifeharness/features/journal/data/note_folder_dao.dart';
import 'package:lifeharness/features/journal/domain/note.dart';
import 'package:lifeharness/features/journal/presentation/note_export.dart';
import 'package:lifeharness/features/journal/presentation/note_mount_write.dart';
import 'package:lifeharness/core/platform/saf_tree.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// V1.64 批3 · N-2「导出为本地目录」服务件（工单 交棒话术-20261004 §15 · 面板＝本批唯一规格依据）。
// 平台通道全走注入缝（ensureDir/create）＝用例不碰真 SAF（批2 `saf_tree` 同定式）；
// 库用真 in-memory sqlite（「门禁必须真库」口径），Delta→md 逐形态现钉。

/// 假 SAF：只记账不写盘。`dup` 模拟原生「同名追加 (2)」；`failFor`＝指定文件返回码；
/// `missingAsset`＝这些本地附件路径「读不到」（＝拷失败计数）。
class FakeSaf {
  FakeSaf({this.dirCode = 'ok', this.failFor = const {}, this.missingAsset = const {}});

  final String dirCode;
  final Map<String, String> failFor;
  final Set<String> missingAsset;
  final List<String> dirs = [];
  final List<Map<String, String>> files = [];

  Future<MountWriteResult> ensureDir(
      {required String tree, required String relPath, required String name}) async {
    if (dirCode != 'ok') return MountWriteResult(code: dirCode);
    dirs.add(relPath.isEmpty ? name : '$relPath/$name');
    return MountWriteResult(code: 'ok', name: name, uri: 'content://t/$name');
  }

  Future<MountWriteResult> create(
          {required String tree,
          required String relPath,
          required String name,
          required String text,
          String mime = 'text/markdown',
          String srcPath = ''}) =>
      Future(() {
        final code = failFor[name];
        if (code != null) return MountWriteResult(code: code);
        if (srcPath.isNotEmpty && missingAsset.contains(srcPath)) {
          return const MountWriteResult(code: 'error');
        }
        var actual = name;
        var n = 1;
        while (files.any((f) => f['relPath'] == relPath && f['name'] == actual)) {
          n++;
          final dot = name.lastIndexOf('.');
          actual = dot > 0
              ? '${name.substring(0, dot)}($n)${name.substring(dot)}'
              : '$name($n)';
        }
        files.add({
          'relPath': relPath,
          'name': actual,
          'text': text,
          'mime': mime,
          'srcPath': srcPath,
        });
        return MountWriteResult(
            code: 'ok',
            name: actual,
            uri: 'content://t/$actual',
            localPath: '$relPath/$actual');
      });
}

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

  Note make(String title, String content,
          {String kind = 'plain', String? folder}) =>
      Note(
          title: title,
          content: content,
          kind: kind,
          folder: folder,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now());

  Note richNote(String delta) => Note(
      title: 't',
      content: delta,
      kind: 'rich',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now());

  Future<NoteExportReport> run(
      {required String scope,
      required FakeSaf saf,
      String treePath = 'Download/导出口'}) {
    return exportNotesToTree(
        notes: notes,
        folders: folders,
        treeUri: 'content://tree/1',
        treePath: treePath,
        scope: scope,
        ensureDir: saf.ensureDir,
        create: saf.create);
  }

  group('① Quill Delta → Markdown（无损·图片不丢）', () {
    test('标题/粗斜删/行内码/链接/列表/待办/引用/代码块逐项转 md', () {
      final delta = jsonEncode([
        {'insert': '一句', 'attributes': {'bold': true}},
        {'insert': '加', 'attributes': {'italic': true}},
        {'insert': '斜', 'attributes': {'strike': true}},
        {'insert': '码', 'attributes': {'code': true}},
        {'insert': '链', 'attributes': {'link': 'https://a.b'}},
        {'insert': '\n', 'attributes': {'heading': 2}},
        {'insert': '无序\n', 'attributes': {'list': 'bullet'}},
        {'insert': '没做\n', 'attributes': {'list': 'unchecked'}},
        {'insert': '做了\n', 'attributes': {'list': 'checked'}},
        {'insert': '引用行\n', 'attributes': {'blockquote': true}},
        {'insert': 'print(1)\n', 'attributes': {'code-block': true}},
        {'insert': '正文\n'},
      ]);
      final md = noteToMarkdown(richNote(delta), const {});
      expect(md, contains('## **一句***加*~~斜~~`码`[链](https://a.b)'),
          reason: '行级属性取行末换行符那份（Quill 模型），内联按 bold/italic/strike/code/link 包');
      expect(md, contains('- 无序'));
      expect(md, contains('- [ ] 没做'));
      expect(md, contains('- [x] 做了'));
      expect(md, contains('> 引用行'));
      expect(md, contains('```\nprint(1)\n```'));
      expect(md, contains('正文'));
    });

    test('富文本图片落 ![](\\_assets/名)（退化成「图片」二字＝丢附件＝刀①）', () {
      final delta = jsonEncode([
        {'insert': '看图\n'},
        {
          'insert': {'image': '/docs/note_images/ab12.png'}
        },
        {'insert': '\n'},
      ]);
      final md = noteToMarkdown(
          richNote(delta), const {'/docs/note_images/ab12.png': 'ab12.png'});
      expect(md, contains('![图片](_assets/ab12.png)'),
          reason: 'md 内必须引用相对路径（需求 N-2「md 内引用相对路径」）');
      expect(md, isNot(contains('/docs/note_images')), reason: '绝对路径不许漏进导出包');
    });

    test('纯文本里的本地图片语法换相对名·外链原样保留', () {
      final md = noteToMarkdown(
          make('t', '![图](/x/y/z.jpg) 与 ![网](https://a.b/c.png)'),
          const {'/x/y/z.jpg': 'z.jpg'});
      expect(md, '![图](_assets/z.jpg) 与 ![网](https://a.b/c.png)');
    });

    test('脏稿（kind=rich 但正文非 JSON）容错回退纯文本，不抛', () {
      expect(noteToMarkdown(make('t', '手输的一段', kind: 'rich'), const {}),
          contains('手输的一段'));
    });
  });

  group('② 附件规划与拷贝', () {
    test('一篇多图各拷一次·两篇同图只拷一次·mime 按扩展名', () async {
      await notes.save(make('甲', '![a](/i/one.png)\n![b](/i/two.jpg)', folder: '灵感'));
      await notes.save(make('乙', '![again](/i/one.png)', folder: '灵感'));
      final saf = FakeSaf();
      final r = await run(scope: '', saf: saf);
      expect(r.exported, 2);
      expect(r.assets, 2, reason: 'one.png 与 two.jpg 各一枚，重复引用不重复拷');
      final copied =
          saf.files.where((f) => f['relPath'] == '笔记导出/_assets').toList();
      expect(copied.map((f) => f['name']).toSet(), {'one.png', 'two.jpg'});
      expect(copied.firstWhere((f) => f['name'] == 'two.jpg')['mime'], 'image/jpeg',
          reason: '附件必须给对 mime＝写成 text/markdown 会把图毁成文本');
      expect(saf.dirs, containsAll(['笔记导出', '笔记导出/_assets']),
          reason: '目录必须先建出来（原生 createDocument 撞同名会自己加「 (2)」＝脏盘）');
    });

    test('不同目录同名附件＝追加序号，绝不互相覆盖', () {
      final map = planAssetNames(['/a/x.png', '/b/x.png']);
      expect(map.values.toSet().length, 2);
      expect(map['/b/x.png'], isNot(map['/a/x.png']));
    });

    test('读不到的本地附件＝计入「没拷成」，正文导出照完成', () async {
      await notes.save(make('甲', '![a](/i/gone.png)'));
      final r = await run(scope: '', saf: FakeSaf(missingAsset: {'/i/gone.png'}));
      expect(r.exported, 1, reason: '附件失败不许吞掉正文导出');
      expect(r.failedAssets, 1);
      expect(r.line, contains('1 张附件没拷成'), reason: '失败必须进汇总句');
    });
  });

  group('③ 挂载节点与只读守卫', () {
    test('导出后库里落「笔记导出」＝source=export·origin 现算', () async {
      await notes.save(make('甲', '正文'));
      await run(scope: '', saf: FakeSaf());
      final f = await folders.byName(kNoteExportRoot);
      expect(f, isNotNull);
      expect(f!.source, 'export',
          reason: '摘掉 source＝导出夹变成手建夹＝「导出」标全树消失（刀②）');
      expect(f.originUri, 'content://tree/1');
      expect(f.originPath, 'Download/导出口/笔记导出');
      expect(f.isMount, isTrue, reason: '必须能走既有的「移除挂载」通道');
    });

    test('导出夹＝只读挂载，库内笔记保存不回写它（红线反证·刀③）', () async {
      await folders.create(kNoteExportRoot,
          source: 'export',
          originUri: 'content://tree/1',
          originPath: '笔记导出');
      await notes.save(make('甲', '正文', folder: kNoteExportRoot));
      final saved = (await notes.list()).first;
      expect(await noteWritesBackToMount(saved: saved, folders: folders), isFalse,
          reason: '把 export 放宽成回写＝导出包被后续编辑改写，违 N-2「只读挂载，不回写」');
    });

    test('再导一次＝同一挂载节点刷新锚点，不重复建夹', () async {
      await notes.save(make('甲', '正文'));
      await run(scope: '', saf: FakeSaf(), treePath: 'Download/甲口');
      await run(scope: '', saf: FakeSaf(), treePath: 'Download/乙口');
      expect((await folders.list()).where((f) => f.name == kNoteExportRoot).length, 1);
      expect((await folders.byName(kNoteExportRoot))!.originPath,
          'Download/乙口/笔记导出');
    });

    test('目标目录建不出来＝整批不写盘并出实码，树上不挂假成功', () async {
      await notes.save(make('甲', '正文'));
      final r = await run(scope: '', saf: FakeSaf(dirCode: 'no_perm'));
      expect(r.errorCode, 'no_perm');
      expect(r.line, contains('只有读取权限'));
      final r2 = await run(scope: '', saf: FakeSaf(dirCode: 'error'));
      expect(r2.errorCode, 'error');
      expect(await folders.byName(kNoteExportRoot), isNull,
          reason: '一个文件都没落成就不许在树上挂出「笔记导出」＝假成功');
    });
  });

  group('④ 范围·软删红线·文件名词法', () {
    test('「当前目录」只导所选夹本身（原型 nxDo 口径）；空范围＝全部笔记', () async {
      await notes.save(make('甲', 'a', folder: '灵感'));
      await notes.save(make('乙', 'b', folder: '灵感'));
      await notes.save(make('丙', 'c', folder: '其他'));
      expect((await run(scope: '灵感', saf: FakeSaf())).exported, 2);
      expect((await run(scope: '', saf: FakeSaf())).exported, 3);
    });

    test('回收站里的笔记不参与导出（E 批红线）', () async {
      final n = await notes.save(make('删我', 'x'));
      await notes.save(make('留我', 'y'));
      await notes.softDelete(n.id!);
      expect((await run(scope: '', saf: FakeSaf())).exported, 1,
          reason: 'deleted_at 行混进导出包＝把回收站内容交给用户');
    });

    test('同名标题由原生追加 (2)·非法字符换横杠·空标题落「未命名笔记」', () async {
      await notes.save(make('同名', 'a'));
      await notes.save(make('同名', 'b'));
      await notes.save(make('a/b:c', 'c'));
      await notes.save(make('', 'd'));
      final saf = FakeSaf();
      final r = await run(scope: '', saf: saf);
      expect(r.exported, 4);
      expect(saf.files.map((f) => f['name']),
          containsAll(['同名.md', '同名(2).md', 'a-b-c.md', '未命名笔记.md']));
    });

    test('写不进的那几篇进汇总句，不静默少导', () async {
      await notes.save(make('甲', 'a'));
      await notes.save(make('乙', 'b'));
      final r = await run(scope: '', saf: FakeSaf(failFor: {'乙.md': 'error'}));
      expect(r.exported, 1);
      expect(r.failedNotes, 1);
      expect(r.line, contains('1 篇没写成'));
    });
  });

  group('⑤ 通道接线在册（源码守护·代码行原文）', () {
    test('Dart 两枚缝与 Kotlin 侧方法名同名，且批3 扩口齐（mime/srcPath/建目录）', () {
      final dart = File('lib/core/platform/saf_tree.dart').readAsStringSync();
      final kt = File(
              'android/app/src/main/kotlin/com/lifeharness/lifeharness/MainActivity.kt')
          .readAsStringSync();
      for (final m in ['createInTree', 'ensureDirInTree']) {
        expect(dart, contains("'$m'"), reason: 'Dart 缝缺 $m＝导出点了必抛 MissingPlugin');
        expect(kt, contains('"$m"'), reason: '原生分派缺 $m');
      }
      expect(kt, contains('ensureChildDir'),
          reason: '没有「建目录（或复用）」的原生口＝_assets/ 永远写不进去');
      expect(kt, contains('MIME_TYPE_DIR'));
      expect(kt, contains('input.copyTo(out)'), reason: '附件必须走字节流，写字符串必坏图');
      expect(dart, contains("String mime = 'text/markdown'"),
          reason: '缺省 mime 必须还是 md＝批2 写回行为不许变');
    });

    test('导出件不动壳层，且落 export 标', () {
      final src =
          File('lib/features/journal/presentation/note_export.dart').readAsStringSync();
      expect(src.contains('core/router'), isFalse,
          reason: '批3 只住模块内（叠层与壳路由都不碰）');
      expect(src, contains("source: 'export'"));
      expect(src, contains('kNoteExportRoot'));
    });
  });
}
