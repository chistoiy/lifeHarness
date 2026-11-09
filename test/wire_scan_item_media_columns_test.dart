/// 媒体清理扫描器 · v53 物品多图/凭证列守护。
///
/// `item_profiles.photos` / `attachments` 是 **JSON 路径数组文本**，与既有
/// `photo` 列同一条判定（basename 出现在列文本里即算引用）。漏登记 ⇒ 在档
/// 多图/发票/说明书会被当孤儿清掉。每条用例正档（在档不被删）与负档
/// （真孤儿仍入列）同例都断。
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
    tmp = Directory.systemTemp.createTempSync('lh_scan_item_v53_');
    imgDir = p.join(tmp.path, 'note_images');
    Directory(imgDir).createSync();
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  });
  tearDown(() async {
    await db.close();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  MediaUsageScanner scanner() =>
      MediaUsageScanner(db: db, mediaDirs: <String>[imgDir]);

  test('photos/attachments JSON 数组算引用；无引用文件仍入孤儿', () async {
    await db.execute('CREATE TABLE item_profiles (id INTEGER PRIMARY KEY, '
        'photo TEXT, photos TEXT, attachments TEXT)');
    for (final n in <String>[
      'multi1.jpg',
      'multi2.jpg',
      'invoice.pdf',
      'free.jpg',
    ]) {
      File(p.join(imgDir, n)).writeAsBytesSync(<int>[1]);
    }
    await db.insert('item_profiles', <String, Object?>{
      'photos': '["/data/user/0/app/files/note_images/multi1.jpg",'
          '"/data/user/0/app/files/note_images/multi2.jpg"]',
      'attachments': '[{"kind":"发票",'
          '"path":"/data/user/0/app/files/note_images/invoice.pdf",'
          '"name":null}]',
    });

    final r = await scanner().scan();
    expect(r.totalFiles, 4);
    expect(r.orphans.map((e) => e.name), <String>['free.jpg'],
        reason: '正档：JSON 两列里的路径算在档；负档：真孤儿仍被列出');
  });

  test('JSON 列按 basename 判定：路径前缀变了仍算引用；未登记文件名仍是孤儿',
      () async {
    await db.execute('CREATE TABLE item_profiles (id INTEGER PRIMARY KEY, '
        'photo TEXT, photos TEXT, attachments TEXT)');
    File(p.join(imgDir, 'keep.jpg')).writeAsBytesSync(<int>[1]);
    File(p.join(imgDir, 'keep2.jpg')).writeAsBytesSync(<int>[1]);
    // 恢复/迁移后路径前缀会变：只留 basename 可认（与既有列同一条判定）。
    await db.insert('item_profiles', <String, Object?>{
      'photos': '["/old/prefix/keep.jpg"]',
      'attachments': '[]',
    });

    final r = await scanner().scan();
    expect(r.orphans.map((e) => e.name), <String>['keep2.jpg'],
        reason: '正档：旧前缀 keep.jpg 仍算引用；负档：keep2.jpg 未被任何列提及');
  });
}
