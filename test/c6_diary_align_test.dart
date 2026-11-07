/// C 案批6a · 日记 D1~D7 对齐常驻守护（2026-11-07）。
/// 规格＝`docs/handoff/交棒话术-20261107-记录四模块拆分C案批1路由与底栏池.md` §14 裁定记录。
/// 纯源码级：不起整机、不建库。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final s =
      File('lib/features/journal/presentation/journal_page.dart')
          .readAsStringSync();

  test('① D1 日记段顶栏带动态副标题（_diarySub）', () {
    expect(s, contains("title: tab == 'diary'"),
        reason: '日记段副标题被摘除（原型 p-diaryHome pageSub）');
    expect(s, contains('String _diarySub(WidgetRef ref)'),
        reason: '副标题取数函数被摘除');
  });

  test('② D2 月历卡 grad-soft 低饱和渐变（浅/深两档）＋onMood 文字', () {
    expect(s, contains('Color(0xFFEDE9FE)'), reason: '浅档淡紫渐变被摘除');
    expect(s, contains('Color(0xFF3730A3)'), reason: '深档深紫渐变被摘除');
    expect(s, contains('final onMood'), reason: '月历卡文字色回退恒白');
    expect(s, isNot(contains('gradient: tokens.gradient,\n              borderRadius: BorderRadius.circular(24)')),
        reason: '月历卡回退主题全饱和渐变');
  });

  test('③ D3 回顾钮＝白/70 胶囊＋柱状线性图标＋slate 细字（去 emoji）', () {
    expect(s, contains("Icons.bar_chart"), reason: '回顾钮线性图标被摘除');
    expect(s, contains("color: Colors.white.withValues(alpha: .7)"),
        reason: '回顾钮胶囊底回退白/20 平底');
    expect(s, isNot(contains("'📊 回顾'")), reason: '回顾钮 emoji 复活');
  });

  test('④ D4 月历色条降饱和同明度色组', () {
    expect(s, contains('Color(0xFF9BA3E8)'), reason: '降饱和色组被换回');
    expect(s, isNot(contains('Color(0xFF6366F1)')), reason: '高饱和彩虹档复活');
  });

  test('⑤ D6 列表卡收藏/点亮固定语义色', () {
    expect(s, contains('color: kJournalStarred'), reason: '点亮回退主题色');
    expect(s, contains('color: kJournalLiked'), reason: '收藏回退主题色');
  });

  test('⑥ D7 那年今日「N 年前 · MM-DD」口径', () {
    expect(s, contains(' 年前 · '), reason: '那年今日回退全日期');
  });

  test('⑦ D5 月历卡月份中文数字', () {
    expect(s, contains('_cnMonth(now.month)'), reason: '月份回退阿拉伯数字');
    expect(s, contains("const _cnMonths = ["), reason: '中文月表被摘除');
  });
}
