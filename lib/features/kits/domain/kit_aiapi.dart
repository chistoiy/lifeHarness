/// 小工具合集 · AI API 验证纯计算（批3）。
///
/// 只管「该发什么请求 / 结果怎么读 / 表单怎么落库」这三件事：真实请求与留痕
/// 在 `core/ai/ai_verify_channel.dart`（R7 唯一入口），本文件保持零依赖纯函数。
/// 红线：**Key 永不进本层的任何字符串与落库结构**（只存保险箱，屏上只当次使用）。
library;

import 'kit_calc.dart' show kitRelText;

/// 原型默认验证提示词。
const String kKitAiapiPromptDefault = '请只回复四个字：连接成功';

/// 两种协议（与 core/ai 同口径）。
const String kKitAiapiProtoOpenai = 'openai';
const String kKitAiapiProtoAnthropic = 'anthropic';

/// 模拟演示的等待时长（屏侧用 FakeAsync 可预期推进）。
const int kKitAiapiMockDelayMs = 900;

String kitAiapiProtoLabel(String protocol) =>
    protocol == kKitAiapiProtoAnthropic
    ? 'Anthropic Messages API（协议适配）'
    : 'OpenAI 兼容';

/// 表单校验：缺 Base URL / 缺 Key 时给原型同款文案（null=可发）。
String? kitAiapiCheck({required String baseUrl, required bool hasKey}) {
  if (baseUrl.trim().isEmpty) return '请填写 Base URL';
  if (!hasKey) return '请先填入 API Key（或使用模拟演示查看交互效果）';
  return null;
}

/// 请求进行中的说明行（原型把 POST 目标摊在结果卡上）。
String kitAiapiRequestLine({
  required String url,
  required String protocol,
  required String model,
}) =>
    'POST $url · ${kitAiapiProtoLabel(protocol)} · '
    'model=${model.trim().isEmpty ? 'default' : model.trim()} …';

/// 结果卡首行（成功/失败/模拟三态）。
String kitAiapiHead({
  required bool ok,
  required int ms,
  bool mock = false,
  String? status,
}) {
  if (mock) return '✔ 200 OK（模拟）· $ms ms';
  if (ok) return '✔ 200 OK · $ms ms';
  return status == null ? '✖ 请求未通过 · $ms ms' : '✖ HTTP $status · $ms ms';
}

/// token 用量行（无用量给 n/a，不编数字）。
String kitAiapiUsage({
  required int inTok,
  required int outTok,
  required bool ok,
  bool mock = false,
}) {
  if (!ok) return 'usage: n/a';
  if (inTok == 0 && outTok == 0) return 'usage: n/a';
  return 'usage: $inTok + $outTok tokens${mock ? '（模拟值）' : ''}';
}

/// 结论行（模拟必须写明不校验真实 Key，避免被读成「端点可用」）。
String kitAiapiVerdict({required bool ok, required bool mock}) =>
    switch ((ok, mock)) {
      (true, true) => '模拟演示 · 不发真实请求 · 不校验 Key',
      (true, false) => '验证通过 · 可前往设置页逐项开启 AI 能力矩阵',
      (false, _) => '未通过 · 按上方归因排查后再试',
    };

/// 结果卡的完整行序（屏侧逐行渲染，方便按颜色分档）。
List<String> kitAiapiResultLines({
  required String head,
  String reply = '',
  String usage = '',
  required String verdict,
  String error = '',
  String detail = '',
}) => [
  head,
  if (error.isNotEmpty) error,
  if (detail.isNotEmpty) detail,
  if (reply.isNotEmpty) '模型回复：$reply',
  if (usage.isNotEmpty) usage,
  verdict,
];

/// 验证记录一行（数据源是 ai_calls 里的真实留痕，不是前端假数据）。
String kitAiapiHistLine({
  required String provider,
  required String model,
  required bool ok,
  required int ms,
  required String err,
  required int? ts,
  required DateTime now,
}) =>
    '${kitRelText(ts, now)} · $provider/$model · '
    '${ok ? '✔ ${ms}ms' : '✖ ${err.isEmpty ? '失败' : err}'}';

/// 表单落库（`kit_tool_data.tool='aiapi'`；**只存端点与提示词，不存 Key**）。
Map<String, Object?> kitAiapiEncode({
  required String providerId,
  required String baseUrl,
  required String model,
  required String prompt,
  required String protocol,
}) => {
  'aiProv': providerId,
  'aiUrl': baseUrl,
  'aiModel': model,
  'aiPrompt': prompt,
  'aiProto': protocol,
};

class KitAiapiState {
  const KitAiapiState({
    required this.providerId,
    required this.baseUrl,
    required this.model,
    required this.prompt,
    required this.protocol,
  });

  final String providerId;
  final String baseUrl;
  final String model;
  final String prompt;
  final String protocol;

  static KitAiapiState decode(Map<String, Object?> d) => KitAiapiState(
    providerId: d['aiProv'] as String? ?? '',
    baseUrl: d['aiUrl'] as String? ?? '',
    model: d['aiModel'] as String? ?? '',
    prompt: (d['aiPrompt'] as String?)?.isEmpty == true
        ? kKitAiapiPromptDefault
        : d['aiPrompt'] as String? ?? kKitAiapiPromptDefault,
    protocol: d['aiProto'] == kKitAiapiProtoAnthropic
        ? kKitAiapiProtoAnthropic
        : kKitAiapiProtoOpenai,
  );
}
