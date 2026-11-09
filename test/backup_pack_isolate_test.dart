/// 轮6（2026-10-04）备份导出崩溃根治的常驻用例：
/// ① `LhBak.create` 打包阶段在**真 Isolate.run** 下产出合法包（跨 isolate
///    只传 plain 数据的契约测试——默认 packRunner 内联是测试路径，本文件
///    显式切到生产注入的执行器，防「生产路径从没被测过」的盲区）；
/// ② `lh/saf` 通道 Dart 侧契约：saveAs 入参（srcPath/fileName=basename）、
///    成功=显示名、取消=null、失败抛 PlatformException（UI 层据此兜底可见）。
library;

import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/backup/lh_bak.dart';
import 'package:lifeharness/core/platform/saf.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Database> _miniDb() async {
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await db.execute('CREATE TABLE t1 (id INTEGER PRIMARY KEY, v TEXT)');
  await db.insert('t1', {'id': 1, 'v': 'a'});
  await db.insert('t1', {'id': 2, 'v': 'b'});
  await db.insert('t1', {'id': 3, 'v': 'c'});
  return db;
}

Future<R> _inline<R>(Future<R> Function() task) => task();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory work;
  late Database db;
  late Directory attachDir;
  late Directory outDir;

  setUp(() async {
    LhBak.snapshotFactory = databaseFactoryFfi;
    work = await Directory.systemTemp.createTemp('r6_pack_');
    db = await _miniDb();
    attachDir = Directory('${work.path}/note_images')..createSync();
    File('${attachDir.path}/pic.png').writeAsBytesSync(List.filled(2048, 0x5A));
    outDir = Directory('${work.path}/backup')..createSync();
  });

  tearDown(() async {
    await db.close();
    LhBak.packRunner = _inline;
    try {
      work.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('打包阶段真隔离（生产 packRunner=Isolate.run 路径）', () {
    test('明文包：Isolate.run 下 create→verify 全链路成立', () async {
      LhBak.packRunner = Isolate.run;
      final res = await LhBak.create(
        db: db,
        outDirPath: outDir.path,
        attachDirs: [attachDir.path],
      );
      expect(res.file.existsSync(), isTrue);
      expect(res.file.lengthSync(), greaterThan(0));
      expect(res.manifest.tables['t1']?.rows, 3);
      expect(res.manifest.members, contains('attachments/note_images/pic.png'));
      // 包必须能被校验（zip/manifest/逐表校验和全对齐＝跨 isolate 无损）。
      final m = await LhBak.verify(res.file.path);
      expect(m.tables['t1'], res.manifest.tables['t1']);
    });

    test('口令加密包：PBKDF2+AES-GCM 在后台 isolate 同样成立', () async {
      LhBak.packRunner = Isolate.run;
      final res = await LhBak.create(
        db: db,
        outDirPath: outDir.path,
        attachDirs: [attachDir.path],
        passphrase: 'r6-pass',
      );
      expect(res.manifest.encrypted, isTrue);
      expect(res.manifest.members, contains('db.sqlite.enc'));
      final m = await LhBak.verify(res.file.path, passphrase: 'r6-pass');
      expect(m.tables['t1']?.rows, 3);
    });
  });

  group('lh/saf 通道 Dart 侧契约', () {
    Future<void> mock(
        Future<Object?>? Function(MethodCall call) handler) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(safChannel, handler);
    }

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(safChannel, null);
    });

    test('saveAs 传 srcPath+basename，成功回显示名', () async {
      MethodCall? seen;
      await mock((call) async {
        seen = call;
        return 'picked_name.lhbak';
      });
      final saved = await safSaveAs('/data/user/0/app/docs/backup/x.lhbak');
      expect(saved, 'picked_name.lhbak');
      expect(seen?.method, 'saveAs');
      expect(seen?.arguments['srcPath'],
          '/data/user/0/app/docs/backup/x.lhbak');
      expect(seen?.arguments['fileName'], 'x.lhbak');
    });

    test('用户取消 = null；provider 失败抛 PlatformException（UI 兜底可见）',
        () async {
      await mock((call) async => null);
      expect(await safSaveAs('/tmp/a.lhbak'), isNull);
      await mock((call) async {
        throw PlatformException(code: 'save_failed', message: '无输出流');
      });
      await expectLater(
          safSaveAs('/tmp/a.lhbak'), throwsA(isA<PlatformException>()));
    });
  });
}
