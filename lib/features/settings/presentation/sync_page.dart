import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/providers.dart';
import '../../../core/sync/diff_service.dart';
import '../../../core/sync/remote_store.dart';
import '../../../core/sync/service_config.dart';
import '../../../core/sync/snapshot_service.dart';
import '../../../core/sync/sync_orchestrator.dart';
import '../../../core/sync/sync_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart';
import 'sync_backup_sheet.dart';
import 'widgets/sync_sheets.dart';

/// V1.41 Task 18 · P1「数据与同步」主页（原型 index-sync.html p-sync）。
///
/// 口径：
/// - 当前服务卡：协议徽标（文字）+ 派生服务名 + 容量三态渲染
///   （有配额=进度条 / 仅已用=文本行 / 全 null=无容量行）+ 最近同步摘要
///   （= 同步历史首条）；
/// - 入口行：立即同步 / 差异对比(S3) / 备份导出·导入(S5·Task 10) /
///   控流(S6) / 同步历史(P2) / 日志(/log)；
/// - 切换服务列表：单选 activeId；
/// - 「立即同步」经差异扫描后进 S4 进度半屏（编排只执行可执行条目，
///   一致条目自动跳过）；
/// - 底部原型三 tab（同步/历史/日志）在 app 内以入口行承载——
///   /sync 是栈页不占底栏导航池（见 task-18 报告差异说明）。
class SyncPage extends ConsumerStatefulWidget {
  const SyncPage({super.key});

  @override
  ConsumerState<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends ConsumerState<SyncPage> {
  SyncConfigSnapshot _snap = const SyncConfigSnapshot(services: []);

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    if (!mounted) return;
    setState(() => _snap = ref.read(syncConfigStoreProvider).load());
  }

  ServiceConfig? get _active {
    final id = _snap.activeId;
    if (id == null) return null;
    for (final c in _snap.services) {
      if (c.id == id) return c;
    }
    return null;
  }

  void _toast(String msg) {
    if (mounted) AppToast.show(context, msg);
  }

  // ---- 动作 ----

  Future<void> _switchTo(String id) async {
    if (id == _snap.activeId) return;
    await ref.read(syncConfigStoreProvider).setActive(id);
    ref.invalidate(syncQuotaProvider);
    _reload();
    _toast('已切换激活服务 · ${serviceDisplayName(_active ?? _snap.services.first)}');
  }

  Future<void> _openEdit({ServiceConfig? cfg}) async {
    final result = await showServiceEditSheet(context, config: cfg);
    if (!mounted) return;
    ref.invalidate(syncQuotaProvider);
    _reload();
    if (result is ServiceEditVerifyRequest) {
      await showVerifySheet(context, config: result.config);
    }
  }

  Future<void> _openVerify() async {
    final c = _active;
    if (c == null) {
      _toast('请先配置并激活云服务');
      return;
    }
    await showVerifySheet(context, config: c);
  }

  Future<void> _openDiff() async {
    final req = await showDiffSheet(context);
    if (req != null && mounted) {
      final o = ref.read(syncOrchestratorProvider);
      await showSyncProgressSheet(context,
          orchestrator: o,
          task: () => o.run(req.diffs),
          queue: req.diffs,
          config: _active);
    }
    _reload();
  }

  /// 立即同步：compare → 全量可执行条目 → S4 进度半屏。
  Future<void> _syncNow() async {
    final o = ref.read(syncOrchestratorProvider);
    List<FileDiff> actionable;
    try {
      await o.compare();
      actionable = o.state.value.diffs
          .where((d) => d.status != DiffStatus.inSync)
          .toList(growable: false);
    } catch (e) {
      _toast('同步准备失败：$e');
      return;
    }
    if (!mounted) return;
    if (actionable.isEmpty) {
      _toast('无差异可同步 · 两端一致');
      return;
    }
    await showSyncProgressSheet(context,
        orchestrator: o,
        task: () => o.run(actionable),
        queue: actionable,
        config: _active);
    _reload();
  }

  Future<void> _openThrottle() async {
    if (_active == null) {
      _toast('请先配置并激活云服务');
      return;
    }
    await showThrottleSheet(context);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final active = _active;
    final quota = ref.watch(syncQuotaProvider).valueOrNull;
    final history = SyncHistory.read(ref.watch(sharedPreferencesProvider));
    final prefs = ref.watch(sharedPreferencesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('数据与同步')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (active == null)
            Container(
              key: const ValueKey('svc-empty-card'),
              decoration: context.cardDecoration,
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 16),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('尚未配置云服务',
                            style:
                                TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
                        Text('WebDAV · S3 · 差异比对 · 同步历史',
                            style: TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                  ),
                  FilledButton(
                    key: const ValueKey('btn-add-svc'),
                    onPressed: () => _openEdit(),
                    child: const Text('添加服务'),
                  ),
                ],
              ),
            )
          else
            Container(
              key: const ValueKey('svc-card'),
              decoration: context.cardDecoration,
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ProtoBadge(isS3: active.isS3),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(serviceDisplayName(active),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 14.5, fontWeight: FontWeight.w800)),
                      ),
                      const ProtoStateTag(text: '已激活', color: Color(0xFF047857)),
                      const SizedBox(width: 8),
                      ProtoMiniBtn(
                          key: const ValueKey('btn-edit-svc'),
                          label: '编辑配置',
                          onTap: () => _openEdit(cfg: active)),
                      const SizedBox(width: 8),
                      ProtoMiniBtn(
                          key: const ValueKey('btn-verify-svc'),
                          label: '验证连接',
                          onTap: _openVerify),
                    ],
                  ),
                  // 容量三态（R9）：有配额进度条 / 仅已用文本行 / 全 null 无行。
                  if (quota != null &&
                      (quota.quotaBytes != null || quota.usedBytes != null)) ...[
                    const SizedBox(height: 12),
                    _CapacityBlock(quota: quota),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.schedule,
                          size: 13, color: Color(0xFF94A3B8)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_lastSyncSummary(history),
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF64748B))),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          if (active != null) ...[
            const SizedBox(height: 12),
            Container(
              key: const ValueKey('btn-sync-now'),
              decoration: BoxDecoration(
                gradient: tokens.gradient,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _syncNow,
                  borderRadius: BorderRadius.circular(15),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 13),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.sync, size: 16, color: Colors.white),
                        SizedBox(width: 6),
                        Text('立即同步',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: Colors.white)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Container(
            decoration: context.cardDecoration,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _EntryRow(
                  key: const ValueKey('sync-diff-entry'),
                  icon: Icons.compare_arrows,
                  title: '差异对比',
                  sub: '本地快照目录 · 云端目录 · 四态差异',
                  onTap: _openDiff,
                ),
                const Divider(height: 1, indent: 14, endIndent: 14),
                _EntryRow(
                  key: const ValueKey('sync-backup-entry'),
                  icon: Icons.inventory_2_outlined,
                  title: '备份导出/导入',
                  sub: '.lhbak 容器 · 口令加密 · 日志随包',
                  onTap: () => showBackupSheet(context),
                ),
                const Divider(height: 1, indent: 14, endIndent: 14),
                _EntryRow(
                  key: const ValueKey('sync-throttle-entry'),
                  icon: Icons.speed_outlined,
                  title: '控流',
                  sub: active == null
                      ? '未配置服务'
                      : '请求间隔 ${active.requestIntervalMs}ms · '
                          '快照 ${_keepN(prefs)} 份 · 仅Wi-Fi ${_wifiOnly(prefs) ? '开' : '关'}',
                  onTap: _openThrottle,
                ),
                const Divider(height: 1, indent: 14, endIndent: 14),
                _EntryRow(
                  key: const ValueKey('sync-history-entry'),
                  icon: Icons.history,
                  title: '同步历史',
                  sub: _histSummary(history),
                  onTap: () => context.go('/sync/history'),
                ),
                const Divider(height: 1, indent: 14, endIndent: 14),
                _EntryRow(
                  key: const ValueKey('sync-log-entry'),
                  icon: Icons.article_outlined,
                  title: '日志',
                  sub: '环形缓冲 300 · 按日落盘',
                  onTap: () => context.go('/log'),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(2, 16, 2, 7),
            child: Text('切换服务',
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF94A3B8))),
          ),
          Container(
            key: const ValueKey('svc-switch-list'),
            decoration: context.cardDecoration,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final c in _snap.services) ...[
                  if (c != _snap.services.first)
                    const Divider(height: 1, indent: 14, endIndent: 14),
                  InkWell(
                    key: ValueKey('svc-switch-${c.id}'),
                    onTap: () => _switchTo(c.id),
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(
                        children: [
                          ProtoBadge(isS3: c.isS3),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(serviceDisplayName(c),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 13, fontWeight: FontWeight.w700)),
                                const SizedBox(height: 1),
                                Text('云端目录 ${c.cloudDirName} · ${Uri.tryParse(c.apiUrl)?.host ?? c.apiUrl}',
                                    style: const TextStyle(
                                        fontSize: 10, color: Color(0xFF94A3B8))),
                              ],
                            ),
                          ),
                          _RadioDot(on: c.id == _snap.activeId),
                        ],
                      ),
                    ),
                  ),
                ],
                if (_snap.services.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(14),
                    child: Text('暂无服务 · 请到「服务配置」添加',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: const [
              _LockDotSmall(),
              SizedBox(width: 6),
              Expanded(
                child: Text('凭据仅存本机加密区 · 应用内除本服务外无任何网络请求',
                    style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static int _keepN(SharedPreferences prefs) {
    final raw = prefs.getInt(kSyncKeepSnapshotsKey);
    return (raw != null && raw >= 1) ? raw : kSyncKeepSnapshotsDefault;
  }

  static bool _wifiOnly(SharedPreferences prefs) =>
      prefs.getBool(kSyncWifiOnlyKey) == true;

  String _lastSyncSummary(List<SyncHistoryEntry> history) {
    if (history.isEmpty) return '从未同步 · 待首轮执行';
    final e = history.first;
    return '最近同步 ${formatHistoryTime(e.ts)} · 上传 ${e.up} · 下载 ${e.down}'
        ' · ${formatBytes(e.bytes)} · ${e.ok ? '成功' : (e.error?.contains('canceled') == true ? '已取消' : '有失败')}';
  }

  String _histSummary(List<SyncHistoryEntry> history) {
    if (history.isEmpty) return '暂无记录';
    final today = DateTime.now();
    final yesterday = today.subtract(const Duration(days: 1));
    bool same(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;
    var nToday = 0, nYday = 0;
    for (final e in history) {
      final d = DateTime.fromMillisecondsSinceEpoch(e.ts);
      if (same(d, today)) {
        nToday++;
      } else if (same(d, yesterday)) {
        nYday++;
      }
    }
    return '今日 $nToday 轮 · 昨日 $nYday 轮';
  }
}

/// 容量三态渲染（原型 #svcCap 三分支）。
class _CapacityBlock extends StatelessWidget {
  const _CapacityBlock({required this.quota});

  final CloudQuota quota;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final int? q = quota.quotaBytes;
    final int? u = quota.usedBytes;
    return Container(
      key: const ValueKey('svc-cap'),
      child: (q != null && q > 0 && u != null)
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('已用 ${formatBytes(u)} / 共 ${formatBytes(q)}',
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF64748B))),
                    Text('${(u / q * 100).round()}%',
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF64748B))),
                  ],
                ),
                const SizedBox(height: 5),
                Container(
                  key: const ValueKey('quota-bar'),
                  height: 6,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2F7),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: (u / q).clamp(0.0, 1.0),
                    child: DecoratedBox(
                        decoration: BoxDecoration(
                            gradient: tokens.gradient,
                            borderRadius: BorderRadius.circular(99))),
                  ),
                ),
              ],
            )
          : Row(
              children: [
                Text('已用 ${formatBytes(u ?? 0)}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('桶级求和 · 无配额概念',
                      style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
                ),
              ],
            ),
    );
  }
}

/// 入口行（原型 .row：r-ic 圆角底图标 + 标题 + 副题 + chevron）。
class _EntryRow extends StatelessWidget {
  const _EntryRow({
    super.key,
    required this.icon,
    required this.title,
    required this.sub,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String sub;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: tokens.accent.withValues(alpha: .11),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 16, color: tokens.accent),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 1),
                  Text(sub,
                      style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                size: 15, color: Color(0xFF94A3B8)),
          ],
        ),
      ),
    );
  }
}

/// 协议徽标（文字，无 emoji；原型 .badge-webdav/.badge-s3 同口径）。
class ProtoBadge extends StatelessWidget {
  const ProtoBadge({super.key, required this.isS3});

  final bool isS3;

  @override
  Widget build(BuildContext context) {
    final color = isS3 ? const Color(0xFF059669) : const Color(0xFF0284C7);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isS3 ? 'S3' : 'WebDAV',
        style: TextStyle(
            fontSize: 9, fontWeight: FontWeight.w800, color: color, letterSpacing: .4),
      ),
    );
  }
}

/// 状态角标（原型 .tag-ok 等）。
class ProtoStateTag extends StatelessWidget {
  const ProtoStateTag({super.key, required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .13),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(text,
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: color)),
      );
}

/// 卡内小动作钮（原型 .mini-btn）。
class ProtoMiniBtn extends StatelessWidget {
  const ProtoMiniBtn({super.key, required this.label, required this.onTap});

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

class _RadioDot extends StatelessWidget {
  const _RadioDot({required this.on});

  final bool on;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: on ? tokens.accent : const Color(0xFFCBD5E1), width: 2),
      ),
      child: on
          ? Padding(
              padding: const EdgeInsets.all(3),
              child: DecoratedBox(
                  decoration: BoxDecoration(
                      color: tokens.accent, shape: BoxShape.circle)),
            )
          : null,
    );
  }
}

class _LockDotSmall extends StatelessWidget {
  const _LockDotSmall();

  @override
  Widget build(BuildContext context) => Container(
        width: 7,
        height: 7,
        decoration:
            const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle),
      );
}
