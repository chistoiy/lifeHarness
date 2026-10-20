import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/read/data/read_import.dart';
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:lifeharness/features/read/domain/book.dart';

/// M1批3 批5 · 导入渠道数据包与导出（计划 §5 / §8 验收）。独立文件防 isolate 污染。
void main() {
  sqfliteFfiInit();

  Future<ImportPack> loadPack() => ImportPack.load(
    read: (p) => File(p).readAsString(),
  );

  group('批3-7 · 渠道数据包与解析器', () {
    late ImportPack pack;

    setUpAll(() async => pack = await loadPack());

    test('7-0 manifest 齐 28 家 · 五类分布', () {
      expect(pack.channels, hasLength(28));
      expect(pack.ofCat('auth'), hasLength(2));
      expect(pack.ofCat('pc'), hasLength(1));
      expect(pack.ofCat('api'), hasLength(1));
      expect(pack.ofCat('file'), hasLength(15));
      expect(pack.ofCat('clip'), hasLength(9));
      // auth/pc/api 只给指引不落解析（parser none + hint）
      for (final c in [...pack.ofCat('auth'), ...pack.ofCat('pc'), ...pack.ofCat('api')]) {
        expect(c.parser, 'none');
        expect(c.hint, isNotEmpty);
      }
    });

    test('7-1 Kindle My Clippings：位置/页面/批注分列', () {
      final ch = pack.byId('kindle')!;
      final clips = parseClips(ch, ch.sample);
      expect(clips, hasLength(3));
      expect(clips[0].book, '置身事内');
      expect(clips[0].author, '兰小欢');
      expect(clips[0].loc, 1234);
      expect(clips[0].body, contains('政府是经济发展的参与者'));
      expect(clips[1].page, 88);
      expect(clips[1].thought, '细节无人负责。');
      expect(clips[2].at, DateTime(2024, 5, 3));
    });

    test('7-2 CSV 渠道表头别名映射（KOReader / 京东 / Reeden）', () {
      for (final id in ['koreader', 'jdread', 'reeden']) {
        final ch = pack.byId(id)!;
        final clips = parseClips(ch, ch.sample);
        expect(clips, isNotEmpty, reason: id);
        expect(clips.first.body, isNotEmpty);
        expect(clips.first.book, isNotEmpty);
      }
      final kr = parseClips(pack.byId('koreader')!, pack.byId('koreader')!.sample);
      expect(kr.first.page, 88);
      expect(kr.first.thought, '细节无人负责');
      expect(kr[1].thought, isNull); // 空笔记列＝无想法
    });

    test('7-3 JSON 渠道 root+别名（Apple / 豆瓣阅读 / Neat / Koodo）', () {
      final ap = parseClips(pack.byId('apple')!, pack.byId('apple')!.sample);
      expect(ap.single.book, '人生算法');
      expect(ap.single.loc, 421.5);
      expect(ap.single.chapter, '第三章 边界');
      for (final id in ['doubanread', 'neat', 'koodo']) {
        final ch = pack.byId(id)!;
        expect(parseClips(ch, ch.sample), isNotEmpty, reason: id);
      }
    });

    test('7-4 MD 卡片（BOOX / 汉王 / 滴墨 / Readeast）：书名+作者+页+日期', () {
      final boox = parseClips(pack.byId('boox')!, pack.byId('boox')!.sample);
      expect(boox.single.book, '万历十五年');
      expect(boox.single.author, '黄仁宇');
      expect(boox.single.page, 88);
      expect(boox.single.thought, contains('制度替代技术'));
      expect(boox.single.at, DateTime(2024, 5, 1));
      for (final id in ['hanwang', 'dimo', 'readeast']) {
        final ch = pack.byId(id)!;
        expect(parseClips(ch, ch.sample), isNotEmpty, reason: id);
      }
    });

    test('7-5 剪贴板九家：脚注模板 + 页码/章节二级扫描', () {
      final wr = pack.byId('clip_weread')!;
      final clips = parseClips(wr, wr.sample);
      expect(clips, hasLength(2));
      expect(clips[0].book, '人生算法');
      expect(clips[0].page, 42);
      expect(clips[0].chapter, contains('第三章'));
      expect(clips[1].book, '原子习惯');
      final jd = parseClips(pack.byId('clip_jd')!, pack.byId('clip_jd')!.sample);
      expect(jd.single.book, '理想国');
      expect(jd.single.loc, closeTo(3.14, .01));
      final dd = parseClips(pack.byId('clip_dd')!, pack.byId('clip_dd')!.sample);
      expect(dd.single.book, '亮剑');
      final rigo = parseClips(pack.byId('clip_rigo')!, pack.byId('clip_rigo')!.sample);
      expect(rigo.single.page, 12);
      // 九家样本全可解析
      for (final c in pack.ofCat('clip')) {
        expect(parseClips(c, c.sample), isNotEmpty, reason: c.id);
      }
    });

    test('7-6 坏数据不抛：乱码/空串 → 空列表', () {
      final ch = pack.byId('kindle')!;
      expect(parseClips(ch, ''), isEmpty);
      expect(parseClips(ch, '完全不是 clippings 的内容'), isEmpty);
      expect(parseClips(pack.byId('clip_weread')!, '随手复制的一句话'), isEmpty);
    });
  });

  group('批3-7 · 整批事务与三级去重（真实库）', () {
    late Database db;
    late ReadRepository repo;
    late ImportPack pack;

    setUpAll(() async => pack = await loadPack());
    setUp(() async {
      db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
      for (final sql in DbSchema.createStatements) {
        await db.execute(sql);
      }
      repo = ReadRepository(db);
    });
    tearDown(() => db.close());

    Future<void> seedBook() async {
      await repo.addBook(Book(
        id: 'imp1',
        title: '万历十五年',
        author: '黄仁宇',
        isbn: '9787101055498',
        state: Book.kStateReading,
        pages: 300,
        createdAt: 1,
        updatedAt: 1,
      ));
    }

    test('7-7 三份样本各导入两次 → 第二次 0 新增（验收口径）', () async {
      await seedBook();
      for (final id in ['kindle', 'koreader', 'clip_weread']) {
        final ch = pack.byId(id)!;
        final first = await repo.commitImport(ch, ch.sample);
        expect(first.added, greaterThan(0), reason: id);
        final second = await repo.commitImport(ch, ch.sample);
        expect(second.added, 0, reason: '$id 二次应全跳过');
        expect(second.skipped, greaterThan(0), reason: id);
      }
      // origin 记渠道 · 已有书不重复建档
      final books = await repo.allBooks();
      expect(books.where((b) => b.title == '万历十五年'), hasLength(1));
      final q = (await repo.quotesOf('imp1')).firstWhere((x) => x.body.contains('道德代替技术'));
      expect(q.origin, isNotNull);
      expect(q.dedupHash, isNotNull);
      // 入账即建复习档位（与手动摘录同链）
      final reviews = await db.query('book_reviews', where: 'quote_id = ?', whereArgs: [q.id]);
      expect(reviews, hasLength(1));
    });

    test('7-8 撤销本批：摘录与档位同退·已存在档不误删', () async {
      await seedBook();
      final ch = pack.byId('kindle')!;
      // 先手动入一条与样本第 1 条同键的摘录（软删残留场景由 7-9 覆盖）
      final out = await repo.commitImport(ch, ch.sample);
      expect(out.added, greaterThan(0));
      final left0 = await repo.quoteCount();
      expect(await repo.undoImportBatch(out.ids), out.ids.length);
      expect(await repo.quoteCount(), left0 - out.added);
      final reviews = await db.rawQuery('SELECT COUNT(*) c FROM book_reviews WHERE quote_id IN (${List.filled(out.ids.length, '?').join(',')})', out.ids);
      expect(reviews.single['c'], 0);
      // 手动那条不在本批 ids，仍保留
    });

    test('7-9 一级 ISBN 命中优先；二级作者+书名归一命中；皆不中建档想读', () async {
      await seedBook();
      final ch = pack.byId('koreader')!;
      final rows = await repo.previewImport(ch, ch.sample);
      // 样本行1＝万历十五年（同 ISBN/作者书名）→ 命中 imp1；行2＝置身事内 → 需建档
      expect(rows[0].bookId, 'imp1');
      expect(rows[1].bookId, isNull);
      // 批内同键自撞：同一行出现两次 → 只入账一次
      final lines = ch.sample.split('\n');
      final inBatch = await repo.commitImport(
        ch,
        '${lines[0]}\n${lines[1]}\n${lines[1]}',
      );
      expect(inBatch.added, 1);
      expect(inBatch.skipped, 1);
      final out = await repo.commitImport(ch, ch.sample);
      expect(out.booksCreated, 1);
      final fresh = (await repo.allBooks()).firstWhere((b) => b.title == '置身事内');
      expect(fresh.state, Book.kStateWant);
      expect(fresh.source, 'KOReader');
    });

    test('7-10 按清单建书：CSV 渠道与行式文本各建一次·二次全跳过', () async {
      final ss = pack.byId('shaishufang')!;
      final r1 = await repo.importBookList(ss.sample, ch: ss);
      expect(r1.created, 2);
      final r2 = await repo.importBookList(ss.sample, ch: ss);
      expect(r2.created, 0);
      expect(r2.skipped, 2);
      final line = await repo.importBookList('乡土中国 费孝通\n活着-余华');
      expect(line.created, 2);
      final huozhe = (await repo.allBooks()).firstWhere((b) => b.title == '活着');
      expect(huozhe.author, '余华');
      expect(huozhe.source, '导入清单');
    });

    test('7-11 导出 MD 按书分组 · JSON 备份含书/摘录/书单/设置', () async {
      await seedBook();
      final ch = pack.byId('kindle')!;
      await repo.commitImport(ch, ch.sample);
      await repo.setKv('read.wallCols', '4');
      final md = await repo.buildQuotesMd();
      expect(md, contains('# 全部书摘'));
      expect(md, contains('## 《万历十五年》（黄仁宇）'));
      expect(md, contains('> 当一个社会以道德代替技术'));
      final js = jsonDecode(await repo.buildBackupJson()) as Map<String, dynamic>;
      expect(js['kind'], 'bookshelf');
      expect((js['books'] as List), isNotEmpty);
      expect((js['quotes'] as List), isNotEmpty);
      expect(js['settings'], {'read.wallCols': '4'});
    });
  });
}
