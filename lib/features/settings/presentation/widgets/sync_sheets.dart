import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../../core/providers.dart';
import '../../../../core/sync/cloud_clean_service.dart';
import '../../../../core/sync/diff_service.dart';
import '../../../../core/sync/remote_store.dart';
import '../../../../core/sync/service_config.dart';
import '../../../../core/sync/snapshot_service.dart';
import '../../../../core/sync/sync_ledger.dart';
import '../../../../core/sync/sync_orchestrator.dart';
import '../../../../core/sync/sync_providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/ui_kit.dart';

part 'sync_mini_widgets.dart';
part 'sync_service_edit_sheet.dart';
part 'sync_verify_sheet.dart';
part 'sync_diff_sheet.dart';

/// V1.41 Task 18 · /sync 弹层家族（原型 index-sync.html s-svc-edit /
/// s-svc-verify / s-diff / s-syncprog / s-throttle；s-backup 归 Task 10）。
///
/// 口径：
/// - S1 凭据只经 [CredentialVault] 写入，成功才落配置（R11）；删服务连带清
///   保险箱键 + 台账键（D1/D3 无孤儿）。
/// - S2 三态 = 连接通过 / 凭据错误 / 网络失败，文案随协议（WebDAV 提示应用
///   密码 · S3 提示子账户 AK/SK + 桶权限）；凭据缺失时本地预检直出，不发请求。
/// - S3 四态分组 + 一致组折叠计数 + 逐条勾选 + 合计行；仅云端行带「下载」
///   （下载到导出目录，**绝不自动导入**）。
/// - S4 订阅 [SyncOrchestrator.state]（current/done/total + 取消钮）。
/// - S6 档位写回当前 ServiceConfig、快照份数滚轮（T6 同源单列滚轮实现）、
///   仅Wi-Fi 开关存 prefs `sync_wifiOnly`（T19 消费）。
/// - 文案一律功能标签式，无教学句、无 emoji（UI 规范）。

/// 仅 Wi-Fi 自动同步开关的 prefs 键（本期只存值）。
const String kSyncWifiOnlyKey = 'sync_wifiOnly';


// ============================ S4 · 同步进度半屏 ============================

Future<void> showSyncProgressSheet(
  BuildContext context, {
  required SyncOrchestrator orchestrator,
  required Future<SyncOutcome> Function() task,
  required List<FileDiff> queue,
  ServiceConfig? config,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    isDismissible: false,
    enableDrag: false,
    builder: (_) => _ProgressSheet(
        orchestrator: orchestrator, task: task, queue: queue, config: config),
  );
}

class _ProgressSheet extends ConsumerStatefulWidget {
  const _ProgressSheet({
    required this.orchestrator,
    required this.task,
    required this.queue,
    this.config,
  });

  final SyncOrchestrator orchestrator;
  final Future<SyncOutcome> Function() task;
  final List<FileDiff> queue;
  final ServiceConfig? config;

  @override
  ConsumerState<_ProgressSheet> createState() => _ProgressSheetState();
}

class _ProgressSheetState extends ConsumerState<_ProgressSheet> {
  SyncOutcome? _outcome;
  String? _error;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    try {
      final out = await widget.task();
      if (!mounted) return;
      setState(() {
        _outcome = out;
        _finished = true;
      });
      AppToast.show(
          context,
          out.canceled
              ? '同步已取消 · 无成功标记文件下次续传'
              : '同步完成 · 上传 ${out.up} · 下载 ${out.down} · 失败 ${out.failed.length}');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _finished = true;
      });
      AppToast.show(context, '同步失败：$e');
    }
  }

  /// 队列渲染顺序与编排器执行顺序同构（非快照上传在前、快照最后、再下载段）：
  /// done 计数才能对上「第几格」；口径唯一来源 [SnapshotService.isSyncSnapshotName]。
  List<FileDiff> get _ordered {
    final uploads = widget.queue
        .where((d) => d.status == DiffStatus.onlyLocal || d.status == DiffStatus.modified)
        .toList();
    final downloads =
        widget.queue.where((d) => d.status == DiffStatus.onlyRemote).toList();
    bool isSnap(FileDiff d) =>
        SnapshotService.isSyncSnapshotName(p.basename(d.relativePath));
    return [
      ...uploads.where((d) => !isSnap(d)),
      ...uploads.where(isSnap),
      ...downloads,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final ordered = _ordered;
    final totalBytes = ordered.fold<int>(0, (a, d) => a + _diffBytes(d));
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ValueListenableBuilder<SyncTaskState>(
              valueListenable: widget.orchestrator.state,
              builder: (context, s, _) {
                final running = s.running;
                final done = s.done;
                final total = s.total;
                final doneBytes = ordered
                    .take(done.clamp(0, ordered.length))
                    .fold<int>(0, (a, d) => a + _diffBytes(d));
                final canceled = _outcome?.canceled ?? false;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(running ? '同步进行中' : '同步结束',
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w800)),
                        ),
                        if (widget.config != null)
                          Text(
                              '${serviceDisplayName(widget.config!)} · 单任务串行',
                              style: const TextStyle(
                                  fontSize: 10.5, color: Color(0xFF94A3B8))),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '$done / $total${s.current == null ? '' : ' · ${s.current!.relativePath}'}',
                          key: const ValueKey('sync-prog-line'),
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w800),
                        ),
                        Text('${formatBytes(doneBytes)} / ${formatBytes(totalBytes)}',
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w800)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Container(
                      key: const ValueKey('sync-prog-bar'),
                      height: 6,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF2F7),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: total == 0 ? 0 : (done / total).clamp(0.0, 1.0),
                        child: DecoratedBox(
                            decoration: BoxDecoration(
                                gradient: tokens.gradient,
                                borderRadius: BorderRadius.circular(99))),
                      ),
                    ),
                    const SizedBox(height: 10),
                    for (var i = 0; i < ordered.length; i++)
                      _row(ordered[i], i, done, running, canceled,
                          failedPaths: s.failedPaths),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text('同步失败：$_error',
                            style: const TextStyle(
                                fontSize: 11.5, color: Color(0xFFDC2626))),
                      ),
                    if ((_outcome?.downloadedToExports ?? 0) > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                            '已下载 ${_outcome!.downloadedToExports} 个云端文件到导出目录 · 未自动导入，请经「备份导出/导入」发起恢复',
                            key: const ValueKey('sync-import-guide'),
                            style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF047857))),
                      ),
                    if ((_outcome?.failed.isNotEmpty ?? false))
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text('失败 ${_outcome!.failed.length} 个 · 明细见日志',
                            style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFDC2626))),
                      ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        PillChip(
                            // 人话口径：功能标签式（评审修复轮1——不直出
                            // 「HttpGate/requestIntervalMs」工程术语）。
                            label:
                                '请求间隔 ${widget.config?.requestIntervalMs ?? ServiceConfig.defaultRequestIntervalMs}ms · 防服务端频控'),
                        const Expanded(
                          child: Text('遇限流自动退避重发',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                  fontSize: 10, color: Color(0xFF94A3B8))),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        key: const ValueKey('btn-cancel-sync'),
                        onPressed: running
                            ? () => widget.orchestrator.cancel()
                            : (_finished || total == 0)
                                ? () => Navigator.of(context).pop()
                                : null,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: running ? const Color(0xFFDC2626) : null,
                          side: BorderSide(
                              color: running
                                  ? const Color(0xFFFCA5A5)
                                  : tokens.cardBorder),
                        ),
                        child: Text(running ? '取消' : '完成'),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(
      FileDiff d, int i, int done, bool running, bool canceled,
      {Set<String> failedPaths = const {}}) {
    final isCurrent = running && i == done;
    final String status;
    final Color color;
    if (failedPaths.contains(d.relativePath)) {
      // R3③：失败文件如实显「失败」——旧版只按 done 计数渲染，
      // 出现过「三行全绿完成 + 页脚失败 3 个」的矛盾画面。
      status = '失败';
      color = const Color(0xFFDC2626);
    } else if (i < done) {
      status = '完成 ${formatBytes(_diffBytes(d))}';
      color = const Color(0xFF10B981);
    } else if (isCurrent) {
      status = '传输中';
      color = context.tokens.accent;
    } else if (canceled) {
      status = '取消未传';
      color = const Color(0xFFB45309);
    } else {
      status = '排队 ${formatBytes(_diffBytes(d))}';
      color = const Color(0xFF94A3B8);
    }
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFEEF2F7)))),
      child: Row(
        children: [
          _DirTag(up: d.status != DiffStatus.onlyRemote),
          const SizedBox(width: 9),
          Expanded(
            child: Text(d.relativePath,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 10.5, fontFamily: 'monospace', fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 8),
          Text(status,
              style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }
}

// ============================ S6 · 控流弹层 ============================

const List<int> _kThrottleTiers = [150, 300, 800];
const List<int> _kKeepOptions = [3, 5, 10, 20];

Future<void> showThrottleSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => const _ThrottleSheet(),
  );
}

class _ThrottleSheet extends ConsumerStatefulWidget {
  const _ThrottleSheet();

  @override
  ConsumerState<_ThrottleSheet> createState() => _ThrottleSheetState();
}

class _ThrottleSheetState extends ConsumerState<_ThrottleSheet> {
  ServiceConfig? _cfg;
  int _keepN = kSyncKeepSnapshotsDefault;
  bool _wifi = false;
  bool _autoArc = false;
  bool _purge30 = false;

  @override
  void initState() {
    super.initState();
    final prefs = ref.read(sharedPreferencesProvider);
    try {
      _cfg = readActiveService(ref.read(syncConfigStoreProvider));
    } on StateError {
      _cfg = null;
    }
    final raw = prefs.getInt(kSyncKeepSnapshotsKey);
    _keepN = (raw == null || raw < 1) ? kSyncKeepSnapshotsDefault : raw;
    _wifi = prefs.getBool(kSyncWifiOnlyKey) ?? false;
    _autoArc = prefs.getBool(CloudCleanService.kAutoArchive) ?? false;
    _purge30 = prefs.getBool(CloudCleanService.kArchivePurge30) ?? false;
  }

  void _setAutoArc(bool v) {
    setState(() => _autoArc = v);
    ref.read(sharedPreferencesProvider).setBool(CloudCleanService.kAutoArchive, v);
  }

  void _setPurge30(bool v) {
    setState(() => _purge30 = v);
    ref.read(sharedPreferencesProvider)
        .setBool(CloudCleanService.kArchivePurge30, v);
  }

  void _toast(String msg) {
    if (mounted) AppToast.show(context, msg);
  }

  /// 档位写回当前 ServiceConfig（R10 按服务配置，非全局）。
  Future<void> _setInterval(int ms) async {
    final cfg = _cfg;
    if (cfg == null || cfg.requestIntervalMs == ms) return;
    final store = ref.read(syncConfigStoreProvider);
    final snap = store.load();
    final target = snap.services.where((c) => c.id == cfg.id).firstOrNull;
    if (target == null) return;
    target.requestIntervalMs = ms;
    try {
      await store.save(snap);
    } on StateError catch (e) {
      _toast('写入失败：${e.message}');
      return;
    }
    setState(() => _cfg = target);
    _toast('请求间隔已设为 ${ms}ms · 仅作用于该服务的同步请求排队');
  }

  void _setKeepN(int n) {
    if (n == _keepN) return;
    setState(() => _keepN = n);
    ref.read(sharedPreferencesProvider).setInt(kSyncKeepSnapshotsKey, n);
  }

  /// T19：自动同步引擎接入后消费 `sync_wifiOnly`——本期自动同步未接，
  /// 开关先存值（手动同步不受限）。
  void _setWifi(bool v) {
    setState(() => _wifi = v);
    ref.read(sharedPreferencesProvider).setBool(kSyncWifiOnlyKey, v);
  }

  @override
  Widget build(BuildContext context) {
    final cfg = _cfg;
    final interval = cfg?.requestIntervalMs ?? ServiceConfig.defaultRequestIntervalMs;
    final keepIdx = _kKeepOptions.indexOf(_keepN);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('控流设置',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            const Text('同步请求统一排队 · 按服务设置请求间隔',
                style: TextStyle(fontSize: 11, color: Colors.grey)),
            const _SecTitle('节流档位 · 请求间隔'),
            Row(
              children: [
                for (final ms in _kThrottleTiers) ...[
                  Expanded(
                    child: _SegBtn(
                        key: ValueKey('throttle-seg-$ms'),
                        label: '${ms}ms',
                        on: interval == ms,
                        onTap: () => _setInterval(ms)),
                  ),
                  if (ms != _kThrottleTiers.last) const SizedBox(width: 6),
                ],
              ],
            ),
            const SizedBox(height: 7),
            Text(
              '请求间隔 · 非全局带宽 · 当前 ${interval}ms'
              '${cfg == null ? '（未配置服务）' : '（${serviceDisplayName(cfg)}）'}',
              style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
            ),
            const SizedBox(height: 14),
            Container(
              decoration: context.cardDecoration,
              padding: const EdgeInsets.all(13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('429 / 503 退避',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
                  SizedBox(height: 4),
                  Text(
                      'Retry-After 优先 · 2s→4s→8s · 单次上限 30s · 重发 ≤3 · 重发必重建请求对象',
                      style: TextStyle(fontSize: 10, color: Color(0xFF64748B))),
                ],
              ),
            ),
            const _SecTitle('历史快照份数 N · 同步对象 = 最新 N 份快照 + 日志'),
            NumberWheel(
              key: const ValueKey('keep-n-wheel'),
              labels: [for (final n in _kKeepOptions) '$n 份'],
              index: keepIdx < 0 ? 1 : keepIdx,
              onSel: (i) => _setKeepN(_kKeepOptions[i]),
            ),
            const SizedBox(height: 5),
            const Center(
              child: Text('超份数丢最旧 · care.syncExcluded 置位则快照排除呵护表并写入 manifest',
                  style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('仅 Wi-Fi 自动同步',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      Text('每天节流 · 手动同步不受限',
                          style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
                    ],
                  ),
                ),
                Switch(
                  key: const ValueKey('wifi-switch'),
                  value: _wifi,
                  onChanged: _setWifi,
                ),
              ],
            ),
            // R5d：云端自动归档（只移不删）+ 归档区 30 天清理（默认关）。
            Row(
              children: [
                const Expanded(
                  child: Text('同步后自动归档云端未引用附件',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ),
                Switch(
                  key: const ValueKey('auto-archive-switch'),
                  value: _autoArc,
                  onChanged: _setAutoArc,
                ),
              ],
            ),
            Row(
              children: [
                const Expanded(
                  child: Text('归档区 30 天后清理',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ),
                Switch(
                  key: const ValueKey('archive-purge-switch'),
                  value: _purge30,
                  onChanged: _setPurge30,
                ),
              ],
            ),
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('缓存',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700,
                              color: Color(0xFF64748B))),
                      Text('同目录清单 60s · 容量 5min · MKCOL 进程内记忆',
                          style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
                    ],
                  ),
                ),
                const Text('列举超时 30s · 传输 10min',
                    style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// R5d：云端孤儿附件清理半屏（S7）。
///
/// 口径：打开即 force 拉云端清单 + 本地引用集算孤儿；勾选后两钮——
/// 「归档」move 到 media_archive/（默认动作、可回退）；「彻底删除」需
/// 二次确认弹窗。零孤儿显空态。文案功能标签式，无教学句。
Future<void> showCloudCleanSheet(BuildContext context,
    {required ServiceConfig config}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _CloudCleanSheet(config: config),
  );
}

class _CloudCleanSheet extends ConsumerStatefulWidget {
  const _CloudCleanSheet({required this.config});

  final ServiceConfig config;

  @override
  ConsumerState<_CloudCleanSheet> createState() => _CloudCleanSheetState();
}

class _CloudCleanSheetState extends ConsumerState<_CloudCleanSheet> {
  late Future<List<FileEntry>> _future = _load();
  final Set<String> _checked = {};
  bool _busy = false;

  Future<List<FileEntry>> _load() {
    final store = ref.read(remoteStoreFactoryProvider)(widget.config);
    return ref.read(cloudCleanServiceProvider).cloudOrphans(store, widget.config);
  }

  void _rescan() {
    setState(() {
      _checked.clear();
      _future = _load();
    });
  }

  Future<void> _act({required bool archive}) async {
    final sel = _orphans.where((e) => _checked.contains(e.relativePath)).toList();
    if (sel.isEmpty) return;
    if (!archive) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (bc) => AlertDialog(
          title: const Text('彻底删除'),
          content: Text('将从云端移除 ${sel.length} 个文件，不可恢复。'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(bc, false), child: const Text('取消')),
            FilledButton(
                key: const ValueKey('cc-purge-confirm'),
                onPressed: () => Navigator.pop(bc, true),
                child: const Text('删除')),
          ],
        ),
      );
      if (ok != true) return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    final store = ref.read(remoteStoreFactoryProvider)(widget.config);
    final svc = ref.read(cloudCleanServiceProvider);
    final n = archive
        ? await svc.archive(store, widget.config, sel)
        : await svc.purge(store, widget.config, sel);
    if (!mounted) return;
    setState(() => _busy = false);
    AppToast.show(context, archive ? '已归档 $n 个文件' : '已删除 $n 个文件');
    _rescan();
  }

  List<FileEntry> _orphans = const [];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .72),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text('清理云端',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            ),
            Expanded(
              child: FutureBuilder<List<FileEntry>>(
                future: _future,
                builder: (context, s) {
                  if (!s.hasData) {
                    return const SizedBox(
                        height: 160,
                        child: Center(child: CircularProgressIndicator()));
                  }
                  _orphans = s.data!;
                  if (_orphans.isEmpty) {
                    return const SizedBox(
                      height: 160,
                      child: Center(
                          child: Text('云端无未引用附件',
                              key: ValueKey('cc-empty'),
                              style: TextStyle(fontSize: 13))),
                    );
                  }
                  return ListView.builder(
                    itemCount: _orphans.length,
                    itemBuilder: (context, i) {
                      final e = _orphans[i];
                      return CheckboxListTile(
                        key: ValueKey('cc-row-${e.relativePath}'),
                        dense: true,
                        value: _checked.contains(e.relativePath),
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: _busy
                            ? null
                            : (v) => setState(() =>
                                v == true
                                    ? _checked.add(e.relativePath)
                                    : _checked.remove(e.relativePath)),
                        title: Text(e.relativePath,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12, fontFamily: 'monospace')),
                        subtitle: Text(
                            '${(e.size / 1024).toStringAsFixed(1)} KB',
                            style: const TextStyle(fontSize: 11)),
                      );
                    },
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const ValueKey('cc-archive'),
                      onPressed:
                          _busy || _checked.isEmpty ? null : () => _act(archive: true),
                      child: Text(_checked.isEmpty
                          ? '归档'
                          : '归档（${_checked.length}）'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('cc-purge'),
                      style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFDC2626)),
                      onPressed: _busy || _checked.isEmpty
                          ? null
                          : () => _act(archive: false),
                      child: const Text('彻底删除'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
