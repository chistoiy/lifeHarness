import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/theme/app_typography.dart';

/// 阅读模块批3 · 字体与数字（F3-4/F3-5）常驻守护。
///
/// 口径（《UI组件规范》〇A · LH-F01 三档角色链）：
/// **正文衬线 / 标题与 UI 标签无衬线 / 数字等宽**。
void main() {
  test('F3-4 字体角色链：body 衬线首族 + 衬线回落链', () {
    expect(kFontBody.first, 'Noto Serif SC');
    expect(kFontBody.fallback, contains('serif'));
    final st = kFontBody.apply(const TextStyle(fontSize: 12));
    expect(st.fontFamily, 'Noto Serif SC');
    expect(st.fontFamilyFallback, contains('serif'));
    // UI 档必须是无衬线（标题行不吃衬线）。
    expect(kFontUi.fallback, contains('sans-serif'));
  });

  test('F3-4 书摘/详情摘录/X-Ray 摘录正文走 kFontBody（衬线）', () {
    const bodySites = [
      'lib/features/read/presentation/stats/quotes_lib_page.dart',
      'lib/features/read/presentation/shelf/book_detail.dart',
      'lib/features/read/presentation/reader/reader_xray_panel.dart',
    ];
    for (final p in bodySites) {
      expect(
        File(p).readAsStringSync().contains('kFontBody.apply'),
        isTrue,
        reason: '$p 正文未吃衬线角色链',
      );
    }
  });

  test('F3-5 统计四卡/记录四格/概览/目标读数走 tabular-nums', () {
    const numSites = [
      'lib/features/read/presentation/stats/read_stat_page.dart',
      'lib/features/read/presentation/stats/read_log_page.dart',
      'lib/features/read/presentation/read_tab.dart',
      'lib/features/read/presentation/shelf/shelf_goal.dart',
    ];
    for (final p in numSites) {
      expect(
        File(p).readAsStringSync().contains('FontFeature.tabularFigures()'),
        isTrue,
        reason: '$p 读数未走等宽数字',
      );
    }
  });
}
