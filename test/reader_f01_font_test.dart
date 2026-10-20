import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lifeharness/core/theme/app_theme.dart';
import 'package:lifeharness/core/theme/app_typography.dart';
import 'package:lifeharness/features/read/data/epub_cache.dart' show PagStore;
import 'package:lifeharness/features/read/domain/reader_cfg.dart';
import 'package:lifeharness/features/read/presentation/reader/reader_pager.dart';

/// LH-F01 · 三档字体角色落到 Flutter（规格＝《UI组件规范》〇A 节＋F01 工单 §1）。
///
/// 这一组用例守的是四件容易回退的事：
/// ① 三串链与原型**逐字符一致**（谁把它改回 `'serif'/'sans-serif'` 泛族就红）；
/// ② 阅读器默认族＝衬线，但**老用户落库的选择必须原样读回**（含旧默认 `system`）；
/// ③ 测量与渲染同源：`ReaderLayout` 与 `ReaderCfg` 必须给同一族＋同一回落链；
/// ④ 主题 `--app-font` 作**整档覆盖**、角色链作默认（2026-10-03 产品拍板）。
void main() {
  group('1 · 三档角色链与规范同串', () {
    test('正文＝衬线链（链首 Noto Serif SC，链尾落到 Android 泛族 serif）', () {
      expect(kFontBody.role, 'body');
      expect(kFontBody.first, 'Noto Serif SC');
      expect(kFontBody.fallback, [
        'Source Han Serif SC',
        'Songti SC',
        'STSong',
        'SimSun',
        'Georgia',
        'serif',
      ]);
    });

    test('UI＝无衬线链 · 代码＝等宽链', () {
      expect(kFontUi.first, 'Inter');
      expect(kFontUi.fallback, [
        'Noto Sans SC',
        'Source Han Sans SC',
        'PingFang SC',
        'Microsoft YaHei',
        'system-ui',
        'sans-serif',
      ]);
      expect(kFontCode.first, 'ui-monospace');
      expect(kFontCode.fallback, ['JetBrains Mono', 'Consolas', 'Menlo', 'monospace']);
    });

    test('三档链首都不许是 Android 泛族名（泛族只允许出现在链尾兜底）', () {
      const generics = {'serif', 'sans-serif', 'monospace'};
      for (final r in [kFontBody, kFontUi, kFontCode]) {
        expect(generics.contains(r.first), isFalse,
            reason: '${r.role} 链首又变回泛族＝LH-F01 被摘，中文正文会掉进黑体');
        expect(r.fallback.last, isNotEmpty);
      }
    });
  });

  group('2 · 阅读器默认族与老用户落库', () {
    test('默认 cfg 正文字族取到 body 链首（工单 §1 判据 a）', () {
      const c = ReaderCfg();
      expect(c.font, 'serif', reason: '正文默认族由「系统默认」改「衬线」');
      expect(c.fontFamily, 'Noto Serif SC');
      expect(c.fontFamilyFallback, contains('serif'));
    });

    test('老用户落库 hei / system 原样读回，写路径不覆盖默认值（判据 b）', () {
      final hei = ReaderCfg.decode(jsonEncode({'font': 'hei'}));
      expect(hei.font, 'hei');
      expect(hei.fontFamily, 'Inter', reason: '黑体档现在走 UI 无衬线链');

      final legacy = ReaderCfg.decode(jsonEncode({'font': 'system'}));
      expect(legacy.font, 'system', reason: '白名单里的 system 必须读得回（老用户落库值）');
      expect(legacy.fontFamily, isNull, reason: 'system＝不指定，跟随平台默认');
      expect(legacy.fontFamilyFallback, isNull);

      // 缺键＝没选过 → 吃新默认；脏值同理（不许把老值兜成 system 再丢链）。
      expect(ReaderCfg.decode(jsonEncode({'fs': 21})).font, 'serif');
      expect(ReaderCfg.decode(jsonEncode({'font': 'comic'})).font, 'serif');
    });

    test('三值族各归其档 · 未知值不指定', () {
      expect(lhFontRoleOfReaderFont('serif'), same(kFontBody));
      expect(lhFontRoleOfReaderFont('hei'), same(kFontUi));
      expect(lhFontRoleOfReaderFont('mono'), same(kFontCode));
      expect(lhFontRoleOfReaderFont('system'), isNull);
    });
  });

  group('3 · 测量与渲染同源', () {
    test('ReaderLayout.of 与 ReaderCfg 给同一族与同一回落链', () {
      for (final f in ['serif', 'hei', 'mono', 'system']) {
        final c = ReaderCfg(font: f);
        final l = ReaderLayout.of(c, width: 360, height: 640);
        expect(l.font, c.font);
        expect(l.fontFamily, c.fontFamily, reason: '$f 档两边族名不一致＝分页表与上屏分家');
        expect(l.fontFamilyFallback, c.fontFamilyFallback);
        expect(l.base.fontFamily, c.fontFamily,
            reason: 'paraStyle 吃 l.base，base 漏掉字族等于白设');
        expect(l.base.fontFamilyFallback, c.fontFamilyFallback);
      }
    });

    test('LhFontRole.apply 保留原样式的字号与颜色（只换字族）', () {
      const base = TextStyle(fontSize: 19, height: 1.62, color: Color(0xFF3B3630));
      final t = kFontBody.apply(base);
      expect(t.fontSize, 19);
      expect(t.height, 1.62);
      expect(t.color, const Color(0xFF3B3630));
      expect(t.fontFamily, 'Noto Serif SC');
      expect(t.fontFamilyFallback, kFontBody.fallback);
    });
  });

  group('4 · 主题令牌与角色链的覆盖关系（2026-10-03 拍板）', () {
    ThemeData themeWith(Map<String, dynamic> vars) => AppTheme.build(
          ThemeTokens.fromMap('t', vars),
          isDark: false,
        );

    test('未设 --app-font：全局走 UI 无衬线链', () {
      final t = themeWith(const {'--accent': '#6366F1'});
      // ThemeData 的 fontFamily 不单独暴露，它 `apply` 进 textTheme（SDK theme_data.dart:510）
      // → 断言落在具体角色样式上，顺带证明「一切 UI 标签＝无衬线」真的生效。
      expect(t.textTheme.bodyLarge?.fontFamily, 'Inter');
      expect(t.textTheme.bodyLarge?.fontFamilyFallback, kFontUi.fallback);
      expect(t.textTheme.titleLarge?.fontFamily, 'Inter');
      expect(t.textTheme.labelLarge?.fontFamilyFallback, kFontUi.fallback);
    });

    test('设了 --app-font：整档跟随主题（角色链让位）', () {
      final t = themeWith(const {'--app-font': 'Songti SC'});
      expect(t.textTheme.bodyLarge?.fontFamily, 'Songti SC');
      expect(t.textTheme.titleLarge?.fontFamily, 'Songti SC');
      expect(t.textTheme.bodyLarge?.fontFamilyFallback, kFontUi.fallback,
          reason: '主题指定的族名本机取不到时仍有中文兜底，不掉回引擎默认字');
    });
  });

  group('5 · 分页表版本必须升（映射串变了而枚举值没变）', () {
    test('PagStore.tableVersion ≥ 3', () {
      expect(PagStore.tableVersion, greaterThanOrEqualTo(3),
          reason: 'fnt\${font} 进的是枚举值：链换了而枚举没变，旧分页表会继续命中，'
              '真机表现为改字体后页码/偏移与实排不符');
    });
  });
}
