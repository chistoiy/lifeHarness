import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../shared/widgets/image_attach.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../domain/item_extras.dart';
import 'items_kit.dart';

/// I05/I08/I10/I11/I12/I13/I14 实物属性编辑弹层（建档草稿态 / 详情改档共用）。
/// 返回编辑后的 [ItemExtras]；取消＝null。**写库由调用方决定**（草稿态绝不落库，
/// 因为建档时还没有 item_id）。
Future<ItemExtras?> showItemExtrasSheet(BuildContext context,
        {required ItemExtras initial}) =>
    showItemsSheet<ItemExtras>(
      context,
      title: '实物属性',
      builder: (_) => ItemExtrasSheet(initial: initial),
    );

class ItemExtrasSheet extends StatefulWidget {
  const ItemExtrasSheet({super.key, required this.initial});

  final ItemExtras initial;

  @override
  State<ItemExtrasSheet> createState() => _ItemExtrasSheetState();
}

class _ItemExtrasSheetState extends State<ItemExtrasSheet> {
  late final TextEditingController _l1Ctl;
  late final TextEditingController _l2Ctl;
  late final TextEditingController _barcodeCtl;
  late final TextEditingController _loanToCtl;
  late final TextEditingController _loanDueCtl;
  late final TextEditingController _cfKeyCtl;
  late final TextEditingController _cfValCtl;

  late List<String> _photos;
  late List<ItemAttachment> _attachments;
  late Map<String, String> _customFields;
  String? _loanAt;
  String _attachKind = kAttachKinds.first;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _photos = List<String>.of(i.photos);
    _attachments = List<ItemAttachment>.of(i.attachments);
    _customFields = Map<String, String>.of(i.customFields);
    _loanAt = i.loanAt;
    final loc = decodeLocation(i.locationPath);
    _l1Ctl = TextEditingController(text: loc?.l1 ?? '');
    _l2Ctl = TextEditingController(text: loc?.l2 ?? '');
    _barcodeCtl = TextEditingController(text: i.barcode ?? '');
    _loanToCtl = TextEditingController(text: i.loanTo ?? '');
    _loanDueCtl = TextEditingController(text: i.loanDue ?? '');
    _cfKeyCtl = TextEditingController();
    _cfValCtl = TextEditingController();
  }

  @override
  void dispose() {
    _l1Ctl.dispose();
    _l2Ctl.dispose();
    _barcodeCtl.dispose();
    _loanToCtl.dispose();
    _loanDueCtl.dispose();
    _cfKeyCtl.dispose();
    _cfValCtl.dispose();
    super.dispose();
  }

  ItemExtras _collect() {
    final loc = (_l1Ctl.text.trim().isEmpty && _l2Ctl.text.trim().isEmpty)
        ? null
        : encodeLocation(_l1Ctl.text, _l2Ctl.text);
    final lent = _loanToCtl.text.trim().isNotEmpty;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    return ItemExtras(
      photos: List<String>.unmodifiable(_photos),
      locationPath: isValidLocationPath(loc) ? loc : null,
      attachments: List<ItemAttachment>.unmodifiable(_attachments),
      barcode:
          _barcodeCtl.text.trim().isEmpty ? null : _barcodeCtl.text.trim(),
      loanTo: lent ? _loanToCtl.text.trim() : null,
      loanAt: lent ? (_loanAt ?? today) : null,
      loanDue: _loanDueCtl.text.trim().isEmpty
          ? null
          : _loanDueCtl.text.trim(),
      customFields: Map<String, String>.unmodifiable(_customFields),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final overdue = isLoanOverdue(
      loanTo: _loanToCtl.text,
      loanDue: _loanDueCtl.text,
      today: DateTime.now(),
    );
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // —— I01 单图入口 / I14 多图 ——
          _head('照片 · 多图（I01 拍照/相册 + I14 多图）'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < _photos.length; i++)
                _chip(
                  key: ValueKey('i-extras-photo-$i'),
                  label: p.basename(_photos[i]),
                  icon: Icons.image_outlined,
                  scheme: scheme,
                  onDelete: () => setState(() => _photos.removeAt(i)),
                ),
              MiniBtn(
                key: const ValueKey('i-extras-photo-cam'),
                icon: Icons.photo_camera_outlined,
                label: '拍照',
                onTap: () => _pickPhoto(ImageSource.camera),
              ),
              MiniBtn(
                key: const ValueKey('i-extras-photo-lib'),
                icon: Icons.photo_library_outlined,
                label: '相册',
                onTap: () => _pickPhoto(ImageSource.gallery),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('首张作封面 · 复用既有图片选择基建（拍照/相册）落本机目录',
              style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 14),

          // —— I05 位置两层树 ——
          _head('位置两层树（I05 · 房间 / 收纳位）'),
          Row(
            children: [
              Expanded(
                  child: _tf(_l1Ctl, '一级 · 房间', scheme,
                      const ValueKey('i-extras-loc1'))),
              const SizedBox(width: 8),
              Expanded(
                  child: _tf(_l2Ctl, '二级 · 收纳位', scheme,
                      const ValueKey('i-extras-loc2'))),
            ],
          ),
          const SizedBox(height: 14),

          // —— I08 凭证附件 ——
          _head('凭证附件（I08 · 发票照片 / 说明书 PDF）'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (var i = 0; i < _attachments.length; i++)
                _chip(
                  key: ValueKey('i-extras-attach-$i'),
                  label: '${_attachments[i].kind}·${p.basename(_attachments[i].path)}',
                  icon: Icons.receipt_long_outlined,
                  scheme: scheme,
                  onDelete: () => setState(() => _attachments.removeAt(i)),
                ),
              _attachKindDropdown(scheme),
              MiniBtn(
                key: const ValueKey('i-extras-attach-add'),
                icon: Icons.attach_file,
                label: '添加凭证',
                onTap: _addAttachment,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('任意文件走既有 FilePicker 通道 · 落本机 note_images（与 I01 同基建、随整包备份）',
              style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 14),

          // —— I10 条码扫码 ——
          _head('条码（I10 · 复用既有 flutter_zxing ISBN 扫码通道）'),
          Row(
            children: [
              Expanded(
                  child: _tf(_barcodeCtl, '扫码或手输 EAN/UPC', scheme,
                      const ValueKey('i-extras-barcode'))),
              const SizedBox(width: 8),
              MiniBtn(
                key: const ValueKey('i-extras-scan'),
                icon: Icons.qr_code_scanner,
                label: '扫码',
                onTap: _scanBarcode,
              ),
            ],
          ),
          const SizedBox(height: 14),

          // —— I11 借出归还 ——
          _head('借出归还（I11 · 到期提醒）'),
          Row(
            children: [
              Expanded(
                  child: _tf(_loanToCtl, '借给谁', scheme,
                      const ValueKey('i-extras-loan-to'))),
              const SizedBox(width: 8),
              Expanded(
                  child: _tf(_loanDueCtl, '应还日 YYYY-MM-DD', scheme,
                      const ValueKey('i-extras-loan-due'))),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              if (overdue)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text('已逾期',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: scheme.error)),
                ),
              MiniBtn(
                key: const ValueKey('i-extras-loan-return'),
                icon: Icons.assignment_return_outlined,
                label: '标记归还',
                onTap: _markReturned,
              ),
            ],
          ),
          const SizedBox(height: 14),

          // —— I13 自定义字段 ——
          _head('自定义字段（I13 · 键值）'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in _customFields.entries)
                _chip(
                  key: ValueKey('i-extras-cf-${e.key}'),
                  label: '${e.key}: ${e.value}',
                  icon: Icons.label_outline,
                  scheme: scheme,
                  onDelete: () =>
                      setState(() => _customFields.remove(e.key)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                  child: _tf(_cfKeyCtl, '字段名', scheme,
                      const ValueKey('i-extras-cf-key'))),
              const SizedBox(width: 8),
              Expanded(
                  child: _tf(_cfValCtl, '值', scheme,
                      const ValueKey('i-extras-cf-val'))),
            ],
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: MiniBtn(
              key: const ValueKey('i-extras-cf-add'),
              icon: Icons.add,
              label: '添加字段',
              onTap: _addCustomField,
            ),
          ),
          const SizedBox(height: 14),

          // —— I12 AI 拍照识别：需求门灰位（零在线服务 / 零网络目的地）——
          _aiGrayCard(scheme),
          const SizedBox(height: 16),
          _saveBtn(scheme),
        ],
      ),
    );
  }

  Widget _head(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
      );

  Widget _tf(TextEditingController ctl, String label, ColorScheme scheme,
          Key key) =>
      TextField(
        key: key,
        controller: ctl,
        style: TextStyle(fontSize: 12, color: scheme.onSurface),
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          filled: true,
          fillColor: scheme.surfaceContainerHighest,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
        ),
      );

  Widget _chip({
    required Key key,
    required String label,
    required IconData icon,
    required ColorScheme scheme,
    required VoidCallback onDelete,
  }) =>
      GestureDetector(
        key: key,
        onTap: onDelete,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: scheme.primary),
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10.5, color: scheme.onSurface)),
              ),
              const SizedBox(width: 4),
              Icon(Icons.close, size: 12, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      );

  Widget _attachKindDropdown(ColorScheme scheme) => DropdownButton<String>(
        value: _attachKind,
        isDense: true,
        style: TextStyle(fontSize: 11, color: scheme.onSurface),
        items: [
          for (final k in kAttachKinds)
            DropdownMenuItem<String>(value: k, child: Text(k)),
        ],
        onChanged: (v) {
          if (v != null) {
            setState(() {
              _attachKind = v;
            });
          }
        },
      );

  Widget _aiGrayCard(ColorScheme scheme) {
    final g = kAiPhotoRecognitionGate;
    return Container(
      key: const ValueKey('i-extras-ai-gray'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_outlined,
                  size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text('${g.label}（需求门 · 灰位）',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '拍照→AI 建议名称/品牌/分类→确认入库：本地入口占位，未启用；'
            '不接任何在线服务、零新增网络目的地。',
            style:
                TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _saveBtn(ColorScheme scheme) => GestureDetector(
        key: const ValueKey('i-extras-save'),
        onTap: () => Navigator.of(context).pop(_collect()),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text('保存实物属性',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: scheme.onPrimary)),
        ),
      );

  // ==================== 交互（沿用既有基建，零新依赖） ====================

  /// I01/I14：复用 `pickAndStoreImage`（ImagePicker → 内容寻址落 note_images）。
  Future<void> _pickPhoto(ImageSource src) async {
    final scheme = Theme.of(context).colorScheme;
    final dest = await pickAndStoreImage(
      context,
      bg: scheme.surface,
      fg: scheme.onSurface,
      direct: src,
    );
    if (dest != null && mounted) setState(() => _photos.add(dest));
  }

  /// I08：复用既有 FilePicker 任意文件通道 + 内容寻址落 `note_images/`
  /// （与 `pickAndStoreImage` / health `pickAndStorePdf` 同款本地文件基建，
  /// 落备份根而非另造目录，确保随整包备份带走）。
  ///
  /// ⚠ 交叉域后续项（本轮 `lib/core/media` 不在允许改的路径内）：
  /// `MediaUsageScanner._refColumns` 目前只登记 `('item_profiles','photo')`；
  /// v53 新增的 `photos` / `attachments` 两列需在下一批补登，否则存储清理
  /// 会把在档多图/凭证误判为孤儿。本批不越线改 media，先留明确说明。
  Future<String?> _pickAttachmentPath() async {
    String? src;
    try {
      final r = await FilePicker.platform.pickFiles(type: FileType.any);
      src = (r == null || r.files.isEmpty) ? null : r.files.single.path;
    } catch (_) {
      return null;
    }
    if (src == null) return null;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final outDir = Directory(p.join(dir.path, 'note_images'));
      if (!await outDir.exists()) await outDir.create(recursive: true);
      final bytes = File(src).readAsBytesSync();
      final hash = crypto.sha256.convert(bytes).toString();
      final dest = p.join(outDir.path, hash + p.extension(src));
      final f = File(dest);
      if (!await f.exists()) f.writeAsBytesSync(bytes);
      return dest;
    } catch (_) {
      return null;
    }
  }

  Future<void> _addAttachment() async {
    final dest = await _pickAttachmentPath();
    if (!mounted) return;
    if (dest == null) {
      AppToast.show(context, '未选择凭证文件');
      return;
    }
    setState(() {
      _attachments.add(ItemAttachment(
          kind: _attachKind, path: dest, name: p.basename(dest)));
    });
  }

  /// I10：复用既有 `/read/scan` 路由（IsbnScanPage · flutter_zxing 一维码通道）。
  /// 路由未接线时留位＋明确说明，绝不硬造 API、零新增网络目的地。
  Future<void> _scanBarcode() async {
    final router = GoRouter.maybeOf(context);
    if (router == null) {
      AppToast.show(context, '扫码通道 /read/scan（flutter_zxing）· 当前未接线路由');
      return;
    }
    final code = await router.push<String>('/read/scan');
    if (code == null || !mounted) return;
    if (!isValidBarcode(code)) {
      AppToast.show(context, '扫描结果不是有效条码（需 8/12/13/14 位数字）');
      return;
    }
    setState(() {
      _barcodeCtl.text = code;
    });
  }

  void _markReturned() {
    setState(() {
      _loanToCtl.clear();
      _loanDueCtl.clear();
      _loanAt = null;
    });
  }

  void _addCustomField() {
    final k = _cfKeyCtl.text.trim();
    if (!isValidCustomFieldKey(k)) {
      AppToast.show(context, '字段名不合法（非空/无首尾空格/≤32字/非保留键）');
      return;
    }
    setState(() {
      _customFields[k] = _cfValCtl.text.trim();
      _cfKeyCtl.clear();
      _cfValCtl.clear();
    });
  }
}
