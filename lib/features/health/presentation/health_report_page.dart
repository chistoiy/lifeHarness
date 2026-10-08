import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/image_attach.dart' show showImageLightbox;
import '../../../shared/widgets/ui_kit.dart';
import '../domain/health_models.dart';
import '../domain/health_report.dart';
import 'health_providers.dart';
import 'health_sheets.dart';

/// 检查报告（原型 `p-report` · 路由 `/health/report` · 批3.5b）。
///
/// 三块共用**同一份档案内全量**（`healthReportProvider` 一次把父行＋检验项拼好），
/// 四条口径写在最近处：
/// · 统计三位吃**全量**、月份 chips 只筛下面的卡（原型 `rpRender` 先算 `rpStat` 再 `filter`），
///   所以筛到 9 月时「报告 4 份」不会跟着变成 1 份；
/// · 卡片**默认折叠**（原型 `rpBody` 起手带 `hidden`），点行头只展开明细，不当编辑入口用；
/// · 偏高/偏低按行内参考范围**实时算**（`hkFlagOf`），表里没有状态列，改参考范围不需要迁移；
/// · 底部常驻「上传检查报告」（原型空态原话「点下方上传」），入口在这不在 AppBar——
///   操作条挂 `bottomNavigationBar`，FAB 会压住末行卡片的按钮（真机踩过同形）。
class HealthReportPage extends ConsumerStatefulWidget {
  const HealthReportPage({super.key});

  static const Key kStat = ValueKey('hrpt-stat');
  static const Key kMonths = ValueKey('hrpt-months');

  @override
  ConsumerState<HealthReportPage> createState() => _HealthReportPageState();
}

class _HealthReportPageState extends ConsumerState<HealthReportPage> {
  String _month = '全部';

  /// 展开的报告 id 集合：默认全折叠（原型口径），切档案不清空——档案换了 id 就不撞，
  /// 撞了也只是少折叠一次，不静默改用户看过的展开态。
  final Set<int> _open = {};

  @override
  Widget build(BuildContext context) {
    ref.watch(healthTickProvider);
    final profiles = (ref.watch(healthProfilesProvider).valueOrNull ?? const <HealthProfile>[])
        .where((p) => !p.archived)
        .toList();
    final all = ref.watch(healthReportProvider).valueOrNull ?? const <ReportBundle>[];
    final stat = rpStatOf(all);
    final chips = rpMonthChips(all);
    // 「全部」还在、当前选的月份这批数据里没了（删掉最后一份报告）→ 回落全部，
    // 不然屏上会是一片空白加一枚点不掉的 chips。
    if (_month != '全部' && !chips.contains(_month)) _month = '全部';
    final shown = rpDesc(rpByMonth(all, _month));

    return Scaffold(
      appBar: AppBar(title: const Text('检查报告')),
      bottomNavigationBar: _addBar(context),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        children: [
          _profileBar(profiles),
          const SizedBox(height: 8),
          _statCard(context, stat),
          const SizedBox(height: 12),
          _monthRow(context, chips),
          const SizedBox(height: 4),
          if (shown.isEmpty)
            Text(rpEmptyTx,
                key: const ValueKey('hrpt-empty'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant))
          else
            ..._cards(context, shown),
          const SizedBox(height: 8),
          Text('报告图片与 PDF 仅存本机 · 随本地备份导出',
              key: const ValueKey('hrpt-footnote'),
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  // ==================== 档案 chips（切换即整屏重取，跨档案不聚合） ====================

  Widget _profileBar(List<HealthProfile> profiles) {
    final cur = ref.read(activeHealthProfileProvider);
    return SizedBox(
      height: 30,
      child: ListView(
        key: const ValueKey('hrpt-bar'),
        scrollDirection: Axis.horizontal,
        children: [
          for (final p in profiles)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: PillChip(
                key: ValueKey('hrpt-profile-${p.id}'),
                label: '${p.name} ${p.rel}',
                selected: p.id == cur,
                onTap: () {
                  ref.read(activeHealthProfileProvider.notifier).state = p.id;
                  healthTouch(ref);
                },
              ),
            ),
        ],
      ),
    );
  }

  // ==================== 统计三位 ====================

  Widget _statCard(BuildContext context, RpStat stat) {
    final scheme = Theme.of(context).colorScheme;
    final cells = <(String, String)>[
      ('报告', '${stat.reports} 份'),
      ('异常项', '${stat.abnormal} 条'),
      ('图片/PDF', '${stat.attachments} 个'),
    ];
    return Container(
      key: HealthReportPage.kStat,
      decoration: context.cardDecoration,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          for (final (label, value) in cells)
            Expanded(
              child: Container(
                key: ValueKey('hrpt-stat-$label'),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: scheme.onSurface.withValues(alpha: .05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text(value,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: context.tokens.accent)),
                    const SizedBox(height: 2),
                    Text(label,
                        style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ==================== 月份 chips ====================

  Widget _monthRow(BuildContext context, List<String> chips) {
    return SizedBox(
      key: HealthReportPage.kMonths,
      height: 30,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final m in chips)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: PillChip(
                key: ValueKey('hrpt-month-$m'),
                label: rpMonthTx(m),
                selected: m == _month,
                onTap: () => setState(() => _month = m),
              ),
            ),
        ],
      ),
    );
  }

  // ==================== 报告卡（默认折叠） ====================

  List<Widget> _cards(BuildContext context, List<ReportBundle> bs) {
    final scheme = Theme.of(context).colorScheme;
    return [
      for (final b in bs)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            key: ValueKey('hrpt-card-${b.report.id}'),
            clipBehavior: Clip.antiAlias,
            decoration: context.cardDecoration,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  key: ValueKey('hrpt-toggle-${b.report.id}'),
                  onTap: () => setState(() => _open.contains(b.report.id!)
                      ? _open.remove(b.report.id!)
                      : _open.add(b.report.id!)),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(b.report.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 13, fontWeight: FontWeight.w800)),
                              const SizedBox(height: 2),
                              Text(rpCardSub(b),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 9, color: scheme.onSurfaceVariant)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        _flag(context, rpBadgeTx(b.abnormalCount),
                            b.abnormalCount > 0 ? scheme.error : context.tokens.accent,
                            key: ValueKey('hrpt-badge-${b.report.id}')),
                        const SizedBox(width: 6),
                        Text(rpArrow(_open.contains(b.report.id)),
                            key: ValueKey('hrpt-arrow-${b.report.id}'),
                            style: TextStyle(
                                fontSize: 13, color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ),
                if (_open.contains(b.report.id)) _body(context, b),
              ],
            ),
          ),
        ),
    ];
  }

  Widget _body(BuildContext context, ReportBundle b) {
    final scheme = Theme.of(context).colorScheme;
    final r = b.report;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (r.files.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(
                key: ValueKey('hrpt-files-${r.id}'),
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < r.files.length; i++)
                    _attachThumb(context, r.files[i], ValueKey('hrpt-file-$i')),
                ],
              ),
            ),
          if (b.metrics.isEmpty)
            Text(rpNoMetricTx,
                key: ValueKey('hrpt-metric-empty-${r.id}'),
                style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant))
          else
            Column(
              key: ValueKey('hrpt-metrics-${r.id}'),
              children: [
                for (final m in b.metrics)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      key: ValueKey('hrpt-metric-${m.id}'),
                      children: [
                        Expanded(
                            child: Text(m.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11))),
                        Text(rpMetricValueTx(m),
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w800)),
                        const SizedBox(width: 6),
                        Text(rpMetricRefTx(m),
                            style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant)),
                        const SizedBox(width: 6),
                        _flag(
                            context,
                            hkFlagTx(b.flagOf(m)),
                            _flagColor(scheme, b.flagOf(m)),
                            key: ValueKey('hrpt-flag-${m.id}')),
                      ],
                    ),
                  ),
              ],
            ),
          Text(rpAdviceTx(r.doctorAdvice),
              key: ValueKey('hrpt-advice-${r.id}'),
              style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          // 原型这里有第三枚「关联笔记 ›」，本体是 `toast(…（模拟）)`：真实双向链接属批7 共享面，
          // 按「不铺假入口」整枚不出现（偏离登记在批3.5 工单 §2），这里不留占位。
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: ValueKey('hrpt-metric-add-${r.id}'),
                  style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      minimumSize: const Size(0, 32),
                      visualDensity: VisualDensity.compact),
                  onPressed: () => showHealthMetricSheet(context, report: r, metrics: b.metrics),
                  child: const Text('＋ 检验项',
                      maxLines: 1, style: TextStyle(fontSize: 11)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  key: ValueKey('hrpt-del-${r.id}'),
                  onPressed: () => _delete(b),
                  style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      minimumSize: const Size(0, 32),
                      visualDensity: VisualDensity.compact),
                  child: Text('删除报告',
                      maxLines: 1,
                      style: TextStyle(
                          fontSize: 11, color: scheme.error, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 附件缩略位（56×56）：图片点开看大图，PDF 只作本机留档标记（无内建阅读器，点了不给假预览）。
  Widget _attachThumb(BuildContext context, String path, Key key) {
    final scheme = Theme.of(context).colorScheme;
    final isPdf = path.toLowerCase().endsWith('.pdf');
    return GestureDetector(
      key: key,
      onTap: isPdf ? null : () => showImageLightbox(context, path),
      child: Container(
        width: 56,
        height: 56,
        alignment: Alignment.center,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: scheme.onSurface.withValues(alpha: .05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: isPdf
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.description_outlined, size: 16, color: scheme.onSurfaceVariant),
                  Text('PDF', style: TextStyle(fontSize: 8, color: scheme.onSurfaceVariant)),
                ],
              )
            : Image.file(File(path),
                width: 56,
                height: 56,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    Icon(Icons.broken_image_outlined, size: 16, color: scheme.onSurfaceVariant)),
      ),
    );
  }

  Color _flagColor(ColorScheme scheme, HkFlag f) =>
      hkIsAbnormal(f) ? scheme.error : (f == HkFlag.none ? scheme.outline : context.tokens.accent);

  Widget _flag(BuildContext context, String tx, Color color, {required Key key}) {
    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(tx,
          style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, color: color)),
    );
  }

  // ==================== 底部上传条 ====================

  Widget _addBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 8 + MediaQuery.viewPaddingOf(context).bottom),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: FilledButton.icon(
        key: const ValueKey('hrpt-add'),
        onPressed: () => showHealthReportSheet(context),
        icon: const Icon(Icons.add, size: 16),
        label: const Text('上传检查报告', style: TextStyle(fontSize: 13)),
      ),
    );
  }

  // ==================== 写操作 ====================

  /// 删除＝先确认（原型 `confirmRow('删除 名称 报告')`），确认后只清 DB 行——
  /// 附件文件交给既有清理服务回收（工单 §2），这里不碰文件系统。
  Future<void> _delete(ReportBundle b) async {
    final ok = await lhConfirm(context, rpDelTx(b.report.name));
    if (!ok || !mounted) return;
    final container = ProviderScope.containerOf(context, listen: false);
    await container.read(healthRepositoryProvider).deleteReport(b.report.profileId, b.report.id!);
    container.read(healthTickProvider.notifier).state++;
    _open.remove(b.report.id);
    if (!mounted) return;
    AppToast.show(context, rpDeletedTx);
  }
}
