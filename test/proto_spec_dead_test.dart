/// C 案批4 · 八份专版旧四段死调用清理常驻守护（2026-11-07）。
/// 规格＝`docs/handoff/交棒话术-20261107-记录四模块拆分C案批1路由与底栏池.md` §12。
/// 纯源码级：不起整机、不建库。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const specs = <String>[
    'index-bookshelf.html',
    'index-day_aim__goods.html',
    'index-health.html',
    'index-journal.html',
    'index-ledger.html',
    'index-maternity_bady.html',
    'index-media.html',
    'index_habitcheck.html',
  ];
  const reg = 'prototype/_modules.json';

  String read(String name) => File('prototype/$name').readAsStringSync();

  test('① 八份专版零 p-records FAB 分支／零弹层打开调用', () {
    for (final name in specs) {
      final s = read(name);
      expect(s, isNot(contains("'p-records':{ico:'✎'")),
          reason: '$name 的不可达 FAB 分支复活');
      expect(s, isNot(contains("openSheet('sheetAddMedia')")),
          reason: '$name 又去打开已删弹层');
    }
  });

  test('② 八份专版零悬挂重定向条目／零弹层 markup', () {
    for (final name in specs) {
      final s = read(name);
      expect(s, isNot(contains('"sheetAddMedia":')),
          reason: '$name 的 RED 表仍指向已删锚点');
      expect(RegExp(r'<div\b[^>]*\bid="sheetAddMedia"').hasMatch(s), isFalse,
          reason: '$name 复活了屏级弹层 markup');
    }
    final d = jsonDecode(File(reg).readAsStringSync()) as Map<String, dynamic>;
    for (final key in <String>['screens', 'violations', 'redirects']) {
      final arr = (d[key] as List).cast<Map<String, dynamic>>();
      expect(arr.where((x) => jsonEncode(x).contains('sheetAddMedia')), isEmpty,
          reason: '注册表 $key 仍登记已删弹层');
    }
  });

  test('③ 边界：可达件未误删（FAB_CFG 其余键／孪生空转链／壳零改动）', () {
    for (final name in specs) {
      final s = read(name);
      expect(s, contains('const FAB_CFG={'),
          reason: '$name 的 FAB 配置表整块被误删');
      expect(s, contains("'p-dashboard':"),
          reason: '$name 的首页 FAB 键被误删');
      expect(s, contains('renderMedia'),
          reason: '$name 的计时器链被越界清掉（属 §13 剩余债，本批不动）');
    }
    expect(File('prototype/index.html').readAsStringSync(),
        contains('p-records'),
        reason: '壳内笔记主面仍在，本批不得碰壳');
  });
}
