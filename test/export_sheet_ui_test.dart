/// V1.66 批2 ·「导出数据」面板 widget 用例（原型 sheetExport·工单批2 面板）：
/// - 范围 chips 互斥与计数（全部数据 ↔ 模块多选）；
/// - 附可读 Markdown 可用性判定（无笔记类模块置灰＝面板变异刀③）；
/// - 子集 + .lhbak 警示行（切格式随显隐）；
/// - 主钮文案与导出放量（modules/withProjection/withMd 透传）。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/backup/backup_service.dart';
import 'package:lifeharness/core/backup/lh_bak.dart';
import 'package:lifeharness/core/database/schema.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/core/platform/saf_tree.dart';
import 'package:lifeharness/features/settings/presentation/export_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';

/// 23 表展示用 manifest（同 backup_sheet_ui_test 口径）。
LhBakManifest buildManifest() => LhBakManifest(
      dbVersion: DbSchema.version,
      appVersion: kAppVersion,
      createdAt: DateTime(2026, 10, 13, 12),
      tables: const {
        'books': TableStat(rows: 3, checksum: 'a'),
        'habits': TableStat(rows: 0, checksum: '-'),
      },
      excludedTables: const [],
      encrypted: false,
      members: const ['manifest.json', 'db.sqlite'],
    );

class _FakeBackupService extends BackupService {
  _FakeBackupService(this._db, {SharedPreferences? prefs})
      : super(
            exportDir: () => '/tmp/fake_export',
            db: () => _db(),
            prefs: prefs);

  final Future<Database> Function() _db;

  int exportCalls = 0;
  List<String>? lastModules;
  bool? lastWithProjection;
  bool? lastWithMd;
  bool? lastWithAttachments;
  Object? exportError;

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
  }) async {
    exportCalls++;
    if (exportError != null) throw exportError!;
    lastModules = List.of(modules);
    lastWithProjection = withProjection;
    lastWithMd = withMd;
    lastWithAttachments = withAttachments;
    return LhBakCreateResult(
        File('/fake/lifeharness_20261013_120000.lhbak'), buildManifest());
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late _FakeBackupService fake;
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('export_sheet_ui_');
    fake = _FakeBackupService(() async => databaseFactoryFfi.openDatabase(
          inMemoryDatabasePath,
          options: OpenDatabaseOptions(
            version: DbSchema.version,
            onCreate: (d, v) async {
              for (final sql in DbSchema.createStatements) {
                await d.execute(sql);
              }
            },
          ),
        ));
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    try {
      temp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<void> pumpSheet(WidgetTester tester) async {
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        backupServiceProvider.overrideWithValue(fake),
      ],
      child: const MaterialApp(home: Scaffold(body: ExportSheet())),
    ));
    await settle5(tester);
  }

  /// 预估跑在真异步（sqflite ffi 走独立 isolate）：runAsync 跳出 FakeAsync
  /// 让真实 isolate 消息回流，再推帧让 setState 上屏。时长放宽防 ffi 冷启。
  Future<void> flush(WidgetTester tester) async {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 800)));
    await settle5(tester);
  }

  testWidgets('默认态＝全部数据：chips 全不选、md 可用、无警示行、主钮「导出备份」',
      (tester) async {
    await pumpSheet(tester);
    await flush(tester);
    // 「全部数据」两处＝范围 chip 与底部汇总行同文案。
    expect(find.text('全部数据'), findsWidgets);
    expect(find.text('全部模块'), findsOneWidget);
    expect(find.byKey(const ValueKey('ex-scope-warn')), findsNothing);
    expect(find.text('导出备份'), findsOneWidget);
  });

  testWidgets('chips 互斥与计数：全部→单选模块→再点取消＝计数随动（面板变异刀①UI 面）',
      (tester) async {
    await pumpSheet(tester);
    await tester.tap(find.byKey(const ValueKey('ex-chip-read')));
    await settle5(tester);
    await flush(tester);
    expect(find.text('已选 1 个模块'), findsOneWidget);
    expect(find.byKey(const ValueKey('ex-scope-warn')), findsOneWidget);
    // 子集+lhbak → 主钮「导出」
    expect(find.text('导出'), findsOneWidget);

    // 再加一个模块＝多选累加（模块间互斥只对「全部数据」成立）。
    await tester.tap(find.byKey(const ValueKey('ex-chip-habit')));
    await settle5(tester);
    await flush(tester);
    expect(find.text('已选 2 个模块'), findsOneWidget);

    // 点「全部数据」回默认。
    await tester.tap(find.byKey(const ValueKey('ex-chip-all')));
    await settle5(tester);
    await flush(tester);
    expect(find.text('全部模块'), findsOneWidget);
    expect(find.byKey(const ValueKey('ex-scope-warn')), findsNothing);
  });

  testWidgets('md 开关可用性判定：无笔记类模块置灰且不出 toast 误放行（面板变异刀③）',
      (tester) async {
    await pumpSheet(tester);
    // 记账无笔记类数据 → md 行置灰（Switch 拒开）。
    await tester.tap(find.byKey(const ValueKey('ex-chip-ledger')));
    await settle5(tester);
    await flush(tester);
    final sw = tester.widget<SwitchListTile>(
        find.byKey(const ValueKey('ex-md-tgl')));
    expect(sw.onChanged, isNotNull); // 仍在（点它出实话 toast）
    // 点开关：拒开并出实话。
    await tester.tap(find.byKey(const ValueKey('ex-md-tgl')));
    await settle5(tester);
    expect(find.text('所选模块无笔记类数据，Markdown 投影不可用'), findsOneWidget);
    // 值没被打开（value 仍 false——置灰态由 value && available 合成）。
    final sw2 = tester.widget<SwitchListTile>(
        find.byKey(const ValueKey('ex-md-tgl')));
    expect(sw2.value, isFalse);
  });

  testWidgets('切「可读目录」档：警示行收起、主钮「导出」', (tester) async {
    await pumpSheet(tester);
    await tester.tap(find.byKey(const ValueKey('ex-chip-read')));
    await settle5(tester);
    expect(find.byKey(const ValueKey('ex-scope-warn')), findsOneWidget);
    await tester.tap(find.text('可读目录 md+csv+json'));
    await settle5(tester);
    await flush(tester);
    expect(find.byKey(const ValueKey('ex-scope-warn')), findsNothing);
  });

  testWidgets('主钮放量：modules/withProjection/withMd 透传，导出后收面板',
      (tester) async {
    // 阅读模块先有数据（内存库 singleInstance 跨连接共享）——空态会禁用主钮。
    // ffi 是真异步 isolate：seed 必须包 runAsync，否则 FakeAsync 里永久挂起
    // 且堵死共享连接队列（连带后续用例的预估查询全部无响应）。
    await tester.runAsync(() async {
      final seed =
          await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await seed.insert(DbSchema.tBooks,
          {'id': 'b1', 'title': '书', 'created_at': 0, 'updated_at': 0});
    });
    await pumpSheet(tester);
    await tester.tap(find.byKey(const ValueKey('ex-chip-read')));
    await settle5(tester);
    await flush(tester);
    await tester.tap(find.byKey(const ValueKey('ex-go')));
    await pollText(tester, '已导出：lifeharness_20261013_120000.lhbak');
    expect(fake.exportCalls, 1);
    expect(fake.lastModules, ['read']);
    expect(fake.lastWithProjection, isTrue);
    expect(fake.lastWithMd, isTrue);
    expect(fake.lastWithAttachments, isTrue);
    await clearToasts(tester);
  });

  testWidgets('空态：所选模块无数据 → 主钮禁用＋「所选范围暂无数据」', (tester) async {
    await pumpSheet(tester);
    // 内存库跨用例共享且 schema 自带种子行（habit_dict 等）——选零种子的
    // AI 记录模块（ai_calls 无种子）才能命中空态。
    await tester.tap(find.byKey(const ValueKey('ex-chip-ai')));
    await settle5(tester);
    // 预估链是真实异步（快照 VACUUM＋gzip 实测，ffi 冷启可能超一秒）：
    // 有界轮询等空态行出现，不做一次性 flush 假设。
    for (var i = 0;
        i < 20 &&
            find.text('所选范围暂无数据').evaluate().isEmpty;
        i++) {
      await tester
          .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await settle5(tester);
    }
    expect(find.text('所选范围暂无数据'), findsOneWidget);
    final btn = tester.widget<FilledButton>(
        find.byKey(const ValueKey('ex-go')));
    expect(btn.onPressed, isNull);
  });

  group('④ 导出位置（V1.66 装机回知批·原型同步）', () {
    Future<void> pumpSheetWith(WidgetTester tester, _FakeBackupService svc) async {
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          backupServiceProvider.overrideWithValue(svc),
        ],
        child: const MaterialApp(home: Scaffold(body: ExportSheet())),
      ));
      await settle5(tester);
    }

    String richTexts(WidgetTester tester) => tester
        .widgetList<RichText>(find.byType(RichText))
        .map((r) => r.text.toPlainText())
        .join('\n');

    testWidgets('默认态＝「默认 · 应用目录」；选目录后显示人话名并持久化', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final svc = _FakeBackupService(fake._db, prefs: prefs);
      final oldPick = safPickTree;
      safPickTree = () async =>
          'content://com.android.externalstorage.documents/tree/primary%3ADownload%2FlifeHarness';
      addTearDown(() => safPickTree = oldPick);
      await pumpSheetWith(tester, svc);
      await flush(tester);
      expect(richTexts(tester), contains('默认 · 应用目录'));

      await tester.tap(find.byKey(const ValueKey('ex-loc-row')));
      await settle5(tester);
      expect(richTexts(tester), contains('Download/lifeHarness'));
      expect(svc.exportTreeName, 'Download/lifeHarness');
      expect(svc.exportTreeUri, contains('tree/primary'));
    });

    testWidgets('导出直达：设位置后主钮导出 → 包拷入目录树（zip 档·原名）', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final svc = _FakeBackupService(fake._db, prefs: prefs);
      await svc.setExportTree(
          'content://com.android.externalstorage.documents/tree/primary%3ADownload%2FlifeHarness');
      final oldCreate = safCreateInTree;
      String? gotTree, gotName, gotSrc, gotMime;
      safCreateInTree = (
              {required String tree,
              required String relPath,
              required String name,
              required String text,
              String mime = 'text/markdown',
              String srcPath = ''}) async {
        gotTree = tree;
        gotName = name;
        gotSrc = srcPath;
        gotMime = mime;
        return const MountWriteResult(
            code: 'ok',
            name: 'lifeharness_20261013_120000.lhbak',
            localPath: 'Download/lifeHarness');
      };
      addTearDown(() => safCreateInTree = oldCreate);
      await pumpSheetWith(tester, svc);
      await flush(tester);
      await tester.tap(find.byKey(const ValueKey('ex-go')));
      expect(
          await pollText(tester,
              '已导出：lifeharness_20261013_120000.lhbak · Download/lifeHarness'),
          isTrue);
      expect(gotTree, contains('tree/primary'));
      expect(gotName, 'lifeharness_20261013_120000.lhbak');
      expect(gotSrc, '/fake/lifeharness_20261013_120000.lhbak');
      expect(gotMime, 'application/zip');
      await clearToasts(tester);
    });
  });
}
