import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/sync/sync_orchestrator.dart';
import '../../../core/sync/sync_providers.dart';
import '../../../core/theme/app_theme.dart';
import 'widgets/sync_sheets.dart';

/// V1.41 Task 18 · P2「同步历史」列表页（原型 index-sync.html p-synchist）。
///
/// 口径：行 = 时间 · 服务名 / 上传 n · 下载 m · 量 · 结果角标；点击行 → /log
/// （原型「已定位该轮同步日志区间」→ 本期跳日志窗口页）。数据源
/// [SyncHistory.read]（prefs `sync_history` 头部新→旧，上限 100 条）。
///
/// 导航口径（评审修复轮1 Important-1）：行点击用 push 压栈而非 go 替换栈——
/// 与 R2 项④同源根因，go 会让系统返回键直接退出 app。
class SyncHistoryPage extends ConsumerWidget {
  const SyncHistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = SyncHistory.read(ref.watch(sharedPreferencesProvider));
    final services = ref.watch(syncConfigStoreProvider).load().services;
    String nameOf(String id) {
      for (final c in services) {
        if (c.id == id) return serviceDisplayName(c);
      }
      return id;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('同步历史'),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(0),
          child: SizedBox.shrink(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Container(
            key: const ValueKey('hist-list'),
            decoration: context.cardDecoration,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                if (entries.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('暂无同步记录',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ),
                for (final e in entries) ...[
                  if (e != entries.first)
                    const Divider(height: 1, indent: 14, endIndent: 14),
                  _HistRow(
                    key: ValueKey('hist-row-${e.ts}'),
                    entry: e,
                    serviceName: nameOf(e.serviceId),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 0, 4, 0),
            child: Text('上限 100 条 · 点击行进入日志窗口',
                style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
          ),
        ],
      ),
    );
  }
}

class _HistRow extends StatelessWidget {
  const _HistRow({
    super.key,
    required this.entry,
    required this.serviceName,
  });

  final SyncHistoryEntry entry;
  final String serviceName;

  @override
  Widget build(BuildContext context) {
    final canceled = entry.error?.contains('canceled') ?? false;
    final (tag, color) = entry.ok
        ? ('成功', const Color(0xFF047857))
        : canceled
            ? ('已取消', const Color(0xFFB45309))
            : ('部分失败', const Color(0xFFEF4444));
    final tokens = context.tokens;
    return InkWell(
      onTap: () => context.push('/log'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .11),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(
                  entry.ok
                      ? Icons.check_rounded
                      : Icons.error_outline_rounded,
                  size: 16,
                  color: color),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${formatHistoryTime(entry.ts)} · $serviceName',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 1),
                  Text(
                      entry.up == 0 && entry.down == 0 && entry.bytes == 0 && !entry.ok
                          ? '— · $tag'
                          : '上传 ${entry.up} · 下载 ${entry.down} · ${formatBytes(entry.bytes)} · $tag',
                      style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: .13),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(tag,
                  style:
                      TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: color)),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 15, color: tokens.accentLight),
          ],
        ),
      ),
    );
  }
}
