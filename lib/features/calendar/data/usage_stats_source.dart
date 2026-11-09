/// C06：`lh/usagestats` 通道封装（读分段/探权限/跳设置页）。
///
/// 降级口径：任何原生异常都不向 UI 抛——统一折成
/// [UsageQueryResult]（`granted=false`＋人话文案）或 `false`，
/// 调用方只按结果分支，**不重试、不反复弹**。
library;

import 'package:flutter/services.dart';

import '../domain/usage_segment.dart';

/// 与 Kotlin `UsageStatsChannel.CHANNEL` 同源。
const String kUsageStatsChannel = 'lh/usagestats';

/// 单次查询上限：超过 7 天的历史对「建议今天的时间块」无意义，也防止
/// `queryEvents` 一次拉太多事件（原生不切窗口，这里先收口）。
const Duration kUsageMaxQueryWindow = Duration(days: 7);

class UsageStatsSource {
  UsageStatsSource({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(kUsageStatsChannel);

  final MethodChannel _channel;

  /// 是否已授予「使用情况访问」。平台缺失/异常一律 false（按未授权降级）。
  Future<bool> hasPermission() async {
    try {
      return await _channel.invokeMethod<bool>('hasPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 跳系统「使用情况访问」设置页；无设置页返回 false（界面保持原态）。
  Future<bool> openSettings() async {
    try {
      return await _channel.invokeMethod<bool>('openSettings') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 取 `[from, to)` 的原始前台分段。
  ///
  /// - 未授权：原生回 `granted=false`＋空分段＋去授予文案；
  /// - 平台缺失/通道异常：同样回 `granted=false`＋文案，不抛；
  /// - 窗口超过 [kUsageMaxQueryWindow] 时截断到 from+7 天。
  Future<UsageQueryResult> query({
    required DateTime from,
    required DateTime to,
  }) async {
    if (!to.isAfter(from)) {
      return UsageQueryResult.denied('时间范围无效：结束时刻必须晚于开始时刻');
    }
    final limit = from.add(kUsageMaxQueryWindow);
    final end = to.isAfter(limit) ? limit : to;
    try {
      final raw = await _channel.invokeMethod<Object?>('querySegments', {
        'fromMs': from.millisecondsSinceEpoch,
        'toMs': end.millisecondsSinceEpoch,
      });
      return UsageQueryResult.fromNative(raw);
    } on MissingPluginException {
      return UsageQueryResult.unsupported();
    } on PlatformException catch (e) {
      final detail = e.message?.trim();
      return UsageQueryResult.denied(
        detail == null || detail.isEmpty
            ? '使用情况访问查询失败，已跳过本次自动采集'
            : '使用情况访问查询失败：$detail',
      );
    } catch (_) {
      return UsageQueryResult.denied('使用情况访问查询失败，已跳过本次自动采集');
    }
  }
}
