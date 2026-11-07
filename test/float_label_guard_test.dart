// 表单浮动标签源码级常驻守护（浮动标签批3 实现轮 · 工单 §1C）。
//
// 为什么是源码扫描而不是 widget 断言：labelText 上浮行为由 Flutter 默认 auto 提供，
// widget 测试断言「有标签」成本高于收益；真正会回归的是「字段名被写回 hintText」
// 与「新增输入框忘记显式 auto」——这两件事静态判得准。
//
// 口径（产品 2026-11-07 裁定）：A/B/C/D 全改（字段名进 labelText、示例值留 hintText、
// D 类删外部标题行）、E 类搜索/正文豁免、全仓显式 floatingLabelBehavior.auto。
// 棘轮：auto 与 labelText 的计数只许增不许减；下降＝有人把标签改回占位符。
//
// 三刀变异（只在内存注入，不动盘上源码）：
//   FL_KNIFE=1 抹掉一处 auto → 红「auto 计数」
//   FL_KNIFE=2 抹掉工厂的 labelText → 红「共享工厂」
//   FL_KNIFE=3 复活「https://… 当标签」→ 红「反向错用」
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _auto = 'floatingLabelBehavior: FloatingLabelBehavior.auto';

/// 登记时实测（2026-11-08 批3 落刀后）：lib/**/*.dart 共 599 份。
const _baselineAuto = 58;
const _baselineLabel = 60;

/// 7 处共享装饰工厂（批3 已把 label 提成命名参数并写入 labelText）。
const _factories = <String>[
  'lib/features/items/presentation/item_edit_page.dart',
  'lib/features/items/presentation/item_detail_page.dart',
  'lib/features/days/presentation/day_edit_page.dart',
  'lib/features/care/presentation/event_sheet.dart',
  'lib/features/care/presentation/baby_sheets.dart',
  'lib/features/care/presentation/ev_sheets.dart',
  'lib/features/settings/presentation/ai_page_form.dart',
  'lib/features/settings/presentation/profile_edit_sheet.dart',
];

/// D 类外部标题行：删了才真省高度，出现即回归。
const _deletedTitles = <String, List<String>>{
  'lib/features/care/presentation/cycle_sheet.dart': ["const CLabel('备注'),"],
  'lib/features/care/presentation/event_sheet.dart': ["const CLabel('备注'),"],
  'lib/features/items/presentation/item_edit_page.dart': ["const _Lbl('物品备注'),"],
  'lib/features/nfc/presentation/nfc_sheets.dart': [
    "_label('名称', scheme),",
    "_label('默认描述（选填）', scheme),",
  ],
  'lib/features/settings/presentation/ai_page_form.dart': [
    "_label('名称'),",
    "_label('Base URL（必填 · 按端点要求填完整前缀）'),",
    "_label('模型名（必填）'),",
    "_label('API Key（该服务商单独保存）'),",
  ],
};

/// E 类豁免抽样：这些 hint 必须仍是 hint，不许被搬去 labelText。
const _exemptHints = <String, String>{
  'lib/features/care/presentation/baby_sheets.dart': '搜索食物名称',
  'lib/features/inbox/presentation/inbox_page.dart': '脑中任何念头，扔进来…',
};

Map<String, String> _readAll() {
  final out = <String, String>{};
  for (final e in Directory('lib').listSync(recursive: true)) {
    if (e is! File || !e.path.endsWith('.dart')) continue;
    final key = e.path.replaceAll('\\', '/');
    out[key] = e.readAsStringSync();
  }
  return out;
}

int _count(Map<String, String> srcs, String needle) =>
    srcs.values.fold(0, (n, s) => n + needle.allMatches(s).length);

void main() {
  test('浮动标签源码守护 · auto / labelText 棘轮 + 工厂 + 反向错用 + D 类标题', () {
    final srcs = _readAll();
    final knife = Platform.environment['FL_KNIFE'] ?? '0';

    // —— 变异刀（仅内存注入等价缺陷，不写盘）——
    if (knife == '1') {
      // 特意挑非工厂文件，保证这一刀只打在「auto 计数」守护上
      final k = srcs.keys.firstWhere(
          (k) => srcs[k]!.contains('$_auto,') && !_factories.contains(k));
      srcs[k] = srcs[k]!.replaceFirst('$_auto,', '');
    } else if (knife == '2') {
      for (final k in _factories) {
        if (srcs.containsKey(k)) {
          srcs[k] = srcs[k]!.replaceAll('labelText: label,', '');
        }
      }
    } else if (knife == '3') {
      const k = 'lib/features/journal/presentation/note_edit_rich.dart';
      srcs[k] = "${srcs[k]!}\n// knife3\nconst _x = \"labelText: 'https://…'\";\n";
    }

    for (final f in _factories) {
      expect(srcs.containsKey(f), isTrue, reason: '共享工厂文件不存在：$f');
      expect(srcs[f]!, contains('labelText: label'),
          reason: '共享工厂缺 labelText: label：$f');
      expect(srcs[f]!, contains(_auto),
          reason: '共享工厂缺显式 auto：$f');
    }

    // 反向错用：示例值不得当字段名
    for (final e in srcs.entries) {
      expect(e.value.contains("labelText: 'https://…'"), isFalse,
          reason: '反向错用复活：${e.key}');
    }

    // D 类外部标题行零残留
    for (final e in _deletedTitles.entries) {
      final s = srcs[e.key] ?? '';
      for (final title in e.value) {
        expect(s.contains(title), isFalse,
            reason: 'D 类外部标题行复活：${e.key} → $title');
      }
    }

    // E 类豁免：搜索/正文的占位文案不许被当成字段名搬走
    for (final e in _exemptHints.entries) {
      if (!srcs.containsKey(e.key)) continue;
      expect(srcs[e.key]!, contains(e.value),
          reason: 'E 类豁免占位文案被改动：${e.key} → ${e.value}');
    }

    // 棘轮计数放最后，保证三刀各自落在对应守护面
    final nAuto = _count(srcs, _auto);
    final nLabel = _count(srcs, 'labelText:');
    expect(nAuto, greaterThanOrEqualTo(_baselineAuto),
        reason: '显式 auto 声明减少＝有输入框把浮动标签改回了占位符');
    expect(nLabel, greaterThanOrEqualTo(_baselineLabel),
        reason: 'labelText 总数减少＝字段名被搬回 hintText');

    // 规范口径不得回退
    final spec = File('docs/UI组件规范.md').readAsStringSync();
    expect(spec.contains('独立 TextField（hint=占位语）'), isFalse,
        reason: 'LH-C04 规格回退成 hint=占位语');
    expect(spec.contains('labelText=字段名'), isTrue,
        reason: 'LH-C04 规格未同步浮动标签口径');
  });
}
