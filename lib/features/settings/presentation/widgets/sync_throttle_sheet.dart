part of 'sync_sheets.dart';

// 治理G7d②：S6 控流弹层自 sync_sheets 整块外提（行为零改动）。
// 档位常量 + 快照份数滚轮 + 仅Wi-Fi 开关（prefs sync_wifiOnly · T19 消费）。
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
