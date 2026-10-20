import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/backup/backup_service.dart';
import 'package:lifeharness/core/backup/lh_bak.dart' show LhBak;
import 'package:lifeharness/core/database/app_database.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/logging/app_log.dart';
import 'package:lifeharness/core/logging/file_log_sink.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 健康批6b · 本地备份排除接线（需求 176 行／隐私段：「健康数据随本地备份」关闭时
/// 整模块从 `.lhbak` 排除；工单 §3 守护例三条）。
///
/// 四条判定：
/// · 开关关（reader 返回 true）＝ `health_*` 十四表整模块不进包，且 `manifest.excludedTables` 据实登记
///   （恢复报告靠这一行说话，不登记＝用户以为备了其实没备）；
/// · 开关开＝表回来；
/// · **其余模块不受影响**：待办等照常入包（排除面只圈健康）；
/// · `applyHealthExclusion: false`（同步快照那条腿的传法）＝无视本地开关，
///   健康表照常进包——「本地不进包」与「上不上云」是两件事。
///
/// 独立文件（健康侧新增常驻例不进既有备份大文件，防 isolate 污染）。
void main() {
  sqfliteFfiInit();
  // ffi 全局工厂（同 backup_restore_test 开头那两行）：`LhBak.snapshotFactory`
  // 默认吃 sqflite 的全局 databaseFactory，测试里不赋值就是「Bad state: not initialized」。
  databaseFactory = databaseFactoryFfi;
  LhBak.snapshotFactory = databaseFactoryFfi;

  late Directory tmp;
  late String dbPath;
  final opened = <Database>[];

  Future<Database> openApp() async {
    final d = await databaseFactoryFfi.openDatabase(File(dbPath).path);
    opened.add(d);
    return d;
  }

  Future<void> createSchema() async {
    final d = await openApp();
    for (final sql in DbSchema.createStatements) {
      await d.execute(sql);
    }
    await d.insert(DbSchema.tTodos,
        {'title': '健康外的模块', 'created_at': 1, 'updated_at': 1});
    // 用药打卡＝敏感面代表（需求 176 行的那句「含敏感用药记录」）。
    await d.insert('health_drug_log', {
      'profile_id': 1,
      'drug_id': 1,
      'date': '2026-10-08',
      'time': '08:00',
      'state': 'taken',
      'note': '',
      'created_at': 1,
    });
    await d.close();
  }

  BackupService svcWith(bool excluded) => BackupService(
        exportDir: () => '${tmp.path}/backup',
        db: openApp,
        healthExcluded: () => excluded,
      );

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('lh_health_bak_');
    dbPath = '${tmp.path}/app.db';
    await createSchema();
    AppLog.reset();
  });

  tearDown(() async {
    try {
      await AppDatabase.instance.close();
    } catch (_) {}
    await FileLogSink.dispose();
    AppLog.reset();
    for (final d in opened) {
      try {
        await d.close();
      } catch (_) {
        // Windows 偶发句柄未放：不留测试假红（同 backup_restore_test 口径）。
      }
    }
    opened.clear();
    try {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('开关关＝health_* 十四表整模块不进包，excludedTables 据实登记', () async {
    final res = await svcWith(true).exportBackup(withAttachments: false);
    for (final t in DbSchema.healthTables) {
      expect(res.manifest.tables.containsKey(t), isFalse, reason: '$t 应被剔出本地包');
      expect(res.manifest.excludedTables, contains(t));
    }
  });

  test('开关开＝健康表回到包里', () async {
    final res = await svcWith(false).exportBackup(withAttachments: false);
    expect(res.manifest.tables.containsKey('health_drug_log'), isTrue);
    for (final t in DbSchema.healthTables) {
      expect(res.manifest.excludedTables, isNot(contains(t)));
    }
  });

  test('排除面只圈健康：待办等其余模块照常入包', () async {
    final res = await svcWith(true).exportBackup(withAttachments: false);
    expect(res.manifest.tables.containsKey(DbSchema.tTodos), isTrue);
  });

  test('applyHealthExclusion:false（同步快照）＝无视本地开关', () async {
    final res = await svcWith(true).exportBackup(
      withAttachments: false,
      applyHealthExclusion: false,
    );
    expect(res.manifest.tables.containsKey('health_drug_log'), isTrue);
    expect(res.manifest.excludedTables, isNot(contains('health_drug_log')));
  });

  test('读取器抛异常＝照常含进包（本地包缺表是不可逆缺口，宁多存）', () async {
    final svc = BackupService(
      exportDir: () => '${tmp.path}/backup',
      db: openApp,
      healthExcluded: () => throw StateError('组根接线断了'),
    );
    final res = await svc.exportBackup(withAttachments: false);
    expect(res.manifest.tables.containsKey('health_drug_log'), isTrue);
    expect(res.manifest.excludedTables, isNot(contains('health_drug_log')));
  });

  test('未注入读取器（旧调用侧/测试）＝行为不变', () async {
    final res = await BackupService(
      exportDir: () => '${tmp.path}/backup',
      db: openApp,
    ).exportBackup(withAttachments: false);
    expect(res.manifest.tables.containsKey('health_drug_log'), isTrue);
  });
}
