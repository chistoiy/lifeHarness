/// R5b：MediaHashMigrator 存量图片内容寻址迁移验收。
///
/// 口径：旧命名（非 64hex）→ SHA256 改名 + 六列引用替换；目标已存在 →
/// 删源合并引用；已是 hash 名跳过（幂等）；单文件失败不中断。
library;

import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/logging/app_log.dart';
import 'package:lifeharness/core/media/media_hash_migrator.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tmp;
  late String imgDir;
  late Database db;

  String hashOf(List<int> bytes) => crypto.sha256.convert(bytes).toString();

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('lh_media_mig_');
    imgDir = p.join(tmp.path, 'note_images');
    Directory(imgDir).createSync();
    AppLog.reset();
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute(
        'CREATE TABLE notes (id INTEGER PRIMARY KEY, content TEXT)');
    await db.execute(
        'CREATE TABLE book_quotes (id INTEGER PRIMARY KEY, image_paths TEXT)');
  });
  tearDown(() async {
    AppLog.reset();
    await db.close();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('旧命名图片 → hash 改名 · notes.content 引用整串替换 · 幂等重跑零动作',
      () async {
    final bytes = [1, 2, 3, 4];
    final old = File(p.join(imgDir, '1758000000000.jpg'))
      ..writeAsBytesSync(bytes);
    final oldPath = old.path;
    await db.insert('notes', {'content': '前文 ![]($oldPath) 后文'});

    final stats =
        await MediaHashMigrator(db: db, noteImagesDir: imgDir).migrate();
    expect(stats['renamed'], 1);
    final newPath = p.join(imgDir, '${hashOf(bytes)}.jpg');
    expect(File(newPath).existsSync(), isTrue);
    expect(old.existsSync(), isFalse);
    final row = (await db.query('notes')).first;
    expect(row['content'], contains(newPath));
    expect(row['content'], isNot(contains('1758000000000')));

    // 幂等：第二次扫描 0 个旧命名。
    final again =
        await MediaHashMigrator(db: db, noteImagesDir: imgDir).migrate();
    expect(again['scanned'], 0);
  });

  test('目标 hash 文件已存在（同图重复）→ 删源合并，引用改指目标', () async {
    final bytes = [9, 8, 7];
    final dup = File(p.join(imgDir, '1758111111111.png'))
      ..writeAsBytesSync(bytes);
    final target = File(p.join(imgDir, '${hashOf(bytes)}.png'))
      ..writeAsBytesSync(bytes);
    await db.insert('book_quotes', {'image_paths': '["${dup.path}"]'});

    final stats =
        await MediaHashMigrator(db: db, noteImagesDir: imgDir).migrate();
    expect(stats['merged'], 1);
    expect(dup.existsSync(), isFalse);
    expect(target.existsSync(), isTrue);
    final row = (await db.query('book_quotes')).first;
    expect(row['image_paths'], contains(p.basename(target.path)));
    expect(row['image_paths'], isNot(contains('1758111111111')));
  });

  test('目录不存在 → 全零统计不抛', () async {
    final stats = await MediaHashMigrator(
            db: db, noteImagesDir: p.join(tmp.path, 'nope'))
        .migrate();
    expect(stats['scanned'], 0);
    expect(stats['renamed'], 0);
  });
}
