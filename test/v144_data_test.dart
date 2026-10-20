import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/read/data/isbn_enrich.dart';
import 'package:lifeharness/features/read/data/read_repository.dart';
import 'package:lifeharness/features/read/domain/book.dart';

/// V1.44 批1（数据层）：详情页扩展字段、搜索页 window.__DATA__ 列表解析、
/// searchList 联想→搜索页链、Book word_count/binding 落库（DB v24）。
void main() {
  sqfliteFfiInit();

  final desktop = File('test/fixtures/douban_isbn_desktop.html')
      .readAsStringSync();
  final searchPage = File('test/fixtures/douban_search.html')
      .readAsStringSync();

  setUp(() => DoubanGuard.reset());

  group('详情页扩展字段（真页 fixture 钉格式）', () {
    test('万历十五年：装帧/定价/丛书/ISBN/简介照填，无译者的条目留 null', () {
      final meta = IsbnEnrich.parse(desktop)!;
      expect(meta.title, '万历十五年');
      expect(meta.binding, '平装');
      expect(meta.price, '18.00元');
      expect(meta.priceValue, 18.0);
      expect(meta.series, '黄仁宇作品系列');
      expect(meta.isbn, '9787108009821');
      expect(meta.intro, isNotNull);
      expect(meta.intro!.contains('万历十五年'), isTrue);
      expect(meta.translator, isNull); // 该条目本无译者
      expect(meta.wordCount, isNull); // 该条目本无字数
    });
  });

  group('搜索页 window.__DATA__ 解析', () {
    test('三体真页 fixture：出多行且 abstract 四段拆分正确', () {
      final rows = IsbnEnrich.parseSearchRows(searchPage);
      expect(rows.length, greaterThanOrEqualTo(3));
      final r = rows.firstWhere((e) => e.subjectId == '3066477');
      expect(r.title, contains('三体'));
      expect(r.author, '刘慈欣');
      expect(r.publisher, '重庆出版社');
      expect(r.pubDate, '2008-5');
      expect(r.price, '32.00');
      expect(r.rating, 9.3);
      expect(r.coverUrl, startsWith('https://img'));
    });
    test('非搜索页 HTML → 空列表不抛', () {
      expect(IsbnEnrich.parseSearchRows('<html>none</html>'), isEmpty);
      // 截断的坏 JSON（大页断连形态）也不炸。
      expect(
        IsbnEnrich.parseSearchRows('window.__DATA__ = {"items": [{"id":'),
        isEmpty,
      );
    });
  });

  group('searchList 联想→搜索页兜底链', () {
    test('suggest 有行：直接映射（不请求搜索页）', () async {
      final hits = <String>[];
      final rows = await IsbnEnrich.searchList(
        '三体',
        fetch: (u) async {
          hits.add(u.toString());
          if (u.path.contains('subject_suggest')) {
            return jsonEncode([
              {
                'id': '2567698',
                'title': '三体',
                'author_name': '[美] 刘慈欣',
                'year': '2008',
                'pic': 'https://img3.doubanio.com/x.jpg',
              },
            ]);
          }
          return null;
        },
      );
      expect(rows.length, 1);
      expect(rows.first.author, '刘慈欣'); // 国别前缀剥离
      expect(rows.first.coverUrl, isNotNull);
      expect(hits.length, 1, reason: 'suggest 命中就不该再打搜索页');
    });
    test('suggest 恒空 → 搜索页 fixture 出列表', () async {
      final rows = await IsbnEnrich.searchList(
        '三体',
        fetch: (u) async =>
            u.path.contains('subject_suggest') ? '[]' : searchPage,
      );
      expect(rows.length, greaterThanOrEqualTo(3));
      expect(rows.any((e) => e.subjectId == '2567698'), isTrue);
    });
    test('搜索页命中拦截页 → 熔断触发并回空', () async {
      final rows = await IsbnEnrich.searchList(
        '三体',
        fetch: (u) async => u.path.contains('subject_suggest')
            ? '[]'
            : '<html><title>禁止访问</title></html>',
      );
      expect(rows, isEmpty);
      expect(DoubanGuard.active(), isTrue);
    });
    test('熔断冷却期：一个请求都不发', () async {
      DoubanGuard.trip();
      var called = 0;
      final rows = await IsbnEnrich.searchList(
        '三体',
        fetch: (u) async {
          called++;
          return null;
        },
      );
      expect(rows, isEmpty);
      expect(called, 0);
    });
  });

  group('DB v24 · Book word_count/binding', () {
    late Database db;
    late ReadRepository repo;
    setUp(() async {
      db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
      for (final sql in DbSchema.createStatements) {
        await db.execute(sql);
      }
      repo = ReadRepository(db);
    });
    tearDown(() => db.close());

    test('新库 DDL 已含两列，addBook→bookById 往返', () async {
      await repo.addBook(
        Book(
          id: 'w1',
          title: '三体',
          state: Book.kStateWant,
          wordCount: 217000,
          binding: '平装',
          createdAt: 1,
          updatedAt: 1,
        ),
      );
      final b = (await repo.bookById('w1'))!;
      expect(b.wordCount, 217000);
      expect(b.binding, '平装');
      // 备份导出走 toRow，新列自动随行。
      expect(jsonEncode(b.toRow()), contains('word_count'));
    });

    test('老库（v23 形态 books 表）跑 migrations[23] 补列成功', () async {
      // 独立文件库：ffi noIsolate 下 :memory: 共享连接，会撞 setUp 的 books 表。
      final f = File(
        '${Directory.systemTemp.path}\\v144_mig_${DateTime.now().microsecondsSinceEpoch}.db',
      );
      final db2 = await databaseFactoryFfiNoIsolate.openDatabase(f.path);
      // v23 时的 books 表：无 word_count/binding 两列。
      await db2.execute('''
        CREATE TABLE books (
          id TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          author TEXT NOT NULL DEFAULT '佚名',
          state TEXT NOT NULL DEFAULT '想读',
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
      for (final sql in DbSchema.migrations[23]!) {
        await db2.execute(sql);
      }
      final cols = await db2.rawQuery('PRAGMA table_info(books)');
      final names = cols.map((c) => c['name']).toSet();
      expect(names, containsAll(['word_count', 'binding', 'fee_date']));
      await db2.close();
      await f.delete();
    });
  });
}
