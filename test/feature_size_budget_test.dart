import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// 单 feature 总行数预算门禁（高保真体量整改批 6a·2026-10-16 立）。
///
/// 动机：`size_budget_test.dart` 只管单文件行数、**不管模块总量**——read 可以
/// 一直长到任意大而那道闸不红（工单 §1.2：read 48,940 行＝第二名 2.7 倍）。
/// 本闸补这一面：`lib/features/<name>/` 整棵子树的 `.dart` 行数总和＝该 feature
/// 总量，超过 [featureBudget] 登记值＝红，**只许减不许增**（棘轮，同 size_budget
/// 家族口径）。拆完/还债请把登记值调小（不要删项——默认面是「全部登记」）。
///
/// 判红三类：① 总量超登记＝长大；② 新 feature 目录未登记＝新模块必须登记现值；
/// ③ 登记项对应目录消失＝删项。变小只提醒不判红（拆小是好事，同 C-4 口径）。
/// 纯静态扫描，无需 pump。
void main() {
  const featuresDir = 'lib/features';

  // 立闸时实测基线（2026-10-16·工作区 HEAD `2b12d608` 干净树）：read 48,940 行/99 文件
  // ＝工单 §1.2 靶子数；其余 feature 同法取现值。此后只许减不许增。
  const featureBudget = <String, int>{
    'read': 48940,
    'ledger': 18045,
    'media': 13573,
    'health': 12862,
    'settings': 12516,
    'journal': 12212,
    'habit': 12141,
    'care': 10909,
    'mindmap': 6540,
    'calendar': 5874,
    'items': 4248,
    'days': 3492,
    'todo': 3143,
    'goals': 2809,
    'dashboard': 1401,
    'inbox': 593,
  };

  test('feature 总量预算：lib/features 单模块总行数只许减不许增', () {
    final grown = <String>[], shrunk = <String>[], unregistered = <String>[];
    final seen = <String>{};
    for (final feat
        in Directory(featuresDir).listSync().whereType<Directory>()) {
      final name = p.basename(feat.path);
      var lines = 0;
      for (final f in feat.listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        lines += f.readAsLinesSync().length;
      }
      seen.add(name);
      final b = featureBudget[name];
      if (b == null) {
        unregistered.add('$name（$lines 行，未登记）');
      } else if (lines > b) {
        grown.add('$name（$lines > 预算 $b）');
      } else if (lines < b) {
        shrunk.add('$name（$lines < 登记 $b，请把预算改成 $lines）');
      }
    }
    final stale = featureBudget.keys.where((k) => !seen.contains(k)).toList();
    expect(grown, isEmpty,
        reason: 'feature 总量长大了：预算只许减不许增。确属必要增长请先走治理评审'
            '并同步调大登记值（默认不许）。');
    expect(unregistered, isEmpty,
        reason: '新 feature 目录未登记总量上限：把现值登记进 featureBudget（'
            '之后只许减）。');
    // 变小不是变坏——拆分/删代码让模块变轻是好事，判红只会让并行会话互相踩出
    // 「我没动为什么红」。降级为提醒，收紧登记值由看到提醒的人顺手做。
    if (shrunk.isNotEmpty) {
      // ignore: avoid_print
      print('[feature_size_budget 提醒] 以下 feature 已变小，请顺手调小登记值：\n  '
          '${shrunk.join('\n  ')}');
    }
    expect(stale, isEmpty,
        reason: '以下登记项对应 feature 目录已消失，请删掉（否则守护悄悄空转）：'
            '${stale.join('、')}');
  });
}
