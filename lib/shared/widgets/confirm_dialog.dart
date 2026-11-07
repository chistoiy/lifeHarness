import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// LH-S31 破坏性操作二次确认（批六 T3 · 由日子模块 `daysConfirm` 提升为公共原语）。
///
/// 口径：取消在左、destructive 动作在右并着玫红 `#F43F5E`（与表单就地错误同族色），
/// 两者视觉上分得开；点遮罩/返回＝取消，**绝不默认执行**。
/// 文案由调用方给一句人话（说清删的是什么、能不能回来），本原语不拼句子。
/// key 沿用日子侧的 `d-confirm-ok` / `d-confirm-cancel`——既有用例与真机走查锚点不拆。
///
/// **NFC 批2 扩展（2026-10-17）**：加两个可选参数，**默认值与原行为逐位相同**——
/// · [title]：非空时在正文上方加一行标题（冻结档 F2-9 要求「标题＝卡名」，而既有
///   删除确认从不带标题，故缺省 null ⇒ 既有 30 处版式一字不动）；
/// · [destructive]：缺省 true 保持玫红确认钮（删除/不可逆语义）；**执行类确认**
///   （如 NFC 贴卡「要去「X」吗」）传 false ⇒ 确认钮改用主题主色，不把「执行」染成
///   「删除」的红（语义正确性，不是审美）。
///
/// 为什么放 shared：`features/days/**` 不能被 `features/care/**` import（架构守护 R1），
/// 而两侧要的是同一个确认版式；复制一份迟早分叉。
Future<bool> lhConfirm(BuildContext context, String message,
    {String okLabel = '删除', String? title, bool destructive = true}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (bc) => AlertDialog(
      title: (title == null || title.trim().isEmpty)
          ? null
          : Text(title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      content: Text(message, style: const TextStyle(fontSize: 13)),
      actions: [
        TextButton(
          key: const ValueKey('d-confirm-cancel'),
          onPressed: () => Navigator.pop(bc, false),
          child: const Text('取消'),
        ),
        TextButton(
          key: const ValueKey('d-confirm-ok'),
          // 手感批（2026-10-11）：按下 destructive 钮＝一记确认震；取消不震（不可逆才值得震）。
          // 执行类确认（destructive=false）不震——「要去某页」不是不可逆动作。
          onPressed: () {
            if (destructive) HapticFeedback.mediumImpact();
            Navigator.pop(bc, true);
          },
          child: Text(okLabel,
              style: TextStyle(
                  color: destructive
                      ? const Color(0xFFF43F5E)
                      : Theme.of(bc).colorScheme.primary,
                  fontWeight: FontWeight.w800)),
        ),
      ],
    ),
  );
  return r ?? false;
}
