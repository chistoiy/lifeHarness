/// 「仅摘要发送」策略（需求清单 §六 原则 4）· C01 拍板口径 2026-11-06。
///
/// 产品授权「按推荐进行」，定死以下五条，日后改口径须走需求门：
/// ① **只作用于注入用户原文的能力点**（[kAiSummaryTasks]）；聚合统计类
///    （周报点评、周期解读）本就只发统计值，不重复处理；工具验证是用户手填，不注入业务数据。
/// ② **只压缩变量值，不压缩提示词模板**——截渲染后的整段 user 会把输出格式
///    约定一起截掉，属于静默降级。
/// ③ 阈值 [kSummaryThreshold]：≤120 字原样发送（短文本本就是摘要级信息，
///    且身份串已由 `redactForSend` 打码）；超过才摘要。
/// ④ 摘要形态＝多行取前 [kSummaryHeadLines] 行、再取前 [kSummaryHeadChars] 字
///    ＋「原文 N 字，已省略 M 字」回执。**不做生成式摘要**：那会二次出网、
///    多烧 token、还把不可预测的模型输出塞进隐私链路。
/// ⑤ 默认开启（`ai.summaryOnly`）；审阅层／实际请求／`ai_calls` 留痕全部走
///    `AiService.renderForSend` 同一份结果，所以「审阅所见＝实际所发＝记录所记」。
library;

/// 需要「仅摘要发送」的敏感能力点（注入日记正文／碎片／摘录／选中文本／交易明细）。
const Set<String> kAiSummaryTasks = {
  'journal.reflect',
  'inbox.triage',
  'read.quote_insight',
  'read.explain',
  'ledger.categorize',
};

const int kSummaryThreshold = 120;
const int kSummaryHeadChars = 40;
const int kSummaryHeadLines = 3;

/// 单个变量值的摘要；短文本原样返回。
String summarizeValue(String value) {
  if (value.length <= kSummaryThreshold) return value;
  final lines = value.split('\n');
  final head = lines.take(kSummaryHeadLines).join('\n');
  final kept = head.length <= kSummaryHeadChars
      ? head
      : head.substring(0, kSummaryHeadChars);
  return '$kept…（原文 ${value.length} 字，已省略 '
      '${value.length - kept.length} 字）';
}

/// 对白的名单能力点、且开关打开时，把长变量值换成摘要。
/// 返回新的 Map，不改调用方传入的 vars（业务侧后续仍可能读原文）。
Map<String, String> applySummaryPolicy(
  String taskId,
  Map<String, String> vars, {
  required bool enabled,
}) {
  if (!enabled || !kAiSummaryTasks.contains(taskId)) return vars;
  return vars.map((k, v) => MapEntry(k, summarizeValue(v)));
}
