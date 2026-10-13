import 'dart:async' show unawaited;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/logging/app_log.dart';
import '../../../core/platform/saf_tree.dart';
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
/// - 「立即同步」先为同步目录生成新快照再差异扫描，进 S4 进度半屏（编排只执行
///   可执行条目，一致条目自动跳过）；
/// - 底部原型三 tab（同步/历史/日志）在 app 内以入口行承载——
///   /sync 是栈页不占底栏导航池（见 task-18 报告差异说明）。
class SyncPage extends ConsumerStatefulWidget {
  const SyncPage({super.key});

  @override
  ConsumerState<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends ConsumerState<SyncPage> {
  SyncConfigSnapshot _snap = const SyncConfigSnapshot(services: []);

  /// 「立即同步」动作进行中（compare 网络前置 await 可 30s+ 直至 S4 关闭）。
  /// 页面级防重入闸：期间「立即同步」「差异对比」入口置灰
  /// （评审修复轮1——叠两层 S4 会让第二层 run 撞单任务门闩报错）。
  bool _busy = false;

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
    await showServiceEditSheet(context, config: cfg);
    if (!mounted) return;
    ref.invalidate(syncQuotaProvider);
    _reload();
  }

  Future<void> _openVerify() async {
    final c = _active;
    if (c == null) {
      _toast('请先配置并激活云服务');
      return;
    }
    await showVerifySheet(context, config: c);
  }

  /// 导出位置：系统目录树选择（持久授权），导出直达＋备份列表合并读。
  Future<void> _pickExportLoc() async {
    final uri = await safPickTree();
    if (uri == null) return; // 取消不动现值
    final svc = ref.read(backupServiceProvider);
    await svc.setExportTree(uri);
    if (mounted) {
      setState(() {});
      AppToast.show(context, '已设导出位置 · ${svc.exportTreeName}');
    }
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

  /// 立即同步：生成快照 → compare → 全量可执行条目 → S4 进度半屏。
  ///
  /// 防重入（评审修复轮1）：compare 前置网络 await 可 30s+，连点会叠出
  /// 第二层 S4（第二层 run 撞编排器单任务门闩抛「已在运行」）。
  /// [_busy] 覆盖整个动作（try/finally 完成/异常必复位），期间两个
  /// 会触发 compare 的入口（立即同步 / 差异对比）置灰禁用。
  Future<void> _syncNow() async {
    if (_busy) return;
    final o = ref.read(syncOrchestratorProvider);
    setState(() => _busy = true);
    try {
      List<FileDiff> actionable;
      try {
        // 终审修复波（Critical-1）：快照的唯一生产触发点。同步对象是
        // <docs>/sync/ 目录，compare 前必须先 build 一份新快照，否则该
        // 目录永远为空、上传链空转。最小实现=静默前置（不为 S4 增设
        // 「生成快照」步骤——进度态按文件条目计数，生成不是传输条目）；
        // 失败与 compare 同走「同步准备失败」toast（此段仍在 busy 保护区内）。
        await ref.read(snapshotServiceProvider).build();
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
      // R5d：同步结束后自动归档钩子（开关默认关；只归档不删除）。整体
      // try 包裹：provider 未装配（测试环境）或服务内异常都不得影响页面。
      final act = _active;
      if (act != null) {
        unawaited(() async {
          try {
            await ref.read(cloudCleanServiceProvider).autoCleanAfterSync(
                ref.read(remoteStoreFactoryProvider)(act), act);
          } catch (e) {
            AppLog.add('云端自动归档钩子忽略：$e', level: LhLevel.warn);
          }
        }());
      }
      _reload();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
            Opacity(
              // 置灰禁用态 = 工程惯例（habit_kit：onTap null + opacity .35）。
              opacity: _busy ? .35 : 1,
              child: Container(
                key: const ValueKey('btn-sync-now'),
                decoration: BoxDecoration(
                  gradient: tokens.gradient,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _busy ? null : _syncNow,
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
                  // _busy 期间同样禁用：S3 打开即发 compare，防叠层
                  // （评审修复轮1）。
                  onTap: _busy ? null : _openDiff,
                ),
                const Divider(height: 1, indent: 14, endIndent: 14),
                _EntryRow(
                  key: const ValueKey('sync-export-loc-entry'),
                  icon: Icons.drive_file_move_outline,
                  title: '导出位置',
                  sub: ref.watch(backupServiceProvider).exportTreeName == null
                      ? '默认 · 应用目录 · 选择后导出直达、备份列表合并显示'
                      : ref.watch(backupServiceProvider).exportTreeName!,
                  onTap: _pickExportLoc,
                ),
                const Divider(height: 1, indent: 14, endIndent: 14),
                _EntryRow(
                  key: const ValueKey('sync-backup-entry'),
                  icon: Icons.inventory_2_outlined,
                  title: '备份导出/导入',
                  sub: '.lhbak 可读的包 · 范围导出 · 纯明文',
                  onTap: () => showBackupSheet(context),
                ),
                const Divider(height: 1, indent: 14, endIndent: 14),
                _EntryRow(
                  key: const ValueKey('sync-throttle-entry'),
                  icon: Icons.speed_outlined,
                  title: '控流',
                  sub: active == null
                      ? '未配置服务'
                      // 人话口径：功能标签式（评审修复轮1——不直出工程术语）。
                      : '请求间隔 ${active.requestIntervalMs}ms · 防服务端频控 · '
                          '快照 ${_keepN(prefs)} 份 · 仅Wi-Fi ${_wifiOnly(prefs) ? '开' : '关'}',
                  onTap: _openThrottle,
                ),
                const Divider(height: 1, indent: 14, endIndent: 14),
                _EntryRow(
                  key: const ValueKey('sync-history-entry'),
                  icon: Icons.history,
                  title: '同步历史',
                  sub: _histSummary(history),
                  // R2 项④：go→push，从 /sync 进历史页后返回回 /sync 而非退出 app。
                  onTap: () => context.push('/sync/history'),
                ),
                const Divider(height: 1, indent: 14, endIndent: 14),
                // 日志入口外移（2026-09-26 真机反馈）：唯一入口在「设置 → 运行日志」，
                // 本页不再挂日志行；「同步历史」点行仍可跳日志页。
                // R5d：云端孤儿附件清理入口（归档为主，删除需逐项确认）。
                _EntryRow(
                  key: const ValueKey('sync-cloud-clean-entry'),
                  icon: Icons.cloud_off_outlined,
                  title: '清理云端',
                  sub: '未引用附件归档 · 彻底删除需确认',
                  onTap: active == null ? null : () => showCloudCleanSheet(context, config: active),
                ),
                const Divider(height: 1, indent: 14, endIndent: 14),
                // B-1 备份文件（原型 p-sub-data 追加行 · 导入主通道：
                // 云下载的包落在应用 exports/，SAF 逛不到，恢复链路此前断在这）。
                _EntryRow(
                  key: const ValueKey('sync-backupfiles-entry'),
                  icon: Icons.folder_zip_outlined,
                  title: '备份文件',
                  sub: '本机导出 · 云端下载 · 恢复前自动',
                  onTap: () => context.push('/settings/backup-files'),
                ),
                // B-4 数据库概览（原型 p-sub-data 追加行 · 轮7 产品自查诉求）。
                _EntryRow(
                  key: const ValueKey('sync-dbstats-entry'),
                  icon: Icons.insights_outlined,
                  title: '数据库概览',
                  sub: '记录构成 · 可再生数据 · 异常自查',
                  onTap: () => context.push('/settings/db-overview'),
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
          // R2 项⑤c：切换服务区底部常驻「添加服务」钮——过去仅空态有入口，用户
          // 想用另一协议新增只能改已建服务协议（覆盖同一服务，致列表只剩一个）。
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('btn-add-svc-persistent'),
              onPressed: () => _openEdit(),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('添加服务'),
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
    // 禁用态 = onTap null + 置灰（工程惯例，habit_kit 同口径）。
    return Opacity(
      opacity: onTap == null ? .35 : 1,
      child: InkWell(
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
                        style:
                            const TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  size: 15, color: Color(0xFF94A3B8)),
            ],
          ),
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
