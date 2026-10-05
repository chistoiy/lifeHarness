import 'package:flutter/material.dart';

/// LH-S31 破坏性操作二次确认（批六 T3 · 由日子模块 `daysConfirm` 提升为公共原语）。
///
/// 口径：取消在左、destructive 动作在右并着玫红 `#F43F5E`（与表单就地错误同族色），
/// 两者视觉上分得开；点遮罩/返回＝取消，**绝不默认执行**。
/// 文案由调用方给一句人话（说清删的是什么、能不能回来），本原语不拼句子。
/// key 沿用日子侧的 `d-confirm-ok` / `d-confirm-cancel`——既有用例与真机走查锚点不拆。
///
/// 为什么放 shared：`features/days/**` 不能被 `features/care/**` import（架构守护 R1），
/// 而两侧要的是同一个确认版式；复制一份迟早分叉。
Future<bool> lhConfirm(BuildContext context, String message,
    {String okLabel = '删除'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (bc) => AlertDialog(
      content: Text(message, style: const TextStyle(fontSize: 13)),
      actions: [
        TextButton(
          key: const ValueKey('d-confirm-cancel'),
          onPressed: () => Navigator.pop(bc, false),
          child: const Text('取消'),
        ),
        TextButton(
          key: const ValueKey('d-confirm-ok'),
          onPressed: () => Navigator.pop(bc, true),
          child: Text(okLabel,
              style: const TextStyle(
                  color: Color(0xFFF43F5E), fontWeight: FontWeight.w800)),
        ),
      ],
    ),
  );
  return r ?? false;
}
