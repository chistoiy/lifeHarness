import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// 预算式文件体积门禁（治理收口批·A 档口径 2026-09-29 拍板）。
///
/// 口径：`lib/**` 单文件行数超过 [lineBudget] 必须先进 [budget] 登记（登记值＝登记时行数），
/// 此后只许减不许增——超线未登记＝红；超出登记预算＝红；变小则提示更新登记（棘轮收紧）。
/// 登记面是治理评估 §7「范围重定」列出的 A 档遗留大文件：不逐一压缩，长期管住不再长大。
/// 拆完一个请**删掉对应登记项**（不是调小），让门禁回到「超线即红」的默认面。
void main() {
  const libDir = 'lib';
  const lineBudget = 1200;

  // 治理 G0~G7d⑤ 交付后（2026-09-29）实测登记的基线预算。
  const budget = <String, int>{
    'features/read/presentation/read_sheets_b2.dart': 1778,
    'features/ledger/presentation/ledger_pick_sheets.dart': 1581,
    'features/read/presentation/shelf/book_detail.dart': 1570,
    'features/habit/presentation/habit_detail_page.dart': 1521,
    'features/habit/presentation/habit_stat_page.dart': 1504,
    'features/read/presentation/stats/read_stat_page.dart': 1383,
    'features/calendar/presentation/calendar_page.dart': 1377,
    'features/read/presentation/shelf/book_form_page.dart': 1362,
    'features/ledger/data/ledger_repository.dart': 1352,
    'features/read/presentation/read_sheets_b3.dart': 1331,
    'features/journal/presentation/diary_edit_page.dart': 1260,
    'features/todo/presentation/widgets/todo_edit_sheet.dart': 1231,
  };

  test('体积预算：lib 超线文件必须登记且只许减不许增', () {
    final over = <String>[], grown = <String>[], shrunk = <String>[];
    final seen = <String>{};
    for (final f in Directory(libDir).listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final rel = p.posix.joinAll(p.split(p.relative(f.path, from: libDir)));
      final lines = f.readAsLinesSync().length;
      if (lines <= lineBudget) continue;
      seen.add(rel);
      final b = budget[rel];
      if (b == null) {
        over.add('$rel（$lines 行，未登记）');
      } else if (lines > b) {
        grown.add('$rel（$lines > 预算 $b）');
      } else if (lines < b) {
        shrunk.add('$rel（$lines < 登记 $b，请把预算改成 $lines 或删项归还默认面）');
      }
    }
    final stale = budget.keys.where((k) => !seen.contains(k)).toList();
    expect(over, isEmpty,
        reason: '新文件超过 $lineBudget 行预算线：先拆分，确需豁免再登记进本测试 budget 表'
            '（登记＝允许存在的当前行数，之后只许减）。');
    expect(grown, isEmpty,
        reason: '已登记大文件长大了：预算只许减不许增。'
            '确属必要增长请先走治理评审并同步更新登记值。');
    expect(shrunk, isEmpty,
        reason: '以下文件已变小，棘轮要收紧：把登记值调小；若已降到预算线下请删掉登记项。');
    expect(stale, isEmpty,
        reason: '以下登记项对应的文件已消失或已降到预算线下，请删掉（否则守护悄悄空转）：'
            '${stale.join('、')}');
  });
}
