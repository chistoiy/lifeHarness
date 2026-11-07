import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/features/read/presentation/stats/read_stat_heat_card.dart';

/// 阅读模块批3 波3 · 触控热区（F3-8）常驻守护。
///
/// 口径（冻结方案 F3-8 · C4「视觉可小，热区不小」）：
/// 关键可点元素命中区 ≥44×44；密排例外两处＝
/// 热力格（节距 16 满铺命中，44 会互相吃格）与
/// 段内感想点（24² 槽，44 会把段后空隙撑大 30px+）——
/// 例外口径已登记工单 §4。
void main() {
  group('F3-8 热力格：命中＝满节距 16²', () {
    testWidgets('格子命中槽 16×16（视觉 13 居中）且点格回调', (tester) async {
      DateTime? tapped;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ReadStatHeatCard(
              year: 2026,
              month: 0,
              scopeTag: '2026|min',
              metricName: '时长',
              goalDay: 30,
              valueAt: (i) => i % 3 == 0 ? 12 : 0,
              minutesAt: (_) => 45,
              summary: 'x',
              onTapDay: (c, d, i) => tapped = d,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final cell = tester.getSize(find.byKey(const ValueKey('rs-heat-0')));
      // 满节距命中：≥16×16（旧命中只有 13²）。
      expect(cell.width, greaterThanOrEqualTo(16.0));
      expect(cell.height, greaterThanOrEqualTo(16.0));

      // 默认视口＝最后一个有数据的列贴右，1 号格在屏外；点年末那格（有数据）。
      await tester.tap(find.byKey(const ValueKey('rs-heat-364')));
      await tester.pump();
      expect(tapped, isNotNull);
    });
  });

  group('F3-8 关键目标 ≥44 命中（源码守护）', () {
    // 密排/带状态的整页用例难单独泵起（依赖仓内 provider/仓库态），
    // 按 catch_log_guard 同款源码守护口径，钉死每处的命中槽尺寸写法。
    final cases = <String, List<List<String>>>{
      // 顶栏图标钮：去 compact（默认 48²）＝read 面禁用 VisualDensity.compact。
      'lib/features/read/presentation/reader/reader_chrome.dart': [
        ['无 compact 密度', 'visualDensity: VisualDensity.compact'],
      ],
      // 选区手柄：命中簇 44 宽（原 31）。
      'lib/features/read/presentation/reader/reader_sel_layer.dart': [
        ['手柄命中簇 44 宽', 'const w = 44.0'],
      ],
      // 书架圆钮：命中槽 44²。
      'lib/features/read/presentation/shelf/shelf_views.dart': [
        ['圆钮命中槽 44²', 'width: 44,\n          height: 44,'],
      ],
      // 外观背景色块：命中槽 44²。
      'lib/features/read/presentation/reader/reader_appearance_subs.dart': [
        ['背景块命中槽 44²', 'width: 44,\n                height: 44,'],
      ],
      // 书摘库三枚文字钮：minimumSize 44。
      'lib/features/read/presentation/stats/quotes_lib_page.dart': [
        ['文字钮 minimumSize 44', 'minimumSize: const Size(44, 44)'],
      ],
      // 设置页 tab：命中槽高 44。
      'lib/features/read/presentation/read_settings_page.dart': [
        ['tab 命中槽高 44', 'height: 44,'],
      ],
    };

    test('关键目标命中写法在场（≥44 或登记例外）', () {
      cases.forEach((path, checks) {
        // 仓内文件是 CRLF，先归一化再比。
        final src = File(path).readAsStringSync().replaceAll('\r\n', '\n');
        for (final check in checks) {
          final label = check[0], needle = check[1];
          // 「无 compact」类负向断言：命中即红。
          if (label.startsWith('无 ')) {
            expect(src, isNot(contains(needle)), reason: '$path: $label');
          } else {
            expect(src, contains(needle), reason: '$path: $label');
          }
        }
      });
    });

    test('弹层骨架：read 面所有 showModalBottomSheet 均带把手（F3-10）', () {
      final dir = Directory('lib/features/read/presentation');
      final files = dir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();
      var sheetCalls = 0;
      for (final f in files) {
        final src = f.readAsAsStringSyncSafe();
        // 逐调用体扫：showModalBottomSheet(...) 内必须出现 showDragHandle
        // （含把手即达标；refine 件的 ConstrainedBox 内滚基准不在此断言）。
        var i = 0;
        while (true) {
          i = src.indexOf('showModalBottomSheet', i);
          if (i < 0) break;
          // 注释命中跳过。
          final lineStart = src.lastIndexOf('\n', i) + 1;
          final line = src.substring(lineStart, src.indexOf('\n', lineStart));
          if (!line.trimLeft().startsWith('/')) {
            final open = src.indexOf('(', i);
            var depth = 0;
            var j = open;
            for (; j < src.length; j++) {
              if (src[j] == '(') depth++;
              if (src[j] == ')') {
                depth--;
                if (depth == 0) break;
              }
            }
            final body = src.substring(i, j);
            sheetCalls++;
            expect(
              body.contains('showDragHandle'),
              isTrue,
              reason: '${f.path}: showModalBottomSheet 缺把手（F3-10）',
            );
          }
          i += 'showModalBottomSheet'.length;
        }
      }
      expect(sheetCalls, greaterThanOrEqualTo(20), reason: 'read 面 sheet 数量守护');
    });
  });
}

extension on File {
  // 测试内小工具：按 UTF-8 读全文（dart:io File.readAsStringSync 即可，
  // 包一层避免上面调用处拼写分叉）。
  String readAsAsStringSyncSafe() => readAsStringSync();
}
