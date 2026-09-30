import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/features/goals/data/goals_repository.dart';
import 'package:lifeharness/features/goals/domain/goal_models.dart';
import 'package:lifeharness/features/goals/presentation/goals_page.dart';
import 'package:lifeharness/features/goals/presentation/goals_providers.dart';

/// 批3 · 目标 OKR 四屏 UI（V1.42 模块7 · 原型 P10/P10a/P10b/P10c 对译断言）。
/// 独立文件防 isolate 污染；固定钟 2026-09-19（goalsClockProvider 缝）。
void main() {
  sqfliteFfiInit();
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 9, 19);
  late Database db;
  late GoalsRepository repo;

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    for (final sql in DbSchema.createStatements) {
      await db.execute(sql);
    }
    repo = GoalsRepository(db);
  });

  tearDown(() => db.close());

  Future<void> pump(WidgetTester tester, Widget home) async {
    final container = ProviderContainer(overrides: [
      goalsRepositoryProvider.overrideWithValue(repo),
      goalsClockProvider.overrideWithValue(() => now),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: MaterialApp(home: home)));
    await settle5(tester);
  }

  /// toast 长句用包含语义轮询（大 pump 会跳过 SnackBar 退场期）。
  Future<bool> pollContains(WidgetTester tester, String part) async {
    for (var i = 0; i < 15; i++) {
      if (find.textContaining(part).evaluate().isNotEmpty) return true;
      await tester.pump(const Duration(milliseconds: 80));
    }
    return find.textContaining(part).evaluate().isNotEmpty;
  }

  Future<void> clearToasts2(WidgetTester tester) async {
    await clearToasts(tester);
  }

  Future<int> seedGoal(String title, String period, List<GoalKr> krs,
      {int sort = 0}) async {
    final id = await db.insert(DbSchema.tGoals, {
      'title': title,
      'period': period,
      'sort': sort,
      'created_at': now.millisecondsSinceEpoch,
      'updated_at': now.millisecondsSinceEpoch,
    });
    for (final kr in krs) {
      await db.insert(DbSchema.tGoalKrs, {
        'goal_id': id,
        'label': kr.label,
        'target': kr.target,
        'unit': kr.unit,
        'src': kr.source.wire,
        'cur': kr.cur,
      });
    }
    return id;
  }

  GoalKr k(String label,
          {double tgt = 1,
          double cur = 0,
          String unit = '项',
          KrSource src = KrSource.manual}) =>
      GoalKr(
          goalId: 0,
          label: label,
          target: tgt,
          unit: unit,
          source: src,
          cur: cur);

  /// 演示边界态播种（原型 D.okr L2446-2464）：Q1/Q2 归档、Q3 进行中、Q4 预建空。
  Future<Map<String, int>> seedDemo() async {
    final ids = <String, int>{};
    await repo.setPeriodArchived('2026 Q1', true);
    await repo.setPeriodArchived('2026 Q2', true);
    ids['q1'] = await seedGoal('O1 作息与运动地基搭建', '2026 Q1',
        [k('建立每周运动习惯 ≥2 次', tgt: 2, cur: 3, unit: '次/周'), k('连续日记 ≥60 天', tgt: 60, cur: 64, unit: '天')],
        sort: 0);
    ids['q2'] = await seedGoal('O2 财务台账启动', '2026 Q2',
        [k('账户台账 100% 建档', tgt: 5, cur: 4, unit: '%'), k('存量物品完成归类', tgt: 20, cur: 11, unit: '件')],
        sort: 1);
    // Q3 O1：80/55/63 → 均值 66（环测试基准）
    ids['o1'] = await seedGoal(
        'O1 建立可持续的健康作息', '2026 Q3',
        [
          k('每周运动 ≥3 次', tgt: 5, cur: 4, unit: '次/周'),
          k('23:30 前入睡率 ≥80%', tgt: 31, cur: 17, unit: '天/月'),
          k('本季读完 16 本书', tgt: 16, cur: 10, unit: '本'),
        ],
        sort: 0);
    ids['o2'] = await seedGoal(
        'O2 财务清晰可控', '2026 Q3',
        [
          k('月度结余率 ≥50%', tgt: 100, cur: 49, unit: '%', src: KrSource.habit),
          k('建立全部物品台账', tgt: 1, unit: '项'),
        ],
        sort: 1);
    ids['o3'] = await seedGoal(
        'O3 输出式学习成体系', '2026 Q3',
        [
          k('读书笔记输出 ≥8 篇', tgt: 8, cur: 4, unit: '篇'),
          k('周复盘 KPT 连续 12 周', tgt: 12, cur: 3, unit: '周'),
          k('技术分享 ≥2 次', tgt: 2),
        ],
        sort: 2);
    return ids;
  }

  group('P10 列表屏', () {
    testWidgets('周期卡实算/切换与边界 toast/上限行/归档只读拦截', (tester) async {
      await useSurface(tester);
      await seedDemo();
      await pump(tester, const GoalsPage());

      // 标题 + 副行全实算：Q3 三目标 pct 66/0(habit 源空表汇聚归 0)/25 → 均值 30
      expect(find.text('2026 Q3 · 进行中'), findsOneWidget);
      expect(find.text('3 个目标 · 平均进度 30% · KR 达成 0/8'), findsOneWidget);
      expect(find.text('66%'), findsOneWidget);
      expect(find.textContaining('单周期建议 ≤ 5 个 O · 当前 3/5，超出时创建入口将提醒收敛'),
          findsOneWidget);
      // O 卡底部口径行 + KR 迷你行百分比实算
      expect(find.textContaining('进度由关联数据自动汇聚（联动 L3/L4/L5 · 可手动回填）'),
          findsNWidgets(3));
      expect(find.text('80%'), findsOneWidget);

      // ‹‹ 切到 Q1 归档周期：卡片灰态口径行 + 新建拦截 toast 逐字
      await tester.tap(find.byKey(const ValueKey('g-period-prev')));
      await tester.pumpAndSettle();
      expect(await pollContains(tester, '已切换到 2026 Q2 · 已归档 · 只读'), isTrue);
      await tester.tap(find.byKey(const ValueKey('g-period-prev')));
      await tester.pumpAndSettle();
      await pollContains(tester, '已切换到 2026 Q1 · 已归档 · 只读');
      expect(find.textContaining('归档周期保留最终达成口径 · 复盘已关联'), findsOneWidget);
      expect(find.textContaining('· 归档'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('g-new')));
      expect(await pollContains(tester, '归档周期只读 · 请切到进行中周期再创建/编辑'), isTrue);
      // 下界
      await tester.tap(find.byKey(const ValueKey('g-period-prev')));
      expect(await pollContains(tester, '最早周期为 2026 Q1'), isTrue);
      await clearToasts2(tester);

      // › 走到 Q4 上界
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byKey(const ValueKey('g-period-next')));
        await tester.pumpAndSettle();
        await clearToasts2(tester);
      }
      expect(find.text('2026 Q4 · 未开始 · 可预建'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('g-period-next')));
      expect(await pollContains(tester, '已是最后一个周期'), isTrue);
      await clearToasts2(tester);

      // 归档/恢复小钮（当前周期）
      await tester.tap(find.byKey(const ValueKey('g-period-prev')));
      await tester.pumpAndSettle(); // 回到 Q3
      await clearToasts2(tester);
      await tester.tap(find.byKey(const ValueKey('g-period-archive')));
      expect(await pollContains(tester, '已归档 2026 Q3 · 周期转为只读'), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('2026 Q3 · 已归档 · 只读'), findsOneWidget);
      await clearToasts2(tester);
      await tester.tap(find.byKey(const ValueKey('g-period-restore')));
      expect(await pollContains(tester, '已恢复 2026 Q3 · 可继续编辑'), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('2026 Q3 · 进行中'), findsOneWidget);
      await drainLogTimer(tester); // 仓库写入落 key 行 → 排空 AppLog 节流 Timer
    });

    testWidgets('年度视角含周期/归档 chip', (tester) async {
      await useSurface(tester);
      await seedDemo();
      await pump(tester, const GoalsPage());

      await tester.tap(find.byKey(const ValueKey('g-scope-year')));
      expect(await pollContains(tester, '年度视角：跨周期总览全部 O（含归档）'), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('2026 年度视角 · 全部周期'), findsOneWidget);
      // 全部 5 个 O 都在
      expect(find.textContaining('个目标 · 平均进度'), findsOneWidget);
      expect(find.text('O1 作息与运动地基搭建'), findsOneWidget);
      expect(find.text('O3 输出式学习成体系'), findsOneWidget);
      // 归档态 chip 带「· 归档」；非归档季度 chip 仅周期名
      expect(find.text('2026 Q1 · 归档'), findsOneWidget);
      expect(find.text('2026 Q3'), findsNWidgets(3));
      await tester.tap(find.byKey(const ValueKey('g-scope-quarter')));
      expect(await pollContains(tester, '周期视角：仅 2026 Q3'), isTrue);
      await drainLogTimer(tester); // 仓库写入落 key 行 → 排空 AppLog 节流 Timer
    });

    testWidgets('空态双钮 + 复制上期清零重编号 toast', (tester) async {
      await useSurface(tester);
      await seedDemo();
      await pump(tester, const GoalsPage());

      await tester.tap(find.byKey(const ValueKey('g-period-next'))); // Q4 空
      await tester.pumpAndSettle();
      await clearToasts2(tester);
      expect(find.textContaining('本周期还没有目标。'), findsOneWidget);
      expect(find.byKey(const ValueKey('g-new-empty')), findsOneWidget);
      expect(find.byKey(const ValueKey('g-copy-prev')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('g-copy-prev')));
      expect(
          await pollContains(tester, '已从 2026 Q3 复制 3 个目标为 2026 Q4 草稿（进度清零）'),
          isTrue);
      await tester.pumpAndSettle();
      // 重编号从已有数+1 起：O1/O2/O3 → 仍 O1..O3（Q4 原本为空），进度全 0%
      expect(find.text('O1 建立可持续的健康作息'), findsOneWidget);
      expect(find.textContaining('当前 0 个目标 · 平均进度 0% · KR 达成 0/8'), findsNothing);
      expect(find.textContaining('3 个目标 · 平均进度 0% · KR 达成 0/8'), findsOneWidget);
      // 复制成功后空态消失（原型同口径：复制入口仅在空周期出现）
      expect(find.byKey(const ValueKey('g-copy-prev')), findsNothing);
      await drainLogTimer(tester); // 仓库写入落 key 行 → 排空 AppLog 节流 Timer
    });

    testWidgets('无可复制历史周期 toast', (tester) async {
      await useSurface(tester);
      await repo.setPeriodArchived('2026 Q1', true);
      await pump(tester, const GoalsPage());
      await tester.tap(find.byKey(const ValueKey('g-period-prev')));
      await tester.tap(find.byKey(const ValueKey('g-period-prev'))); // Q1
      await tester.pumpAndSettle();
      await clearToasts2(tester);
      await tester.tap(find.byKey(const ValueKey('g-copy-prev')));
      expect(await pollContains(tester, '没有可复制的历史周期'), isTrue);
      await drainLogTimer(tester); // 仓库写入落 key 行 → 排空 AppLog 节流 Timer
    });
  });

  group('P10a 详情屏', () {
    testWidgets('hero 环 66% + 剩 11 天实算 + 回填/来源明细', (tester) async {
      await useSurface(tester);
      final ids = await seedDemo();
      await pump(tester, const GoalsPage());

      await tester.tap(find.byKey(ValueKey('g-okr-${ids['o1']}')));
      await tester.pumpAndSettle();
      expect(find.text('目标详情'), findsOneWidget);
      expect(find.text('66%'), findsOneWidget);
      expect(find.text('2026 Q3 · 3 个 KR · 截止 09-30（剩 11 天）'), findsOneWidget);
      expect(find.text('当前 4 / 目标 5 次/周'), findsOneWidget);
      expect(find.textContaining('数据源：手动 · 每日 00:00 自动重算'), findsNWidgets(3));
      expect(find.textContaining(
              '汇聚口径：关联待办完成数 / 阅读本数 / 日记篇数 / 习惯打卡 / 记账结余自动计算 KR；关闭「自动汇聚」后该 KR 转手动回填。'),
          findsOneWidget);
      // 加入复盘（本批仅 toast 挂清单）
      await tester.tap(find.byKey(const ValueKey('g-detail-add-review')));
      expect(await pollContains(tester, '本目标已加入「季度复盘」对照清单'), isTrue);
      await clearToasts2(tester);

      // 回填弹层：输入 5 保存 → cur 4→5，进度 80→100%，O 均值 66→73
      await tester.tap(find.byKey(const ValueKey('g-kr-bump-0')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('g-bump-input')), '5');
      await tester.tap(find.byKey(const ValueKey('g-bump-save')));
      expect(await pollContains(tester, '每周运动 ≥3 次 已回填 5/5 次/周'), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('当前 5 / 目标 5 次/周'), findsOneWidget);
      expect(find.text('73%'), findsOneWidget);

      // 来源明细弹层含「手动回填」留痕
      await tester.tap(find.byKey(const ValueKey('g-kr-detail-0')));
      await tester.pumpAndSettle();
      expect(find.text('手动回填'), findsWidgets);
      expect(find.textContaining('手动回填 cur=5'), findsOneWidget);
      await tester.tapAt(const Offset(5, 5)); // 关弹层
      await tester.pumpAndSettle();
      await clearToasts2(tester);
      await drainLogTimer(tester); // 仓库写入落 key 行 → 排空 AppLog 节流 Timer
    });

    testWidgets('自动汇聚 KR 展示来源 chip + 数据源行', (tester) async {
      await useSurface(tester);
      final ids = await seedDemo();
      await db.insert(DbSchema.tHabitEntries, {
        'habit_id': 'h1',
        'day': '2026-09-01',
        'checked': 1,
        'origin': 'manual',
        'created_at': now.millisecondsSinceEpoch,
        'updated_at': now.millisecondsSinceEpoch,
      });
      await pump(tester, const GoalsPage());
      await tester.tap(find.byKey(ValueKey('g-okr-${ids['o2']}')));
      await tester.pumpAndSettle();
      expect(find.text('自动汇聚'), findsOneWidget);
      expect(find.textContaining('数据源：习惯打卡 · 每日 00:00 自动重算'), findsOneWidget);
      expect(find.text('当前 1 / 目标 100 %'), findsOneWidget); // 汇聚实算回写
      await drainLogTimer(tester); // 仓库写入落 key 行 → 排空 AppLog 节流 Timer
    });

    testWidgets('归档详情：复制为新周期目标 + 查看最近复盘', (tester) async {
      await useSurface(tester);
      final ids = await seedDemo();
      await pump(tester, const GoalsPage());
      await tester.tap(find.byKey(const ValueKey('g-period-prev')));
      await tester.tap(find.byKey(const ValueKey('g-period-prev'))); // Q1
      await tester.pumpAndSettle();
      await clearToasts2(tester);
      await tester.tap(find.byKey(ValueKey('g-okr-${ids['q1']}')));
      await tester.pumpAndSettle();
      expect(find.textContaining('截止 03-31 · 已归档'), findsOneWidget);
      expect(find.text('归档周期 · 只读 · 保留最终达成口径'), findsOneWidget);
      expect(find.byKey(const ValueKey('g-kr-bump-0')), findsNothing);
      expect(find.byKey(const ValueKey('g-detail-edit')), findsNothing);
      expect(find.textContaining('归档周期数据冻结在期末时点。'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('g-detail-copy')));
      expect(await pollContains(tester, '已复制为 2026 Q3 新目标 · 进度已清零'), isTrue);
      await clearToasts2(tester);
      await tester.tap(find.byKey(const ValueKey('g-detail-review')));
      await tester.pumpAndSettle();
      expect(find.textContaining('KR 达成对照（自动汇聚）'), findsOneWidget);
      await drainLogTimer(tester); // 仓库写入落 key 行 → 排空 AppLog 节流 Timer
    });
  });

  group('P10b 编辑屏', () {
    testWidgets('校验链逐字 + 新建落库 + KR 上限/弹层选择', (tester) async {
      await useSurface(tester);
      await seedDemo();
      await pump(tester, const GoalsPage());
      await tester.tap(find.byKey(const ValueKey('g-new')));
      await tester.pumpAndSettle();
      expect(find.text('新建目标'), findsOneWidget);

      // 校验链 ①③（②需 <2 行，见下方单独用例）
      await tester.tap(find.byKey(const ValueKey('g-edit-save')));
      expect(await pollContains(tester, '先写目标 O 标题'), isTrue);
      await clearToasts2(tester);
      await tester.enterText(find.byKey(const ValueKey('g-edit-title')), 'O4 把身体养回来');
      await tester.tap(find.byKey(const ValueKey('g-edit-save')));
      expect(await pollContains(tester, 'KR 描述不能为空'), isTrue);
      await clearToasts2(tester);

      // KR 行：描述 + 单位/数据源底部弹层选择（禁系统 select）
      await tester.enterText(find.byKey(const ValueKey('g-edit-kr-0-label')), '每周运动 ≥3 次');
      await tester.enterText(find.byKey(const ValueKey('g-edit-kr-1-label')), '体检指标全部转阴');
      await tester.tap(find.byKey(const ValueKey('g-edit-kr-0-unit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('g-opt-单位-次/周')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('g-edit-kr-1-src')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('g-opt-数据源-待办完成数')));
      await tester.pumpAndSettle();

      // 添加 KR 至上限 4，再点 toast
      await tester.tap(find.byKey(const ValueKey('g-edit-kr-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('g-edit-kr-add')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('g-edit-kr-2-label')), 'c');
      await tester.enterText(find.byKey(const ValueKey('g-edit-kr-3-label')), 'd');
      await tester.tap(find.byKey(const ValueKey('g-edit-kr-add')));
      expect(await pollContains(tester, 'KR 上限 4 个 · 建议合并同类项'), isTrue);
      await clearToasts2(tester);
      // ≥2 守护：✕ 出现且删到 2 后消失
      expect(find.byKey(const ValueKey('g-edit-kr-0-del')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('g-edit-save')));
      expect(await pollContains(tester, '目标已创建到 2026 Q3 · KR 数据源已挂自动汇聚'), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('O4 把身体养回来'), findsOneWidget); // 回列表可见
      final d = await repo.loadAll(now: now);
      final g = d.goals.firstWhere((x) => x.title == 'O4 把身体养回来');
      expect(g.krs.length, 4);
      expect(g.krs.first.unit, '次/周');
      expect(g.krs[1].source, KrSource.todo);
      expect(find.textContaining('当前 4/5'), findsOneWidget);
      await drainLogTimer(tester); // 仓库写入落 key 行 → 排空 AppLog 节流 Timer
    });

    testWidgets('校验链②：仅 1 KR 的目标保存提示「至少 2 个 KR」', (tester) async {
      await useSurface(tester);
      final gid = await seedGoal('O9 残缺', '2026 Q3', [k('只有一条')]);
      await pump(tester, const GoalsPage());
      await tester.tap(find.byKey(ValueKey('g-okr-$gid')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('g-detail-edit')));
      await tester.pumpAndSettle();
      expect(find.text('编辑目标'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('g-edit-save')));
      expect(await pollContains(tester, '至少 2 个 KR'), isTrue);
      await drainLogTimer(tester); // 仓库写入落 key 行 → 排空 AppLog 节流 Timer
    });

    testWidgets('归档周期保存拦截 + 删除二次确认连退', (tester) async {
      await useSurface(tester);
      final ids = await seedDemo();
      await pump(tester, const GoalsPage());

      // 新建态选归档周期 Q2 → 保存拦截逐字
      await tester.tap(find.byKey(const ValueKey('g-new')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('g-edit-title')), 'O5 试探');
      await tester.enterText(find.byKey(const ValueKey('g-edit-kr-0-label')), 'a');
      await tester.enterText(find.byKey(const ValueKey('g-edit-kr-1-label')), 'b');
      await tester.tap(find.byKey(const ValueKey('g-edit-period-q2')));
      await tester.pumpAndSettle();
      expect(find.textContaining('2026 Q2 · 已归档 · 只读'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('g-edit-save')));
      expect(await pollContains(tester, '归档周期不可写入 · 请选择进行中的周期'), isTrue);
      await clearToasts2(tester);
      await tester.pageBack();
      await tester.pumpAndSettle();

      // 删除：详情 → 编辑 → 二次确认 → 连退回列表（目标消失）
      await tester.tap(find.byKey(ValueKey('g-okr-${ids['o3']}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('g-detail-edit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('g-edit-del')));
      await tester.pumpAndSettle();
      expect(find.textContaining('确认删除此目标？KR 与复盘记录一并移除'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('g-edit-del-confirm')));
      expect(await pollContains(tester, '目标已删除'), isTrue);
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('g-okr-${ids['o3']}')), findsNothing);
      expect(find.byKey(ValueKey('g-okr-${ids['o1']}')), findsOneWidget);
      await drainLogTimer(tester); // 仓库写入落 key 行 → 排空 AppLog 节流 Timer
    });
  });

  group('P10c 季度复盘屏', () {
    testWidgets('季 chips 文案 + 对照表实算 + 保存转只读', (tester) async {
      await useSurface(tester);
      final ids = await seedDemo();
      await repo.saveReview(const GoalReview(period: '2026 Q2', keep: '作息稳', problem: '入睡拖', trial: '绑定打卡'));
      await pump(tester, const GoalsPage());
      await tester.tap(find.byKey(const ValueKey('g-review-entry')));
      await tester.pumpAndSettle();

      // chips：Q2 已归档 + Q3 撰写中（默认选中当前季）
      expect(find.text('2026 Q2 · 已归档'), findsOneWidget);
      expect(find.text('2026 Q3 · 撰写中'), findsOneWidget);
      // 对照表：Q3 三目标 + KR 达成数实算
      expect(find.text('2026 Q3 KR 达成对照（自动汇聚）'), findsOneWidget);
      expect(find.text('66%'), findsOneWidget);
      expect(find.text('0/3 KR 达成'), findsNWidgets(2));
      expect(find.text('0/2 KR 达成'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('g-review-q-0'))); // Q2
      await tester.pumpAndSettle();
      expect(find.text('作息稳'), findsOneWidget); // 归档内容回显
      // 归档态：按钮行＝「分享复盘卡」（V1.57 A 批新增入口）· 保存/Try 钮不出
      expect(find.byKey(const ValueKey('g-review-save')), findsNothing);
      expect(find.byKey(const ValueKey('g-review-draft')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('g-review-share')));
      await tester.pumpAndSettle();
      expect(find.text('分享长图'), findsOneWidget);
      expect(find.text('KR 达成对照'), findsOneWidget);
      expect(find.text('Keep · 做对了什么'), findsOneWidget);
      expect(find.text('数据仅存本机'), findsOneWidget);
      Navigator.of(tester.element(find.byKey(const ValueKey('sc-sheet')))).pop();
      await tester.pumpAndSettle();

      // 回 Q3 撰写中：填 KPT → 保存 → 转只读归档视图
      await tester.tap(find.byKey(const ValueKey('g-review-q-1')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('g-review-keep')), '节奏好');
      await tester.enterText(find.byKey(const ValueKey('g-review-problem')), '入睡被短视频拖');
      await tester.enterText(find.byKey(const ValueKey('g-review-trial')), '绑定日记打卡');
      await tester.tap(find.byKey(const ValueKey('g-review-save')));
      expect(await pollContains(tester, '复盘已保存 · 已转为只读归档视图'), isTrue);
      await tester.pumpAndSettle();
      expect(find.text('2026 Q3 · 已归档'), findsOneWidget);
      expect(find.byKey(const ValueKey('g-review-share')), findsOneWidget); // 归档后出分享钮
      expect(find.byKey(const ValueKey('g-review-draft')), findsNothing);
      final d = await repo.loadAll(now: now);
      expect(d.reviewFor('2026 Q3')!.archived, isTrue);
      expect(d.reviewFor('2026 Q3')!.keep, '节奏好');
      expect(ids['o1'], isNotNull);
      await drainLogTimer(tester); // 仓库写入落 key 行 → 排空 AppLog 节流 Timer
    });

    testWidgets('Try 空拦截 → 生成下季草稿后列表可见', (tester) async {
      await useSurface(tester);
      await seedDemo();
      await pump(tester, const GoalsPage());
      await tester.tap(find.byKey(const ValueKey('g-review-entry')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('g-review-draft')));
      expect(await pollContains(tester, '先在 Try 里写下改法'), isTrue);
      await clearToasts2(tester);

      await tester.enterText(
          find.byKey(const ValueKey('g-review-trial')), '把物品建档从记账流水一键升级切入');
      await tester.tap(find.byKey(const ValueKey('g-review-draft')));
      expect(
          await pollContains(tester, '已从 Try 生成 2026 Q4 目标草稿 · 可在列表继续编辑'),
          isTrue);
      await tester.pumpAndSettle(); // 弹回列表
      expect(find.text('目标 OKR'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('g-period-next'))); // Q4
      await tester.pumpAndSettle();
      await clearToasts2(tester);
      expect(find.text('O1 由 2026 Q3 复盘 Try 生成'), findsOneWidget);
      expect(find.textContaining('把物品建档从记账流水一键升级切入'), findsOneWidget);
      await drainLogTimer(tester); // 仓库写入落 key 行 → 排空 AppLog 节流 Timer
    });
  });
}
