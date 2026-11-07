/// C 案批5 · 四模块细节对齐（零争议项）常驻守护（2026-11-07）。
/// 规格＝`docs/handoff/交棒话术-20261107-记录四模块拆分C案批1路由与底栏池.md` §14。
/// 纯源码级：不起整机、不建库。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String read(String p) => File(p).readAsStringSync();

  test('① 日记筛选空态有「清除筛选」钮并接 resetJournalFilter', () {
    final s = read('lib/features/journal/presentation/journal_page.dart');
    expect(s, contains("key: const ValueKey('diary-clear-filter')"),
        reason: '筛选空态的清除筛选钮被摘除（原型 p-diaryHome 同位文字钮）');
    expect(s, contains('resetJournalFilter'), reason: '清除筛选未接四维重置');
  });

  test('② 日记列表卡标签全量渲染，不得回退 take(3) 静默截断', () {
    final s = read('lib/features/journal/presentation/journal_page_card.dart');
    expect(s, contains('for (final t in e.tags)'), reason: '标签改回截断渲染');
    expect(s, contains('Wrap('), reason: '标签容器必须可换行（全量渲染的前提）');
    expect(s, isNot(contains('e.tags.take(3)')), reason: '静默丢标签复活');
  });

  test('③ 日记 FAB 长按展开有触感反馈', () {
    final s =
        read('lib/features/journal/presentation/widgets/diary_fan_fab.dart');
    expect(s, contains('HapticFeedback.lightImpact()'),
        reason: '扇形展开触感被摘除（原型 navigator.vibrate(8) 同口径）');
  });

  test('④ 影音游按进度排序 SQL 能力在册（菜单暴露随排序形态裁定另批）', () {
    final repo = read('lib/features/media/data/media_repository.dart');
    expect(repo, contains("'year':"),
        reason: '发行年排序 SQL 白名单被摘除');
    expect(repo, contains("'progress': 'MAX(main_pct, side_pct, ach_pct)"),
        reason: '按进度排序 SQL 白名单被摘除');
  });

  test('⑤ 影音游工作台「计时中」行不再是死入口', () {
    final s = read('lib/features/media/presentation/media_workbench.dart');
    expect(s, contains(r"context.push('/media/item/${s.itemId}')"),
        reason: '计时中行点击接线被摘除（原型 mStartTimerFor 跳详情语义）');
    expect(
        s, isNot(contains("key: const ValueKey('media-running-row'),\n"
            '        borderRadius: BorderRadius.circular(14),\n'
            '        onTap: null,')),
        reason: '死入口 onTap: null 复活');
  });
}
