import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/features/calendar/domain/usage_pending_plan.dart';
import 'package:lifeharness/features/calendar/domain/usage_segment.dart';

/// C06 自动时间采集守护：分段清洗／跨天切分／建议块／原生回包容错／
/// 习惯目标筛选／待确认队列规划／拒权降级。纯函数级、正负两档同例都断。
void main() {
  UsageSegment seg(String pkg, DateTime start, DateTime end, {String? label}) =>
      UsageSegment(
        packageName: pkg,
        label: label ?? pkg,
        start: start,
        end: end,
      );

  Map<String, Object?> habitRow(
    String id, {
    String type = 'pos',
    String? sourceKinds = '["日程事件"]',
    int? archivedAt,
    int? deletedAt,
  }) => <String, Object?>{
    'id': id,
    'name': '习惯$id',
    'type': type,
    'source_kinds': sourceKinds,
    'archived_at': archivedAt,
    'deleted_at': deletedAt,
  };

  test('① normalizeUsageSegments：同包相邻合并 / 滤短 / 排除包 / 脏段', () {
    final raw = <UsageSegment>[
      seg('com.a', DateTime(2026, 11, 9, 9, 0), DateTime(2026, 11, 9, 9, 10)),
      // 间隔 1 分钟＝合并容差内 → 与上段并成 09:00–09:30
      seg('com.a', DateTime(2026, 11, 9, 9, 11), DateTime(2026, 11, 9, 9, 30)),
      // 30 秒短切屏 → 丢弃
      seg('com.b', DateTime(2026, 11, 9, 10, 0), DateTime(2026, 11, 9, 10, 0, 30)),
      // 排除包 → 丢弃
      seg('com.self', DateTime(2026, 11, 9, 11, 0), DateTime(2026, 11, 9, 11, 10)),
      // 结束早于开始 → 丢弃
      seg('com.c', DateTime(2026, 11, 9, 12, 0), DateTime(2026, 11, 9, 11, 0)),
      seg('com.d', DateTime(2026, 11, 9, 13, 0), DateTime(2026, 11, 9, 13, 5)),
    ];

    final out = normalizeUsageSegments(
      raw,
      excludePackages: const <String>{'com.self'},
    );

    expect(out.length, 2, reason: '正档：只剩 com.a 合并段与 com.d');
    expect(out.first.packageName, 'com.a', reason: '正档：按开始时间排序');
    expect(out.first.start, DateTime(2026, 11, 9, 9, 0),
        reason: '正档：合并保留首段起点');
    expect(out.first.end, DateTime(2026, 11, 9, 9, 30),
        reason: '正档：合并取末段终点');
    expect(out.first.minutes, 30, reason: '正档：合并后时长 30 分钟');
    expect(out.any((s) => s.packageName == 'com.b'), isFalse,
        reason: '负档：短于阈值的切屏不入建议');
    expect(out.any((s) => s.packageName == 'com.self'), isFalse,
        reason: '负档：排除包不入建议');
    expect(out.any((s) => s.packageName == 'com.c'), isFalse,
        reason: '负档：倒挂脏段丢弃');
  });

  test('② splitUsageByDay：跨 00:00 切两段 / 日内不切 / 恰好止于 00:00 不产空段', () {
    final cross = seg(
      'com.a',
      DateTime(2026, 11, 9, 23, 30),
      DateTime(2026, 11, 10, 1, 10),
    );
    final inside = seg(
      'com.b',
      DateTime(2026, 11, 9, 8, 0),
      DateTime(2026, 11, 9, 9, 0),
    );
    final toMidnight = seg(
      'com.c',
      DateTime(2026, 11, 9, 22, 0),
      DateTime(2026, 11, 10, 0, 0),
    );

    final out = splitUsageByDay(<UsageSegment>[cross, inside, toMidnight]);

    expect(out.length, 4, reason: '正档：跨天 2 段＋日内 1 段＋止于零点 1 段');
    expect(out[0].end, DateTime(2026, 11, 10, 0, 0),
        reason: '正档：跨天前段截到次日 00:00');
    expect(out[1].start, DateTime(2026, 11, 10, 0, 0),
        reason: '正档：跨天后段从 00:00 起');
    expect(out[1].end, DateTime(2026, 11, 10, 1, 10),
        reason: '正档：后段保留真实结束');
    expect(out[2].start, inside.start, reason: '负档：日内段原样保留');
    expect(out[2].end, inside.end, reason: '负档：日内段不切');
    expect(
      out.where((s) => s.packageName == 'com.c').length,
      1,
      reason: '负档：恰好止于 00:00 不产出零长度尾段',
    );
  });

  test('③ buildUsageSuggestions：分钟口径 / 24:00=1440 / 零长度丢弃', () {
    final out = buildUsageSuggestions(<UsageSegment>[
      seg('com.a', DateTime(2026, 11, 9, 8, 5), DateTime(2026, 11, 9, 9, 20)),
      seg('com.b', DateTime(2026, 11, 9, 23, 40), DateTime(2026, 11, 10, 0, 0)),
      seg('com.c', DateTime(2026, 11, 9, 12, 0), DateTime(2026, 11, 9, 12, 0)),
    ]);

    expect(out.length, 2, reason: '正档：零长度段不产建议');
    expect(out[0].startMin, 8 * 60 + 5, reason: '正档：开始分钟口径');
    expect(out[0].endMin, 9 * 60 + 20, reason: '正档：结束分钟口径');
    expect(out[0].minutes, 75, reason: '正档：建议时长 75 分钟');
    expect(out[0].day, DateTime(2026, 11, 9), reason: '正档：day 归到当日零点');
    expect(out[1].endMin, 1440, reason: '正档：跨到 24:00 记 1440');
    expect(out.any((s) => s.packageName == 'com.c'), isFalse,
        reason: '负档：零长度段不入选');
  });

  test('④ UsageQueryResult.fromNative：脏数据不抛 / 拒权清空分段', () {
    final ok = UsageQueryResult.fromNative(<String, Object?>{
      'granted': true,
      'message': '',
      'segments': <Object?>[
        <String, Object?>{
          'package': 'com.a',
          'label': '应用A',
          'startMs': DateTime(2026, 11, 9, 9, 0).millisecondsSinceEpoch,
          'endMs': DateTime(2026, 11, 9, 9, 30).millisecondsSinceEpoch,
        },
        // 结束早于开始 → 跳过
        <String, Object?>{
          'package': 'com.b',
          'label': '应用B',
          'startMs': DateTime(2026, 11, 9, 10, 0).millisecondsSinceEpoch,
          'endMs': DateTime(2026, 11, 9, 9, 0).millisecondsSinceEpoch,
        },
        // 包名缺失 → 跳过
        <String, Object?>{'startMs': 1, 'endMs': 2},
      ],
    });
    expect(ok.granted, isTrue, reason: '正档：granted 透传');
    expect(ok.segments.length, 1, reason: '正档：脏切片被跳过');
    expect(ok.segments.first.label, '应用A', reason: '正档：label 原样');

    final denied = UsageQueryResult.fromNative(<String, Object?>{
      'granted': false,
      'message': '去系统设置授予使用情况访问',
      'segments': <Object?>[
        <String, Object?>{
          'package': 'com.a',
          'label': '应用A',
          'startMs': 0,
          'endMs': 600000,
        },
      ],
    });
    expect(denied.granted, isFalse, reason: '负档：granted=false');
    expect(denied.segments, isEmpty, reason: '负档：拒权残留分段不参与建议');
    expect(denied.message, contains('使用情况访问'), reason: '负档：保留去授予文案');

    final garbage = UsageQueryResult.fromNative(null);
    expect(garbage.granted, isFalse, reason: '负档：null 回包按拒权降级');
    expect(garbage.message, UsageQueryResult.deniedMessage,
        reason: '负档：无文案时用默认去授予文案');
  });

  test('⑤ usagePendTargetOf：正向+源匹配入选 / 负向·归档·删除·源不符不入', () {
    final hit = usagePendTargetOf(habitRow('h1'));
    expect(hit, isNotNull, reason: '正档：正向且绑定「日程事件」');
    expect(hit!.id, 'h1', reason: '正档：id 透传');
    expect(hit.name, '习惯h1', reason: '正档：名透传');

    expect(usagePendTargetOf(habitRow('h2', type: 'neg')), isNull,
        reason: '负档：负向习惯不吃使用时长');
    expect(usagePendTargetOf(habitRow('h3', archivedAt: 1)), isNull,
        reason: '负档：归档习惯不入队');
    expect(usagePendTargetOf(habitRow('h4', deletedAt: 1)), isNull,
        reason: '负档：已删除习惯不入队');
    expect(
      usagePendTargetOf(habitRow('h5', sourceKinds: '["待办勾选"]')),
      isNull,
      reason: '负档：未绑定该来源',
    );
    expect(
      usagePendTargetOf(habitRow('h6', sourceKinds: null)),
      isNull,
      reason: '负档：空 source_kinds 默认「手动打卡」，不匹配日程事件',
    );
    expect(
      usagePendTargetOf(habitRow('h7', sourceKinds: '{bad json')),
      isNull,
      reason: '负档：脏 JSON 按未绑定处理且不抛',
    );
    expect(
      usageSourceKindsOf('["日程事件","手动打卡"]'),
      <String>['日程事件', '手动打卡'],
      reason: '正档：多来源逐项解析',
    );
  });

  test('⑥ planUsagePends：同日合并累加 / 已处理不复活 / 空目标不产草稿', () {
    const targets = <UsagePendTarget>[
      UsagePendTarget(id: 'h1', name: '习惯h1'),
    ];
    final suggestions = <UsageSuggestion>[
      UsageSuggestion(
        day: DateTime(2026, 11, 9),
        packageName: 'com.a',
        label: '应用A',
        startMin: 540,
        endMin: 570,
      ),
      UsageSuggestion(
        day: DateTime(2026, 11, 9),
        packageName: 'com.b',
        label: '应用B',
        startMin: 840,
        endMin: 860,
      ),
    ];

    final drafts = planUsagePends(targets, suggestions);
    expect(drafts.length, 1, reason: '正档：同习惯同日合并为一条');
    expect(drafts.first.habitId, 'h1', reason: '正档：目标习惯正确');
    expect(drafts.first.day, '2026-11-09', reason: '正档：day 用 YYYY-MM-DD');
    expect(drafts.first.src, kUsagePendSrc, reason: '正档：来源沿用「日程事件」');
    expect(drafts.first.minutes, 50, reason: '正档：同日两条建议累加 30+20');

    // 跨日不许合并（变异刀实证：去重键少了 day 维度时这条必须红）
    final crossDay = planUsagePends(targets, <UsageSuggestion>[
      ...suggestions,
      UsageSuggestion(
        day: DateTime(2026, 11, 10),
        packageName: 'com.c',
        label: '应用C',
        startMin: 600,
        endMin: 630,
      ),
    ]);
    expect(crossDay.length, 2, reason: '负档：跨日不得合并成一条');
    expect(crossDay.map((d) => d.day).toSet(), {'2026-11-09', '2026-11-10'},
        reason: '正档：两天的草稿都在');

    final blocked = planUsagePends(
      targets,
      suggestions,
      existingKeys: const <String>{'h1|2026-11-09|日程事件'},
    );
    expect(blocked, isEmpty, reason: '负档：已确认/已丢弃的建议同日不复活');

    expect(planUsagePends(const <UsagePendTarget>[], suggestions), isEmpty,
        reason: '负档：无目标习惯不产草稿');
    expect(planUsagePends(targets, const <UsageSuggestion>[]), isEmpty,
        reason: '负档：无建议不产草稿');
  });

  test('⑦ 拒权/不支持降级：有明确文案且无异常', () {
    final denied = UsageQueryResult.denied();
    expect(denied.granted, isFalse, reason: '负档：默认拒权');
    expect(denied.segments, isEmpty, reason: '负档：拒权无分段');
    expect(denied.message, contains('使用情况访问'),
        reason: '负档：文案指明去授予哪项权限');
    expect(denied.message, contains('系统设置'),
        reason: '负档：文案给出可执行路径');

    final noSeg = UsageQueryResult(granted: false, message: 'x');
    expect(noSeg.hasSegments, isFalse, reason: '负档：无分段');

    final alt = UsageQueryResult.unsupported();
    expect(alt.granted, isFalse, reason: '负档：平台缺失按不支持降级');
    expect(alt.message, UsageQueryResult.unsupportedMessage,
        reason: '负档：不支持文案可展示');

    expect(normalizeUsageSegments(const <UsageSegment>[]), isEmpty,
        reason: '正档：空输入不炸');
  });
}
