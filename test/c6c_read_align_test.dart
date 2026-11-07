/// C 案批6c · 阅读 R1~R8 回写原型常驻守护（2026-11-07）。
/// 规格＝`docs/handoff/交棒话术-20261107-记录四模块拆分C案批1路由与底栏池.md` §14 裁定记录。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final s = File('prototype/index-bookshelf.html').readAsStringSync();

  test('① R1/R2 工作台副行＝bsFmt 时分制＋连续天数宽容口径', () {
    expect(s, contains(r'本周 ${bsFmt(week)} / 目标 ${bsFmt(BS_GOAL.weekMin)}'),
        reason: '本周时长回退小数小时');
    expect(s, contains('const _st0 = BS_LOG[262].m > 0 ? 262 : 261'),
        reason: '断签口径回退「今天没读即断」');
  });

  test('② R3 工作台计时 pill 按 BS_FULLTIMER 分流', () {
    expect(s, contains('onclick="recHubTimerTap()"'), reason: 'pill 回退恒胶囊');
    expect(s, contains('if (BS_FULLTIMER) { rtOpen(ing[0].id); return }'),
        reason: '分流分支被摘除');
  });

  test('③ R5 轨道/网格本地书直达阅读器', () {
    expect(s, contains(r"(b.local ? `brOpen('${b.id}')` : `shOpen('${b.id}')`)"),
        reason: '本地书分流被摘除（恒进详情）');
  });

  test('④ R6/R7/R8 摘录空态＋品牌 token＋工作台 FAB', () {
    expect(s, contains('还没有摘录 · 点右下角 ＋ 记第一条'), reason: '摘录空态被摘除');
    expect(s, isNot(contains(r'qtReview()"><span class="w-9 h-9 rounded-xl bg-violet-50')),
        reason: '复习卡 violet 硬编码复活');
    expect(s, contains("bg-brand-50 dark:bg-brand-500/15 text-brand-500"),
        reason: '复习卡未走品牌 token');
    expect(s, contains("'p-readhub':{ico:'＋',act:()=>qeOpen(null,(bsIng()[0]||{}).id)}"),
        reason: '工作台 FAB 配置被摘除');
  });
}
