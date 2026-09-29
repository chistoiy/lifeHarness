// 小工具工具屏共用小件（批2 起，13 个工具屏共用；原型 `.mini-btn` / `.prog-chip`
// / `.inp` / `.card` 口径）。
//
// 命名一律 `kit-tool-*`，键值前缀由各屏自带。
import 'dart:io' as io;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/ui_kit.dart';
import '../../domain/kit_color.dart' show KitRgb, kitHexToRgb;

/// hex 串 → Flutter Color（工具屏共用；非法串回落透明黑）。
Color kitColor(String hex) {
  final rgb = kitHexToRgb(hex) ?? const KitRgb(0, 0, 0);
  return Color(0xFF000000 | (rgb.r << 16) | (rgb.g << 8) | rgb.b);
}

/// 小工具描边按钮（原型 `.mini-btn`）。
Widget kitToolBtn(
  BuildContext context,
  String label,
  VoidCallback? onTap, {
  String? keyName,
  bool small = false,
  Color? color,
}) {
  final tokens = context.tokens;
  return Padding(
    padding: EdgeInsets.only(right: small ? 4 : 6, top: small ? 0 : 2, bottom: small ? 0 : 2),
    child: OutlinedButton(
      key: keyName == null ? null : ValueKey(keyName),
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: EdgeInsets.symmetric(horizontal: small ? 8 : 11, vertical: small ? 4 : 7),
        side: BorderSide(color: tokens.cardBorder),
        shape: const StadiumBorder(),
        foregroundColor: color ?? tokens.accent,
      ),
      child: Text(label, style: TextStyle(fontSize: small ? 10 : 11.5, fontWeight: FontWeight.w700)),
    ),
  );
}

/// 可切换的胶囊筛选钮（原型 `.prog-chip` + `.on`）。
class KitToolChip extends StatelessWidget {
  const KitToolChip({
    super.key,
    required this.label,
    required this.on,
    required this.onTap,
    this.keyName,
    this.flex = false,
  });

  final String label;
  final bool on;
  final VoidCallback onTap;
  final String? keyName;
  final bool flex;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: on ? tokens.accent : tokens.card,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: on ? tokens.accent : tokens.cardBorder),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: on ? Colors.white : Colors.grey,
        ),
      ),
    );
    final tap = GestureDetector(
      // 显式 ValueKey<String>：公有字段不参与流分析提升（`ValueKey(keyName)` 会
      // 得到 ValueKey<String?>，与测试里的 find.byKey(ValueKey('x')) 不同型不命中）。
      key: keyName == null ? null : ValueKey<String>(keyName!),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: chip,
    );
    return flex ? Expanded(child: tap) : tap;
  }
}

/// 工具屏分区标题（原型 `.row-title`）。
Widget kitToolSection(String text, {List<Widget> trailing = const []}) => Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
        ),
        ...trailing,
      ],
    );

/// 内联说明文案（原型 `.text-[9px] text-slate-400`）。
Widget kitToolNote(String text, {Key? key}) => Text(
      text,
      key: key,
      style: const TextStyle(fontSize: 10, color: Colors.grey, height: 1.5),
    );

/// 行内结果文案（原型 `#dDiff` / `#dAdd` 那类着色结果行）。
Widget kitToolResult(String text, Color color, {String keyName = 'kit-tool-result'}) => Text(
      text,
      key: ValueKey(keyName),
      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: color),
    );

/// 浅色子卡（原型 `.card !bg-slate-50`）。
Widget kitToolSubCard(BuildContext context, Widget child) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.tokens.card.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.tokens.cardBorder),
      ),
      child: child,
    );

/// 数字输入框（原型 `<input type=number>`；只收整数，空串回落 0）。
class KitToolNumberField extends StatefulWidget {
  const KitToolNumberField({
    super.key,
    required this.value,
    required this.onChanged,
    this.width = 76,
    this.min = 0,
    this.max = 999999,
    this.keyName,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final double width;
  final int min;
  final int max;

  /// 内部 TextField 的键（用例直接 find 输入框；命名沿用各屏前缀）。
  final String? keyName;

  @override
  State<KitToolNumberField> createState() => _KitToolNumberFieldState();
}

class _KitToolNumberFieldState extends State<KitToolNumberField> {
  late final TextEditingController _c = TextEditingController(text: '${widget.value}');

  @override
  void didUpdateWidget(covariant KitToolNumberField old) {
    super.didUpdateWidget(old);
    // 外部复位（快捷钮改值）时同步文本，避免脏字符串。
    if (old.value != widget.value && int.tryParse(_c.text) != widget.value) {
      _c.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: widget.width,
        child: TextField(
          key: widget.keyName == null
              ? null
              : ValueKey<String>(widget.keyName!),
          controller: _c,
          keyboardType: TextInputType.number,
          style: const TextStyle(fontSize: 12),
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (v) {
            final n = int.tryParse(v) ?? widget.min;
            widget.onChanged(n.clamp(widget.min, widget.max));
          },
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 9),
          ),
        ),
      );
}

/// 复制并提示（原型 `cpCopy` + toast）。
void kitToolCopy(BuildContext context, String text, {String msg = '已复制'}) {
  if (text.isEmpty) {
    AppToast.show(context, '还没有可复制的内容');
    return;
  }
  Clipboard.setData(ClipboardData(text: text));
  AppToast.show(context, msg);
}

/// 另存到本机（批3 起 imgz/b64 共用）：先走系统保存对话框，平台不支持时落
/// 应用文件目录。取消或失败返回 null（调用方按「已取消」口径提示）。
///
/// 内部是**真异步 I/O**，只能在生产通道或 `tester.runAsync` 里执行；widget 测试
/// 一律经各屏的 `save` 注入缝替换掉它。
Future<String?> kitToolSaveBytes({
  required String fileName,
  required Uint8List bytes,
  String dialogTitle = '保存到本机',
}) async {
  try {
    final picked = await FilePicker.platform.saveFile(
      dialogTitle: dialogTitle,
      fileName: fileName,
      bytes: bytes,
    );
    if (picked != null) return picked;
  } catch (_) {
    // 平台不支持系统另存 → 落应用文件目录。
  }
  try {
    final dir = await getApplicationDocumentsDirectory();
    final f = io.File('${dir.path}/$fileName');
    await f.writeAsBytes(bytes, flush: true);
    return f.path;
  } catch (_) {
    return null;
  }
}
