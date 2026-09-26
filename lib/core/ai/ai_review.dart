import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ai_client.dart';
import 'ai_service.dart';
import 'ai_providers.dart';
import '../../shared/widgets/ui_kit.dart' show AppToast;

/// AI 生成中弹层的宿主 Navigator 定位键（可选注入，见 [aiRunWithReview]）。
///
/// 为什么需要它：弹层 push 与 pop **必须同源**。showDialog 默认
/// `useRootNavigator: true` 把弹层挂到根栈，而页面在 GoRouter ShellRoute 分支里
/// 时 `Navigator.of(context)` 拿到的是分支栈——pop 打不到根弹层，黑色屏障
/// 永挂 = 真机「黑屏卡死」。注入 app 根 Navigator 的 key 后，通道一律
/// 在根栈上开合（不依赖私有 `_RootNavigator` 类型）；未注入时退化为
/// 「弹层开在调用页所属 Navigator」（useRootNavigator:false），同样同源。
final ValueNotifier<GlobalKey<NavigatorState>?> aiRootNavKey =
    ValueNotifier<GlobalKey<NavigatorState>?>(null);

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

  // 进度弹层两道护栏（真机「黑屏卡死」= 黑色屏障永挂，两种成因都要防）：
  // ①开关同源：弹层与 pop 都走 [aiRootNavKey] 指向的那个栈（未注入时用调用页
  //   所属栈）。ShellRoute 分支页里 `Navigator.of(context)` 是分支栈，而
  //   showDialog 默认 push 根栈——pop 打不到根弹层，屏障永挂。
  // ②首帧竞态：`showDialog` 的 push 是同步入栈、builder 要等下一帧才跑；
  //   端点极快或同步失败（局域网 Ollama、参数校验即抛）时请求在同一帧内就
  //   return，弹层 context 还没拿到 → 旧 pop 静默失效，屏障照样永挂。
  //   所以 pop 以「是否已开」为准，未建帧时直接从宿主栈弹顶路由。
  final navContext = aiRootNavKey.value?.currentState?.context ?? context;
  final nav = Navigator.of(navContext);
  var progressOpen = false, progressBuilt = false;
  BuildContext? progressCtx;
  showDialog(
    context: navContext,
    useRootNavigator: false,
    barrierDismissible: false,
    builder: (ctx) {
      progressBuilt = true;
      progressCtx = ctx;
      return const PopScope(
        canPop: false,
        child: AlertDialog(content: Row(children: [
          CircularProgressIndicator(),
          SizedBox(width: 14),
          Text('AI 生成中…', style: TextStyle(fontSize: 13)),
        ])),
      );
    },
  );
  progressOpen = true;

  void closeProgressDialog() {
    if (!progressOpen) return;
    progressOpen = false;
    final c = progressCtx;
    if (c != null && c.mounted) {
      Navigator.of(c).pop(); // 已建帧：从弹层自身反查同一栈关闭
    } else if (!progressBuilt && nav.mounted) {
      nav.pop(); // 未建帧即完成：路由已在栈顶，直接弹出拆屏障
    }
    progressCtx = null;
  }

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
  // 无论页面是否仍在，先关进度弹层：屏障永挂才是「黑屏」，页面没了也要拆。
  closeProgressDialog();
  if (!context.mounted) return null;
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
