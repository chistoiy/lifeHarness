import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/logging/app_log.dart';
import 'package:lifeharness/core/logging/file_log_sink.dart';

/// 日志管理增强包（V1.42）：手动归档 / 归档清单 / 解包阅读 / 删除归档 /
/// 手动清理落盘 / 内存缓冲清空。
///
/// 纪律同 log_file_sink_test：纯 test() + 系统临时目录同步创建，
/// 不碰 path_provider；显式 flush；tearDown FileLogSink.dispose + AppLog.reset。
void main() {
  late String dir;
  late Directory archDir;

  setUp(() {
    AppLog.reset();
    dir = Directory.systemTemp.createTempSync('lh_log_manage_').path;
    archDir = Directory('$dir${Platform.pathSeparator}archive');
  });

  tearDown(() async {
    await FileLogSink.dispose();
    AppLog.reset();
    try {
      Directory(dir).deleteSync(recursive: true);
    } catch (_) {
      // Windows 句柄偶发未放：残留可忽略。
    }
  });

  /// 落 n 条并刷盘（当天基础文件）。
  Future<void> seedDisk(int n) async {
    for (var i = 0; i < n; i++) {
      FileLogSink.write(LhLogLine(DateTime.now(), LhLevel.error, 'err行$i'));
    }
    await FileLogSink.flush();
  }

  group('archive 归档', () {
    test('未 init / 空目录：archive 返回 null，不动文件系统', () async {
      expect(await FileLogSink.archive(), isNull);
      await FileLogSink.init(dir);
      expect(await FileLogSink.archive(), isNull);
      expect(archDir.existsSync(), isFalse);
    });

    test('归档=打包+删原文件；archiveText 可回读全部成员内容', () async {
      await FileLogSink.init(dir);
      await seedDisk(3);
      expect(await FileLogSink.dayFiles(), isNotEmpty);

      final r = await FileLogSink.archive();
      expect(r, isNotNull);
      expect(r!.files, 1); // 三条都落当天同一基础文件
      expect(r.bytes, greaterThan(0));
      expect(await FileLogSink.dayFiles(), isEmpty, reason: '归档即搬家');
      expect(File('$dir/${r.name}').existsSync(), isFalse);

      final text = await FileLogSink.archiveText(r.name);
      for (var i = 0; i < 3; i++) {
        expect(text, contains('err行$i'));
      }
    });

    test('removeSource=false 保留原文件', () async {
      await FileLogSink.init(dir);
      await seedDisk(1);
      final r = await FileLogSink.archive(removeSource: false);
      expect(r, isNotNull);
      expect(await FileLogSink.dayFiles(), isNotEmpty);
    });

    test('同秒二次归档不互相覆盖（_2 序号防撞）', () async {
      await FileLogSink.init(dir);
      await seedDisk(1);
      final a = await FileLogSink.archive();
      await seedDisk(2);
      final b = await FileLogSink.archive();
      expect(a, isNotNull);
      expect(b, isNotNull);
      expect(b!.name, isNot(a!.name));
      expect(await FileLogSink.archiveText(a.name), contains('err行0'));
      expect(await FileLogSink.archiveText(b.name), contains('err行1'));
    });

    test('归档包超上限裁最旧（名内时间戳排序）', () async {
      await FileLogSink.init(dir);
      archDir.createSync(recursive: true);
      // 预置 10 个历史档（0900~0909），再落盘归档一次 → 最旧 0900 出局。
      for (var i = 0; i < FileLogSink.maxArchives; i++) {
        File('${archDir.path}/lh-arch-20260901-09000$i.zip')
            .writeAsBytesSync([0x50, 0x4b, 0x05, 0x06, ...List.filled(18, 0)]);
      }
      await seedDisk(1);
      final r = await FileLogSink.archive();
      final list = await FileLogSink.archives();
      expect(list, hasLength(FileLogSink.maxArchives));
      expect(list.map((e) => e.name), contains(r!.name));
      expect(list.map((e) => e.name),
          isNot(contains('lh-arch-20260901-090000.zip')));
    });

    test('archives() 新→旧 + created 从名复原不依赖 mtime', () async {
      await FileLogSink.init(dir);
      archDir.createSync(recursive: true);
      File('${archDir.path}/lh-arch-20260901-083000.zip').createSync();
      File('${archDir.path}/lh-arch-20260902-120000.zip').createSync();
      File('${archDir.path}/note.txt').createSync(); // 非档名不入列
      final list = await FileLogSink.archives();
      expect(list.map((e) => e.name),
          ['lh-arch-20260902-120000.zip', 'lh-arch-20260901-083000.zip']);
      expect(list.last.created, DateTime(2026, 9, 1, 8, 30, 0));
    });

    test('deleteArchive 只认档名（非法名静默拒，防路径注入）', () async {
      await FileLogSink.init(dir);
      archDir.createSync(recursive: true);
      File('${archDir.path}/lh-arch-20260901-083000.zip').createSync();
      await FileLogSink.deleteArchive('../note.txt');
      await FileLogSink.deleteArchive('lh-arch-20260901-083000.zip');
      expect(await FileLogSink.archives(), isEmpty);
    });
  });

  group('purgeDisk / clearMemory 清理', () {
    test('purgeDisk 删全部落盘分卷并清尺寸缓存，归档包不受影响', () async {
      await FileLogSink.init(dir);
      archDir.createSync(recursive: true);
      File('${archDir.path}/lh-arch-20260901-083000.zip').createSync();
      await seedDisk(1);
      // 顶满分卷：再来一大批确保多文件形态。
      for (var i = 0; i < 20; i++) {
        FileLogSink.write(LhLogLine(DateTime.now(), LhLevel.warn, 'w$i'));
      }
      await FileLogSink.flush();

      final n = await FileLogSink.purgeDisk();
      expect(n, greaterThanOrEqualTo(1));
      expect(await FileLogSink.dayFiles(), isEmpty);
      expect(await FileLogSink.archives(), hasLength(1),
          reason: '清理毁日志，不毁归档');
      // 清理后继续写入：新基础文件重建成功（缓存已清）。
      await seedDisk(1);
      expect(await FileLogSink.dayFiles(), isNotEmpty);
    });

    test('AppLog.clearMemory 清缓冲并通知版本（不动落盘挂点）', () async {
      await FileLogSink.init(dir);
      AppLog.add('一条');
      expect(AppLog.lines, hasLength(1));
      final v0 = AppLog.version.value;
      AppLog.clearMemory();
      expect(AppLog.lines, isEmpty);
      expect(AppLog.allText(), isEmpty);
      expect(AppLog.version.value, greaterThan(v0));
      // 挂点仍在：新行照常落盘。
      AppLog.add('清理后的新行');
      await FileLogSink.flush();
      expect(await FileLogSink.dayFiles(), isNotEmpty);
    });
  });
}
