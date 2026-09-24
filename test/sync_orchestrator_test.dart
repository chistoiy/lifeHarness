/// Task 17：`SyncOrchestrator` 编排验收测试（串行 / 续传台账 / 取消 /
/// 仅云端下载引导导入 / 历史 100 条）。
///
/// 口径（设计稿 §4.1/§4.2 + 计划钉死）：
/// - compare()：1 次远端 list（60s 清单缓存在 store 内建）+ 本地清单 +
///   台账 knownPaths → computeDiff；忽略规则读 prefs `sync_ignore`
///   （逗号分隔，D5 两侧同时剔除）；
/// - run()：仅本地/已修改 → 上传，**非快照先、`.lhbak` 快照最后**，
///   逐文件成功即 `SyncLedger.record` 单条（「先附件→后DB→成功标记」落法）；
///   仅云端 → 下载到 `<docs>/exports/`，**不自动导入**（台账也不记——
///   台账语义 = 本机上传成功过）；同任务严格串行（调度 R3，并发水位==1）；
///   单任务门闩：running 时再次 run 抛 StateError；
/// - cancel()：置标志，当前文件传完即停、队列清空；
/// - 假 store 抛异常 → 计入 failed、其余继续、run 正常返回（R9 不整任务炸）；
/// - 历史：prefs `sync_history` JSON 数组**头部插入**，上限 100 条，
///   `{ts,serviceId,dir,up,down,bytes,ok,error?}`。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/logging/app_log.dart';
import 'package:lifeharness/core/sync/diff_service.dart';
import 'package:lifeharness/core/sync/remote_store.dart';
import 'package:lifeharness/core/sync/service_config.dart';
import 'package:lifeharness/core/sync/snapshot_service.dart';
import 'package:lifeharness/core/sync/sync_ledger.dart';
import 'package:lifeharness/core/sync/sync_orchestrator.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

FileEntry fe(String path, {int size = 10, String? etag}) =>
    FileEntry(relativePath: path, size: size, etag: etag);

/// 假 store：内存清单 + put/get 记录；[delay] 让并发调用水位可测
/// （若编排器并行发射，maxInflight 会 >1）。
class _FakeStore implements RemoteStore {
  _FakeStore({this.files = const {}, this.onPut});

  /// 远端清单（rel → 条目）；get 会往本地写一条内容可辨识的文件。
  final Map<String, FileEntry> files;
  final Future<void> Function(String rel)? onPut;

  /// 每次 put/get 前的驻留延时：若编排器并行发射，maxInflight 会 >1。
  final Duration delay = const Duration(milliseconds: 2);

  final List<String> putOrder = [];
  final Map<String, String> putLocalPaths = {};
  int inflight = 0;
  int maxInflight = 0;
  bool closed = false;

  Future<void> _track(String rel, Future<void> Function()? hook) async {
    inflight++;
    if (inflight > maxInflight) maxInflight = inflight;
    await Future<void>.delayed(delay);
    try {
      if (hook != null) await hook();
    } finally {
      inflight--;
    }
  }

  @override
  Future<void> put(ServiceConfig c, String localPath, String cloudRelative) async {
    putOrder.add(cloudRelative); // 记录「尝试序」：失败/取消前也留痕
    await _track(cloudRelative, onPut == null ? null : () => onPut!(cloudRelative));
    putLocalPaths[cloudRelative] = localPath;
  }

  @override
  Future<void> get(ServiceConfig c, String cloudRelative, String localPath) async {
    await _track(cloudRelative, null);
    File(localPath)
      ..createSync(recursive: true)
      ..writeAsStringSync('remote-content:$cloudRelative');
  }

  @override
  Future<CloudListing> list(ServiceConfig c, String cloudDirName,
          {bool force = false}) async =>
      CloudListing(files.values.toList());

  @override
  Future<void> ensureDirectory(ServiceConfig c, String cloudRelativeDir) async {}

  @override
  Future<VerifyResult> verify(ServiceConfig c) async => VerifyResult(true);

  @override
  Future<CloudQuota> quota(ServiceConfig c, {bool force = false}) async =>
      CloudQuota();

  @override
  void close() => closed = true;
}

/// 假 SnapshotService：只实装编排器消费的两个成员（syncDir/docsDir/
/// localInventory），其余走 noSuchMethod 哨兵——误用即抛，防假绿。
class _FakeSnap implements SnapshotService {
  _FakeSnap({required this.syncDir, required this.docsDirRoot});

  @override
  final String syncDir;
  final String docsDirRoot;

  @override
  String Function() get docsDir => () => docsDirRoot;

  @override
  Future<List<FileEntry>> localInventory() async {
    final dir = Directory(syncDir);
    if (!dir.existsSync()) return [];
    final out = <FileEntry>[];
    for (final e in dir.listSync(recursive: true).whereType<File>()) {
      final rel = p.posix.joinAll(p.split(p.relative(e.path, from: syncDir)));
      out.add(FileEntry(relativePath: rel, size: e.lengthSync()));
    }
    out.sort((a, b) => a.relativePath.compareTo(b.relativePath));
    return out;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('SnapshotService.${invocation.memberName} 不该被 T17 触碰');
}

void main() {
  late Directory tmp;
  late String docsDir;
  late String syncDir;
  late SharedPreferences prefs;
  late ServiceConfig cfg;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    tmp = Directory.systemTemp.createTempSync('lh_orch_');
    docsDir = p.join(tmp.path, 'documents');
    syncDir = p.join(docsDir, 'sync');
    Directory(syncDir).createSync(recursive: true);
    cfg = ServiceConfig(id: 's1', cloudDirName: 'lh_sync');
    AppLog.reset();
  });

  tearDown(() {
    AppLog.reset();
    try {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// 在 sync/ 下写一个本地文件并返回其差异条目。
  FileDiff localDiff(String rel, int size, DiffStatus status) {
    final f = File(p.join(syncDir, rel))
      ..createSync(recursive: true)
      ..writeAsBytesSync(List.filled(size, 65));
    expect(f.existsSync(), isTrue);
    return FileDiff(
      relativePath: rel,
      status: status,
      local: fe(rel, size: size),
    );
  }

  SyncOrchestrator build(SnapshotService snap, RemoteStore store) =>
      SyncOrchestrator(
        snapshotService: snap,
        prefs: prefs,
        activeConfig: () => cfg,
        storeFactory: (_) => store,
      );

  group('compare()', () {
    test('本地清单 vs 远端清单 + sync_ignore 双侧剔除 + 台账 staleHint', () async {
      localDiff('a.log', 3, DiffStatus.onlyLocal);
      File(p.join(syncDir, 'skip.tmp'))
        ..createSync(recursive: true)
        ..writeAsBytesSync([1, 2]);
      await prefs.setString(SyncOrchestrator.ignoreKey, '*.tmp');
      final snap = _FakeSnap(syncDir: syncDir, docsDirRoot: docsDir);
      // 远端：a.log 同 size（inSync）、c.txt 仅云端、skip.tmp 双侧都该被忽略。
      final store = _FakeStore(files: {
        'a.log': fe('a.log', size: 3),
        'c.txt': fe('c.txt', size: 9),
        'skip.tmp': fe('skip.tmp', size: 4),
      });
      // 台账预先记 c.txt = 本机曾上传成功 → onlyRemote 命中 → staleHint。
      await SyncLedger(prefs, serviceId: cfg.id, cloudDirName: cfg.cloudDirName)
          .record([fe('c.txt')]);
      final orch = build(snap, store);

      final diffs = await orch.compare();
      expect(diffs.map((d) => d.relativePath), ['a.log', 'c.txt']); // .tmp 两侧同剔
      expect(diffs[0].status, DiffStatus.inSync);
      expect(diffs[1].status, DiffStatus.onlyRemote);
      expect(diffs[1].staleHint, isTrue, reason: '台账命中 → D2 残留提示');
      expect(orch.state.value.diffs, diffs, reason: '结果入 state 供 S3 半屏');
    });

    test('sync_ignore 未配置 = 空规则；台账空 = 不报残留', () async {
      final snap = _FakeSnap(syncDir: syncDir, docsDirRoot: docsDir);
      final store = _FakeStore(files: {'new.txt': fe('new.txt')});
      final orch = build(snap, store);
      final diffs = await orch.compare();
      expect(diffs.single.relativePath, 'new.txt');
      expect(diffs.single.staleHint, isFalse);
    });
  });

  group('run() 上传', () {
    test('严格串行：假 store 并发水位恒为 1', () async {
      final snap = _FakeSnap(syncDir: syncDir, docsDirRoot: docsDir);
      final selected = [
        localDiff('f1.bin', 2, DiffStatus.onlyLocal),
        localDiff('f2.bin', 2, DiffStatus.onlyLocal),
        localDiff('f3.bin', 2, DiffStatus.onlyLocal),
      ];
      final store = _FakeStore();
      final outcome = await build(snap, store).run(selected);
      expect(store.maxInflight, 1);
      expect(outcome.up, 3);
      expect(outcome.failed, isEmpty);
    });

    test('非快照先、.lhbak 快照最后；逐文件成功即台账单条', () async {
      final snap = _FakeSnap(syncDir: syncDir, docsDirRoot: docsDir);
      final logs = localDiff('logs/l1.log', 4, DiffStatus.onlyLocal);
      final shot = localDiff(
          'sync_20260925_120000.lhbak', 7, DiffStatus.modified);
      final png = localDiff('attachments/a.png', 5, DiffStatus.onlyLocal);
      // 刻意把快照放勾选清单中间：编排器必须自行把它排到最后。
      final store = _FakeStore();
      final outcome =
          await build(snap, store).run([logs, shot, png]);

      expect(store.putOrder,
          ['logs/l1.log', 'attachments/a.png', 'sync_20260925_120000.lhbak']);
      expect(store.putLocalPaths['logs/l1.log'], p.join(syncDir, 'logs/l1.log'),
          reason: '上传源 = syncDir 下绝对路径');
      final ledger =
          SyncLedger(prefs, serviceId: cfg.id, cloudDirName: cfg.cloudDirName);
      expect(ledger.knownPaths(),
          {'logs/l1.log', 'attachments/a.png', 'sync_20260925_120000.lhbak'});
      expect(ledger.entry('logs/l1.log')!.size, 4);
      expect(outcome.up, 3);
      expect(outcome.bytes, 4 + 7 + 5);
      expect(outcome.canceled, isFalse);
    });

    test('cancel()：当前文件传完即停，已传台账在、未传不在、running=false',
        () async {
      final snap = _FakeSnap(syncDir: syncDir, docsDirRoot: docsDir);
      final selected = [
        localDiff('a.bin', 1, DiffStatus.onlyLocal),
        localDiff('b.bin', 1, DiffStatus.onlyLocal),
        localDiff('c.bin', 1, DiffStatus.onlyLocal),
      ];
      late SyncOrchestrator orch;
      final store = _FakeStore(onPut: (rel) async {
        if (rel == 'b.bin') orch.cancel(); // 第二个传输中请求取消
      });
      orch = build(snap, store);

      final states = <bool>[];
      orch.state.addListener(() => states.add(orch.state.value.running));
      final outcome = await orch.run(selected);

      expect(outcome.up, 2, reason: 'b 是「当前文件」：传完才停');
      expect(outcome.canceled, isTrue);
      final ledger =
          SyncLedger(prefs, serviceId: cfg.id, cloudDirName: cfg.cloudDirName);
      expect(ledger.recorded('a.bin'), isTrue);
      expect(ledger.recorded('b.bin'), isTrue);
      expect(ledger.recorded('c.bin'), isFalse);
      expect(store.putOrder, ['a.bin', 'b.bin']);
      expect(orch.state.value.running, isFalse);
      expect(states.first, isTrue, reason: '运行中透出 running=true');
    });

    test('单文件抛异常：计入 failed、其余继续、run 正常返回、失败不入台账',
        () async {
      final snap = _FakeSnap(syncDir: syncDir, docsDirRoot: docsDir);
      final selected = [
        localDiff('ok1.bin', 2, DiffStatus.onlyLocal),
        localDiff('boom.bin', 2, DiffStatus.onlyLocal),
        localDiff('ok2.bin', 2, DiffStatus.modified),
      ];
      final store = _FakeStore(onPut: (rel) async {
        if (rel == 'boom.bin') throw const SocketException('net down');
      });
      final outcome = await build(snap, store).run(selected);

      expect(outcome.failed, ['boom.bin']);
      expect(outcome.up, 2);
      expect(store.putOrder, ['ok1.bin', 'boom.bin', 'ok2.bin']);
      final ledger =
          SyncLedger(prefs, serviceId: cfg.id, cloudDirName: cfg.cloudDirName);
      expect(ledger.recorded('boom.bin'), isFalse);
      expect(ledger.recorded('ok2.bin'), isTrue);
      expect(AppLog.lines.any((l) =>
          l.level == LhLevel.warn && l.text.contains('boom.bin')),
          isTrue,
          reason: 'R9：失败不吞痕——warn 落日志但不 rethrow 到 UI 外');
    });

    test('单任务门闩：running 时二次 run 抛 StateError', () async {
      final snap = _FakeSnap(syncDir: syncDir, docsDirRoot: docsDir);
      final selected = [localDiff('slow.bin', 1, DiffStatus.onlyLocal)];
      final gate = Completer<void>();
      final store = _FakeStore(onPut: (_) => gate.future);
      final orch = build(snap, store);

      final first = orch.run(selected);
      await pumpEventQueue();
      await expectLater(orch.run(selected), throwsStateError);
      gate.complete();
      final outcome = await first;
      expect(outcome.up, 1);
      expect(orch.state.value.running, isFalse);
    });

    test('inSync 条目混入勾选清单：不上传不计数', () async {
      final snap = _FakeSnap(syncDir: syncDir, docsDirRoot: docsDir);
      final store = _FakeStore();
      final outcome = await build(snap, store).run([
        FileDiff(relativePath: 'same.bin', status: DiffStatus.inSync),
      ]);
      expect(store.putOrder, isEmpty);
      expect(outcome.up, 0);
    });
  });

  group('run() 仅云端下载', () {
    test('onlyRemote → <docs>/exports/，不自动导入、不入台账；透出计数',
        () async {
      final snap = _FakeSnap(syncDir: syncDir, docsDirRoot: docsDir);
      final store = _FakeStore(files: {
        'someone_else.lhbak': fe('someone_else.lhbak', size: 42),
      });
      final selected = [
        FileDiff(
          relativePath: 'someone_else.lhbak',
          status: DiffStatus.onlyRemote,
          remote: fe('someone_else.lhbak', size: 42),
        ),
      ];
      final orch = build(snap, store);
      final outcome = await orch.run(selected);

      final dest = p.join(docsDir, 'exports', 'someone_else.lhbak');
      expect(File(dest).existsSync(), isTrue);
      expect(outcome.down, 1);
      expect(outcome.downloadedToExports, 1);
      expect(outcome.bytes, 42);
      final ledger =
          SyncLedger(prefs, serviceId: cfg.id, cloudDirName: cfg.cloudDirName);
      expect(ledger.recorded('someone_else.lhbak'), isFalse,
          reason: '台账语义 = 本机上传成功，下载不记');
      expect(
          AppLog.lines.any((l) => l.text.contains('导入')),
          isTrue,
          reason: '完成提示引导去 S5 导入（不自动覆盖本机库）');
    });

    test('上传+下载混选：先传后下；取消后下载段也不跑', () async {
      final snap = _FakeSnap(syncDir: syncDir, docsDirRoot: docsDir);
      late SyncOrchestrator orch;
      final store = _FakeStore(
        files: {'r.lhbak': fe('r.lhbak')},
        onPut: (rel) async => orch.cancel(),
      );
      orch = build(snap, store);
      final outcome = await orch.run([
        localDiff('u.bin', 1, DiffStatus.onlyLocal),
        FileDiff(relativePath: 'r.lhbak', status: DiffStatus.onlyRemote),
      ]);
      expect(outcome.up, 1);
      expect(outcome.down, 0, reason: '取消清空剩余队列（含下载段）');
      expect(outcome.canceled, isTrue);
    });
  });

  group('进度态', () {
    test('每文件推进 done/current；rateLimitedWaitSeconds 本期恒 null', () async {
      final snap = _FakeSnap(syncDir: syncDir, docsDirRoot: docsDir);
      final selected = [
        localDiff('x1.bin', 1, DiffStatus.onlyLocal),
        localDiff('x2.bin', 1, DiffStatus.onlyLocal),
      ];
      final orch = build(snap, _FakeStore());
      final seen = <SyncTaskState>[];
      orch.state.addListener(() => seen.add(orch.state.value));

      await orch.run(selected);

      expect(orch.state.value.done, 2);
      expect(orch.state.value.total, 2);
      expect(orch.state.value.current, isNull);
      final progressing = seen.where((s) => s.total == 2 && s.done > 0);
      expect(progressing.map((s) => s.done), containsAll([1, 2]));
      expect(seen.every((s) => s.rateLimitedWaitSeconds == null), isTrue,
          reason: '退避在 HttpGate 内部，store 不回调——不造假通道，T18 再接');
    });
  });

  group('SyncHistory', () {
    test('run 结束头插一条：字段齐全，新记录在 index 0', () async {
      final snap = _FakeSnap(syncDir: syncDir, docsDirRoot: docsDir);
      final orch = build(snap, _FakeStore());
      await orch.run([localDiff('h.bin', 3, DiffStatus.onlyLocal)]);
      await orch.run([]); // 空任务也留痕（ok=true, up=0）

      final list = jsonDecode(prefs.getString(SyncHistory.prefsKey)!) as List;
      expect(list, hasLength(2));
      final newest = Map<String, dynamic>.from(list[0] as Map);
      expect(newest['serviceId'], 's1');
      expect(newest['dir'], 'lh_sync');
      expect(newest['up'], 0);
      expect(newest['ok'], isTrue);
      expect(newest['error'], isNull);
      final prev = Map<String, dynamic>.from(list[1] as Map);
      expect(prev['up'], 1);
      expect(prev['bytes'], 3);
      expect(prev['ts'], isA<int>());
    });

    test('失败任务落 error 文案；append 上限 100 截断且新者在头', () async {
      final snap = _FakeSnap(syncDir: syncDir, docsDirRoot: docsDir);
      final store = _FakeStore(onPut: (rel) async {
        throw StateError('403');
      });
      await build(snap, store).run([localDiff('f.bin', 1, DiffStatus.onlyLocal)]);
      final list = jsonDecode(prefs.getString(SyncHistory.prefsKey)!) as List;
      expect(Map<String, dynamic>.from(list.first as Map)['ok'], isFalse);
      expect(Map<String, dynamic>.from(list.first as Map)['error'],
          contains('f.bin'));

      for (var i = 0; i < 105; i++) {
        await SyncHistory.append(
          prefs,
          SyncHistoryEntry(
            ts: 1000 + i,
            serviceId: 's$i',
            dir: 'd',
            up: i,
            down: 0,
            bytes: 0,
            ok: true,
          ),
        );
      }
      final all = SyncHistory.read(prefs);
      expect(all, hasLength(SyncHistory.maxEntries));
      expect(all.first.serviceId, 's104', reason: '头部插入');
      expect(all.last.serviceId, 's5', reason: '最旧 5 条被截');
    });

    test('坏 JSON 容错 = 空历史，不炸链路', () async {
      await prefs.setString(SyncHistory.prefsKey, '{not-json');
      expect(SyncHistory.read(prefs), isEmpty);
    });
  });
}
