/// R5c：MediaUsageScanner 本地孤儿图片扫描/清理验收。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/media/media_usage_scanner.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tmp;
  late String imgDir;
  late Database db;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('lh_media_scan_');
    imgDir = p.join(tmp.path, 'note_images');
    Directory(imgDir).createSync();
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('CREATE TABLE notes (id INTEGER PRIMARY KEY, content TEXT)');
  });
  tearDown(() async {
    await db.close();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  MediaUsageScanner scanner() =>
      MediaUsageScanner(db: db, mediaDirs: [imgDir]);

  test('被引用文件不列、未引用入孤儿（basename 命中即算引用）', () async {
    File(p.join(imgDir, 'used.jpg')).writeAsBytesSync([1]);
    File(p.join(imgDir, 'free.jpg')).writeAsBytesSync([2]);
    await db.insert('notes', {'content': '文 ![](some/other/prefix/used.jpg)'});

    final r = await scanner().scan();
    expect(r.totalFiles, 2);
    expect(r.orphans.map((e) => e.name), ['free.jpg']);
    expect(r.orphanBytes, 1);
  });

  test('deleteOrphans：根内删除计数；根外路径一律拒绝（护栏）', () async {
    final a = File(p.join(imgDir, 'a.jpg'))..writeAsBytesSync([1]);
    final outside = File(p.join(tmp.path, 'outside.jpg'))
      ..writeAsBytesSync([1]);
    final n = scanner().deleteOrphans([a.path, outside.path]);
    expect(n, 1);
    expect(a.existsSync(), isFalse);
    expect(outside.existsSync(), isTrue, reason: '媒体根之外绝不删');
  });

  test('健康附件两列也算引用：报告 files 与症状 photos 少登记一列就在档的被删', () async {
    // 批3.5 起症状照片与报告附件落进 note_images/：引用清单不认这两列，
    // 清理扫描会把用户存进去的原件当孤儿删掉（「存了就等于没存」）。
    await db.execute('CREATE TABLE health_report (id INTEGER PRIMARY KEY, files TEXT)');
    await db.execute('CREATE TABLE health_symptom (id INTEGER PRIMARY KEY, photos TEXT)');
    File(p.join(imgDir, 'rp.pdf')).writeAsBytesSync([1]);
    File(p.join(imgDir, 'sym.jpg')).writeAsBytesSync([2]);
    await db.insert('health_report', {'files': '["/data/x/rp.pdf"]'});
    await db.insert('health_symptom', {'photos': '["/data/x/sym.jpg"]'});

    final r = await scanner().scan();
    expect(r.totalFiles, 2);
    expect(r.orphans, isEmpty, reason: 'basename 命中即算引用，路径前缀换了也认');
  });

  test('空目录/无表 → 零孤儿不抛', () async {
    final r = await scanner().scan();
    expect(r.orphans, isEmpty);
    expect(r.totalFiles, 0);
  });
}
