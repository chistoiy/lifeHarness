/// 节点增强域件（批5 F4-9 · 冻结方案 §2.5 末行）：
/// `节点标签 / 任务属性（联动待办）/ 节点图片` 的**纯 Dart 口径**。
///
/// 本件刻意零 Flutter 依赖（可被纯 Dart 测试直接跑，也便于被 painter 与导出层
/// 共用）——标签编解码在模型 `fromRow` 与落库两处都要用，是本批最易写两遍的口径，
/// 抽成一对函数后**由用例钉「只有这一份」**（工单 §4f.1 变异刀2 钉点）。
///
/// 三段口径（逐条对应原型 `sheetMm-node` 的标签/任务属性/节点图片三段）：
/// · **标签**＝落库存 JSON 数组文本、输入侧按 `[,，]` 切、**损坏回落空列表**；
/// · **任务**＝勾选框命中经 [mmCompleteNodeTask]（linkage 出口）发事件，
///   本件只提供事件载荷构造（不 import linkage —— R3：domain 不得依赖 presentation，
///   linkage 属 shared 亦不反向依赖 domain，故载荷字段在此定义、由出口转发）；
/// · **图片**＝只存路径（画布只画占位角标，见工单 §4f.3 口径一）。
library;

import 'dart:convert';

/// 标签输入的合法分隔符集：半角逗号 ＋ 全角逗号（原型 `split(/[,，]/)`）。
final RegExp _tagSplit = RegExp(r'[,，]');

/// 输入文本 → 标签列表（弹层输入侧）。逐项 trim、去空、**去重且保序**
/// （重名标签画布上会叠成两个同款 chip，没有信息量）。
List<String> mmTagsParse(String raw) {
  final out = <String>[];
  final seen = <String>{};
  for (final part in raw.split(_tagSplit)) {
    final t = part.trim();
    if (t.isEmpty || !seen.add(t)) continue;
    out.add(t);
  }
  return out;
}

/// 标签列表 → 输入框文本（弹层读回侧：`, ` 连接，与原型 `join(', ')` 一致）。
String mmTagsFormat(List<String> tags) => tags.join(', ');

/// 标签列表 → 落库文本（JSON 数组）。空列表落 **null** 而不是 `'[]'`——
/// 空标签与「无此列」在 DB 层同义，避免存量行被 `'[]'` 污染。
String? mmTagsEncode(List<String> tags) =>
    tags.isEmpty ? null : jsonEncode(tags);

/// 落库文本 → 标签列表。**损坏文本一律回落空列表不抛**（变异刀2 钉点）：
/// 真机上该列可能被外部改库/同步写坏，一个坏标签不该让整张图打不开。
List<String> mmTagsDecode(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const <String>[];
  try {
    final v = jsonDecode(raw);
    if (v is! List) return const <String>[];
    return [
      for (final e in v)
        if (e is String && e.trim().isNotEmpty) e.trim(),
    ];
  } on FormatException {
    // catch-ok: 标签列是可选增强字段，坏值回落空列表即可（不记日志避免刷屏）
    return const <String>[];
  }
}

/// 批5 任务完成事件的来源标识（写进 [MmNodeTaskEvent.source] 固定串）。
const String mmTaskEventSource = 'mindmap';

/// 导图节点任务勾选 → 事件载荷（工单 §4f.2 ④）。
///
/// **不复用待办的完成事件类**：`TaskCompletedEvent` 的 `todoId` 语义是待办行 id，
/// 导图节点塞进去会让 `habit_mounts` 等既有订阅方按 id 反查待办落空——虽然它们
/// 查不到即 return 不误伤，但载荷语义被污染后新订阅方无法区分来源。故独立成
/// 一个 Mindmap→Todo 的完成事件，经 `shared/linkage/mindmap_mounts.dart` 出口转发。
class MmNodeTaskEvent {
  const MmNodeTaskEvent({
    required this.mapId,
    required this.nodeId,
    required this.nodeTitle,
    required this.atMs,
  });

  final int mapId;
  final int nodeId;

  /// 完成时的节点显示标题（挂载笔记时取笔记标题——与画布显示同口径）。
  final String nodeTitle;

  final int atMs;

  /// 固定 `'mindmap'`（订阅方按此分流，勿依赖类名）。
  String get source => mmTaskEventSource;
}

/// 批5 节点盒的**附加宽**（标签 chip ＋ 任务勾选框 ＋ 图片占位角标）。
///
/// 与度量同源口径（工单 §4f.2 ①）：画布节点盒必须把这些段的占宽算进去，否则
/// 文字会压到 chip 底下（原型第二趟 `refineBox` 修的就是这件事，本批在
/// 度量层一次算对，不靠渲染层补救）。
///
/// 入参是「该节点实际有几段」而不是整图标志——不同节点段数不同，逐节点算。
double mmNodeExtraWidth({
  required List<String> tags,
  required bool isTask,
  required bool hasImage,
  required double tagWidth,
}) {
  var w = 0.0;
  if (isTask) w += 15 + 3; // 勾选框 15px ＋ 与标题的 3px 缝（同原型 .mm-task）
  if (hasImage) w += 22 + 3; // 缩略占位 22px ＋ 缝（同原型 .mm-thumb）
  if (tags.isNotEmpty) w += tags.length * tagWidth + 3;
  return w;
}