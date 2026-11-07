/// 批4④（工单 §2 · 2026-10-12）·**笔记弹层语言单源**。
///
/// 背景：笔记模块的弹层此前有 ≥3 套写法，同一模块内各写各的——
///  ① `note_sheets.dart`（快照 / Kit / 分享）＝ grabber ＋ 标题，但三处的 grabber
///     外边距与标题内边距各不相同；
///  ② `note_export.dart` / `note_local_import.dart` / `note_open_history.dart` ＝
///     **无 grabber**，标题居中或左对齐不一，底部用 Material `OutlinedButton+FilledButton`；
///  ③ `showFolderPickSheet` ＝ **裸 `ListTile`**（默认主题白底），与自绘描边卡行两套语言。
///
/// 统一口径（本件＝唯一出处，新增笔记弹层照此，不再各写各的）：
///  · **头**：居中 grabber（36×4·alpha .18）＋**左对齐**标题 15/w900 ＋可选副标；
///  · **选项**：`NoteSheetRow`（自绘描边卡行，替代裸 `ListTile`）；
///  · **确认**：`NoteSheetActions`（取消 ＋ 主钮，2:1 宽、统一高）——用于「有后果、要问一句」
///    的弹层；纯选项列表（分享/Kit）不出现此钮，直接用 `NoteSheetRow` 点即做。
library;

import 'package:flutter/material.dart';

/// 笔记段危险色单源（rose-500，与 calendar/care 各页同值）：批量删确认、移除挂载等
/// 「有后果」主钮/文字统一引用这里，不再各处重写字面量（color_ratchet 计数不再随弹层加而涨）。
const Color kNoteDanger = Color(0xFFF43F5E);

/// 弹层头：居中 grabber ＋ 左对齐标题（＋可选副标 / 尾件）。
/// [fg] 传纸色前景（编辑页纸色弹层）；不传＝随主题 [ColorScheme.onSurface]。
class NoteSheetHeader extends StatelessWidget {
  const NoteSheetHeader(
      {super.key, required this.title, this.sub, this.fg, this.trailing});

  final String title;
  final String? sub;
  final Color? fg;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final f = fg ?? scheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
                color: f.withValues(alpha: .18),
                borderRadius: BorderRadius.circular(2)),
          ),
        ),
        Row(
          children: [
            Expanded(
                child: Text(title,
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w900, color: f))),
            ?trailing,
          ],
        ),
        if (sub != null)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(sub!,
                style: TextStyle(
                    fontSize: 10.5, color: f.withValues(alpha: .45))),
          ),
      ],
    );
  }
}

/// 选项行：自绘描边卡行（与笔记 Kit / 分享同款）——替代裸 `ListTile`。
class NoteSheetRow extends StatelessWidget {
  const NoteSheetRow(
      {super.key,
      required this.label,
      this.icon,
      this.onTap,
      this.fg,
      this.color,
      this.dense = false,
      this.trailing});

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final Color? fg;
  final Color? color;
  final bool dense;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final f = fg ?? scheme.onSurface;
    final c = color ?? f;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding:
            EdgeInsets.symmetric(horizontal: 14, vertical: dense ? 10 : 13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: f.withValues(alpha: .16)),
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: c),
              const SizedBox(width: 10),
            ],
            Expanded(
                child: Text(label,
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700, color: c))),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

/// 底部确认行：取消 ＋ 主钮（2:1 宽、统一高）。[danger] ＝ 破坏性主钮（玫红）。
class NoteSheetActions extends StatelessWidget {
  const NoteSheetActions(
      {super.key,
      required this.onCancel,
      required this.primaryLabel,
      this.onPrimary,
      this.danger = false,
      this.primaryKey});

  final VoidCallback? onCancel;
  final String primaryLabel;
  final VoidCallback? onPrimary;
  final bool danger;
  final Key? primaryKey;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
            child:
                OutlinedButton(onPressed: onCancel, child: const Text('取消'))),
        const SizedBox(width: 10),
        Expanded(
            flex: 2,
            child: FilledButton(
              key: primaryKey,
              style: danger
                  ? FilledButton.styleFrom(
                      backgroundColor: kNoteDanger)
                  : null,
              onPressed: onPrimary,
              child: Text(primaryLabel),
            )),
      ],
    );
  }
}
