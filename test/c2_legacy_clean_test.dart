/// C 案批2 · 旧四段兼容层清理常驻守护（2026-11-07）。
/// 规格＝`docs/handoff/交棒话术-20261107-记录四模块拆分C案批1路由与底栏池.md` §7。
/// 纯源码级：不起整机、不建库（widget 侧在 `journal_deeplink_test.dart`）。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/features/journal/presentation/journal_routes.dart';

void main() {
  const jp = 'lib/features/journal/presentation/journal_page.dart';
  const jr = 'lib/features/journal/presentation/journal_routes.dart';
  const jv = 'lib/features/journal/presentation/journal_providers.dart';

  test('① 单段壳：构造只吃 required section，旧四段符号零命中', () {
    final s = File(jp).readAsStringSync();
    expect(s, contains('const JournalPage({super.key, required this.section});'),
        reason: '构造退回可选段＝又有了「默认四段页」这一态');
    // 标题恒取单段名，不得再拼四段前缀（如「记录 · 日记」）。
    // 2026-11-08 重钉：日记段补原型副标题（C 案批6a D1）后标题分两支，两支都仍取单段名。
    expect(s, contains("Text(JournalPage.kRecordLabels[tab] ?? '笔记')"),
        reason: '非日记段标题取单段名表');
    expect(s, contains("const Text('日记')"),
        reason: '日记段标题写死单段名「日记」（副标题另起一行，不带四段前缀）');
    for (final dead in <String>[
      'standalone',
      'initialTab',
      'isRecordTab',
      '_linkTab',
      '_takeLink',
      '_selectTab',
      'rec-switch',
      'recordTabProvider',
      '记录 · ',
    ]) {
      expect(s, isNot(contains(dead)), reason: '旧四段符号 $dead 复活');
    }
  });

  test('② 全局「上次停留段」状态已退役', () {
    expect(File(jv).readAsStringSync(), isNot(contains('recordTabProvider')),
        reason: '段只由路由锁定，不该再有跨页串台的全局 tab 状态');
  });

  test('③ 四条独立路由各锁一段，旧深链兼容跳转仍在', () {
    final s = File(jr).readAsStringSync();
    const pairs = <String, String>{
      '/notes': 'note',
      '/diary': 'diary',
      '/readhub': 'book',
      '/mediahub': 'media',
    };
    for (final e in pairs.entries) {
      final re = RegExp("path: '${e.key}'[\\s\\S]{0,200}?section: '${e.value}'");
      expect(re.hasMatch(s), isTrue, reason: '${e.key} 未锁到 ${e.value} 段');
    }
    expect(s, isNot(contains('standalone')),
        reason: '独立页开关已删，段只由路由锁定');
    // 兼容跳转不是四段兼容类：旧桌面快捷方式／旧深链仍要落对应独立页。
    expect(journalLegacyTarget('book'), '/readhub');
    expect(journalLegacyTarget(null), '/notes');
  });

  test('④ 存量用例零旧形态构造（防兼容层复活）', () {
    final bad = <String>[];
    for (final f in Directory('test').listSync().whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      // 本件自身持有这些禁用串的字面量（用于比对），跳过免自指误报。
      final norm = f.path.replaceAll(r'\', '/');
      if (norm.endsWith('/c2_legacy_clean_test.dart')) continue;
      final s = f.readAsStringSync();
      for (final dead in <String>[
        'const JournalPage()',
        'JournalPage(initialTab:',
        'standalone: true',
      ]) {
        if (s.contains(dead)) bad.add('${f.path}: $dead');
      }
    }
    expect(bad, isEmpty, reason: '旧四段构造复活：$bad');
  });
}
