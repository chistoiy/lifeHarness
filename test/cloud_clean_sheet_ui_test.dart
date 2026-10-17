/// 真机反馈轮③ · S7 清理云端半屏 widget 用例（全选 / 进度 / 取消）。
///
/// 报障原文：「清理云端没办法全选」「点击彻底删除后没有进度，直接堵塞页面，
/// 等待删完才能后续操作」。根因＝这屏从来没做全选入口，且批量执行期只把
/// `_busy` 置真（全控件禁用）却没有任何进度与取消出口。
///
/// 纪律：①服务层全 fake（store/scanner/prefs 走 override，零网络零磁盘）；
/// ②「进行中」UI 用手动 Completer 钉住第一条动作（禁 pumpAndSettle，既定坑）；
/// ③SnackBar 断言先 pollText 命中再 clearToasts 清场。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/media/media_usage_scanner.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/core/sync/cloud_clean_service.dart';
import 'package:lifeharness/core/sync/remote_store.dart';
import 'package:lifeharness/core/sync/service_config.dart';
import 'package:lifeharness/core/sync/sync_providers.dart';
import 'package:lifeharness/features/settings/presentation/widgets/sync_sheets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

class _FakeScanner implements MediaUsageScanner {
  @override
  Future<String> referenceText() async => '没有任何引用';
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('MediaUsageScanner.${invocation.memberName}');
}

/// 云端清单＝三条 attachments 孤儿；每条动作可被 [gate] 钉在第一条上，
/// 让「进行中」的 UI 有稳定观察窗口（否则异步瞬间跑完，测不到进度面）。
class _FakeStore implements RemoteStore {
  _FakeStore(this.files);

  final List<FileEntry> files;
  final moves = <String>[];
  final deletes = <String>[];
  Completer<void>? gate;
  int _steps = 0;

  Future<void> _step(String rel, List<String> log) async {
    _steps++;
    if (_steps == 1 && gate != null) await gate!.future;
    log.add(rel);
  }

  @override
  Future<CloudListing> list(ServiceConfig c, String dir,
          {bool force = false}) async =>
      CloudListing(files);

  @override
  Future<void> move(ServiceConfig c, String from, String to) =>
      _step(from, moves);

  @override
  Future<void> delete(ServiceConfig c, String rel) => _step(rel, deletes);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('RemoteStore.${invocation.memberName}');
}

final cfg = ServiceConfig(id: 's1', cloudDirName: 'lh');

final orphans = [
  FileEntry(relativePath: 'attachments/note_images/a.jpg', size: 1048576),
  FileEntry(relativePath: 'attachments/note_images/b.jpg', size: 1048576),
  FileEntry(relativePath: 'attachments/book_covers/c.jpg', size: 1048576),
];

Future<ProviderContainer> boot(WidgetTester tester, RemoteStore store,
    SharedPreferences prefs) async {
  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    cloudCleanServiceProvider
        .overrideWithValue(CloudCleanService(prefs: prefs, scanner: _FakeScanner())),
    remoteStoreFactoryProvider.overrideWithValue((c) => store),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Builder(builder: (bc) => Scaffold(
              body: Center(
                  child: ElevatedButton(
                key: const ValueKey('open'),
                onPressed: () => showCloudCleanSheet(bc, config: cfg),
                child: const Text('open'),
              )),
            )))));
  await tester.tap(find.byKey(const ValueKey('open')));
  await settle5(tester);
  return container;
}

void main() {
  late SharedPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  testWidgets('屏头给条数与体积合计 · 「全选」一次勾满，再点取消全选', (tester) async {
    final store = _FakeStore(orphans);
    await boot(tester, store, prefs);

    expect(find.byKey(const ValueKey('cc-head')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('cc-head'))).data,
        '未引用 3 个 · 3.0 MB',
        reason: '合计由逐行现算，不写死');
    expect(find.byKey(const ValueKey('cc-all')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('cc-all')));
    await tester.pump();
    expect(_checkedCount(tester), 3, reason: '全选＝三条一次勾上');
    // 勾满后钮翻成「取消全选」（Widget 是同一性比较，判文案要用 find.text）。
    expect(find.text('取消全选'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('cc-all')));
    await tester.pump();
    expect(_checkedCount(tester), 0);
    expect(find.text('全选'), findsOneWidget);
    await clearToasts(tester);
  });

  testWidgets('归档执行期有进度条与计数（不再只剩灰屏）· 完成后报数', (tester) async {
    final store = _FakeStore(orphans)..gate = Completer<void>();
    await boot(tester, store, prefs);
    await tester.tap(find.byKey(const ValueKey('cc-all')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('cc-archive')));
    // 第一条动作被 gate 钉住：此刻应看到「归档中 0 / 3」＋进度条＋取消钮。
    await tester.pump();
    expect(find.byKey(const ValueKey('cc-progress')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('cc-progress'))).data,
        '归档中 0 / 3');
    expect(find.byKey(const ValueKey('cc-bar')), findsOneWidget);
    expect(find.byKey(const ValueKey('cc-cancel')), findsOneWidget);
    // 两枚动作钮让位给进度行（执行期不许再点一次）。
    expect(find.byKey(const ValueKey('cc-archive')), findsNothing);

    store.gate!.complete();
    await settle5(tester);
    expect(store.moves.length, 3);
    await pollText(tester, '已归档 3 个文件');
    expect(find.text('已归档 3 个文件'), findsOneWidget);
    await clearToasts(tester);
  });

  testWidgets('彻底删除中途取消：当前条落定即停手，剩余不动并在提示里报余量',
      (tester) async {
    final store = _FakeStore(orphans)..gate = Completer<void>();
    await boot(tester, store, prefs);
    await tester.tap(find.byKey(const ValueKey('cc-all')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('cc-purge')));
    await settle5(tester);
    await tester.tap(find.byKey(const ValueKey('cc-purge-confirm')));
    await tester.pump();
    // 第一条挂起时按「取消」：该条落定后循环停手。
    expect(find.byKey(const ValueKey('cc-cancel')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cc-cancel')));
    store.gate!.complete();
    await settle5(tester);

    expect(store.deletes.length, lessThan(3),
        reason: '取消后剩余条目不再发出请求');
    await pollText(tester, '已取消，剩');
    expect(find.textContaining('已取消，剩'), findsOneWidget);
    await clearToasts(tester);
  });
}

/// 当前勾上的行数（CheckboxListTile.value 直读，别按文案猜）。
int _checkedCount(WidgetTester tester) => tester
    .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
    .where((t) => t.value == true)
    .length;
