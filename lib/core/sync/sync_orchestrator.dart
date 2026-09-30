/// Task 17：`SyncOrchestrator` 编排（上传/下载/进度/取消/历史）。
///
/// 口径（设计稿 §4.1/§4.2 + 计划钉死）：
/// - compare()：1 次远端 `store.list`（60s 清单缓存在 store 内建，D3）+
///   [SnapshotService.localInventory] + 台账 [SyncLedger.knownPaths] →
///   [computeDiff]；忽略规则读 prefs `sync_ignore`（逗号分隔，D5 双侧剔除）；
/// - run()：**单任务门闩**（running 时再次 run 抛 [StateError]，调度 R3 严格
///   串行）；仅本地/已修改 → 上传，**非快照文件先、`.lhbak` 快照最后**——
///   批量原子性「先附件→后DB→成功标记」在此落为「逐文件 put 成功即
///   [SyncLedger.record] 单条」；仅云端 → 下载到 `<docs>/exports/`，
///   **绝不自动导入**（完成日志引导去 S5 手动恢复）；
/// - cancel()：置标志，**当前文件传完即停**、剩余队列清空；
/// - 单文件异常计入 failed 后继续跑（调度 R9：不吞错——warn 落 [AppLog]，
///   也不 rethrow 到 UI 外）；历史落 prefs `sync_history`（JSON 数组头部
///   插入，上限 100 条，不落 DB 新表——避免 DB v20）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../logging/app_log.dart';
import 'diff_service.dart';
import 'remote_store.dart';
import 'service_config.dart';
import 'snapshot_service.dart';
import 'sync_ledger.dart';

/// 当前激活服务读取器（组合根接 SyncConfigStore.load().activeId → 条目；
/// 无激活服务时由实现方抛 [StateError]，编排层不重复造判空语义）。
typedef ActiveConfigReader = ServiceConfig Function();

/// store 工厂注入点：默认 [RemoteStore.forConfig]（协议分发唯一位点，R2）；
/// 测试注假 store。
typedef RemoteStoreFactory = RemoteStore Function(ServiceConfig config);

/// 台账工厂注入点：按「服务 id + 云端目录」构造（D3 键）。
typedef LedgerFactory = SyncLedger Function(ServiceConfig config);

/// S4 进度半屏的一次快照（不可变，整对象替换触发 [ValueNotifier] 通知）。
class SyncTaskState {
  const SyncTaskState({
    this.diffs = const [],
    this.running = false,
    this.current,
    this.done = 0,
    this.total = 0,
    this.rateLimitedWaitSeconds,
    this.failedPaths = const {},
  });

  /// 最近一次 [SyncOrchestrator.compare] 的结果（S3 半屏数据源）。
  final List<FileDiff> diffs;

  final bool running;

  /// 正在传的文件；空闲/结束为 null。
  final FileDiff? current;

  /// 已完成文件数 / 本任务总文件数（勾选清单里的可执行条目）。
  final int done;
  final int total;

  /// 被限流剩余等待秒数（S4「被限流等待提示」占位）。
  /// **本期恒 null**：429/503 退避发生在 [HttpGate] 内部，store 不向上回调；
  /// T18 若 UI 需要实时退避提示，再接 gate 的回调通道——不留假通道。
  final int? rateLimitedWaitSeconds;

  /// R3③：本任务内已失败的文件相对路径（S4 行状态如实渲染「失败」，
  /// 不再出现「行显完成、页脚显失败」的自相矛盾）。
  final Set<String> failedPaths;
}

/// 一次 [SyncOrchestrator.run] 的结算结果。
class SyncOutcome {
  SyncOutcome({
    this.up = 0,
    this.down = 0,
    List<String>? failed,
    this.bytes = 0,
    this.downloadedToExports = 0,
    this.placed = 0,
    this.canceled = false,
  }) : failed = failed ?? [];

  /// 成功上传文件数。
  int up;

  /// 成功下载文件数（仅云端条目）。
  int down;

  /// R5a：附件条目直落媒体目录的成功数（不计入 downloadedToExports——
  /// 它们已就位可被 App 直接引用，无需再去「备份导入」）。
  int placed;

  /// 失败文件的相对路径（R9：不吞错，UI 可逐条展示）。
  final List<String> failed;

  /// 成功传输的字节合计（上传+下载）。
  int bytes;

  /// 成功落到 `<docs>/exports/` 的文件数——UI 据此提示「去备份导入」，
  /// 同步本身**绝不自动导入**。
  int downloadedToExports;

  /// 用户取消且确有剩余队列未跑时为 true。
  bool canceled;
}

/// 一条同步历史（P2 列表数据源；不落 DB 表，备份可见性走 prefs 导出）。
class SyncHistoryEntry {
  const SyncHistoryEntry({
    required this.ts,
    required this.serviceId,
    required this.dir,
    required this.up,
    required this.down,
    required this.bytes,
    required this.ok,
    this.error,
  });

  /// epoch 毫秒。
  final int ts;
  final String serviceId;

  /// 云端目录名（ServiceConfig.cloudDirName）。
  final String dir;
  final int up;
  final int down;
  final int bytes;
  final bool ok;

  /// 失败/取消时的人话摘要；成功为 null。
  final String? error;

  Map<String, dynamic> toJson() => {
        'ts': ts,
        'serviceId': serviceId,
        'dir': dir,
        'up': up,
        'down': down,
        'bytes': bytes,
        'ok': ok,
        if (error != null && error!.isNotEmpty) 'error': error,
      };

  static SyncHistoryEntry? fromJson(Object? v) {
    if (v is! Map) return null;
    int i(Object? x) => x is num ? x.toInt() : 0;
    return SyncHistoryEntry(
      ts: i(v['ts']),
      serviceId: v['serviceId'] as String? ?? '',
      dir: v['dir'] as String? ?? '',
      up: i(v['up']),
      down: i(v['down']),
      bytes: i(v['bytes']),
      ok: v['ok'] == true,
      error: v['error'] as String?,
    );
  }
}

/// 同步历史读写（prefs `sync_history`，JSON 数组**头部插入**，上限 100 条）。
class SyncHistory {
  SyncHistory._();

  static const prefsKey = 'sync_history';

  /// 容量上限：超限丢弃最旧（设计稿 §4 / brief）。
  static const maxEntries = 100;

  /// 容错读：坏 JSON / 非数组一律按空历史（不炸 P2 列表）。
  static List<SyncHistoryEntry> read(SharedPreferences prefs) {
    final raw = prefs.getString(prefsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final data = jsonDecode(raw);
      if (data is! List) return [];
      return data
          .map(SyncHistoryEntry.fromJson)
          .whereType<SyncHistoryEntry>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 头部插入并截断至 [maxEntries]。
  static Future<void> append(
      SharedPreferences prefs, SyncHistoryEntry entry) async {
    final list = read(prefs);
    list.insert(0, entry);
    if (list.length > maxEntries) list.removeRange(maxEntries, list.length);
    await prefs.setString(prefsKey, jsonEncode([
      for (final e in list) e.toJson(),
    ]));
  }
}

/// 云同步编排器（S3 差异勾选 → S4 进度半屏的中间业务层）。
class SyncOrchestrator {
  SyncOrchestrator({
    required this.snapshotService,
    required this.prefs,
    required this.activeConfig,
    RemoteStoreFactory? storeFactory,
    LedgerFactory? ledgerFactory,
    Future<void> Function(Duration delay)? sleeper,
  })  : _storeFactory = storeFactory ??
            ((c) => RemoteStore.forConfig(c)),
        _ledgerFactory = ledgerFactory ??
            ((c) =>
                SyncLedger(prefs, serviceId: c.id, cloudDirName: c.cloudDirName)),
        _sleeper = sleeper;

  /// 忽略规则 prefs 键（逗号分隔的 glob 形态，D5 喂 [computeDiff]）。
  static const ignoreKey = 'sync_ignore';

  final SnapshotService snapshotService;
  final SharedPreferences prefs;
  final ActiveConfigReader activeConfig;
  final RemoteStoreFactory _storeFactory;
  final LedgerFactory _ledgerFactory;

  /// 文件间协作让位钩子（生产 null = 不额外延时）：注入时可插入真实等待，
  /// 供测试放大并发水位检测窗口。
  final Future<void> Function(Duration delay)? _sleeper;

  /// S3/S4 订阅源：diffs + 进度态（done/total/current/running）。
  final ValueNotifier<SyncTaskState> state = ValueNotifier(const SyncTaskState());

  /// store 按服务 id 复用（保住 store 内建 60s 清单缓存；换服务重建）。
  final Map<String, RemoteStore> _stores = {};

  bool _running = false;
  bool _cancelRequested = false;

  RemoteStore _store(ServiceConfig c) =>
      _stores.putIfAbsent(c.id, () => _storeFactory(c));

  /// 下载落点：`<docs>/exports/`（与备份导出同目录族，S5 导入器可见）。
  String get exportsDir => p.join(snapshotService.docsDir(), 'exports');

  /// 下载 relPath 防护（评审修复轮1）：拼接进 [exportsDir] 前拒绝可逃逸的
  /// 形态——`../` 上跳（含归一化后上跳，如 `a/../../x`）、绝对路径、
  /// Windows 盘符（`C:/…`、`C:\…`）与反斜杠分隔变体。
  static bool _isSafeDownloadRelPath(String rel) {
    if (rel.isEmpty || rel.contains(':') || rel.contains(r'\')) return false;
    if (rel.startsWith('/')) return false;
    final normalized = p.posix.normalize(rel);
    return normalized != '..' && !normalized.startsWith('../');
  }

  Set<String> _ignorePatterns() {
    final raw = prefs.getString(ignoreKey);
    if (raw == null || raw.trim().isEmpty) return const {};
    return raw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
  }

  /// 差异对比：远端 1 次 list（60s 缓存在 store 内建）+ 本地快照目录清单 +
  /// 台账 knownPaths（D2 残留提示）→ [computeDiff]，结果入 [state]。
  Future<List<FileDiff>> compare() async {
    final cfg = activeConfig();
    final listing = await _store(cfg).list(cfg, cfg.cloudDirName);
    // #7：「允许严格校验（MD5）」开＝本地清单带 MD5 摘要，引擎按 32-hex 门槛走严格档。
    final local = await snapshotService.localInventory(withDigest: cfg.verifyContent);
    final diffs = computeDiff(
      local: local,
      remote: listing.files,
      ignorePatterns: _ignorePatterns(),
      ledgerKnown: _ledgerFactory(cfg).knownPaths(),
    );
    state.value = SyncTaskState(
      diffs: diffs,
      running: state.value.running,
      total: state.value.total,
      done: state.value.done,
      current: state.value.current,
    );
    AppLog.add('同步对比完成：${diffs.length} 条差异'
        '（仅本地 ${diffs.where((d) => d.status == DiffStatus.onlyLocal).length}、'
        '仅云端 ${diffs.where((d) => d.status == DiffStatus.onlyRemote).length}、'
        '已修改 ${diffs.where((d) => d.status == DiffStatus.modified).length}）');
    return diffs;
  }

  /// 请求取消：当前文件传完即停，剩余队列（含下载段）清空。
  void cancel() => _cancelRequested = true;

  /// 执行勾选清单：上传段严格「非快照先、快照最后」+ 逐文件成功即台账；
  /// 下载段仅云端条目 → exports/（不自动导入）。见文件头口径。
  Future<SyncOutcome> run(List<FileDiff> selected) async {
    if (_running) {
      throw StateError('同步任务已在运行（单任务门闩，调度 R3）');
    }
    // 预检在置位之前跑：activeConfig/建 store/建 ledger 若抛异常，门闩尚未
    // 置位、无需经 finally 复位，后续 run 不会被永久卡死（评审修复轮1）。
    final cfg = activeConfig();
    final store = _store(cfg);
    final ledger = _ledgerFactory(cfg);

    final outcome = SyncOutcome();
    final errorTexts = <String>[];
    var done = 0;
    var total = 0;

    // 置位后立即进 try：保护区之外不留任何可抛语句，finally 必然执行。
    _running = true;
    _cancelRequested = false;
    try {
      // 「先附件→后DB」落法：稳定分区——非快照保勾选相对顺序在前，
      // `.lhbak` 快照（同步目录里的最新 DB 载体）永远最后。
      final actionable = selected
          .where((d) => d.status != DiffStatus.inSync)
          .toList(growable: false);
      final uploads = actionable
          .where((d) =>
              d.status == DiffStatus.onlyLocal || d.status == DiffStatus.modified)
          .toList();
      final uploadsOrdered = [
        ...uploads.where(
            (d) => !SnapshotService.isSyncSnapshotName(p.basename(d.relativePath))),
        ...uploads.where(
            (d) => SnapshotService.isSyncSnapshotName(p.basename(d.relativePath))),
      ];
      final downloads =
          actionable.where((d) => d.status == DiffStatus.onlyRemote).toList();

      total = uploadsOrdered.length + downloads.length;
      state.value =
          SyncTaskState(diffs: state.value.diffs, running: true, total: total);

      Future<void> step(FileDiff d, Future<int> Function() action) async {        state.value = SyncTaskState(
          diffs: state.value.diffs,
          running: true,
          current: d,
          done: done,
          total: total,
        );
        final bytes = await action();
        done++;
        state.value = SyncTaskState(
          diffs: state.value.diffs,
          running: true,
          current: null,
          done: done,
          total: total,
        );
        if (bytes > 0) outcome.bytes += bytes;
        await _sleeper?.call(Duration.zero);
      }

      // R3③：失败即时入 state.failedPaths——S4 行状态据此渲染「失败」，
      // 不再出现「行显完成、页脚显失败」的自相矛盾。
      void pushFailed(String rel) {
        state.value = SyncTaskState(
          diffs: state.value.diffs,
          running: true,
          done: done,
          total: total,
          failedPaths: {...state.value.failedPaths, rel},
        );
      }

      for (final d in uploadsOrdered) {
        if (_cancelRequested) {
          outcome.canceled = true;
          break;
        }
        final size = d.local?.size ?? 0;
        try {
          await step(d, () async {
            // R5a：源路径经 resolveLocal——attachments/ 前缀映射媒体目录，
            // 其余落 sync/（快照与非快照文件同规则）。
            await store.put(cfg, snapshotService.resolveLocal(d.relativePath),
                d.relativePath);
            // 成功标记（续传台账）：逐文件即时记，中断后下次 compare 判 inSync。
            // 续传语义 = 靠下轮 compare 重算差异，任务内不保留增量状态；
            // 60s 清单缓存窗内陈旧勾选可能对同一文件重复 put（幂等，
            // 耗带宽不损数据）。
            await ledger.record([
              FileEntry(relativePath: d.relativePath, size: size),
            ]);
            outcome.up++;
            return size;
          });
        } catch (e) {
          outcome.failed.add(d.relativePath);
          errorTexts.add('${d.relativePath}: $e');
          AppLog.add('上传失败（${d.relativePath}）：$e', level: LhLevel.warn);
          done++; // 失败也占一格进度，UI 不卡半程
          pushFailed(d.relativePath);
        }
      }
      for (final d in downloads) {
        if (_cancelRequested) {
          outcome.canceled = true;
          break;
        }
        final size = d.remote?.size ?? 0;
        if (!_isSafeDownloadRelPath(d.relativePath)) {
          // 防 `../` 逃逸 exportsDir：非法条目计入 failed、绝不落盘
          // （评审修复轮1）。
          outcome.failed.add(d.relativePath);
          errorTexts.add('${d.relativePath}: 非法相对路径（目录逃逸/绝对路径），已拒绝落盘');
          AppLog.add('下载跳过（${d.relativePath}）：非法相对路径，未落盘',
              level: LhLevel.warn);
          done++; // 与异常文件同口径：占一格进度、不中断其余
          pushFailed(d.relativePath);
          continue;
        }
        // R5a：附件条目直落媒体目录（同名同大小幂等跳过）；其余走 exports
        // 隔离区（下载 ≠ 导入口径不变）。
        final attachDest = snapshotService.resolveDownload(d.relativePath, size);
        final bool toMedia = attachDest != null;
        final dest = toMedia ? attachDest : p.join(exportsDir, d.relativePath);
        try {
          await step(d, () async {
            if (toMedia && File(dest).existsSync() &&
                File(dest).lengthSync() == size) {
              // 已就位（陈旧清单/台账时差）：零传输，计入 placed。
              outcome.down++;
              outcome.placed++;
              return 0;
            }
            Directory(p.dirname(dest)).createSync(recursive: true);
            await store.get(cfg, d.relativePath, dest);
            outcome.down++;
            if (toMedia) {
              outcome.placed++;
            } else {
              outcome.downloadedToExports++;
            }
            return size;
          });
        } catch (e) {
          outcome.failed.add(d.relativePath);
          errorTexts.add('${d.relativePath}: $e');
          AppLog.add('下载失败（${d.relativePath}）：$e', level: LhLevel.warn);
          done++;
          pushFailed(d.relativePath);
        }
      }
      if (outcome.downloadedToExports > 0) {
        // 口径钉死：下载 ≠ 导入。引导去 S5「备份与恢复」手动恢复。
        AppLog.add('已下载 ${outcome.downloadedToExports} 个云端文件到导出目录，'
            '未自动导入：请到「备份与恢复 → 导入」确认后恢复本机库');
      }
      if (outcome.placed > 0) {
        AppLog.add('附件已就位 ${outcome.placed} 个（图片直落媒体目录，可直接引用）');
      }
      if (outcome.canceled) AppLog.add('同步已取消：剩余队列清空');
      return outcome;
    } finally {
      _running = false;
      state.value = SyncTaskState(
          diffs: state.value.diffs,
          done: done,
          total: total,
          failedPaths: outcome.failed.toSet());
      await SyncHistory.append(
        prefs,
        SyncHistoryEntry(
          ts: DateTime.now().millisecondsSinceEpoch,
          serviceId: cfg.id,
          dir: cfg.cloudDirName,
          up: outcome.up,
          down: outcome.down,
          bytes: outcome.bytes,
          ok: outcome.failed.isEmpty && !outcome.canceled,
          error: [
            ...errorTexts,
            if (outcome.canceled) 'canceled（已取消）',
          ].join('；'),
        ),
      );
    }
  }

  /// 释放底层 store 连接（组合根销毁时调用；幂等）。
  void dispose() {
    for (final s in _stores.values) {
      s.close();
    }
    _stores.clear();
    state.dispose();
  }
}
