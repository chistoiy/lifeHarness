part of 'sync_sheets.dart';

// 治理G7d②：S4 同步进度半屏自 sync_sheets 整块外提（行为零改动）。
// 订阅 SyncOrchestrator.state（current/done/total + 取消钮）。
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
      // T7：弹层内已展示原文，提示条走人话＋3.2s，并补一条 warn 日志（双通道）。
      AppToast.showError(context, e,
          prefix: '同步失败', logDetail: '同步失败：$e');
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
