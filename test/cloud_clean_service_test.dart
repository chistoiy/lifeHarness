/// R5d：CloudCleanService 云端孤儿判定/归档/删除/自动钩子验收。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/logging/app_log.dart';
import 'package:lifeharness/core/media/media_usage_scanner.dart';
import 'package:lifeharness/core/sync/cloud_clean_service.dart';
import 'package:lifeharness/core/sync/remote_store.dart';
import 'package:lifeharness/core/sync/service_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeScanner implements MediaUsageScanner {
  _FakeScanner(this.text);
  String text;
  @override
  Future<String> referenceText() async => text;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('MediaUsageScanner.${invocation.memberName}');
}

class _FakeStore implements RemoteStore {
  _FakeStore(this.files);
  CloudListing files;
  final List<(String, String)> moves = [];
  final List<String> deletes = [];
  int listCalls = 0;

  /// 指名让某条 move/delete 抛错（进度必须照推进，失败≠没耗时）。
  final Set<String> throwOn = {};

  @override
  Future<CloudListing> list(ServiceConfig c, String dir,
      {bool force = false}) async {
    listCalls++;
    return files;
  }

  @override
  Future<void> move(ServiceConfig c, String from, String to) async {
    if (throwOn.contains(from)) throw Exception('boom');
    moves.add((from, to));
  }

  @override
  Future<void> delete(ServiceConfig c, String rel) async {
    if (throwOn.contains(rel)) throw Exception('boom');
    deletes.add(rel);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('RemoteStore.${invocation.memberName}');
}

void main() {
  late SharedPreferences prefs;
  late ServiceConfig cfg;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    cfg = ServiceConfig(id: 's1', cloudDirName: 'lh');
    AppLog.reset();
  });
  tearDown(() => AppLog.reset());

  FileEntry fe(String rel, {int size = 10, DateTime? m}) =>
      FileEntry(relativePath: rel, size: size, modified: m);

  CloudCleanService svc(MediaUsageScanner sc) =>
      CloudCleanService(prefs: prefs, scanner: sc);

  test('cloudOrphans：仅 attachments/ 前缀且 basename 未命中引用；归档区豁免；force 拉取',
      () async {
    final store = _FakeStore(CloudListing([
      fe('attachments/note_images/used.jpg'),
      fe('attachments/note_images/free.jpg'),
      fe('sync_20260925.lhbak'),
      fe('media_archive/attachments/old.jpg'),
    ]));
    final r = await svc(_FakeScanner('文中含 used.jpg 不含别的'))
        .cloudOrphans(store, cfg);
    expect(r.map((e) => e.relativePath), ['attachments/note_images/free.jpg']);
    expect(store.listCalls, 1);
  });

  test('archive：move 到 media_archive/ 前缀；单条失败不中断计数', () async {
    final store = _FakeStore(CloudListing([]));
    final r = await svc(_FakeScanner('')).archive(store, cfg,
        [fe('attachments/a.jpg'), fe('attachments/b.jpg')]);
    expect(store.moves, [
      ('attachments/a.jpg', 'media_archive/attachments/a.jpg'),
      ('attachments/b.jpg', 'media_archive/attachments/b.jpg'),
    ]);
    expect(r, 2);
  });

  test('autoCleanAfterSync：开关关 → 零动作；开 → 归档孤儿；30天清理叠加只删归档区超期',
      () async {
    final store = _FakeStore(CloudListing([
      fe('attachments/free.jpg'),
      fe('media_archive/attachments/old.jpg',
          m: DateTime.utc(2026, 8, 1)),
      fe('media_archive/attachments/new.jpg',
          m: DateTime.utc(2026, 9, 20)),
    ]));
    final s = svc(_FakeScanner('无引用'));
    // 默认关：零请求零动作。
    await s.autoCleanAfterSync(store, cfg);
    expect(store.listCalls, 0);
    expect(store.moves, isEmpty);

    await prefs.setBool(CloudCleanService.kAutoArchive, true);
    await s.autoCleanAfterSync(store, cfg);
    expect(store.moves.length, 1); // 只归档 attachments/free.jpg
    expect(store.deletes, isEmpty); // 未开 30 天清理

    await prefs.setBool(CloudCleanService.kArchivePurge30, true);
    store.moves.clear();
    await s.autoCleanAfterSync(store, cfg, now: DateTime.utc(2026, 9, 25));
    expect(store.deletes, ['media_archive/attachments/old.jpg'],
        reason: '仅归档区超 30 天条目被删，new.jpg 保留');
  });

  // 真机反馈轮③：批量几十条期间屏面「像卡死」＝没进度没取消。服务侧必须逐条
  // 回报进度（失败条也推进度：失败≠没耗时），并在当前条落定后按取消停手。
  test('archive/purge：逐条进度（含失败条）· 取消在当前条之后停手', () async {
    final store = _FakeStore(CloudListing([]));
    final s = svc(_FakeScanner(''));
    final prog = <int>[];
    final n = await s.archive(
        store, cfg, [fe('attachments/a.jpg'), fe('attachments/b.jpg')],
        onProgress: (d, t) {
      expect(t, 2, reason: '总数一次给全，UI 才能画比例条');
      prog.add(d);
    });
    expect(prog, [1, 2]);
    expect(n, 2);

    // 中间一条失败：成功数少一，进度仍走满。
    store.throwOn.add('attachments/b.jpg');
    final prog2 = <int>[];
    final n2 = await s.archive(
        store, cfg, [fe('attachments/a.jpg'), fe('attachments/b.jpg')],
        onProgress: (d, _) => prog2.add(d));
    expect(prog2, [1, 2], reason: '失败条也计入已完成，进度条不许倒退或卡住');
    expect(n2, 1);

    // 取消：第 2 条落定后请求停 → 第 3 条不再发出。
    final store2 = _FakeStore(CloudListing([]));
    final prog3 = <int>[];
    final n3 = await svc(_FakeScanner('')).purge(
        store2, cfg,
        [fe('x.jpg'), fe('y.jpg'), fe('z.jpg')],
        onProgress: (d, _) => prog3.add(d),
        cancelRequested: () => store2.deletes.length >= 2);
    expect(store2.deletes, ['x.jpg', 'y.jpg'], reason: '取消后剩余条目不动');
    expect(n3, 2);
    expect(prog3, [1, 2]);
  });
}
