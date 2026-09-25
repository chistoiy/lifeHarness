import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/media/media_usage_scanner.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart';

/// R5c：图片存储清理页（原型口径：本地孤儿图片列表 + 勾选清理）。
///
/// 口径：进入即扫描（FutureBuilder）；只列不自动删；清理需勾选 + 确认
/// 双门槛；完成后重扫。UI 遵循无教学文案红线——只留功能标签与状态。
class MediaCleanPage extends ConsumerStatefulWidget {
  const MediaCleanPage({super.key});

  @override
  ConsumerState<MediaCleanPage> createState() => _MediaCleanPageState();
}

class _MediaCleanPageState extends ConsumerState<MediaCleanPage> {
  late Future<MediaScanResult> _future =
      ref.read(mediaScannerProvider).scan();
  final Set<String> _checked = {};

  void _rescan() {
    setState(() {
      _checked.clear();
      _future = ref.read(mediaScannerProvider).scan();
    });
  }

  String _fmt(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Scaffold(
      backgroundColor: tokens.page,
      appBar: AppBar(title: const Text('图片存储清理')),
      body: FutureBuilder<MediaScanResult>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final r = snap.data!;
          final selectedBytes = r.orphans
              .where((e) => _checked.contains(e.path))
              .fold<int>(0, (a, e) => a + e.size);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        r.orphans.isEmpty
                            ? '无未引用图片'
                            : '未引用 ${r.orphans.length} / 共 ${r.totalFiles} · ${_fmt(r.orphanBytes)}',
                        key: const ValueKey('mc-summary'),
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w800),
                      ),
                    ),
                    TextButton(
                      key: const ValueKey('mc-rescan'),
                      onPressed: _rescan,
                      child: const Text('重新扫描', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: r.orphans.isEmpty
                    ? const SizedBox.shrink()
                    : ListView.builder(
                        itemCount: r.orphans.length,
                        itemBuilder: (context, i) {
                          final e = r.orphans[i];
                          return CheckboxListTile(
                            key: ValueKey('mc-row-${e.name}'),
                            value: _checked.contains(e.path),
                            dense: true,
                            controlAffinity: ListTileControlAffinity.leading,
                            onChanged: (v) => setState(
                                () => v == null
                                    ? _checked.remove(e.path)
                                    : v
                                        ? _checked.add(e.path)
                                        : _checked.remove(e.path)),
                            title: Text(e.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 12, fontFamily: 'monospace')),
                            subtitle: Text(_fmt(e.size),
                                style: const TextStyle(fontSize: 11)),
                          );
                        },
                      ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      key: const ValueKey('mc-delete'),
                      onPressed: _checked.isEmpty
                          ? null
                          : () async {
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (bc) => AlertDialog(
                                  title: const Text('清理选中图片'),
                                  content: Text(
                                      '将删除 ${_checked.length} 个文件 · ${_fmt(selectedBytes)}，不可恢复。'),
                                  actions: [
                                    TextButton(
                                        onPressed: () =>
                                            Navigator.pop(bc, false),
                                        child: const Text('取消')),
                                    FilledButton(
                                        key: const ValueKey('mc-confirm'),
                                        onPressed: () =>
                                            Navigator.pop(bc, true),
                                        child: const Text('删除')),
                                  ],
                                ),
                              );
                              if (ok == true && context.mounted) {
                                final n = ref
                                    .read(mediaScannerProvider)
                                    .deleteOrphans(_checked.toList());
                                AppToast.show(context, '已清理 $n 个文件');
                                _rescan();
                              }
                            },
                      child: Text(_checked.isEmpty
                          ? '清理选中'
                          : '清理选中（${_checked.length}）'),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
