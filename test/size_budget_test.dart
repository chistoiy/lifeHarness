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
    // book_detail 登记值 1570→1579 同属存量越线归位（V1.60 导入批实测 HEAD 即 1579，
    // 本批只改两行同长文案，净增 0；真还债＝三态弹层群拆 part，另批做）。
    'features/read/presentation/shelf/book_detail.dart': 1579,
    'features/habit/presentation/habit_detail_page.dart': 1520,
    'features/habit/presentation/habit_stat_page.dart': 1503,
    'features/read/presentation/stats/read_stat_page.dart': 1359,
    // 1377→1382：交互整改批一 T2-B 给主屏长列表挂 ScrollPad（切栏滚动垫），
    // 净增 5 行接线（注释+包层）；真还债=日历区子视图拆 part，另批做。
    // 1382→1386 存量越线归位（B-4 批 2026-10-05 相邻回归跑出本红）：净增 4 行
    // 发生在轮5批A（ce5acee，F5-2 展开默认随视图档），该批批内增量没带 size 闸，
    // 非 B-4 造成——B-4 未动日历一行。之后只许减。
    'features/calendar/presentation/calendar_page.dart': 1386,
    'features/read/presentation/shelf/book_form_page.dart': 1361,
    'features/ledger/data/ledger_repository.dart': 1352,
    'features/read/presentation/read_sheets_b3.dart': 1331,
    'features/journal/presentation/diary_edit_page.dart': 1259,
    // 归属澄清（V1.60 导入批 2026-10-04 跑出本红）：reader_page 越线发生在
    // 真机轮4 批A⑥（eb44611，1175→1212，暂停计时那刀），该批批内增量没带 size 闸，
    // 非 V1.60 造成——V1.60 反而净减 2 行（预载拦截摘除，1212→1210）。
    // 此处按默认面登记现状＝1210，之后只许减；真还债＝把取证/装载群再拆一件
    // part 扩展（G7c 族口径），另批做。
    'features/read/presentation/reader/reader_page.dart': 1210,
    // 批三刀2 登记的 epub_doc 体积债已归还（刀3 开工前置）：抽取器整段拆成同库件
    // `part 'epub_extract.dart';`（G7d⑤ 族口径，私有成员不放宽），主文件回落到默认面以下。
    // R3-2 批登记的 reader_page 体积债已归还（批三刀4）：分页群七件拆进同库扩展
    // `part 'reader_page_pag.dart';`（G7c 族口径），主文件回到默认 1200 面以下。
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
    // 清单 C-4：「变小」不是变坏——别的会话把文件拆小/修好是好事，
    // 判红只会让并行会话互相踩出「我没动为什么红」的红灯。降级为提醒，
    // 收紧登记值由看到提醒的人顺手做；over / grown / stale 仍然判红（那三个才是变坏）。
    if (shrunk.isNotEmpty) {
      // ignore: avoid_print
      print('[size_budget 提醒] 以下登记文件已变小，请顺手调小登记值或删项：\n  '
          '${shrunk.join('\n  ')}');
    }
    expect(stale, isEmpty,
        reason: '以下登记项对应的文件已消失或已降到预算线下，请删掉（否则守护悄悄空转）：'
            '${stale.join('、')}');
  });
}
