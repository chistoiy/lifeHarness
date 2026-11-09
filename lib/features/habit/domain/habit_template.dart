import 'dart:convert';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import 'habit.dart';

/// 习惯模板（原型 HB_TPL · 计划 §7：模板库走资源包，社区扩展不改码）。
class HabitTemplate {
  const HabitTemplate({
    required this.name,
    required this.icon,
    required this.type,
    required this.cat,
    required this.cycle,
    this.weekDays = const [],
    this.unit,
    this.goal,
    this.target,
    this.remind,
    this.isGroup = false,
    this.groupRule,
    this.subs = const [],
  });

  final String name;
  final String icon;
  final String type;
  final String cat;
  final String cycle;

  /// 周固定日下标（0=周一 … 6=周日）。
  final List<int> weekDays;
  final String? unit;
  final double? goal;

  /// 负向每周额度 / 月度次数（原型 t.target）。
  final int? target;
  final String? remind;
  final bool isGroup;
  final String? groupRule;
  final List<HabitTemplateSub> subs;

  static const _wdMap = {'一': 0, '二': 1, '三': 2, '四': 3, '五': 4, '六': 5, '日': 6};

  factory HabitTemplate.fromJson(Map<String, dynamic> j) => HabitTemplate(
    name: j['n'] as String,
    icon: j['ic'] as String? ?? 'run',
    type: j['type'] as String? ?? Habit.kPos,
    cat: j['cat'] as String? ?? '健康',
    cycle: j['cycle'] as String? ?? Habit.kDay,
    weekDays: [
      for (final d in (j['days'] as List? ?? const []))
        if (_wdMap[d as String] != null) _wdMap[d]!,
    ],
    unit: j['unit'] as String?,
    goal: (j['goal'] as num?)?.toDouble(),
    target: (j['target'] as num?)?.toInt(),
    remind: (j['remind'] as String?)?.isEmpty ?? true ? null : j['remind'] as String,
    isGroup: j['group'] == true,
    groupRule: j['rule'] as String?,
    subs: [
      for (final s in (j['subs'] as List? ?? const []))
        HabitTemplateSub.fromJson(s as Map<String, dynamic>),
    ],
  );
}

class HabitTemplateSub {
  const HabitTemplateSub({required this.name, required this.unit, required this.goal});

  final String name;
  final String unit;
  final double goal;

  factory HabitTemplateSub.fromJson(Map<String, dynamic> j) => HabitTemplateSub(
    name: j['n'] as String,
    unit: j['unit'] as String? ?? '',
    goal: (j['goal'] as num?)?.toDouble() ?? 1,
  );
}

/// 模板库资源包（`assets/habit_templates/index.json`）。
Future<List<HabitTemplate>> loadHabitTemplates({AssetBundle? bundle}) async {
  final raw = await (bundle ?? rootBundle).loadString(
    'assets/habit_templates/index.json',
  );
  return [
    for (final j in jsonDecode(raw) as List)
      HabitTemplate.fromJson(j as Map<String, dynamic>),
  ];
}
