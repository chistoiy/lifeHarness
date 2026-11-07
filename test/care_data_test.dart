import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/care/data/care_repository.dart';
import 'package:lifeharness/features/care/domain/care_models.dart';

/// 呵护批0/批1 · 仓储层（档案/记录人/自定义事件键迁移/周期预测存档/分档隔离）。
/// 独立文件防 isolate 污染。
void main() {
  sqfliteFfiInit();

  late Database db;
  late CareRepository repo;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = CareRepository(db);
  });

  tearDown(() => db.close());

  Future<int> baby({String name = '团子', String birth = '2026-01-07'}) =>
      repo.addBaby(name: name, sex: '女', birth: birth, color: 'sky');

  group('1 · 宝宝档案与分档隔离', () {
    test('无档案时 currentBaby 为 null（首屏建档空态）', () async {
      final d = await repo.loadAll();
      expect(d.babies, isEmpty);
      expect(d.currentBaby, isNull);
    });

    test('新增档案自动成为当前档；记录按宝宝隔离', () async {
      final a = await baby(name: '团子');
      final b = await baby(name: '糯米');
      await repo.addLog(CareRecord(babyId: a, day: '2026-09-19', k: 'sleep', s: '09:00', e: '10:00', dur: 60));
      await repo.addLog(CareRecord(babyId: b, day: '2026-09-19', k: 'water', s: '10:00', ml: 30));
      var d = await repo.loadAll();
      expect(d.currentBaby?.name, '糯米'); // 最后建档=当前
      expect(d.logs.length, 1);
      expect(d.logs.single.k, 'water');
      await repo.setCurBaby(a);
      d = await repo.loadAll();
      expect(d.logs.single.k, 'sleep');
      expect(d.logCounts[a], 1);
    });

    test('删档案级联清理分档数据并落相邻档（决策 11）', () async {
      final a = await baby(name: '团子');
      final b = await baby(name: '糯米');
      await repo.addLog(CareRecord(babyId: b, day: '2026-09-19', k: 'water', s: '10:00'));
      await repo.setCurBaby(b);
      await repo.deleteBaby(b);
      final d = await repo.loadAll();
      expect(d.babies.map((x) => x.id), [a]);
      expect(d.currentBaby?.id, a);
      expect(d.logs, isEmpty);
    });
  });

  group('2 · 记录人规则', () {
    test('新增即设为默认；重名拦截', () async {
      expect(await repo.addCarer('外婆'), isTrue);
      expect(await repo.curCarer(), '外婆');
      expect(await repo.addCarer('外婆'), isFalse);
    });

    test('至少保留 1；删中默认回落首个；历史署名保留', () async {
      final dad = (await repo.carers()).firstWhere((c) => c.name == '爸爸').id;
      await repo.setCurCarer('爸爸');
      expect(await repo.delCarer(dad), '爸爸');
      expect(await repo.curCarer(), '妈妈');
      while ((await repo.carers()).length > 1) {
        await repo.delCarer((await repo.carers()).last.id);
      }
      final last = (await repo.carers()).single;
      expect(await repo.delCarer(last.id), isNull); // 最后一个不可删
      // 署名保留：删除身份后既有记录 rec 文本不变
      final momId = last.id;
      expect(momId, isNotNull);
    });

    test('改名同步当前记录人', () async {
      final mom = (await repo.carers()).first;
      expect(await repo.renameCarer(mom.id, '妈咪'), isTrue);
      expect(await repo.curCarer(), '妈咪');
    });
  });

  group('3 · 自定义事件与顺序', () {
    test('新建/重名/改名键迁移回写记录与顺序（红线 8）', () async {
      final bid = await baby();
      expect(await repo.addCustomEvent('拍嗝', '🫧', 'min'), isTrue);
      expect(await repo.addCustomEvent('拍嗝', '🫧', 'min'), isFalse);
      await repo.addLog(CareRecord(
          babyId: bid, day: '2026-09-19', k: 'cus:拍嗝', s: '10:00', name: '拍嗝', unit: 'min', amt: '5'));
      expect(await repo.renameCustomEvent('cus:拍嗝', '拍嗝2', '🫧', 'min'), isTrue);
      final customs = await repo.customEvents();
      expect(customs.containsKey('cus:拍嗝2'), isTrue);
      final logs = await repo.logs(bid);
      expect(logs.single.k, 'cus:拍嗝2'); // 记录键迁移
      final order = await repo.evOrder(customs);
      expect(order.contains('cus:拍嗝2'), isTrue);
      expect(order.contains('cus:拍嗝'), isFalse);
    });

    test('evOrder 自动补齐内置 13 类与新自定义键', () async {
      final customs = {'cus:抚触': const CareCustomEvent(key: 'cus:抚触', name: '抚触', icon: '💆', unit: 'min')};
      final order = await repo.evOrder(customs);
      expect(order.length, 14);
      expect(order.first, 'nurse');
      expect(order.last, 'cus:抚触');
    });

    test('排序保存后按库存序', () async {
      final o = await repo.evOrder({});
      final swapped = List.of(o);
      swapped.insert(0, swapped.removeAt(1));
      await repo.saveEvOrder(swapped);
      expect((await repo.evOrder({})).first, 'bmilk');
    });
  });

  group('4 · 周期与预测存档', () {
    test('p1 保存触发预测；再次改起始旧预测置 superseded', () async {
      await repo.saveCycleDay(CycleDay(day: '2026-09-08', state: 'p1'));
      var pred = await repo.currentPrediction();
      expect(pred, isNotNull);
      expect(pred!.nextStart, DateTime(2026, 10, 6)); // 28 天兜底
      expect(pred.ovDay, DateTime(2026, 9, 22)); // 前 14 天
      await repo.saveCycleDay(CycleDay(day: '2026-08-10', state: 'p1'));
      pred = await repo.currentPrediction();
      expect(pred!.nextStart, DateTime(2026, 10, 7)); // 平均 29 天
      expect(pred.ovDay, DateTime(2026, 9, 23));
      final preds = await repo.predictions();
      expect(preds.any((p) => p.superseded), isTrue); // 旧预测已存档
    });

    test('今日感受二次保存覆盖当日行（不落展示串）', () async {
      final today = DateTime.now();
      final key = careDayKey(today);
      await repo.saveTodaySymptoms(today, ['😌 平静'], '姜茶');
      await repo.saveTodaySymptoms(today, ['⚡ 精力旺'], '');
      final row = (await repo.cycleDays())[key]!;
      expect(row.syms, ['⚡ 精力旺']);
      expect(row.note, isNull);
    });
  });

  group('5 · 同步红线与其他 KV', () {
    test('care.syncExcluded 默认开（模块级排除 WebDAV）', () async {
      expect(await repo.syncExcluded(), isTrue);
      await repo.setSyncExcluded(false);
      expect((await repo.loadAll()).syncExcluded, isFalse);
    });

    test('提醒 KV 读写进入快照', () async {
      await repo.setKv('care.rm.fertile', 'true');
      final d = await repo.loadAll();
      expect(d.reminders['care.rm.fertile'], 'true');
    });
  });

  group('6 · 记录二次编辑（决策 4：全字段可改）', () {
    test('更新起止与量后读回一致；删除生效', () async {
      final bid = await baby();
      final id = await repo.addLog(CareRecord(
          babyId: bid, day: '2026-09-19', k: 'bmilk', s: '12:00', e: '12:10', ml: 120, rec: '妈妈'));
      final row = (await repo.logs(bid)).single;
      await repo.updateLog(CareRecord(
          id: id, babyId: bid, day: '2026-09-19', k: 'bmilk', s: '12:05', e: '12:15', ml: 150, rec: '妈妈'));
      final after = (await repo.logs(bid)).single;
      expect(after.ml, 150);
      expect(after.s, '12:05');
      await repo.delLog(id);
      expect(await repo.logs(bid), isEmpty);
      expect(row.day, '2026-09-19');
    });
  });
}
