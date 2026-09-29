/// L3 日志批验收钉桩（docs/日志覆盖工单-20260929.md §三·L3）：
/// 记账导入链、待办读取与逾期扫描、日程时间块落库三条高频路径必须留痕，
/// 且**来源归类**正确（日志页按「记账 / 待办 / 日程」筛得出来）。
/// 口径同 L1/L2：只加日志零行为改动，本文件只钉「有没有留痕、归没归对来源」。
library;

import 'package:enough_convert/gbk.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/host/event_bus.dart';
import 'package:lifeharness/core/logging/app_log.dart';
import 'package:lifeharness/features/calendar/data/time_block_dao.dart';
import 'package:lifeharness/features/ledger/data/bill_parser.dart';
import 'package:lifeharness/features/todo/data/todo_dao.dart';
import 'package:lifeharness/features/todo/domain/todo_repository.dart';
import 'package:lifeharness/features/todo/presentation/todo_providers.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

bool logged(String contains, {String? level, bool key = false}) =>
    AppLog.lines.any((l) =>
        l.text.contains(contains) &&
        (level == null || l.level.name == level) &&
        (!key || l.key));

/// 含关键字的行必须全部归到同一来源（日志页筛选口径＝产品定位问题的入口）。
void srcOf(String contains, String want) {
  for (final l in AppLog.lines.where((x) => x.text.contains(contains))) {
    expect(l.src, want, reason: '${l.text} 归到了 ${l.src}，应为 $want');
  }
}

/// 支付宝账单表头（_detect 认「交易时间 + 交易分类 + 收/付款方式」）。
const _alipayHeader = '交易时间,交易分类,交易对方,商品说明,收/付款方式,金额,收/支,交易订单号,交易状态';

String _alipayCsv([int rows = 2]) {
  final b = StringBuffer('$_alipayHeader\n');
  for (var i = 0; i < rows; i++) {
    b.writeln(
        '2026-09-2${i + 1} 12:0$i:33,餐饮美食,楼下面馆,午餐,招商银行信用卡(8663)&遇财神立减,'
        '${12 + i}.50,支出,ALI${1000 + i},交易成功');
  }
  return b.toString();
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  setUp(AppLog.reset);
  tearDown(AppLog.reset);

  group('记账（features/ledger）· 账单解析', () {
    test('GBK 账单：utf8 严格解码失败→按 GBK 回落，并落解析汇总 key 行', () {
      final bytes = gbk.encode(_alipayCsv());
      // 纯中文内容 GBK 编码后不是合法 UTF-8，正好走「utf8 失败→GBK 兜底」真分支。
      final res = parseBillFile(bytes);
      expect(res, isNotNull, reason: 'GBK 账单应解析成功');
      expect(res!.rows.length, 2);
      expect(logged('utf8 解码失败', level: 'warn'), isTrue,
          reason: AppLog.lines.map((l) => l.text).join(' | '));
      expect(logged('账单解析：平台 支付宝', key: true), isTrue,
          reason: '汇总行按关键路径落盘（warn/key 即时刷）');
      expect(res.skipped, 0);
      srcOf('账单', '记账');
    });

    test('PK 头但非 Excel 容器 → error 留痕并返回 null', () {
      final bytes = [0x50, 0x4B, 0x03, 0x04, ...List.filled(64, 0x20)];
      expect(parseBillFile(bytes), isNull);
      expect(logged('xlsx 解包失败', level: 'error'), isTrue,
          reason: AppLog.lines.map((l) => l.text).join(' | '));
      srcOf('xlsx', '记账');
    });

    test('表头认不出 → warn 留痕（真机「导入无反应」看这条）', () {
      expect(parseBillText('日期,金额\n2026-09-01,12.50\n'), isNull);
      expect(logged('未识别到支付宝/微信表头', level: 'warn'), isTrue,
          reason: AppLog.lines.map((l) => l.text).join(' | '));
      srcOf('账单解析', '记账');
    });

    test('只有表头没有流水 → 汇总行如实写 0 条（含规则过滤数）', () {
      final res = parseBillText('$_alipayHeader\n');
      expect(res, isNotNull);
      expect(res!.rows, isEmpty);
      expect(logged('有效 0 条'), isTrue,
          reason: AppLog.lines.map((l) => l.text).join(' | '));
    });

    test('「不计收支」类流水被过滤也在汇总行里可见', () {
      final text = '$_alipayHeader\n'
          '2026-09-01 12:00:00,投资理财,余额宝,收益转入,余额宝,100.00,不计收支,ALI9,交易成功\n'
          '2026-09-02 12:00:00,餐饮美食,面馆,午餐,招商银行信用卡(8663),12.50,支出,ALI8,交易成功\n';
      final res = parseBillText(text);
      expect(res!.rows.length, 1);
      expect(res.skipped, 1);
      expect(logged('有效 1 条 · 规则过滤 1 条'), isTrue,
          reason: AppLog.lines.map((l) => l.text).join(' | '));
    });
  });

  group('待办（features/todo）· 读取与逾期扫描', () {
    late Database db;
    setUp(() async {
      db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    });
    tearDown(() async => db.close());

    /// 空库（不建表）＝DAO 查询必然抛错，用来钉「异常路径有没有留痕」。
    ProviderContainer brokenContainer() {
      final repo = TodoRepository(TodoDao(db), EventBus());
      return ProviderContainer(
          overrides: [todoRepositoryProvider.overrideWithValue(repo)]);
    }

    test('列表读取失败 → error 留痕后原样抛出（不改控制流）', () async {
      final c = brokenContainer();
      await expectLater(c.read(todosProvider.future), throwsA(anything));
      expect(logged('待办列表读取失败', level: 'error'), isTrue,
          reason: AppLog.lines.map((l) => l.text).join(' | '));
      srcOf('待办', '待办');
      c.dispose();
    });

    test('逾期扫描失败 → error 留痕（否则角标恒 0 无从查起）', () async {
      final c = brokenContainer();
      await expectLater(c.read(overdueCountProvider.future), throwsA(anything));
      expect(logged('待办逾期扫描失败', level: 'error'), isTrue,
          reason: AppLog.lines.map((l) => l.text).join(' | '));
      srcOf('逾期扫描', '待办');
      c.dispose();
    });
  });

  group('日程（features/calendar）· 时间块落库', () {
    late Database db;
    late TimeBlockDao dao;
    final today = DateTime.now();
    final d0 = DateTime(today.year, today.month, today.day);

    setUp(() async {
      db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
      for (final sql in DbSchema.createStatements) {
        await db.execute(sql);
      }
      dao = TimeBlockDao(db);
    });
    tearDown(() async => db.close());

    test('标记落库记「段数前后对照」（合并丢块只有这条路可复盘）', () async {
      await dao.markRange(d0, 540, 600, catName: '工作');
      expect(logged('日程标记落库：09:00-10:00 · 工作 · 日内 mark 段 0→1'), isTrue,
          reason: AppLog.lines.map((l) => l.text).join(' | '));
      // 同分类相邻 → 合并为一段，前后数必须体现在日志里。
      await dao.markRange(d0, 600, 660, catName: '工作');
      expect(logged('日内 mark 段 1→1'), isTrue,
          reason: AppLog.lines.map((l) => l.text).join(' | '));
      srcOf('日程标记落库', '日程');
    });

    test('计时收口与撤销回写各落一条 key 行', () async {
      final b = await dao.startTiming(d0, 540, catName: '工作');
      await dao.endTiming(b.id, 600);
      expect(logged('日程计时收口', key: true), isTrue,
          reason: AppLog.lines.map((l) => l.text).join(' | '));
      final snap = await dao.snapshotDay(d0);
      await dao.remove(b.id!);
      expect(await dao.listByDay(d0), isEmpty);
      await dao.restoreDay(d0, snap);
      expect(logged('日程撤销回写：日', key: true), isTrue,
          reason: AppLog.lines.map((l) => l.text).join(' | '));
      expect((await dao.listByDay(d0)).length, snap.length);
      srcOf('日程', '日程');
    });
  });
}
