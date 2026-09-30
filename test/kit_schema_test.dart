import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/kits/data/kit_repository.dart';
import 'package:lifeharness/features/kits/domain/kit_models.dart';

/// V1.47 小工具批0 · DB v27→v28 四表建表与仓储读写。
/// 独立文件防 isolate 污染（既有踩坑）。
void main() {
  sqfliteFfiInit();

  late Database db;
  late KitRepository repo;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.migrations[27]!) {
      await db.execute(sql);
    }
    repo = KitRepository(db);
  });

  tearDown(() => db.close());

  Future<List<String>> tables() async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'kit_%'",
    );
    return rows.map((r) => r['name'] as String).toList()..sort();
  }

  group('1 · v28 建表', () {
    test('migrations[27] 建齐四表', () async {
      expect(await tables(), [
        DbSchema.tKitLayout,
        DbSchema.tKitPlugin,
        DbSchema.tKitToolData,
        DbSchema.tKitUsage,
      ]);
    });

    test('重复执行迁移幂等（IF NOT EXISTS）', () async {
      for (final sql in DbSchema.migrations[27]!) {
        await db.execute(sql);
      }
      expect((await tables()).length, 4);
    });

    test('kit 四表建表到位 · 版本号只守下限（后续批次升版不该撞红本用例）', () {
      // 版本随各模块批次一路上调（kits 自 v28 起建四表），钉死等值会让并行会话
      // 每次升版都把 kits 门禁染红，这里只断言「不低于建表版本」。
      expect(DbSchema.version, greaterThanOrEqualTo(28));
      expect(DbSchema.kitTables, hasLength(4));
      expect(DbSchema.createStatements.join(), contains('kit_usage'));
    });
  });

  group('2 · 足迹流水', () {
    test('logUse 落库并按时间升序读回', () async {
      await repo.logUse('pick');
      await repo.logUse('datec');
      await repo.logUse('pick', kind: kKitKindPlugin);
      final log = await repo.usage();
      expect(log, hasLength(3));
      expect(log.map((e) => e.tool).toList(), ['pick', 'datec', 'pick']);
      expect(log.last.kind, kKitKindPlugin);
    });

    test('sinceMs 窗口截断', () async {
      final t0 = DateTime(2026, 1, 1).millisecondsSinceEpoch;
      await db.insert(DbSchema.tKitUsage, {'tool': 'old', 'ts': t0, 'kind': 'builtin'});
      await db.insert(DbSchema.tKitUsage, {'tool': 'new', 'ts': t0 + 86400000, 'kind': 'builtin'});
      final log = await repo.usage(sinceMs: t0 + 1);
      expect(log.map((e) => e.tool), ['new']);
    });

    test('clearUsage 只清流水，不动收藏与编排', () async {
      await repo.logUse('b64');
      await repo.setFavorites(['b64']);
      await repo.clearUsage();
      expect(await repo.usage(), isEmpty);
      expect(await repo.favorites(), ['b64']);
    });
  });

  group('3 · 收藏与编排', () {
    test('默认值：无收藏、无隐藏、未编排、数据位回落到默认四枚', () async {
      expect(await repo.favorites(), isEmpty);
      expect(await repo.hidden(), isEmpty);
      expect(await repo.order(), isNull);
      expect(await repo.heroSlots(), kKitHeroDefault);
    });

    test('收藏/隐藏/编排写入后读回一致', () async {
      await repo.setFavorites(['ruler', 'tele']);
      await repo.setHidden(['dist']);
      await repo.setOrder(['tele', 'ruler']);
      expect(await repo.favorites(), ['ruler', 'tele']);
      expect(await repo.hidden(), ['dist']);
      expect(await repo.order(), ['tele', 'ruler']);
    });

    test('编排置空=删除该行（回到默认序）', () async {
      await repo.setOrder(['b64']);
      await repo.setOrder(null);
      expect(await repo.order(), isNull);
    });

    test('数据位存枚举名，脏值回落默认而不抛', () async {
      await repo.setHeroSlots([KitMetric.today, KitMetric.recent, KitMetric.size, KitMetric.fav]);
      expect(await repo.heroSlots(),
          [KitMetric.today, KitMetric.recent, KitMetric.size, KitMetric.fav]);
      await db.insert(
        DbSchema.tKitLayout,
        {'key': 'hero', 'value': '["nope",1]', 'updated_at': 1},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      expect(await repo.heroSlots(), kKitHeroDefault);
    });

    test('编排值 JSON 损坏 → 按缺失回落，不炸界面', () async {
      await db.insert(DbSchema.tKitLayout,
          {'key': 'fav', 'value': '{坏数据', 'updated_at': 1});
      expect(await repo.favorites(), isEmpty);
    });
  });

  group('4 · 工具私有数据', () {
    test('无记录返回空 map；写入后读回同结构', () async {
      expect(await repo.toolData('wheel'), isEmpty);
      await repo.setToolData('wheel', {
        'sets': [
          {'name': '晚餐', 'items': ['面', '饭']}
        ],
        'active': 0,
      });
      final back = await repo.toolData('wheel');
      expect(back['active'], 0);
      expect(((back['sets'] as List).first as Map)['name'], '晚餐');
    });

    test('同工具二次写入覆盖（主键 tool 冲突替换）', () async {
      await repo.setToolData('ruler', {'cal': 0.995});
      await repo.setToolData('ruler', {'cal': 1.02});
      expect((await repo.toolData('ruler'))['cal'], closeTo(1.02, 1e-9));
      final rows = await db.rawQuery('SELECT COUNT(*) c FROM ${DbSchema.tKitToolData}');
      expect(rows.first['c'], 1);
    });

    test('损坏 JSON 回落空 map', () async {
      await db.insert(DbSchema.tKitToolData,
          {'tool': 'b64', 'data': '[1,2', 'updated_at': 1});
      expect(await repo.toolData('b64'), isEmpty);
    });
  });

  group('5 · 插件登记', () {
    KitPlugin sample({bool en = false, String ver = '1.2.0'}) => KitPlugin(
          id: 'lh-qr',
          name: '二维码生成',
          ver: ver,
          size: 31,
          src: 'github',
          perms: const ['net', 'file'],
          granted: const ['net'],
          enabled: en,
          installedAt: 1000,
          updatedAt: 2000,
          audit: const [KitAudit(ts: 1000, text: '安装 v1.2.0 · 校验通过')],
        );

    test('upsert + 读回全字段（权限/授予/审计 JSON 往返）', () async {
      await repo.upsertPlugin(sample());
      final list = await repo.plugins();
      expect(list, hasLength(1));
      final p = list.single;
      expect(p.perms, ['net', 'file']);
      expect(p.granted, ['net']);
      expect(p.enabled, isFalse);
      expect(p.audit.single.text, contains('校验通过'));
      expect(jsonEncode(p.audit.single.toJson()), contains('"ts":1000'));
    });

    test('同 id 二次 upsert=升级覆盖，不新增行', () async {
      await repo.upsertPlugin(sample());
      await repo.upsertPlugin(sample(en: true, ver: '1.3.0'));
      final list = await repo.plugins();
      expect(list, hasLength(1));
      expect(list.single.ver, '1.3.0');
      expect(list.single.enabled, isTrue);
    });

    test('启停与删除', () async {
      await repo.upsertPlugin(sample());
      await repo.setPluginEnabled('lh-qr', true);
      expect((await repo.plugins()).single.enabled, isTrue);
      await repo.removePlugin('lh-qr');
      expect(await repo.plugins(), isEmpty);
    });

    test('列缺失/NULL 时模型回落默认值（旧行容错）', () async {
      await db.insert(DbSchema.tKitPlugin, {
        'id': 'bare',
        'name': '裸包',
        'ver': '0.1.0',
        'installed_at': 5,
        'updated_at': 5,
      });
      final p = (await repo.plugins()).single;
      expect(p.src, 'local');
      expect(p.size, 0);
      expect(p.perms, isEmpty);
      expect(p.audit, isEmpty);
      expect(p.enabled, isFalse);
    });
  });
}
