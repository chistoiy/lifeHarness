import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/care/data/care_repository.dart';
import 'package:lifeharness/features/care/presentation/care_notify.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// V1.57 B 批 · 呵护儿保体检节点 + 二次验证遗留键摘除（拍板记录 §十）。
/// 断言面＝节点计算与「排程调用」返回文本；真实送达属真机验收项。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late CareRepository repo;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = CareRepository(db);
  });

  // 内存库按路径复用：不 close 会带着上个用例的表和数据进下一个。
  tearDown(() => db.close());

  group('体检节点表', () {
    test('按出生日推算：42 天 + 3/6/8/12/18 月龄', () {
      final birth = DateTime(2026, 3, 10);
      expect(checkupDate(birth, kCareCheckupNodes[0]),
          DateTime(2026, 3, 10).add(const Duration(days: 42)));
      expect(checkupDate(birth, kCareCheckupNodes[1]), DateTime(2026, 6, 10));
      expect(checkupDate(birth, kCareCheckupNodes[5]),
          DateTime(2027, 9, 10)); // 2026-03 + 18 月
    });

    test('nextCheckup＝最近未达节点；18 月龄后为 null', () {
      final birth = DateTime(2026, 3, 10);
      // 2026-07-01：42 天（04-21）与 3 月龄（06-10）已过 → 下一个＝6 月龄。
      final n = nextCheckup(birth, DateTime(2026, 7, 1));
      expect(n!.$1.label, '6 月龄体检');
      expect(n.$2, DateTime(2026, 9, 10));
      expect(nextCheckup(birth, DateTime(2028, 1, 1)), isNull);
    });
  });

  group('syncCareCheckup', () {
    test('开关关＝不排；开＝排下一节点并返回文案', () async {
      await repo.addBaby(name: '小糖', sex: '女', birth: '2026-06-01',
          color: '#F472B6');
      expect(await syncCareCheckup(repo, now: DateTime(2026, 7, 10)), isNull);
      await repo.setKv('care.rm.checkup', 'true');
      final body =
          await syncCareCheckup(repo, now: DateTime(2026, 7, 10));
      // 下一节点＝42 天体检（2026-06-01 + 42d = 07-13）。
      expect(body, contains('小糖'));
      expect(body, contains('42 天体检'));
      expect(body, contains('7月13日'));
    });

    test('无宝宝档案＝不排不抛', () async {
      await repo.setKv('care.rm.checkup', 'true');
      expect(await syncCareCheckup(repo, now: DateTime(2026, 7, 10)), isNull);
    });
  });

  group('care.rm.lock 读到即清', () {
    test('历史遗留 true 键在 reminderKvs 时被删除', () async {
      await repo.setKv('care.rm.lock', 'true');
      expect((await repo.reminderKvs()).containsKey('care.rm.lock'), isFalse);
      // 行确实从 settings 表消失（不是只隐藏）。
      final rows = await db.query(DbSchema.tSettings,
          where: "key = 'care.rm.lock'");
      expect(rows, isEmpty);
      // 再读不重复报错。
      expect((await repo.reminderKvs()).containsKey('care.rm.lock'), isFalse);
    });
  });
}
