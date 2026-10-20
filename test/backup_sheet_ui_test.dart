/// Task 10：S5 备份半屏 + /sync 空壳页 widget 验收测试（对照原型 s-backup）。
///
/// 纪律：①本地极简 GoRouter 打开 `/sync`（模式照 test/log_page_test.dart，
/// 不拉全 app）；②服务经 `backupServiceProvider.overrideWithValue(fake)` 注入
/// ——断言 exportBackup/importBackup/saveCopyToUserLocation/pickBackupFile
/// 调用次数（导入按钮在勾选二次确认前 0 次、确认后恰 1 次）；
/// ③SnackBar 断言一律 pollText 命中后再走（helpers 铁律）；④导入报告卡必须
/// 展示 manifest.skippedLarge（功能标签式「N 个超大附件未入包」）。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lifeharness/core/backup/backup_service.dart';
import 'package:lifeharness/core/backup/lh_bak.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/settings/presentation/sync_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

/// 23 表 · 共 100 行的展示用 manifest。
LhBakManifest buildManifest({
  List<String>? skippedLarge,
  bool encrypted = false,
}) =>
    LhBakManifest(
      dbVersion: 19,
      appVersion: kAppVersion,
      createdAt: DateTime(2026, 9, 23, 21, 0, 0),
      tables: {
        for (var i = 0; i < 23; i++)
          'tbl_$i': TableStat(rows: i == 0 ? 100 : 0, checksum: i == 0 ? 'a' * 32 : '-')
      },
      excludedTables: const ['care_logs'],
      encrypted: encrypted,
      members: const ['manifest.json', 'db.sqlite'],
      skippedLarge: skippedLarge,
    );

class _FakeBackupService extends BackupService {
  _FakeBackupService()
      : super(exportDir: () => '', db: () => throw UnimplementedError());

  int exportCalls = 0;
  int importCalls = 0;
  int inspectCalls = 0;
  int pickCalls = 0;

  /// 非 null 时 pickBackupFile 抛出它（20261004 缺陷回归：选择器异常必须可见）。
  Object? pickError;

  /// 非 null 时 exportBackup / saveCopyToUserLocation 抛出它
  /// （轮6 缺陷回归：导出异常必须可见，不再顺 async 通道蒸发）。
  Object? exportError;

  String? lastPassphrase;
  bool? lastWithLogs;
  bool? lastWithAttachments;
  List<String>? lastModules;
  bool? lastWithProjection;

  String? pickedPath;
  LhBakManifest? inspectResult;
  Object? inspectError;

  /// 非 null 时 exportBackup/inspect 挂起等待它（轮7 缺陷回归：验证
  /// 「正在导出…」文案只跟导出动作，导入校验期间不得误显示）。
  Completer<void>? gate;

  RestoreReport report = const RestoreReport(
    tableCount: 23,
    totalRows: 100,
    missingTables: [],
    skippedLarge: [],
    autoBackupPath: null,
  );

  @override
  Future<LhBakCreateResult> exportBackup({
    bool withLogs = false,
    bool withAttachments = true,
    String? passphrase,
    List<String> excludeTables = const [],
    String? outDirOverride,
    String? nameTag,
    bool applyHealthExclusion = true,
    List<String> modules = const [],
    bool withProjection = false,
    bool withMd = true,
    ({DateTime from, DateTime to})? timeRange,
  }) async {
    exportCalls++;
    if (gate != null) await gate!.future;
    if (exportError != null) throw exportError!;
    lastPassphrase = passphrase;
    lastWithLogs = withLogs;
    lastWithAttachments = withAttachments;
    lastModules = List.of(modules);
    lastWithProjection = withProjection;
    return LhBakCreateResult(
        File('/fake/lifeharness_20260925_101500.lhbak'),
        inspectResult ?? buildManifest());
  }

  @override
  Future<LhBakManifest> inspect(String filePath, {String? passphrase}) async {
    inspectCalls++;
    if (gate != null) await gate!.future;
    lastPassphrase = passphrase;
    if (inspectError != null) throw inspectError!;
    return inspectResult ?? buildManifest();
  }

  @override
  Future<String?> pickBackupFile() async {
    pickCalls++;
    if (pickError != null) throw pickError!;
    return pickedPath;
  }

  @override
  Future<RestoreReport> importBackup(String filePath, {String? passphrase}) async {
    importCalls++;
    lastPassphrase = passphrase;
    return report;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  late _FakeBackupService fake;

  setUp(() async {
    fake = _FakeBackupService();
    SharedPreferences.setMockInitialValues({});
  });

  /// 本地极简路由：`/` → 按钮 context.go('/sync') → SyncPage。
  Future<void> openSyncPage(WidgetTester tester) async {
    final prefs = await SharedPreferences.getInstance();
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => context.go('/sync'),
              child: const Text('goto-sync'),
            ),
          ),
        ),
      ),
      GoRoute(path: '/sync', builder: (_, _) => const SyncPage()),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        backupServiceProvider.overrideWithValue(fake),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await settle5(tester);
    await tester.tap(find.text('goto-sync'));
    await settle5(tester);
  }

  /// 打开 /sync 并唤起 S5 半屏。
  Future<void> openSheet(WidgetTester tester) async {
    await openSyncPage(tester);
    await tester.tap(find.byKey(const ValueKey('sync-backup-entry')));
    await settle5(tester);
  }

  group('/sync 主页（Task 18 P1 形态）', () {
    testWidgets('标题「数据与同步」+ 备份半屏入口 + 同步主页入口行齐备',
        (tester) async {
      await openSyncPage(tester);
      expect(find.text('数据与同步'), findsOneWidget);
      // Task 18：空壳页占位行已被 P1 全接线替换（brief 钉死）。
      expect(find.text('同步功能批5接入'), findsNothing);
      expect(find.text('尚未配置云服务'), findsOneWidget);
      expect(find.text('立即同步'), findsNothing); // 无激活服务不出主钮
      expect(find.text('控流'), findsOneWidget);
      expect(find.text('备份导出/导入'), findsWidgets); // 入口行标题
    });
  });

  group('S5 导出', () {
    testWidgets('半屏含附件/日志勾选 · 口令入口已下架 · 主钮开范围面板（V1.66 批2）',
        (tester) async {
      await useSurface(tester, const Size(800, 2400));
      await openSheet(tester);

      expect(find.text('备份导出/导入'), findsWidgets);
      expect(find.text('导出范围'), findsOneWidget);
      expect(find.text('附件 attachments/'), findsOneWidget);
      expect(find.text('附带日志 logs/'), findsOneWidget);
      // V1.66 批2：口令段整体下架（新包纯明文·纯明文落 UI）。
      expect(find.text('口令 · 可选（二次输入一致才启用）'), findsNothing);
      expect(find.byKey(const ValueKey('pass-1')), findsNothing);
      expect(find.byKey(const ValueKey('pass-2')), findsNothing);
      expect(find.byKey(const ValueKey('btn-export')), findsOneWidget);
      // V1.66 装机回知批：「另存到…」下架（导出位置直达取代）。
      expect(find.text('另存到…'), findsNothing);
      expect(find.byKey(const ValueKey('btn-export-save')), findsNothing);
      expect(find.text('上次另存：'), findsNothing);

      // 主钮＝开范围面板（原型 sheetExport），不直接放量导出。
      await tester.tap(find.byKey(const ValueKey('btn-export')));
      await settle5(tester);
      expect(find.text('导出数据'), findsOneWidget);
      expect(find.byKey(const ValueKey('ex-go')), findsOneWidget);
      expect(fake.exportCalls, 0);
      await tester.tap(find.byKey(const ValueKey('ex-close')));
      await settle5(tester);

      // 附件/日志勾选只是透传态：重开面板后勾选仍在。
      await tester.tap(find.byKey(const ValueKey('chk-logs')));
      await settle5(tester);
      expect(fake.exportCalls, 0); // 勾选不触发导出（导出在面板内放量）
      await tester.tap(find.byKey(const ValueKey('btn-export')));
      await settle5(tester);
      expect(find.text('导出数据'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('ex-close')));
      await settle5(tester);
    });

    testWidgets('轮7 导入校验期间主钮文案恒「导出数据…」不误显导出中',
        (tester) async {
      await useSurface(tester, const Size(800, 2400));
      await openSheet(tester);

      // 导入选择＋校验进行中：整屏禁用，但导出主钮文案必须仍是「导出数据…」
      // （真机反馈＝校验 60 万行时误显示「正在导出…」）。
      fake.pickedPath = '/fake/lifeharness_20261004_210019.lhbak';
      fake.gate = Completer<void>();
      await tester.tap(find.byKey(const ValueKey('btn-pick-backup')));
      await settle5(tester);
      expect(fake.pickCalls, 1);
      expect(fake.inspectCalls, 1); // 校验挂起在 gate 上
      expect(find.text('正在导出…'), findsNothing);
      expect(find.text('导出数据…'), findsOneWidget);
      fake.gate!.complete();
      fake.gate = null;
      await settle5(tester);
      expect(find.text('manifest 校验通过'), findsOneWidget);
      // 校验完成 → 恢复钮随勾选可用。
      await tester.tap(find.byKey(const ValueKey('confirm-restore')));
      await settle5(tester);
      expect(
          tester.widget<FilledButton>(find.byKey(const ValueKey('btn-restore')))
              .onPressed,
          isNotNull);
    });
  });

  group('S5 导入恢复', () {
    testWidgets('选择→校验报告态（含 skippedLarge 行）→未勾选恢复 0 次→勾选后恰 1 次',
        (tester) async {
      await useSurface(tester, const Size(800, 2400));
      await openSheet(tester);
      fake.pickedPath = '/fake/lifeharness_20260923_210012.lhbak';
      fake.inspectResult = buildManifest(skippedLarge: [
        'attachments/note_images/big1.bin',
        'attachments/note_images/big2.bin',
      ]);
      fake.report = const RestoreReport(
        tableCount: 23,
        totalRows: 100,
        missingTables: [],
        skippedLarge: [
          'attachments/note_images/big1.bin',
          'attachments/note_images/big2.bin',
        ],
        autoBackupPath: null,
      );

      // 未选择文件前恢复不可用
      expect(fake.importCalls, 0);
      await tester.tap(find.byKey(const ValueKey('btn-pick-backup')));
      await settle5(tester);
      expect(fake.pickCalls, 1);
      expect(fake.inspectCalls, 1);

      // 校验报告态
      expect(find.text('manifest 校验通过'), findsOneWidget);
      expect(find.text('lifeharness_20260923_210012.lhbak'), findsOneWidget);
      expect(find.text('23 表 · 100 行'), findsOneWidget);
      expect(find.text('排除表：care_logs'), findsOneWidget);
      // 携带修复项 4：skippedLarge 功能标签行
      expect(find.text('2 个超大附件未入包'), findsOneWidget);

      // 二次确认前：点恢复不放量调用
      await tester.tap(find.byKey(const ValueKey('btn-restore')));
      await settle5(tester);
      expect(fake.importCalls, 0);

      await tester.tap(find.byKey(const ValueKey('confirm-restore')));
      await settle5(tester);
      await tester.tap(find.byKey(const ValueKey('btn-restore')));
      await pollText(tester, '恢复完成：23 表 · 100 行');
      expect(fake.importCalls, 1);
      await clearToasts(tester);
    });

    testWidgets('选择器抛平台异常→可见失败条且可再点（20261004 缺陷回归）',
        (tester) async {
      await useSurface(tester, const Size(800, 2400));
      await openSheet(tester);
      // 复刻线上成因：file_picker 对未知扩展名 lhbak 抛 Unsupported filter。
      fake.pickError = PlatformException(
          code: 'FilePicker', message: 'Unsupported filter');
      await tester.tap(find.byKey(const ValueKey('btn-pick-backup')));
      expect(
        await pollText(tester, '系统选择器打开失败，请重试'),
        isTrue,
        reason: '选择器异常禁止静默蒸发（旧行为＝点了没反应）',
      );
      await clearToasts(tester);
      // 失败后 _busy 必须复位：修好后可继续走通（按钮没死）。
      fake.pickError = null;
      fake.pickedPath = '/fake/ok.lhbak';
      await tester.tap(find.byKey(const ValueKey('btn-pick-backup')));
      await settle5(tester);
      expect(fake.pickCalls, 2);
      expect(find.text('manifest 校验通过'), findsOneWidget);
    });

    testWidgets('加密包校验报 needPassphrase → 口令输入+校验后才可恢复',
        (tester) async {
      await useSurface(tester, const Size(800, 2400));
      await openSheet(tester);
      fake.pickedPath = '/fake/enc.lhbak';
      fake.inspectError =
          const LhBakException(LhBakException.codeNeedPassphrase);
      await tester.tap(find.byKey(const ValueKey('btn-pick-backup')));
      await settle5(tester);
      expect(find.text('加密包需口令'), findsOneWidget);
      expect(find.text('manifest 校验通过'), findsNothing);
      expect(fake.importCalls, 0);

      fake.inspectError = null;
      fake.inspectResult = buildManifest(encrypted: true);
      await tester.enterText(
          find.byKey(const ValueKey('import-pass')), 'topsecret');
      await tester.tap(find.byKey(const ValueKey('btn-verify-import')));
      await settle5(tester);
      expect(find.text('manifest 校验通过'), findsOneWidget);
      expect(fake.lastPassphrase, 'topsecret');
      await clearToasts(tester);
    });
  });

  group('余量批4 · 部分恢复的覆盖范围明说', () {
    testWidgets('子集包校验后：写明覆盖哪几个模块 + 本机将被覆盖 + 可退回',
        (tester) async {
      await useSurface(tester, const Size(800, 2400));
      await openSheet(tester);
      fake.pickedPath = '/fake/subset.lhbak';
      // 子集包：只含「习惯」
      fake.inspectResult = LhBakManifest(
        dbVersion: 19,
        appVersion: kAppVersion,
        createdAt: DateTime(2026, 10, 15, 10, 0, 0),
        tables: {'habit_entries': TableStat(rows: 12, checksum: 'b' * 32)},
        excludedTables: const [],
        encrypted: false,
        members: const ['manifest.json', 'db.sqlite'],
        scope: {
          'modules': ['habit'],
          'from': '2025-10-15T00:00:00.000',
          'to': '2026-10-15T23:59:59.999',
          'timeFilteredTables': ['habit_entries'],
          'withAttachments': true,
        },
      );
      await tester.tap(find.byKey(const ValueKey('btn-pick-backup')));
      await settle5(tester);

      // ① 覆盖范围：哪几个模块（功能标签用模块人话名，不出现 id）
      expect(find.byKey(const ValueKey('restore-scope-note')), findsOneWidget);
      expect(find.text('本次只覆盖：习惯'), findsOneWidget);
      expect(find.text('本次只覆盖：habit'), findsNothing);
      // ② 其余模块不动 + 时间区间如实
      expect(find.textContaining('其余模块数据保持不动'), findsOneWidget);
      expect(find.textContaining('2025-10-15~2026-10-15'), findsOneWidget);
      // ③ 本机被覆盖 + 可退回（回退路径必须写出来，AGENTS 可见变化）
      expect(find.textContaining('本机数据将被包内版本覆盖'), findsOneWidget);
      expect(find.textContaining('可退回'), findsOneWidget);
      // ④ 确认语与主钮按范围改口径
      expect(find.text('恢复将替换上述模块的当前数据'), findsOneWidget);
      expect(find.text('恢复将替换当前数据'), findsNothing);
      expect(find.text('恢复所选模块'), findsOneWidget);
      expect(find.text('恢复整库'), findsNothing);

      // 勾选前不放量，勾选后恰一次
      expect(fake.importCalls, 0);
      await tester.tap(find.byKey(const ValueKey('confirm-restore')));
      await settle5(tester);
      await tester.tap(find.byKey(const ValueKey('btn-restore')));
      await settle5(tester);
      expect(fake.importCalls, 1);
      await clearToasts(tester);
    });

    testWidgets('全量包（无 scope）保持原口径：整库替换、不出现范围卡',
        (tester) async {
      await useSurface(tester, const Size(800, 2400));
      await openSheet(tester);
      fake.pickedPath = '/fake/full.lhbak';
      fake.inspectResult = buildManifest();
      await tester.tap(find.byKey(const ValueKey('btn-pick-backup')));
      await settle5(tester);

      expect(find.byKey(const ValueKey('restore-scope-note')), findsNothing);
      expect(find.text('恢复将替换当前数据'), findsOneWidget);
      expect(find.text('恢复整库'), findsOneWidget);
      await clearToasts(tester);
    });

    testWidgets('scope 认不出的模块 id → 校验态直接报范围无法识别，不给恢复钮',
        (tester) async {
      await useSurface(tester, const Size(800, 2400));
      await openSheet(tester);
      fake.pickedPath = '/fake/bad.lhbak';
      fake.inspectResult = LhBakManifest(
        dbVersion: 19,
        appVersion: kAppVersion,
        createdAt: DateTime(2026, 10, 15),
        tables: const {},
        excludedTables: const [],
        encrypted: false,
        members: const ['manifest.json', 'db.sqlite'],
        scope: const {'modules': ['ghost_module_xyz']},
      );
      await tester.tap(find.byKey(const ValueKey('btn-pick-backup')));
      await settle5(tester);

      expect(find.textContaining('范围无法识别'), findsOneWidget);
      expect(find.byKey(const ValueKey('btn-restore')), findsNothing);
      expect(fake.importCalls, 0);
      await clearToasts(tester);
    });
  });
}
