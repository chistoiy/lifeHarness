import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// 五步 imp-dot 进度条（原型 billStep）。
///
/// 2026-11-08 从 `ledger_import_page.dart` 抽出：主文件已到 1202 行（红线 1200），
/// 本件是页尾一枚纯展示无状态件，抽出零行为变化（存量红消化批1·`size_budget` 那条）。
class LedgerStepDots extends StatelessWidget {
  const LedgerStepDots({super.key, required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Row(
      children: [
        for (var n = 1; n <= 5; n++) ...[
          if (n > 1)
            Expanded(
              child: Container(
                height: 1,
                color: n <= step ? tokens.accent : const Color(0xFFCBD5E1),
              ),
            ),
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: n < step
                  ? tokens.accent
                  : n == step
                  ? tokens.accent
                  : Colors.transparent,
              border: Border.all(
                color: n <= step ? tokens.accent : const Color(0xFFCBD5E1),
              ),
            ),
            child: n < step
                ? const Icon(Icons.check, size: 13, color: Colors.white)
                : Text(
                    '$n',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: n == step ? Colors.white : const Color(0xFF94A3B8),
                    ),
                  ),
          ),
        ],
      ],
    );
  }
}
