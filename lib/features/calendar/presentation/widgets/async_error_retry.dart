import 'package:flutter/material.dart';

/// F4-3（P1-8·时间模块批3）：取数失败态与空态分离——失败显错误卡＋重试入口。
///
/// 主数据面（四视图当日块＋账本汇总/明细）必须走本卡；装饰性消费点
/// （月历圆点/周条计数/问候卡）失败可降级空——主面已示错，不再伪装。
class AsyncErrorRetry extends StatelessWidget {
  const AsyncErrorRetry({
    super.key,
    required this.onRetry,
    this.compact = false,
  });

  /// 重试回调＝失效对应 provider 让其重新取数。
  final VoidCallback onRetry;

  /// 紧凑版（嵌入卡内/明细区）。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_outlined,
              color: scheme.error, size: compact ? 20 : 32),
          const SizedBox(height: 6),
          Text('取数失败',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.error)),
          const SizedBox(height: 4),
          TextButton.icon(
            key: const ValueKey('time-retry'),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }
}
