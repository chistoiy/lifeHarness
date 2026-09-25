import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ai_client.dart';
import 'ai_service.dart';
import 'ai_providers.dart';
import '../../shared/widgets/ui_kit.dart' show AppToast;

/// AI 通用交互通道（需求清单 §6 原则 4/5）：
/// 发送前审阅弹层（展示完整 system/user 内容）→ 请求 → 返回原始结果。
/// 各能力点调用方拿 [AiCallResult] 后自行渲染「结果确认」再写库。
///
/// 返回 null = 用户取消或调用失败（失败已 toast/弹窗归因，不静默）。
Future<AiCallResult?> aiRunWithReview(
  BuildContext context,
  WidgetRef ref, {
  required String taskId,
  required Map<String, String> vars,
  double? temperature,
}) async {
  final svc = ref.read(aiServiceProvider);
  final task = svc.effectiveTask(taskId);
  // 门控前移到入口：未开启/未授权/无 Key 即刻 toast，不进入审阅流程（零请求）。
  final denial = await svc.gate(taskId);
  if (denial != null) {
    if (context.mounted) AppToast.show(context, 'AI 未启用：$denial', ms: 2600);
    return null;
  }
  if (!context.mounted) return null;
  final (system, user) = svc.renderForReview(taskId, vars);
  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      maxChildSize: 0.9,
      builder: (ctx, ctrl) => ListView(
        controller: ctrl,
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          Text('发送给 AI · ${task.name}',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('以下内容将发往你配置的端点；确认后才发起请求。',
              style: TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 12),
          const Text('System',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
          _Box(system),
          const SizedBox(height: 8),
          const Text('User',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
          _Box(user),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('取消')),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                    key: const ValueKey('ai-review-send'),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('允许发送')),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  if (confirmed != true || !context.mounted) return null;

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      canPop: false,
      child: AlertDialog(content: Row(children: [
        CircularProgressIndicator(),
        SizedBox(width: 14),
        Text('AI 生成中…', style: TextStyle(fontSize: 13)),
      ])),
    ),
  );
  AiCallResult? result;
  String? error;
  try {
    result = await svc.request(taskId, vars, temperature: temperature);
  } on AiDenied catch (e) {
    error = e.reason;
  } on AiException catch (e) {
    error = e.userMessage;
  } on AiBadOutput catch (e) {
    error = e.reason;
  } catch (e) {
    error = '$e';
  }
  if (!context.mounted) return null;
  Navigator.of(context).pop(); // 关进度
  if (error != null) {
    AppToast.show(context, 'AI 调用失败：$error', ms: 2600);
    return null;
  }
  return result;
}

/// JSON 结果的通用「确认写入」弹层：展示可编辑前的 AI 原文 + AI 标识。
/// 返回 true=用户确认采用。
Future<bool> aiConfirmWrite(BuildContext context,
    {required String title, required String preview}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: const TextStyle(fontSize: 15)),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('AI 生成 · 写入前请确认',
                style: TextStyle(fontSize: 10.5, color: Colors.amber)),
            const SizedBox(height: 6),
            Flexible(child: SingleChildScrollView(child: _Box(preview))),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('放弃')),
        FilledButton(
            key: const ValueKey('ai-confirm-ok'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认写入')),
      ],
    ),
  );
  return ok == true;
}

class _Box extends StatelessWidget {
  const _Box(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .05),
        borderRadius: BorderRadius.circular(10),
      ),
      child: SelectableText(
        _pretty(text),
        style: const TextStyle(fontSize: 11, fontFamily: 'monospace', height: 1.5),
      ),
    );
  }

  static String _pretty(String s) {
    try {
      return const JsonEncoder.withIndent('  ').convert(jsonDecode(s));
    } catch (_) {
      return s;
    }
  }
}
