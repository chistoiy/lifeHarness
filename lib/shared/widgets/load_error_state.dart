import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'ui_kit.dart';

/// LH-L15 加载失败态（T8 · 事实源＝记账专版 L1 顶部卡 `#finErr`，
/// 2026-10-05 产品过门「照此接 care/todo 两线」）。
///
/// 立这条的理由：**读失败不许装成"这里没有数据"**。原来三处高频页的 error 分支
/// 是 `Text('加载失败：$e')`——把原始异常甩给用户，既读不懂也没出口。本件固定四件套：
/// 人话标题 → 「本机数据未受影响 · <人话原因>」→ 主按钮「重试」→ 次按钮「查看详情」跳日志页。
///
/// 版式口径（照原型样张，勿随手改）：
///  · 图标用线性描边（`Icons.report_outlined`），**禁 emoji**；
///  · 标题 16/w800，原因句 13/w400 次要色，两钮同行（主＝实心、次＝描边）；
///  · 原型样张里那行「（演示位：真实原因句取 humanizeError…）」是**给开发看的注**，
///    真包不渲染——这里直接把 `humanizeError(error)` 放进展位。
class LoadErrorBanner extends StatelessWidget {
  const LoadErrorBanner({
    super.key,
    required this.title,
    required this.error,
    required this.onRetry,
    this.detailPath = '/log',
  });

  /// 语境化标题（「这个账本没加载出来」这类人话句，由各页给）。
  final String title;

  /// 原始异常；展示时过 [humanizeError]，日志页里留全量。
  final Object error;

  /// 「重试」＝重新取数（一般是 invalidate 对应 provider）。
  final VoidCallback onRetry;

  /// 「查看详情」落点（默认运行日志页）。
  final String detailPath;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.report_outlined, size: 26, color: scheme.error),
            const SizedBox(height: 10),
            Text(
              title,
              key: const ValueKey('load-error-title'),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '本机数据未受影响 · ${humanizeError(error)}',
              key: const ValueKey('load-error-reason'),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                FilledButton(
                  key: const ValueKey('load-error-retry'),
                  onPressed: onRetry,
                  child: const Text('重试'),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  key: const ValueKey('load-error-detail'),
                  onPressed: () => context.push(detailPath),
                  child: const Text('查看详情'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
