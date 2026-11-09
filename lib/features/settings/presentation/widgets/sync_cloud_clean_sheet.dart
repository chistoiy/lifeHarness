part of 'sync_sheets.dart';

// 治理G7d②：S7 云端孤儿附件清理半屏自 sync_sheets 整块外提（行为零改动）。
// 打开即 force 拉云端清单算孤儿；「归档」move 到 media_archive/（默认·可回退），「彻底删除」需二次确认。
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

  /// 真机反馈轮③：批量执行期给进度与取消（此前只有 `_busy` 把全控件禁掉，
  /// 几十条删除期间屏面像卡死）。[cancelRequested] 由 service 在每条落定后查询。
  int _done = 0, _total = 0;
  bool _cancel = false;
  String _verb = '归档';

  @override
  void dispose() {
    // 半屏被滑掉/返回关掉＝用户收手：当前条落定后停，剩余不动（重开可继续）。
    _cancel = true;
    super.dispose();
  }

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

  /// 全选/取消全选（真机反馈轮③：这屏此前只能一条条勾，几十上百个孤儿勾不完）。
  void _toggleAll() {
    setState(() {
      if (_checked.length == _orphans.length) {
        _checked.clear();
      } else {
        _checked
          ..clear()
          ..addAll(_orphans.map((e) => e.relativePath));
      }
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
    setState(() {
      _busy = true;
      _cancel = false;
      _done = 0;
      _total = sel.length;
      _verb = archive ? '归档' : '删除';
    });
    final store = ref.read(remoteStoreFactoryProvider)(widget.config);
    final svc = ref.read(cloudCleanServiceProvider);
    void onProgress(int done, int _) {
      if (mounted) setState(() => _done = done);
    }

    final n = archive
        ? await svc.archive(store, widget.config, sel,
            onProgress: onProgress, cancelRequested: () => _cancel)
        : await svc.purge(store, widget.config, sel,
            onProgress: onProgress, cancelRequested: () => _cancel);
    if (!mounted) return;
    final left = _total - _done;
    setState(() => _busy = false);
    AppToast.show(context,
        '${archive ? '已归档' : '已删除'} $n 个文件${left > 0 ? ' · 已取消，剩 $left 个未处理' : ''}');
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
                  return Column(
                    children: [
                      // 屏头：条数＋体积合计（现算）＋全选/取消全选（真机反馈轮③）。
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 10, 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                  '未引用 ${_orphans.length} 个 · '
                                  '${( _orphans.fold<int>(0, (a, e) => a + e.size) / 1048576).toStringAsFixed(1)} MB',
                                  key: const ValueKey('cc-head'),
                                  style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF64748B))),
                            ),
                            TextButton(
                              key: const ValueKey('cc-all'),
                              onPressed:
                                  _busy || _orphans.isEmpty ? null : _toggleAll,
                              child: Text(
                                  _checked.length == _orphans.length
                                      ? '取消全选'
                                      : '全选',
                                  style: const TextStyle(fontSize: 11.5)),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
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
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: _busy
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text('$_verb中 $_done / $_total',
                                  key: const ValueKey('cc-progress'),
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800)),
                            ),
                            TextButton(
                              key: const ValueKey('cc-cancel'),
                              onPressed: () => setState(() => _cancel = true),
                              child: const Text('取消',
                                  style: TextStyle(fontSize: 11.5)),
                            ),
                          ],
                        ),
                        LinearProgressIndicator(
                            key: const ValueKey('cc-bar'),
                            minHeight: 3,
                            value: _total == 0 ? null : _done / _total),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            key: const ValueKey('cc-archive'),
                            onPressed: _busy || _checked.isEmpty
                                ? null
                                : () => _act(archive: true),
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
