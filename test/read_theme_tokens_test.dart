import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/theme/theme_repository.dart';
import 'package:lifeharness/features/read/presentation/stats/read_stat_heat_card.dart';

/// 阅读模块批3 · 主题矩阵与 UI 一致性（F3-1~F3-3）常驻守护。
///
/// 三条：
/// 1. **令牌非空**（F3-1）：`text1/text2/ink` 在全部主题明暗档均落到真实值，
///    且主/次文本不同色（层级区分）。
/// 2. **色阶随主题**（F3-2）：热力五档由 `accent` 派生（末档＝`accent` 本身、
///    跨主题不同、深色档第 0 档非亮块）。
/// 3. **固定靛蓝/灰字清零**（F3-3）：已收 token 的 reader 面文件不再出现
///    固定 `#6366F1` 与 `#94A3B8` 字面量。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('F3-1 文本令牌 text1/text2/ink 全主题明暗档非空且主次不同色', () async {
    final reg = await const ThemeRepository().loadAll();
    expect(reg.ids, isNotEmpty);
    for (final id in reg.ids) {
      final b = reg.of(id);
      for (final t in [b.light, b.dark]) {
        expect(t.text1, isNotNull, reason: '$id 文本主色缺失');
        expect(t.text2, isNotNull, reason: '$id 文本次色缺失');
        expect(t.ink, isNotNull, reason: '$id 墨色缺失');
        expect(t.text1, isNot(t.text2), reason: '$id 主/次文本同色，无层级');
      }
    }
  });

  test('F3-2 热力五档由 accent 派生（跨主题不同 · 深色第 0 档非亮块）', () async {
    final reg = await const ThemeRepository().loadAll();
    final fresh = reg.of('fresh').light;
    final ocean = reg.of('ocean').light;

    // 末档＝accent 本身 ⇒ 证明「随主题」而非硬编码靛蓝。
    expect(readStatHeatColors(fresh, false).last, fresh.accent);
    expect(readStatHeatColors(ocean, false).last, ocean.accent);
    expect(fresh.accent, isNot(ocean.accent));
    expect(
      readStatHeatColors(fresh, false),
      isNot(readStatHeatColors(ocean, false)),
      reason: '两主题色阶相同 ⇒ 未随主题',
    );

    // 五档、深色档第 0 档是深底（不是 `#E2E8F0` 亮块）。
    final dark = readStatHeatColors(fresh, true);
    expect(dark, hasLength(5));
    expect(dark.first.computeLuminance(), lessThan(0.1));
  });

  test('F3-3 已收 token 的 reader 面不再有固定 #6366F1 / #94A3B8 字面量', () {
    const refactored = [
      'lib/features/read/presentation/reader/reader_xray_sheets.dart',
      'lib/features/read/presentation/reader/reader_xray_learn_sheets.dart',
      'lib/features/read/presentation/reader/reader_toc_drawer.dart',
    ];
    for (final p in refactored) {
      final src = File(p).readAsStringSync();
      expect(src.contains('0xFF6366F1'), isFalse, reason: '$p 仍有固定靛蓝字面量');
      expect(src.contains('0xFF94A3B8'), isFalse, reason: '$p 仍有固定灰字字面量');
    }

    // X-Ray 面板：固定灰字已清零；靛蓝只允许在语义类型色表里保留（person 类型）。
    final panel = File(
      'lib/features/read/presentation/reader/reader_xray_panel.dart',
    ).readAsStringSync();
    expect(panel.contains('0xFF94A3B8'), isFalse, reason: 'xray_panel 仍有固定灰字');
    expect(
      RegExp(r"Color\(0xFF6366F1\)").allMatches(panel).length,
      lessThanOrEqualTo(1),
      reason: 'xray_panel 靛蓝字面量超出类型色表允许值',
    );
  });
}
