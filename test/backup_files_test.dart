import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/backup/backup_files.dart';
import 'package:lifeharness/core/logging/app_log.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/settings/presentation/backup_files_page.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

/// B-1 备份文件管理屏（工单＝交棒话术-20261004-备份管理与图片预览批 §2 B-1／§11）。
///
/// 两层分开：数据层跑**真临时目录**（浅层扫描/来源判定/物理删除只能实测）；
/// 屏层注入 fake 扫描器（真实文件 I/O 不进 widget 测试红线）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('数据层：exports/ 浅层扫描与来源三档', () {
    late Directory tmp;
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      tmp = await Directory.systemTemp.createTemp('lh_b1_');
    });
    tearDown(() async => tmp.delete(recursive: true));

    Future<void> mk(String name, int bytes, DateTime mtime) async {
      final f = File(p.join(tmp.path, name));
      await f.writeAsBytes(List<int>.filled(bytes, 0));
      await f.setLastModified(mtime);
    }

    test('三档来源判定与排序：auto 前缀／下载台账＝云端／其余＝本地', () async {
      await mk('lifeharness_20261006_0830.lhbak', 1024,
          DateTime(2026, 10, 6, 8, 30));
      await mk('cloud_pull_20261004.lhbak', 2048, DateTime(2026, 10, 4, 21, 2));
      await mk('auto_before_restore_20261003_191500.lhbak', 4096,
          DateTime(2026, 10, 3, 19, 15));
      await BackupFileScanner.markDownloaded(prefs, 'cloud_pull_20261004.lhbak');

      final list =
          await BackupFileScanner(dir: tmp.path, prefs: prefs).scan();
      expect(
          list.map((e) => e.name),
          [
            'lifeharness_20261006_0830.lhbak',
            'cloud_pull_20261004.lhbak',
            'auto_before_restore_20261003_191500.lhbak',
          ],
          reason: 'mtime 倒序（最近一次备份在最上）');
      expect(
          list.map((e) => e.source.label), ['本地导出', '云端下载', '恢复前自动']);
      expect(list.first.timeText, '10-06 08:30');
    });

    test('非 .lhbak 与子目录不进列表（只扫浅层）', () async {
      await mk('keep.lhbak', 1024, DateTime(2026, 10, 5));
      await mk('note.txt', 10, DateTime(2026, 10, 5));
      Directory(p.join(tmp.path, 'sub')).createSync();
      File(p.join(tmp.path, 'sub', 'deep.lhbak')).writeAsBytesSync([0]);
      final list = await BackupFileScanner(dir: tmp.path, prefs: prefs).scan();
      expect(list.map((e) => e.name), ['keep.lhbak']);
    });

    test('目录不存在＝空清单（首启没有导出记录，不许抛）', () async {
      final list = await BackupFileScanner(
              dir: p.join(tmp.path, 'nope'), prefs: prefs)
          .scan();
      expect(list, isEmpty);
    });

    test('purge＝物理删（文件真没了）并回报释放字节；缺失路径跳过不抛', () async {
      await mk('a.lhbak', 3000, DateTime(2026, 10, 5));
      await mk('b.lhbak', 1000, DateTime(2026, 10, 4));
      final sc = BackupFileScanner(dir: tmp.path, prefs: prefs);
      final freed = await sc.purge(
          [p.join(tmp.path, 'a.lhbak'), p.join(tmp.path, 'gone.lhbak')]);
      expect(freed, 3000);
      expect(File(p.join(tmp.path, 'a.lhbak')).existsSync(), isFalse);
      expect(File(p.join(tmp.path, 'b.lhbak')).existsSync(), isTrue,
          reason: '只删点名的包，其余不许被牵连');
    });

    test('下载台账有上限（只服务角标，不无界增长）', () async {
      for (var i = 0; i < BackupFileScanner.maxLedger + 25; i++) {
        await BackupFileScanner.markDownloaded(prefs, 'f$i.lhbak');
      }
      final kept = BackupFileScanner.downloadedNames(prefs);
      expect(kept.length, lessThanOrEqualTo(BackupFileScanner.maxLedger));
      expect(kept.contains('f${BackupFileScanner.maxLedger + 24}.lhbak'), isTrue,
          reason: '新名必留，先出账的是最旧的');
    });
  });

  group('屏层：清单渲染·后果确认·批量选择·空态', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    List<BackupFileEntry> seed() => [
          BackupFileEntry(
              path: '/x/a.lhbak',
              name: 'a.lhbak',
              bytes: 16112543,
              mtime: DateTime(2026, 10, 6, 8, 30),
              source: BackupFileSource.local),
          BackupFileEntry(
              path: '/x/b.lhbak',
              name: 'b.lhbak',
              bytes: 15874021,
              mtime: DateTime(2026, 10, 4, 21, 2),
              source: BackupFileSource.cloud),
          BackupFileEntry(
              path: '/x/auto_before_restore_1.lhbak',
              name: 'auto_before_restore_1.lhbak',
              bytes: 15204887,
              mtime: DateTime(2026, 10, 3, 19, 15),
              source: BackupFileSource.auto),
        ];

    Widget app(_FakeScanner sc) => ProviderScope(
          overrides: [backupFileScannerProvider.overrideWithValue(sc)],
          child: const MaterialApp(home: BackupFilesPage()),
        );

    testWidgets('三行在册：三档角标·合计由逐行字节算出·次通道常驻', (tester) async {
      await tester.pumpWidget(app(_FakeScanner(seed(), prefs)));
      await settle5(tester);
      final head = tester.widget<RichText>(find
          .descendant(of: find.byKey(const ValueKey('bk-head')), matching: find.byType(RichText)))
          .text.toPlainText();
      expect(head, contains('3 包'));
      expect(head, contains('合计 45.0 MB'),
          reason: '屏头合计必须由逐行字节算出（不写死）');
      // 行内副行是 Text.rich（来源角标要着色），find.text 取不到 span → 统一收平文本再判
      final all = tester
          .widgetList<RichText>(find.byType(RichText))
          .map((r) => r.text.toPlainText())
          .join('\n');
      for (final lab in ['本地导出', '云端下载', '恢复前自动']) {
        expect(all, contains(lab));
      }
      expect(find.byKey(const ValueKey('bk-row-a.lhbak')), findsOneWidget);
      expect(find.text('从其他位置选择'), findsOneWidget);
    });

    // 真机 6078 走查抓的驻留缺陷：日志明明记着「备份导出成功：lifeharness_…lhbak」，
    // 本屏当场与重进都仍是「0 包」＝`backupFilesProvider` 的值跨屏驻留，
    // 不失效就得冷启动才看得见新包。进屏即失效重扫才是对的。
    testWidgets('进屏即重扫：屏外新导出的包不必冷启动就该出现', (tester) async {
      final sc = _FakeScanner([seed().first], prefs);
      final container = ProviderContainer(
          overrides: [backupFileScannerProvider.overrideWithValue(sc)]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
              home: Builder(
                  builder: (c) => Scaffold(
                          body: Center(
                              child: ElevatedButton(
                        key: const ValueKey('go'),
                        onPressed: () => Navigator.push(
                            c,
                            MaterialPageRoute(
                                builder: (_) => const BackupFilesPage())),
                        child: const Text('go'),
                      )))))));

      int rowCount() => tester
          .widgetList(find.byWidgetPredicate((w) =>
              w.key is ValueKey &&
              '${(w.key as ValueKey).value}'.startsWith('bk-row-')))
          .length;

      await tester.tap(find.byKey(const ValueKey('go')));
      await settle5(tester);
      expect(rowCount(), 1, reason: '首进＝替身里那一枚包');
      await tester.pageBack();
      await settle5(tester);

      // 屏外又导出两枚（替身清单变三枚），再进一次屏。
      sc.list = seed();
      await tester.tap(find.byKey(const ValueKey('go')));
      await settle5(tester);
      expect(rowCount(), 3,
          reason: '进屏必须重扫——不失效就会假绿地停在 1 行（真机症状原样）');
      await clearToasts(tester);
    });

    testWidgets('删除单条＝先出后果（物理删·不进回收站），确认后才真删并回报',
        (tester) async {
      final sc = _FakeScanner(seed(), prefs);
      await tester.pumpWidget(app(sc));
      await settle5(tester);
      await tester.tap(find.byKey(const ValueKey('bk-del-a.lhbak')));
      await settle5(tester);
      expect(find.textContaining('物理删除 · 不进回收站 · 不可恢复'), findsOneWidget);
      expect(find.textContaining('回滚资产'), findsNothing, reason: '普通包不吓用户');
      await tester.tap(find.byKey(const ValueKey('d-confirm-ok')));
      await settle5(tester);
      expect(sc.purged, ['/x/a.lhbak']);
      expect(
          find.textContaining('已彻底删除 1 个备份文件 · 15.4 MB 已释放'), findsOneWidget);
      await clearToasts(tester);
    });

    testWidgets('删到「恢复前自动」＝另出回滚资产警示；取消则一个字都不删',
        (tester) async {
      final sc = _FakeScanner(seed(), prefs);
      await tester.pumpWidget(app(sc));
      await settle5(tester);
      await tester.tap(
          find.byKey(const ValueKey('bk-del-auto_before_restore_1.lhbak')));
      await settle5(tester);
      expect(find.textContaining('回滚资产'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('d-confirm-cancel')));
      await settle5(tester);
      expect(sc.purged, isEmpty);
    });

    testWidgets('选择态：行内钮收起·可勾选·全选后「删除 N 项」批量一次确认',
        (tester) async {
      final sc = _FakeScanner(seed(), prefs);
      await tester.pumpWidget(app(sc));
      await settle5(tester);
      await tester.tap(find.byKey(const ValueKey('bk-pick')));
      await settle5(tester);
      expect(find.byKey(const ValueKey('bk-del-a.lhbak')), findsNothing,
          reason: '批量态只留一套入口');
      expect(find.byKey(const ValueKey('bk-pick-a.lhbak')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('bk-all')));
      await settle5(tester);
      expect(find.text('删除 3 项'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('bk-del-batch')));
      await settle5(tester);
      expect(find.textContaining('共 3 个文件 · 45.0 MB'), findsOneWidget);
      expect(find.textContaining('其中 1 个是恢复前自动备份'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('d-confirm-ok')));
      await settle5(tester);
      expect(sc.purged.length, 3);
      await clearToasts(tester);
    });

    testWidgets('空态＝虚线行定式，次通道仍在；空列表不给批量入口', (tester) async {
      await tester.pumpWidget(app(_FakeScanner(const [], prefs)));
      await settle5(tester);
      expect(find.byKey(const ValueKey('bk-empty')), findsOneWidget);
      expect(find.text('暂无备份文件'), findsOneWidget);
      expect(find.text('从其他位置选择'), findsOneWidget);
      expect(
          tester
              .widget<TextButton>(find.byKey(const ValueKey('bk-pick')))
              .onPressed,
          isNull,
          reason: '空列表不给批量入口（钮置灰而不是消失，避免布局跳）');
    });

    testWidgets('删除落 key 行（日志页要能复盘删了什么）', (tester) async {
      final sc = _FakeScanner(seed(), prefs);
      await tester.pumpWidget(app(sc));
      await settle5(tester);
      await tester.tap(find.byKey(const ValueKey('bk-del-b.lhbak')));
      await settle5(tester);
      await tester.tap(find.byKey(const ValueKey('d-confirm-ok')));
      await settle5(tester);
      expect(AppLog.lines.any((l) =>
              l.key &&
              l.text.contains('备份文件删除：1 个') &&
              l.text.contains('b.lhbak')),
          isTrue);
      await drainLogTimer(tester);
      await clearToasts(tester);
    });

    testWidgets('行内恢复只走 S5 校验链；入口行与路由在册', (tester) async {
      // 源码守护：本屏不得自己调 importBackup／不得另造校验 UI（工单 §3 红线）。
      final src =
          File('lib/features/settings/presentation/backup_files_page.dart')
              .readAsStringSync();
      expect(src, contains('showBackupSheet(context, restorePath: e.path)'));
      expect(src, isNot(contains('importBackup')),
          reason: '校验·口令·二次确认只在 S5 一处');
      final sp = File('lib/features/settings/presentation/sync_page.dart')
          .readAsStringSync();
      expect(sp, contains("'/settings/backup-files'"));
      final rt = File(
              'lib/features/settings/presentation/settings_routes.dart')
          .readAsStringSync();
      expect(rt, contains("path: '/settings/backup-files'"));
    });
  });
}

/// 屏层替身：清单可换、purge 只记账（真 I/O 已在数据层组覆盖）。
class _FakeScanner extends BackupFileScanner {
  _FakeScanner(this.list, SharedPreferences prefs)
      : super(dir: '/nonexistent-lh-b1', prefs: prefs);

  /// 可变清单＝模拟「别的入口刚导出／下载了新包」。
  List<BackupFileEntry> list;
  final List<String> purged = [];

  @override
  Future<List<BackupFileEntry>> scan() async => list;

  @override
  Future<int> purge(List<String> paths) async {
    purged.addAll(paths);
    return paths.fold<int>(
        0, (t, path) => t + list.firstWhere((e) => e.path == path).bytes);
  }
}
