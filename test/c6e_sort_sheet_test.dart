/// C 案批6e · 影音游 M2 排序底弹层常驻守护（2026-11-07）。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('M2 排序＝底弹层七键（含发行年/进度）·顶栏 Popup 退役', () {
    final s = File('lib/features/media/presentation/media_shelf_page.dart')
        .readAsStringSync();
    expect(s, contains('void showMediaSortSheet('),
        reason: '底弹层入口函数被摘除');
    expect(s, contains('showModalBottomSheet<void>('), reason: '底弹层形态回退');
    for (final v in const [
      "('recent', '最近活动')", "('rating', '按评分')", "('added', '新增在前')",
      "('year', '按发行年')", "('name', '按名称')", "('duration', '按时长')",
      "('progress', '按进度')",
    ]) {
      expect(s, contains(v), reason: '底弹层缺 $v');
    }
    expect(s, isNot(contains('PopupMenuButton<String>(')), reason: '顶栏下拉菜单复活');
  });
}
