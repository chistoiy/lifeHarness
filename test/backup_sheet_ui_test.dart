/// Task 10：S5 备份半屏 + /sync 空壳页 widget 验收测试（对照原型 s-backup）。
///
/// 纪律：①本地极简 GoRouter 打开 `/sync`（模式照 test/log_page_test.dart，
/// 不拉全 app）；②服务经 `backupServiceProvider.overrideWithValue(fake)` 注入
/// ——断言 exportBackup/importBackup/saveCopyToUserLocation/pickBackupFile
/// 调用次数（导入按钮在勾选二次确认前 0 次、确认后恰 1 次）；
/// ③SnackBar 断言一律 pollText 命中后再走（helpers 铁律）；④导入报告卡必须
/// 展示 manifest.skippedLarge（功能标签式「N 个超大附件未入包」）。
library;

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
  int saveCopyCalls = 0;
  int inspectCalls = 0;
  int pickCalls = 0;

  /// 非 null 时 pickBackupFile 抛出它（20261004 缺陷回归：选择器异常必须可见）。
  Object? pickError;

  String? lastPassphrase;
  bool? lastWithLogs;
  bool? lastWithAttachments;

  String? pickedPath;
  String? saveCopyResult;
  LhBakManifest? inspectResult;
  Object? inspectError;
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
  }) async {
    exportCalls++;
    lastPassphrase = passphrase;
    lastWithLogs = withLogs;
    lastWithAttachments = withAttachments;
    return LhBakCreateResult(
        File('/fake/lifeharness_20260925_101500.lhbak'),
        inspectResult ?? buildManifest());
  }

  @override
  Future<LhBakManifest> inspect(String filePath, {String? passphrase}) async {
    inspectCalls++;
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
  Future<String?> saveCopyToUserLocation(String srcPath) async {
    saveCopyCalls++;
    return saveCopyResult;
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
    testWidgets('半屏含附件/日志勾选 · 口令二次输入 · 导出/另存并列动作钮（R6）',
        (tester) async {
      await useSurface(tester, const Size(800, 2400));
      await openSheet(tester);

      expect(find.text('备份导出/导入'), findsWidgets);
      expect(find.text('导出范围'), findsOneWidget);
      expect(find.text('附件 attachments/'), findsOneWidget);
      expect(find.text('附带日志 logs/'), findsOneWidget);
      expect(find.text('口令 · 可选（二次输入一致才启用）'), findsOneWidget);
      expect(find.byKey(const ValueKey('btn-export')), findsOneWidget);
      expect(find.text('另存到…'), findsOneWidget);
      expect(find.byKey(const ValueKey('btn-export-save')), findsOneWidget);
      // R6：目标位置两态选择行已删（点钮即动作）
      expect(find.text('目标位置'), findsNothing);

      // 勾选参数透传：取消「附带日志」→ withLogs=false
      await tester.tap(find.byKey(const ValueKey('chk-logs')));
      await settle5(tester);
      await tester.tap(find.byKey(const ValueKey('btn-export')));
      await pollText(tester, '已导出：lifeharness_20260925_101500.lhbak');
      expect(fake.exportCalls, 1);
      expect(fake.lastWithLogs, isFalse);
      expect(fake.lastWithAttachments, isTrue);
      expect(fake.lastPassphrase, isNull);
      expect(fake.saveCopyCalls, 0); // 「导出备份」钮不触发改存对话
      await clearToasts(tester);
    });

    testWidgets('口令不一致拒绝导出 · 一致后 passphrase 透传', (tester) async {
      await useSurface(tester, const Size(800, 2400));
      await openSheet(tester);
      await tester.enterText(
          find.byKey(const ValueKey('pass-1')), 'abc123');
      await tester.enterText(
          find.byKey(const ValueKey('pass-2')), 'abc124');
      await tester.tap(find.byKey(const ValueKey('btn-export')));
      await settle5(tester);
      expect(find.text('口令两次输入不一致'), findsOneWidget);
      expect(fake.exportCalls, 0);

      await tester.enterText(
          find.byKey(const ValueKey('pass-2')), 'abc123');
      await tester.tap(find.byKey(const ValueKey('btn-export')));
      await pollText(tester, '已导出：lifeharness_20260925_101500.lhbak');
      expect(fake.exportCalls, 1);
      expect(fake.lastPassphrase, 'abc123');
      await clearToasts(tester);
    });

    testWidgets('R6 另存到…钮一步到位：点即导出+弹层；取消 → 不触发任何后续调用',
        (tester) async {
      await useSurface(tester, const Size(800, 2400));
      await openSheet(tester);

      fake.saveCopyResult = null; // fake dialog 取消
      await tester.tap(find.byKey(const ValueKey('btn-export-save')));
      await pollText(tester, '已导出：lifeharness_20260925_101500.lhbak');
      expect(find.text('另存已取消 · 包保留在应用导出目录'), findsOneWidget);
      expect(fake.exportCalls, 1);
      expect(fake.saveCopyCalls, 1); // 无需再点「导出备份」
      expect(fake.importCalls, 0); // 取消不触发任何恢复类调用
      await clearToasts(tester);

      // 另存成功：展示落点文件名
      fake.saveCopyResult = r'/storage/emulated/0/Download/saved.lhbak';
      await tester.tap(find.byKey(const ValueKey('btn-export-save')));
      await pollText(tester, '已另存：saved.lhbak');
      expect(fake.saveCopyCalls, 2);
      await clearToasts(tester);
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
}
