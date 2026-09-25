import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'ui_kit.dart';

/// M1批2a · 插图公共链（笔记/日记共用·原型 sheetImgSrc）：
/// 相册/拍照弹层 → ImagePicker → 拷贝应用目录 note_images/ → 返回落盘路径
/// （任一步取消/失败=null）。key img-gallery/img-camera 与拆分前一致，
/// 既有 note_test 假平台用例不受影响。
/// [direct] 非空时跳过弹层直取该来源（日记「＋拍照/＋相册」两格）。
Future<String?> pickAndStoreImage(BuildContext context,
    {required Color bg, required Color fg, ImageSource? direct}) async {
  final src = direct != null
      ? (direct == ImageSource.camera ? 'camera' : 'gallery')
      : await showModalBottomSheet<String>(
    context: context,
    backgroundColor: bg,
    builder: (bc) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            key: const ValueKey('img-gallery'),
            title: Text('从相册选择', style: TextStyle(fontSize: 13.5, color: fg)),
            onTap: () => Navigator.of(bc).pop('gallery'),
          ),
          ListTile(
            key: const ValueKey('img-camera'),
            title: Text('拍照', style: TextStyle(fontSize: 13.5, color: fg)),
            onTap: () => Navigator.of(bc).pop('camera'),
          ),
          const SizedBox(height: 6),
        ],
      ),
    ),
  );
  if (src == null || !context.mounted) return null;
  XFile? picked;
  try {
    picked = await ImagePicker().pickImage(
        source: src == 'camera' ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 88);
  } catch (_) {
    if (context.mounted) AppToast.show(context, '相机/相册暂不可用');
    return null;
  }
  if (picked == null || !context.mounted) return null;
  try {
    final dir = await getApplicationDocumentsDirectory();
    final outDir = Directory(p.join(dir.path, 'note_images'));
    if (!await outDir.exists()) await outDir.create(recursive: true);
    final dot = picked.path.lastIndexOf('.');
    final ext = dot > 0 ? picked.path.substring(dot + 1).toLowerCase() : 'jpg';
    // R5b：SHA256 内容寻址命名——同图全局只存一份（去重），文件名即内容
    // 指纹（孤儿判定/差异比对零读二进制）；毫秒时间戳旧名由启动迁移服务收编。
    final bytes = await File(picked.path).readAsBytes();
    final hash = crypto.sha256.convert(bytes).toString();
    final dest = p.join(outDir.path, '$hash.$ext');
    final f = File(dest);
    if (!await f.exists()) await f.writeAsBytes(bytes);
    return context.mounted ? dest : null;
  } catch (_) {
    if (context.mounted) AppToast.show(context, '插图失败 · 请重试');
    return null;
  }
}

/// 本地图片嵌入渲染（image_picker 拷贝后的应用目录文件路径）。
/// M1批2b 起笔记/日记富文本共用（原 note_edit_page 私有类上移）。
class NoteImageEmbedBuilder extends EmbedBuilder {
  const NoteImageEmbedBuilder();

  @override
  String get key => BlockEmbed.imageType;

  @override
  String toPlainText(Embed node) => '图片';

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final path = embedContext.node.value.data as String? ?? '';
    final width = MediaQuery.sizeOf(context).width - 40;
    return Padding(
      key: ValueKey('embed-img-$path'),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(
          File(path),
          width: width,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Container(
            width: width,
            height: 90,
            alignment: Alignment.center,
            color: const Color(0x11000000),
            child: const Text('图片已丢失',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
          ),
        ),
      ),
    );
  }
}

/// 点缩略图看大图（原型 #imgLight：全屏黑底 · 再点任意处关闭）。
void showImageLightbox(BuildContext context, String path) {
  showDialog<void>(
    context: context,
    barrierColor: const Color(0xD9000000),
    builder: (bc) => GestureDetector(
      key: const ValueKey('note-img-light'),
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(bc).pop(),
      child: Center(
        child: InteractiveViewer(
          child: Image.file(File(path),
              errorBuilder: (_, _, _) => const Text('图片已丢失',
                  style: TextStyle(color: Colors.white54))),
        ),
      ),
    ),
  );
}

/// 120×120 方形缩略卡（原型轮9c ins-img · 点图看大图 · 右上✕删）。
/// onTap 为空时点图走大图；delKey 供测试定位。
class ImageSquareCard extends StatelessWidget {
  const ImageSquareCard({
    super.key,
    required this.path,
    required this.fg,
    this.onDelete,
    this.cardKey,
    this.delKey,
  });

  final String path;
  final Color fg;
  final VoidCallback? onDelete;
  final Key? cardKey;
  final Key? delKey;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            GestureDetector(
              key: cardKey,
              onTap: () => showImageLightbox(context, path),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.file(
                  File(path),
                  width: 120,
                  height: 120,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    width: 120,
                    height: 120,
                    alignment: Alignment.center,
                    color: fg.withValues(alpha: .08),
                    child: Text('图片已丢失',
                        style: TextStyle(
                            fontSize: 11, color: fg.withValues(alpha: .45))),
                  ),
                ),
              ),
            ),
            if (onDelete != null)
              Positioned(
                top: -6,
                right: -6,
                child: GestureDetector(
                  key: delKey,
                  onTap: onDelete,
                  child: Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: Color(0xDC000000),
                      shape: BoxShape.circle,
                    ),
                    child: const Text('✕',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Colors.white)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
