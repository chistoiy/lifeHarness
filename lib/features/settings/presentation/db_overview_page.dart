/// B-4 数据库概览屏（原型事实源＝`prototype/index.html` `p-sub-dbstats`）。
///
/// 口径（工单 §7-4）：四段照原型——总览三数 / 异常提示卡 / 按模块行直达 /
/// 技术明细折叠。人话分组为主，技术明细折叠供下钻；备份包体积取不到时
/// **隐藏该格**（不编造数字）；垃圾箱书 >0 才渲染异常卡。
/// 扫描进 FutureBuilder，不在 initState 同步查库；禁 emoji、无教学文案。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/backup/db_overview.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/trash/trash_models.dart';
import '../../../shared/trash/trash_providers.dart';

/// 模块 → 管理页路由（工单 §7-4③「点按直达对应管理页」）。
/// 词表新增模块若无入口，行仍显示（无箭头不可点），不造假热区。
const Map<String, String> _moduleRoutes = {
  '阅读': '/read/shelf',
  '记账': '/ledger',
  '笔记': '/journal?tab=note',
  '待办': '/todo',
  '日程': '/calendar',
  '日记': '/journal?tab=diary',
  '习惯': '/habits',
  '呵护': '/care',
  '物品': '/items',
  '目标': '/goals',
  '日子': '/days',
  '收集箱': '/inbox',
  '时间': '/time-stats',
  'AI': '/settings/ai/usage',
  '设置': '/settings',
};

/// 扫描结果 + 备份包体积（字节；null＝取不到，UI 隐藏该格）。
typedef _OverviewData = ({DbOverview overview, int? backupBytes});

class DbOverviewPage extends ConsumerStatefulWidget {
  const DbOverviewPage({super.key, this.backupSizeReader});

  /// 测试注入缝：widget 测试禁真实目录 I/O（FakeAsync 下永不返回）；
  /// 生产 = null → 走 [latestBackupSizeBytes] 读备份导出目录。
  final Future<int?> Function()? backupSizeReader;

  @override
  ConsumerState<DbOverviewPage> createState() => _DbOverviewPageState();
}

class _DbOverviewPageState extends ConsumerState<DbOverviewPage> {
  late Future<_OverviewData> _future = _load();

  Future<_OverviewData> _load() async {
    final overview = await ref.read(dbOverviewScannerProvider).scan();
    final reader = widget.backupSizeReader ??
        () => latestBackupSizeBytes(ref.read(backupServiceProvider).exportDir());
    final bytes = await reader();
    return (overview: overview, backupBytes: bytes);
  }

  void _refresh() => setState(() {
        // 块体而非箭头：箭头会把 _load() 的 Future 当返回值，触 setState 异步红线。
        _future = _load();
      });

  /// 行数人话化：≥1 万记「X.Y万」（整万省 .0），否则千分位。
  static String fmtCount(int n) {
    if (n >= 10000) {
      final one = (n / 1000).roundToDouble(); // 十分之一万为单位
      if (one % 10 == 0) return '${(one / 10).toStringAsFixed(0)}万';
      return '${(one / 10).toStringAsFixed(1)}万';
    }
    return fmtNum(n);
  }

  /// 千分位。
  static String fmtNum(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Scaffold(
      backgroundColor: tokens.page,
      appBar: AppBar(title: const Text('数据库概览')),
      body: FutureBuilder<_OverviewData>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(
                child: Text('统计未成功，可退出后重试',
                    style: TextStyle(fontSize: 12.5)));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final d = snap.data!;
          final o = d.overview;
          final trashBooks =
              ref.watch(trashCountsProvider).byKind[TrashKind.book] ?? 0;
          return ListView(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
            children: [
              _overviewCard(o, d.backupBytes),
              if (trashBooks > 0) ...[
                const SizedBox(height: 12),
                _warnCard(o, trashBooks),
              ],
              const SizedBox(height: 12),
              _moduleCard(o),
              const SizedBox(height: 12),
              _detailsCard(o),
            ],
          );
        },
      ),
    );
  }

  // —— ① 总览三数 ——
  Widget _overviewCard(DbOverview o, int? backupBytes) {
    final cells = <Widget>[
      _statCell('dbo-total', fmtCount(o.totalRows), '记录总行数', null),
      if (backupBytes != null)
        _statCell('dbo-size', formatBytes(backupBytes), '备份包体积', null),
      _statCell('dbo-regen', '${(o.regenerableRatio * 100).round()}%',
          '可再生占比', const Color(0xFFD97706)),
    ];
    return Container(
      key: const ValueKey('dbo-overview'),
      decoration: context.cardDecoration,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                  child: Text('数据总览',
                      style: TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w800))),
              TextButton(
                key: const ValueKey('dbo-refresh'),
                onPressed: _refresh,
                child:
                    const Text('刷新', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(children: [
            for (final c in cells)
              Expanded(child: c),
          ]),
          if (o.regenerableRows > 0) ...[
            const SizedBox(height: 8),
            Text(
              '大头是可再生数据（删了能在阅读器重新解析），已默认不进备份。',
              style: TextStyle(
                  fontSize: 11, height: 1.5, color: Color(0xFF94A3B8)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statCell(String key, String value, String label, Color? color) {
    return Container(
      key: ValueKey(key),
      margin: const EdgeInsets.symmetric(horizontal: 3),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: color?.withValues(alpha: 0.08) ?? const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: color)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  fontSize: 10, color: Color(0xFF94A3B8))),
        ],
      ),
    );
  }

  // —— ② 异常提示卡（垃圾箱书 >0 才渲染）——
  Widget _warnCard(DbOverview o, int trashBooks) {
    final pct = (o.regenerableRatio * 100).round();
    return Container(
      key: const ValueKey('dbo-warn'),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2, right: 8),
            child: Icon(Icons.error_outline,
                size: 18, color: Color(0xFFF59E0B)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('垃圾箱里有 $trashBooks 本书未彻底删除',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                  '可再生数据（全书索引为主）合计约占数据库 $pct%。'
                  '彻底删除可释放空间（保留期内仍可恢复；同内容多份只算一处）。',
                  style: const TextStyle(
                      fontSize: 11, height: 1.5, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton(
                    key: const ValueKey('dbo-goto-trash'),
                    onPressed: () => context.push('/settings/trash'),
                    style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize:
                            MaterialTapTargetSize.shrinkWrap),
                    child: const Text('去回收站 ›',
                        style: TextStyle(fontSize: 11)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // —— ③ 按模块行（直达管理页）——
  Widget _moduleCard(DbOverview o) {
    return Container(
      key: const ValueKey('dbo-modules'),
      decoration: context.cardDecoration,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: Text('按模块查看',
                style:
                    TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
          ),
          for (final m in o.byModule)
            _moduleRow(o, m.module, m.rows, m.tables),
        ],
      ),
    );
  }

  Widget _moduleRow(DbOverview o, String module, int rows, int tables) {
    final route = _moduleRoutes[module];
    // 模块内的最大可再生表（原型阅读行右侧「全书索引 58.7万 · 可再生」）。
    DbOverviewRow? regen;
    for (final r in o.rows) {
      if (r.module == module &&
          r.label.contains('可再生') &&
          (regen == null || r.rows > regen.rows)) {
        regen = r;
      }
    }
    final regenNote = regen == null
        ? null
        : '${regen.label.replaceAll(' · 可再生', '')} '
            '${fmtCount(regen.rows)} · 可再生';
    return InkWell(
      key: ValueKey('dbo-mod-$module'),
      onTap: route == null ? null : () => context.push(route),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(module,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('${fmtCount(rows)} 行 · $tables 张表',
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF94A3B8))),
                ],
              ),
            ),
            if (regenNote != null)
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(regenNote,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          fontSize: 10, color: Color(0xFF94A3B8))),
                ),
              ),
            if (route != null)
              const Text('›',
                  style:
                      TextStyle(fontSize: 14, color: Color(0xFFCBD5E1))),
          ],
        ),
      ),
    );
  }

  // —— ④ 技术明细（逐表行数，默认折叠）——
  Widget _detailsCard(DbOverview o) {
    return Container(
      key: const ValueKey('dbo-details'),
      decoration: context.cardDecoration,
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        tilePadding: const EdgeInsets.fromLTRB(14, 4, 10, 4),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        title: const Text('技术明细（逐表行数）',
            style:
                TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
        children: [
          for (final r in o.rows)
            Padding(
              key: ValueKey('dbo-tbl-${r.table}'),
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text('${r.table} · ${r.label}',
                        style: const TextStyle(
                            fontSize: 11, fontFamily: 'monospace',
                            color: Color(0xFF64748B))),
                  ),
                  Text(fmtNum(r.rows),
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          if (o.emptyTableCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text('… 其余 ${o.emptyTableCount} 张空表',
                  style: const TextStyle(
                      fontSize: 11, color: Color(0xFF94A3B8))),
            ),
        ],
      ),
    );
  }
}
