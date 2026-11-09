/// C 案批3 · 原型影音游死码清理常驻守护（2026-11-07）。
/// 规格＝`docs/handoff/交棒话术-20261107-记录四模块拆分C案批1路由与底栏池.md` §9。
/// 纯源码级：不起整机、不建库。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const html = 'prototype/index.html';
  const reg = 'prototype/_modules.json';
  const card = 'prototype/screens/index.index.json';
  const id = 'sheetAddMedia';

  test('① 壳内影音游死码零命中（弹层／演示数据／空转函数）', () {
    final s = File(html).readAsStringSync();
    for (final dead in <String>[
      id,
      'const MEDIA=',
      'addMedia(',
      'renderMedia(',
      'mediaList',
      'mdTitle',
      'mdRate',
      'mdLen',
      'mdNote',
    ]) {
      expect(s, isNot(contains(dead)), reason: '壳内影音游死码 $dead 复活');
    }
    // 注：阅读进度弹层另有一枚 🎬 属可达屏视觉，本批不碰，故不设全文 emoji 断言。
    expect(s, contains('function pickChip(el)'),
        reason: '通用 chip 函数属共有件，本批不删');
  });

  test('② 四处登记面已同步：screens／violations／redirects 零该屏，deleted 留一条台账', () {
    final d = jsonDecode(File(reg).readAsStringSync()) as Map<String, dynamic>;
    final screens = (d['screens'] as List).cast<Map<String, dynamic>>();
    expect(screens.where((s) => s['id'] == id), isEmpty,
        reason: '退役屏不得留在屏登记表');
    final viols = (d['violations'] as List).cast<Map<String, dynamic>>();
    expect(viols.where((v) => v['id'] == id), isEmpty,
        reason: '指向已退役屏的历史违规台账未清');
    final reds = (d['redirects'] as List).cast<Map<String, dynamic>>();
    expect(
        reds.where((r) =>
            (r['from'] as String).contains(id) || (r['to'] as String).contains(id)),
        isEmpty,
        reason: '指向已删锚点的重定向未清');
    final deleted = ((d['deleted'] as Map)['index.html'] as List)
        .cast<Map<String, dynamic>>();
    expect(deleted.where((x) => x['id'] == id).length, 1,
        reason: '删屏台账应留且只留一条');
  });

  test('③ 索引卡零该条，壳内不再有屏级媒体弹层', () {
    final c = jsonDecode(File(card).readAsStringSync()) as Map<String, dynamic>;
    final list = (c['screens'] as List).cast<Map<String, dynamic>>();
    expect(list.where((x) => x['id'] == id), isEmpty,
        reason: '索引卡仍登记已删弹层');
    final s = File(html).readAsStringSync();
    expect(RegExp(r'<div\b[^>]*\bid="sheetAddMedia"').hasMatch(s), isFalse,
        reason: '屏级弹层 markup 复活');
  });
}
