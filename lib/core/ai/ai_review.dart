import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logging/app_log.dart';
import '../providers.dart';
import 'ai_client.dart';
import 'ai_service.dart';
import 'ai_providers.dart';
import 'token_stats.dart';
import '../../shared/widgets/ui_kit.dart' show AppToast;

/// token 用量入账：统计写盘失败绝不反噬 AI 结果（顶多看不到用量，不该丢应答）。
Future<void> _recordUsage(
  WidgetRef ref,
  String taskId, {
  int inTok = 0,
  int outTok = 0,
  int latencyMs = 0,
  bool failed = false,
}) async {
  try {
    await AiTokenStats.record(ref.read(sharedPreferencesProvider), taskId,
        inTok: inTok, outTok: outTok, latencyMs: latencyMs, failed: failed);
  } catch (_) {
    // 静默：日志页已有本次调用的完整留痕。
  }
}

/// V1.54.1 批4 · **多批顺序调用**的核心侧出口（与 [aiRunWithReview] 同族、同门控）。
///
/// 为什么要有第二条入口：一个能力点拆成 N 批时，逐批弹「发送内容审阅 + AI 生成中」会把
/// 流程打断——X-Ray 精化的进度本就常驻面板段内（原型 `#xrAiBar`）。R7 要守的东西一件没少：
/// **三重门控、`ai_calls` 留痕、输出结构校验、失败归因**仍由 AiService 执行；调用方在开跑前
/// 用预检卡把「候选数 / 批数 / 单请求预算 / token 估算」列清拿一次确认，写库前再过结果审阅。
/// 拦的是「绕过 core/ai 直取 AiService」，不是「一个任务只许一个弹层」。
Future<String?> aiGateDenied(WidgetRef ref, String taskId) =>
    ref.read(aiServiceProvider).gate(taskId);

/// 逐批调用里的一批：返回解析后的 JSON。门控被拒 / 网络失败 / 输出不合约定**一律上抛**，
/// 由调用方（批执行器）计重试与跳过——这里不吞异常，否则失败批次会被当成没发生。
Future<Map<String, dynamic>> aiRunJsonBatch(
  WidgetRef ref, {
  required String taskId,
  required Map<String, String> vars,
}) async {
  final r = await ref.read(aiServiceProvider).request(taskId, vars);
  return r.requireJson();
}

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
    // 门控拒绝也要留痕：日志页是「所有报错都可查」的落点（真机反馈③），
    // V1.53 的「AI 使用记录」同样要能查到"为什么这条压根没发出去"。
    await svc.recordDenied(taskId, denial);
    AppLog.add('AI 未启用（$taskId）：$denial', level: LhLevel.warn);
    if (context.mounted) AppToast.show(context, 'AI 未启用：$denial', ms: 2600);
    return null;
  }
  if (!context.mounted) return null;
  final (system, user) = svc.renderForReview(taskId, vars);
  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _ReviewSheet(
      name: task.name,
      system: system,
      user: user,
    ),
  );
  if (confirmed != true || !context.mounted) return null;

  // 进度弹层三道护栏（真机「黑屏卡死」与「点击后无法返回」= 屏障永挂 / 没有出口）：
  // ①开关同源：弹层与 pop 都走 [aiRootNavKey] 指向的那个栈（未注入时用调用页
  //   所属栈）。ShellRoute 分支页里 `Navigator.of(context)` 是分支栈，而
  //   showDialog 默认 push 根栈——pop 打不到根弹层，屏障永挂。
  // ②首帧竞态：`showDialog` 的 push 是同步入栈、builder 要等下一帧才跑；
  //   端点极快或同步失败（局域网 Ollama、参数校验即抛）时请求在同一帧内就
  //   return，弹层 context 还没拿到 → 旧 pop 静默失效，屏障照样永挂。
  //   所以 pop 以「是否已开」为准，未建帧时直接从宿主栈弹顶路由。
  // ③用户出口：等待必须可中断。「取消」钮与系统返回都只完成 [cancel]，
  //   关弹层仍由本函数统一执行（避免与 closeProgressDialog 双 pop）；
  //   应答与取消竞速，迟到的结果只被吞掉——不写库、不当成成功播报。
  final navContext = aiRootNavKey.value?.currentState?.context ?? context;
  final nav = Navigator.of(navContext);
  var progressOpen = false, progressBuilt = false;
  BuildContext? progressCtx;
  final cancel = Completer<void>();
  showDialog(
    context: navContext,
    useRootNavigator: false,
    barrierDismissible: false,
    builder: (ctx) {
      progressBuilt = true;
      progressCtx = ctx;
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && !cancel.isCompleted) cancel.complete();
        },
        child: AlertDialog(
          content: const Row(children: [
            CircularProgressIndicator(),
            SizedBox(width: 14),
            Text('AI 生成中…', style: TextStyle(fontSize: 13)),
          ]),
          actions: [
            TextButton(
              key: const ValueKey('ai-progress-cancel'),
              onPressed: () {
                if (!cancel.isCompleted) cancel.complete();
              },
              child: const Text('取消'),
            ),
          ],
        ),
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
  String? logDetail; // 日志侧比 toast 更精确：带失败归类与端点原文
  // 取消票据：请求已经打出去、应答还在路上时用户取消——请求侧迟到的收尾据此
  // 记成「取消」而不是「成功」（结果确实没被采用），使用记录与用户看到的一致。
  final cancelToken = AiCancelToken();
  // 请求侧自己收敛成 'ok'/'err'，好与 cancel.future 一起进 Future.any 竞速；
  // 取消胜出后不再 await 它，异常也已在 onError 里吃掉（无 unhandled error）。
  final settled = Completer<String>();
  svc.request(taskId, vars, temperature: temperature, cancel: cancelToken).then((r) {
    result = r;
    if (!settled.isCompleted) settled.complete('ok');
  }, onError: (Object e, StackTrace _) {
    if (e is AiDenied) {
      error = e.reason;
    } else if (e is AiException) {
      error = e.userMessage;
      logDetail = '${e.kind.name}: ${e.detail}';
    } else if (e is AiBadOutput) {
      error = e.reason;
      logDetail = '输出不合约定';
    } else {
      error = '$e';
      logDetail = e.runtimeType.toString();
    }
    if (!settled.isCompleted) settled.complete('err');
  });
  final outcome =
      await Future.any([settled.future, cancel.future.then((_) => 'cancel')]);

  // 无论页面是否仍在，先关进度弹层：屏障永挂才是「黑屏」，页面没了也要拆。
  closeProgressDialog();

  if (outcome == 'cancel') {
    cancelToken.cancelled = true;
    AppLog.add('AI 调用已取消（$taskId）：等待期间用户取消/返回，应答若迟到将被丢弃',
        level: LhLevel.warn);
    // 取消也算一次发出：请求已经打到端点、token 已消耗，只是应答没等到。
    await _recordUsage(ref, taskId, failed: true);
    if (context.mounted) AppToast.show(context, '已取消本次 AI 生成', ms: 2000);
    return null;
  }

  // 成败都留痕（真机反馈③「日志里没有内容」：AI 通道原先只 toast 不落日志）。
  if (error != null) {
    await _recordUsage(ref, taskId, failed: true);
    AppLog.add(
        'AI 调用失败（$taskId）：$error${logDetail == null ? '' : ' · $logDetail'}',
        level: LhLevel.error);
  } else {
    final r = result!;
    AppLog.add('AI 调用成功（$taskId）· ${r.reply.latencyMs}ms · '
        '入 ${r.reply.promptTokens}/出 ${r.reply.completionTokens} tokens');
    await _recordUsage(ref, taskId,
        inTok: r.reply.promptTokens,
        outTok: r.reply.completionTokens,
        latencyMs: r.reply.latencyMs);
  }
  if (!context.mounted) return null;
  if (error != null) {
    // T7：人话一句＋3.2s 下限；原文上面已按 error 级落日志（含 taskId 归类），
    // 这里传 log:false 只出提示条，不重复刷行。
    AppToast.showError(context, error ?? '未知错误',
        prefix: 'AI 调用失败', log: false);
    return null;
  }
  return result;
}

/// 发送前审阅弹层（V1.53.4③ · 原型 sheetAiReview）：System/User **默认折叠**，
/// 点标题行展开。R7 的「发送前看到发什么」不变——预览行仍给出首行内容，
/// 展开即全文；审阅→发送/取消的竞速与留痕都在 [aiRunWithReview] 外层完成。
class _ReviewSheet extends ConsumerStatefulWidget {
  const _ReviewSheet({required this.name, required this.system, required this.user});

  final String name;
  final String system;
  final String user;

  @override
  ConsumerState<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends ConsumerState<_ReviewSheet> {
  bool _sysOpen = false, _usrOpen = false;

  static String _peek(String s) {
    final line = s.split('\n').first.trim();
    return line.length <= 30 ? line : '${line.substring(0, 30)}…';
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      maxChildSize: 0.9,
      builder: (ctx, ctrl) => ListView(
        controller: ctrl,
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          Text('发送给 AI · ${widget.name}',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('以下内容将发往你配置的端点；确认后才发起请求。',
              style: TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 12),
          _FoldSection(
            key: const ValueKey('ai-review-sys'),
            title: 'System · 发送设定',
            peek: _peek(widget.system),
            open: _sysOpen,
            onToggle: () => setState(() => _sysOpen = !_sysOpen),
            body: widget.system,
          ),
          const SizedBox(height: 8),
          _FoldSection(
            key: const ValueKey('ai-review-usr'),
            title: 'User · 本次内容',
            peek: _peek(widget.user),
            open: _usrOpen,
            onToggle: () => setState(() => _usrOpen = !_usrOpen),
            body: widget.user,
          ),
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
    );
  }
}

/// 折叠段：标题行（标题 + 首行预览 + ∧/∨）点开才渲染全文盒（原型 brRvTog 口径）。
class _FoldSection extends StatelessWidget {
  const _FoldSection({
    super.key,
    required this.title,
    required this.peek,
    required this.open,
    required this.onToggle,
    required this.body,
  });

  final String title;
  final String peek;
  final bool open;
  final VoidCallback onToggle;
  final String body;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant.withValues(alpha: .6)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 11.5, fontWeight: FontWeight.w800)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      peek,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 10.5, color: cs.onSurfaceVariant),
                    ),
                  ),
                  Icon(
                    open ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: cs.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: _Box(body),
            ),
        ],
      ),
    );
  }
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
