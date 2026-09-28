part of 'sync_sheets.dart';

// 治理G7d②：S3 差异半屏自 sync_sheets 整块外提（行为零改动）。
// 四态分组 + 一致组折叠 + 逐条勾选 + 合计行；仅云端行带「下载」；含 _MiniBtn 与 DiffRunRequest。
// ============================ S3 · 差异半屏 ============================

/// S3 → S4 的接力载荷（关闭差异半屏后由页面拉起进度半屏）。
class DiffRunRequest {
  const DiffRunRequest(this.diffs);

  final List<FileDiff> diffs;
}

Future<DiffRunRequest?> showDiffSheet(BuildContext context) {
  return showModalBottomSheet<DiffRunRequest>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => const _DiffSheet(),
  );
}

/// 勾选口径：一条差异的传输字节（上传取本机、下载取云端）。
int _diffBytes(FileDiff d) => switch (d.status) {
      DiffStatus.onlyRemote => d.remote?.size ?? 0,
      _ => d.local?.size ?? d.remote?.size ?? 0,
    };

class _DiffSheet extends ConsumerStatefulWidget {
  const _DiffSheet();

  @override
  ConsumerState<_DiffSheet> createState() => _DiffSheetState();
}

class _DiffSheetState extends ConsumerState<_DiffSheet> {
  List<FileDiff> _diffs = const [];
  final Set<String> _off = {};
  bool _loading = true;
  String? _error;
  bool _sameOpen = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_scan);
  }

  Future<void> _scan() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final diffs = await ref.read(syncOrchestratorProvider).compare();
      if (!mounted) return;
      setState(() {
        _diffs = diffs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  List<FileDiff> _group(DiffStatus s) =>
      _diffs.where((d) => d.status == s).toList(growable: false);

  bool _selected(FileDiff d) => !_off.contains(d.relativePath);

  void _toggle(FileDiff d, bool v) {
    setState(() => v ? _off.remove(d.relativePath) : _off.add(d.relativePath));
  }

  void _selectAllOf(DiffStatus s) {
    setState(() {
      for (final d in _group(s)) {
        _off.remove(d.relativePath);
      }
    });
  }

  List<FileDiff> get _checkedActionable => _diffs
      .where((d) => d.status != DiffStatus.inSync && _selected(d))
      .toList(growable: false);

  ({int up, int down, int bytes}) get _sum {
    var up = 0, down = 0, bytes = 0;
    for (final d in _checkedActionable) {
      if (d.status == DiffStatus.onlyRemote) {
        down++;
      } else {
        up++;
      }
      bytes += _diffBytes(d);
    }
    return (up: up, down: down, bytes: bytes);
  }

  void _runWith(List<FileDiff> diffs) {
    if (diffs.isEmpty) {
      AppToast.show(context, '请先勾选要同步的文件');
      return;
    }
    Navigator.of(context).pop(DiffRunRequest(diffs));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final dir = () {
      try {
        return readActiveService(ref.read(syncConfigStoreProvider)).cloudDirName;
      } on StateError {
        return '未配置';
      }
    }();
    final sum = _sum;
    final same = _group(DiffStatus.inSync);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .88),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Row(
                children: [
                  const Expanded(
                      child: Text('差异对比',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w800))),
                  TextButton(
                    key: const ValueKey('btn-diff-rescan'),
                    onPressed: _loading ? null : _scan,
                    child: const Text('重新扫描', style: TextStyle(fontSize: 11.5)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _loading
                      ? '正在比对本地快照目录与云端 $dir…'
                      : '本地快照目录 · $dir · 忽略规则两端同时剔除',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ),
            ),
            Flexible(
              child: _loading
                  ? const SizedBox(
                      height: 140,
                      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : _error != null
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text('差异扫描失败：$_error',
                              style: const TextStyle(
                                  fontSize: 12, color: Color(0xFFDC2626))),
                        )
                      // 全量子项一次性入树（SingleChildScrollView 非懒构建）：
                      // 一致组折叠头与勾选行不允许被视口裁掉。
                      : SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ..._section(
                                '仅本地',
                                _group(DiffStatus.onlyLocal),
                                up: true,
                              bulkLabel: '全选上传',
                              onBulk: () => _selectAllOf(DiffStatus.onlyLocal),
                            ),
                            ..._section(
                              '仅云端',
                              _group(DiffStatus.onlyRemote),
                              up: false,
                              bulkLabel: '全选下载',
                              onBulk: () => _selectAllOf(DiffStatus.onlyRemote),
                            ),
                            ..._section('已修改', _group(DiffStatus.modified), up: true),
                            // 一致组：默认折叠计数（原型 toggleSame）。
                            InkWell(
                              key: const ValueKey('diff-same-header'),
                              onTap: () => setState(() => _sameOpen = !_sameOpen),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(2, 13, 2, 4),
                                child: Row(
                                  children: [
                                    const Icon(Icons.check_rounded,
                                        size: 13, color: Color(0xFF64748B)),
                                    const SizedBox(width: 6),
                                    const Text('一致',
                                        style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFF64748B))),
                                    const SizedBox(width: 6),
                                    Text('${same.length} 条',
                                        style: const TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w800)),
                                    const Spacer(),
                                    Text(_sameOpen ? '收起 ▴' : '展开 ▾',
                                        style: const TextStyle(
                                            fontSize: 10,
                                            color: Color(0xFF94A3B8))),
                                  ],
                                ),
                              ),
                            ),
                            if (_sameOpen)
                              for (final d in same)
                                Opacity(
                                  opacity: .65,
                                  child: _plainRow(d),
                                ),
                            if (_diffs.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(16),
                                child: Text('两端一致 · 无差异'),
                              ),
                            ],
                          ),
                        ),
                    ),
            // 合计行 + 同步已勾选（原型 .sumbar 吸底）。
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              decoration: BoxDecoration(
                color: tokens.card,
                border: Border(top: BorderSide(color: tokens.cardBorder)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '上传 ${sum.up} · 下载 ${sum.down} · 共 ${formatBytes(sum.bytes)}',
                      key: const ValueKey('diff-sum'),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                    ),
                  ),
                  FilledButton(
                    key: const ValueKey('btn-diff-sync'),
                    onPressed: () => _runWith(_checkedActionable),
                    child: const Text('同步已勾选'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _section(String title, List<FileDiff> rows,
      {required bool up, String? bulkLabel, VoidCallback? onBulk}) {
    if (rows.isEmpty) return const [];
    return [
      Padding(
        key: ValueKey('diff-group-$title'),
        padding: const EdgeInsets.fromLTRB(2, 13, 2, 4),
        child: Row(
          children: [
            Icon(up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                size: 13, color: const Color(0xFF64748B)),
            const SizedBox(width: 6),
            Text(title,
                style: const TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
            const SizedBox(width: 6),
            Text('${rows.length}',
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
            const Spacer(),
            if (bulkLabel != null)
              PillChip(label: bulkLabel, onTap: onBulk),
          ],
        ),
      ),
      for (final d in rows) _checkRow(d, up: up),
    ];
  }

  Widget _checkRow(FileDiff d, {required bool up}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Transform.scale(
            scale: .8,
            child: Checkbox(
              key: ValueKey('diff-chk-${d.relativePath}'),
              value: _selected(d),
              onChanged: (v) => _toggle(d, v ?? false),
            ),
          ),
          const SizedBox(width: 6),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _DirTag(up: up),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(d.relativePath,
                      style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w700)),
                ),
                if (d.status == DiffStatus.modified)
                  Text(
                    '两端内容不同 · 本机 ${formatBytes(d.local?.size ?? 0)} / 云端 ${formatBytes(d.remote?.size ?? 0)} · 冲突本机为准',
                    style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
                  ),
                if (d.staleHint)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: const Color(0xFFF59E0B).withValues(alpha: .55)),
                      ),
                      child: const Text('残留 · 台账记本机曾上传，本机已无此文件',
                          style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFB45309))),
                    ),
                  ),
                if (!up && d.status == DiffStatus.onlyRemote)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _MiniBtn(
                        key: ValueKey('diff-get-${d.relativePath}'),
                        label: '下载',
                        onTap: () => _runWith([d]),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(formatBytes(_diffBytes(d)),
                style: const TextStyle(
                    fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF64748B))),
          ),
        ],
      ),
    );
  }

  Widget _plainRow(FileDiff d) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(d.relativePath,
                  style: const TextStyle(
                      fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.w700)),
            ),
            Text('${formatBytes(_diffBytes(d))} · 一致',
                style: const TextStyle(
                    fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF64748B))),
          ],
        ),
      );
}

/// 弹层内小动作钮（原型 .mini-btn）。
class _MiniBtn extends StatelessWidget {
  const _MiniBtn({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: tokens.accent.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w800, color: tokens.accent)),
      ),
    );
  }
}
