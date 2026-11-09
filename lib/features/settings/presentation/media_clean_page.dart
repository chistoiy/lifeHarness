import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/media/media_usage_scanner.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/image_lightbox.dart';
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
                    // 全选/取消全选（2026-10-07 产品令：本屏此前只能逐张勾，与云端清理屏不同形）。
                    if (r.orphans.isNotEmpty)
                      TextButton(
                        key: const ValueKey('mc-all'),
                        onPressed: () => setState(() {
                          if (_checked.length == r.orphans.length) {
                            _checked.clear();
                          } else {
                            _checked
                              ..clear()
                              ..addAll(r.orphans.map((e) => e.path));
                          }
                        }),
                        child: Text(
                            _checked.length == r.orphans.length ? '取消全选' : '全选',
                            style: const TextStyle(fontSize: 12)),
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
                        itemBuilder: (context, i) => _row(r.orphans[i], i, r),
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
                              final n = _checked.length;
                              final bytes = r.orphans
                                  .where((e) => _checked.contains(e.path))
                                  .fold<int>(0, (a, e) => a + e.size);
                              // 确认版式全仓只一份（批六钉·B-1 同口径）＝公共原语 lhConfirm。
                              final ok = await lhConfirm(
                                  context,
                                  '将删除 $n 个文件 · ${_fmt(bytes)}\n'
                                  '· 本机文件直接删除 · 不进回收站 · 不可恢复',
                                  okLabel: '删除');
                              if (!ok || !context.mounted) return;
                              final m = ref
                                  .read(mediaScannerProvider)
                                  .deleteOrphans(_checked.toList());
                              AppToast.show(context, '已清理 $m 个文件');
                              _rescan();
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

  /// 行＝勾选框（唯一勾选靶点 `mc-chk-*`）＋缩略图＋人话主文案（U3）。
  /// 缩略图与主文案＝预览热区（B-3）；裸哈希退到副行「编号 8 位」，全路径只进预览底部。
  /// 版式照已过门样张：整行不当勾选靶（原型里只有勾选框管选中，点字是看大图）。
  Widget _row(MediaScanEntry e, int i, MediaScanResult r) {
    final tokens = context.tokens;
    final on = _checked.contains(e.path);
    return Padding(
      key: ValueKey('mc-row-${e.name}'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: tokens.card,
          border: Border.all(color: tokens.cardBorder),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Checkbox(
                key: ValueKey('mc-chk-${e.name}'),
                value: on,
                visualDensity: VisualDensity.compact,
                onChanged: (v) => setState(() =>
                    v == null ? _checked.remove(e.path) : _checked.add(e.path))),
            GestureDetector(
              key: ValueKey('mc-view-${e.name}'),
              onTap: () => _view(r, i),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Image.file(File(e.path),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: const Color(0xFF94A3B8),
                                  strokeAlign: BorderSide.strokeAlignInside),
                            ),
                            child: const Icon(Icons.image_outlined,
                                size: 16, color: Color(0xFF94A3B8)),
                          )),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                key: ValueKey('mc-title-${e.name}'),
                behavior: HitTestBehavior.opaque,
                onTap: () => _view(r, i),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${e.rootLabel} · ${e.timeText}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text('${_fmt(e.size)} · ${e.extText} · ${e.codeText}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 预览＝共享查看件（列表档位：i/N·±缩放·翻页·底部人话名＋全路径）。
  void _view(MediaScanResult r, int i) {
    final items = r.orphans
        .map((e) => LhViewItem(
            path: e.path,
            label: '${e.rootLabel} · ${e.timeText}',
            meta: '${e.extText} · ${_fmt(e.size)} · ${e.relPath}'))
        .toList(growable: false);
    showImageViewer(context, items, i);
  }
}
