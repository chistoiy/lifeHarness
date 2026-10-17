import 'dart:io';

import 'package:flutter/material.dart';

/// 批②b（工单 §13·产品过门 E/F/G）：全屏图片查看件。
///
/// 原型事实源＝`prototype/index-sync.html#imgView`（批2 起随 p-sub-mediaclean 迁入该专版）；红线 §3「预览两处同一查看件·禁各造一套」——
/// 笔记/日记缩略图（[showImageLightbox]）与同步差异行、图片清理行（[showImageViewer]）都走本件。
/// 形态：黑底·顶栏「i / N」＋±缩放＋关闭·中间可缩放图（真机双指＝[InteractiveViewer]，
/// 点图 1×⇄2×）·底部人话名（U3）＋技术明细（类型·体积·完整路径）＋左右翻页（到界禁用）。
/// 单图模式（笔记侧）保持旧行为一字不差：点任意处关闭，无顶栏底栏。
class LhViewItem {
  const LhViewItem({
    required this.path,
    required this.label,
    required this.meta,
  });

  /// 磁盘绝对路径（本件只读文件，不触网络）。
  final String path;

  /// 人话主文案（如「笔记插图 · 09-12 14:03」）；单图模式给空串即不渲染底栏。
  final String label;

  /// 技术明细一行（类型 · 体积 · 相对/完整路径），裸哈希只在这里出现。
  final String meta;
}

/// 单图大图查看（笔记/日记缩略图·旧签名与旧行为不变）。
void showImageLightbox(BuildContext context, String path) => _openLhLightbox(
      context,
      [LhViewItem(path: path, label: '', meta: path)],
      listMode: false,
    );

/// 列表查看（差异半屏与图片清理屏共用）：可翻页、可缩放、底部给人话名与明细。
void showImageViewer(BuildContext context, List<LhViewItem> items, int index) =>
    _openLhLightbox(context, items, listMode: true, index: index);

void _openLhLightbox(BuildContext context, List<LhViewItem> items,
    {required bool listMode, int index = 0}) {
  showDialog<void>(
    context: context,
    // 列表档带顶栏与页脚：底下页面文字会透上来与页脚叠成两行（真机 6078 抓到 85%，
    // 6080 复验 95% 仍透）⇒ 列表档改**全不透明**；单图档（笔记/日记）观感一字不动。
    barrierColor: listMode ? const Color(0xFF000000) : const Color(0xD9000000),
    builder: (bc) => _LhLightbox(items: items, listMode: listMode, index: index),
  );
}

class _LhLightbox extends StatefulWidget {
  const _LhLightbox({
    required this.items,
    required this.listMode,
    this.index = 0,
  });

  final List<LhViewItem> items;
  final bool listMode;
  final int index;

  @override
  State<_LhLightbox> createState() => _LhLightboxState();
}

class _LhLightboxState extends State<_LhLightbox> {
  final TransformationController _tc = TransformationController();
  late int _i = widget.index.clamp(0, widget.items.length - 1);
  double _scale = 1;

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  void _setScale(double s) {
    setState(() => _scale = s.clamp(1.0, 4.0));
    _tc.value = Matrix4.diagonal3Values(_scale, _scale, 1.0);
  }

  /// d＝0＝点图互切（1×⇄2×）；±1＝按档缩放。
  void _zoom(int d) => _setScale(d == 0 ? (_scale > 1 ? 1 : 2) : _scale + d);

  void _go(int d) {
    final j = _i + d;
    if (j < 0 || j >= widget.items.length) return;
    setState(() => _i = j);
    _setScale(1); // 换张回原尺寸（原型同档位）
  }

  @override
  Widget build(BuildContext context) {
    final it = widget.items[_i];
    final list = widget.listMode;
    return GestureDetector(
      // 旧件锚点不动：笔记/日记用例点任意处关闭仍命中这里。
      key: const ValueKey('note-img-light'),
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).pop(),
      child: SafeArea(
        child: Column(
          children: [
            if (list)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
                child: Row(
                  children: [
                    Text('${_i + 1} / ${widget.items.length}',
                        key: const ValueKey('lb-pos'),
                        style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: Colors.white70)),
                    const Spacer(),
                    IconButton(
                      key: const ValueKey('lb-zoom-out'),
                      onPressed: () => _zoom(-1),
                      icon: const Icon(Icons.remove,
                          size: 20, color: Colors.white70),
                    ),
                    IconButton(
                      key: const ValueKey('lb-zoom-in'),
                      onPressed: () => _zoom(1),
                      icon: const Icon(Icons.add, size: 20, color: Colors.white70),
                    ),
                    IconButton(
                      key: const ValueKey('lb-close'),
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close,
                          size: 20, color: Colors.white70),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: Center(
                child: GestureDetector(
                  onTap: list ? () => _zoom(0) : null,
                  child: InteractiveViewer(
                    key: const ValueKey('lb-img'),
                    transformationController: _tc,
                    maxScale: 4,
                    child: Image.file(
                      File(it.path),
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const Text('图片已丢失',
                          style: TextStyle(color: Colors.white54)),
                    ),
                  ),
                ),
              ),
            ),
            if (list)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                child: Column(
                  children: [
                    Text(it.label,
                        key: const ValueKey('lb-label'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: Colors.white)),
                    const SizedBox(height: 3),
                    Text(it.meta,
                        key: const ValueKey('lb-meta'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 11, color: Colors.white54)),
                    Row(
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              key: const ValueKey('lb-prev'),
                              onPressed: _i > 0 ? () => _go(-1) : null,
                              icon: const Icon(Icons.chevron_left, size: 18),
                              label: const Text('上一张'),
                              style: TextButton.styleFrom(
                                  foregroundColor: Colors.white70),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              key: const ValueKey('lb-next'),
                              onPressed: _i < widget.items.length - 1
                                  ? () => _go(1)
                                  : null,
                              icon: const Icon(Icons.chevron_right, size: 18),
                              label: const Text('下一张'),
                              style: TextButton.styleFrom(
                                  foregroundColor: Colors.white70),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
