import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import 'sync_backup_sheet.dart';

/// V1.41 Task 10 · /sync 空壳页（原型 index-sync p-sync 先占路由）。
///
/// 口径：本批只放标题 +「备份导出/导入」半屏入口 +「同步功能批5接入」
/// 纯功能标签行；服务配置/同步历史主页归批5（Task 18）完成。
class SyncPage extends ConsumerWidget {
  const SyncPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('数据与同步')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            decoration: context.cardDecoration,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _SyncRow(
                  key: const ValueKey('sync-backup-entry'),
                  title: '备份导出/导入',
                  sub: '.lhbak 容器 · 口令加密 · 日志随包',
                  onTap: () => showBackupSheet(context),
                ),
                const Divider(height: 1),
                const _SyncRow(
                  key: ValueKey('sync-cloud-entry'),
                  title: '云端同步',
                  sub: 'WebDAV · S3 · 差异比对 · 同步历史',
                  trailing: '同步功能批5接入',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncRow extends StatelessWidget {
  const _SyncRow({
    super.key,
    required this.title,
    required this.sub,
    this.trailing = '',
    this.onTap,
  });

  final String title;
  final String sub;
  final String trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w700)),
                  Text(sub,
                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ),
            if (trailing.isNotEmpty)
              Text(trailing,
                  style: const TextStyle(fontSize: 10.5, color: Colors.grey)),
            if (onTap != null)
              const Text(' ›', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}
