/// Task 16：`SyncLedger` 同步台账验收测试（D2 残留判定 + D3 缓存键前缀）。
///
/// 口径（钉死）：
/// - prefs 键 `sync_ledger_{serviceId}|{cloudDirName}`，值 JSON
///   `Map<relativePath, {etag,size,ts}>`；
/// - 台账语义 = 「本机成功传过」：prune **不清**成功记录（云端被外部删除仍
///   留痕供残留判定），整键删除只走删服务的 [SyncLedger.clear]；
/// - knownPaths 元素必为非空 relativePath（T15 评审 Minor：勿把空串喂给
///   computeDiff 的 ledgerKnown）。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/sync/diff_service.dart';
import 'package:lifeharness/core/sync/remote_store.dart';
import 'package:lifeharness/core/sync/sync_ledger.dart';
import 'package:shared_preferences/shared_preferences.dart';

FileEntry fe(String path, {int size = 10, String? etag = 'E1'}) =>
    FileEntry(relativePath: path, size: size, etag: etag);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('record → knownPaths 命中', () {
    test('record 后 knownPaths/recorded 命中；未记录路径 false', () async {
      final prefs = await SharedPreferences.getInstance();
      final ledger =
          SyncLedger(prefs, serviceId: 's1', cloudDirName: 'lh_sync');
      expect(ledger.knownPaths(), isEmpty); // 台账空 = 不报残留
      expect(ledger.recorded('a.lhbak'), isFalse);

      await ledger.record([fe('a.lhbak'), fe('logs/lh-2026-09-25.log')]);
      expect(ledger.knownPaths(), {'a.lhbak', 'logs/lh-2026-09-25.log'});
      expect(ledger.recorded('a.lhbak'), isTrue);
      expect(ledger.recorded('b.lhbak'), isFalse);
    });

    test('合并写：新路径并入、同路径覆写 etag/size，不清旧记录', () async {
      final prefs = await SharedPreferences.getInstance();
      final ledger = SyncLedger(prefs, serviceId: 's1', cloudDirName: 'd');
      await ledger.record([fe('a.lhbak', etag: 'E1', size: 1)]);
      await ledger.record([fe('b.lhbak', etag: 'E2')]);
      await ledger.record([fe('a.lhbak', etag: 'E9', size: 99)]); // 二次上传覆写
      expect(ledger.knownPaths(), {'a.lhbak', 'b.lhbak'});
      final a = ledger.entry('a.lhbak');
      expect(a, isNotNull);
      expect(a!.etag, 'E9');
      expect(a.size, 99);
      expect(a.ts, greaterThan(0));
    });

    test('空串 relativePath 不入台账（knownPaths 非空契约，喂 diff 不脏）',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final ledger = SyncLedger(prefs, serviceId: 's1', cloudDirName: 'd');
      await ledger.record([fe(''), fe('ok.lhbak')]);
      expect(ledger.knownPaths(), {'ok.lhbak'});
      expect(ledger.recorded(''), isFalse);
    });

    test('值结构：prefs JSON Map<relativePath,{etag,size,ts}>', () async {
      final prefs = await SharedPreferences.getInstance();
      final ledger =
          SyncLedger(prefs, serviceId: 's1', cloudDirName: 'lh_sync');
      await ledger.record([fe('a.lhbak', etag: 'E1', size: 7)]);
      final raw = jsonDecode(prefs.getString('sync_ledger_s1|lh_sync')!)
          as Map<String, dynamic>;
      final a = raw['a.lhbak'] as Map<String, dynamic>;
      expect(a['etag'], 'E1');
      expect(a['size'], 7);
      expect(a['ts'], isA<int>());
    });
  });

  group('prune：台账留痕语义，成功记录绝不被清', () {
    test('prune(空集)（云端全没了）成功记录仍在——供残留判定', () async {
      final prefs = await SharedPreferences.getInstance();
      final ledger = SyncLedger(prefs, serviceId: 's1', cloudDirName: 'd');
      await ledger.record([fe('a.lhbak'), fe('b.lhbak')]);
      await ledger.prune({});
      expect(ledger.knownPaths(), {'a.lhbak', 'b.lhbak'});
    });

    test('prune(部分集) 也不动任何已有记录（只有 clear 能整键删）', () async {
      final prefs = await SharedPreferences.getInstance();
      final ledger = SyncLedger(prefs, serviceId: 's1', cloudDirName: 'd');
      await ledger.record([fe('a.lhbak'), fe('b.lhbak')]);
      await ledger.prune({'a.lhbak'}); // b 云端已不存在：仍留痕
      expect(ledger.knownPaths(), {'a.lhbak', 'b.lhbak'});
      expect(ledger.recorded('b.lhbak'), isTrue);
    });
  });

  group('D3 键隔离与整键清理', () {
    test('键 = sync_ledger_{serviceId}|{cloudDirName}；跨 serviceId 隔离',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final a = SyncLedger(prefs, serviceId: 's1', cloudDirName: 'd');
      final b = SyncLedger(prefs, serviceId: 's2', cloudDirName: 'd');
      await a.record([fe('x.lhbak')]);
      expect(prefs.getKeys(), contains('sync_ledger_s1|d'));
      expect(b.knownPaths(), isEmpty); // 换服务 = 新台账，互不串台
      expect(ledgerEmpty(b), isTrue);
    });

    test('同服务不同云端目录也隔离', () async {
      final prefs = await SharedPreferences.getInstance();
      final a = SyncLedger(prefs, serviceId: 's1', cloudDirName: 'd1');
      final b = SyncLedger(prefs, serviceId: 's1', cloudDirName: 'd2');
      await a.record([fe('x.lhbak')]);
      expect(b.knownPaths(), isEmpty);
    });

    test('clear()（删服务）整键移除，knownPaths 落空', () async {
      final prefs = await SharedPreferences.getInstance();
      final ledger = SyncLedger(prefs, serviceId: 's1', cloudDirName: 'd');
      await ledger.record([fe('x.lhbak')]);
      await ledger.clear();
      expect(prefs.getKeys(), isNot(contains('sync_ledger_s1|d')));
      expect(ledger.knownPaths(), isEmpty);
      expect(ledger.recorded('x.lhbak'), isFalse);
    });
  });

  group('容错 + computeDiff 联动（D2 消费位点）', () {
    test('坏 JSON 容忍为空台账，不抛', () async {
      SharedPreferences.setMockInitialValues({
        'sync_ledger_s1|d': '{not json',
      });
      final prefs = await SharedPreferences.getInstance();
      final ledger = SyncLedger(prefs, serviceId: 's1', cloudDirName: 'd');
      expect(ledger.knownPaths(), isEmpty);
      await ledger.record([fe('a.lhbak')]); // 坏数据可被覆盖重写
      expect(ledger.knownPaths(), {'a.lhbak'});
    });

    test('record 后 onlyRemote 命中 staleHint；未 record 的新文件不误报',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final ledger = SyncLedger(prefs, serviceId: 's1', cloudDirName: 'd');
      await ledger.record([fe('gone.lhbak')]);
      final r = computeDiff(
        local: const [],
        remote: [fe('gone.lhbak'), fe('fresh-upload-by-other.lhbak')],
        ignorePatterns: const {},
        ledgerKnown: ledger.knownPaths(),
      );
      expect(
          r.firstWhere((d) => d.relativePath == 'gone.lhbak').staleHint, isTrue);
      expect(r
          .firstWhere((d) => d.relativePath == 'fresh-upload-by-other.lhbak')
          .staleHint, isFalse);
    });
  });
}

bool ledgerEmpty(SyncLedger l) => l.knownPaths().isEmpty;
