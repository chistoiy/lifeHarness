import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/theme/theme_repository.dart';
import 'package:lifeharness/core/theme/theme_tokens.dart';

void main() {
  // 纯 test() 环境下需初始化测试 binding，rootBundle 才能读取 unit_test_assets。
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CSS 令牌解析', () {
    test('hex 6/3/8 位与 rgba', () {
      expect(ThemeTokens.parseColor('#6366f1'), const Color(0xFF6366F1));
      expect(ThemeTokens.parseColor('#fff'), const Color(0xFFFFFFFF));
      // CSS RRGGBBAA → Flutter AARRGGBB
      expect(ThemeTokens.parseColor('#6366f180'), const Color(0x806366F1));
      expect(ThemeTokens.parseColor('rgba(255,255,255,.85)'),
          const Color(0xD9FFFFFF));
      expect(ThemeTokens.parseColor('transparent'), Colors.transparent);
      expect(ThemeTokens.parseColor('nonsense'), isNull);
    });

    test('长度与多阴影（括号内逗号不切分）', () {
      expect(ThemeTokens.parseLength('20px'), 20);
      final single = ThemeTokens.parseBoxShadow('0 1px 3px rgba(15,23,42,.05)');
      expect(single, hasLength(1));
      expect(single.first.offset, const Offset(0, 1));
      expect(single.first.blurRadius, 3);

      final dual =
          ThemeTokens.parseBoxShadow('8px 8px 18px #c9d2e3,-8px -8px 18px #ffffff');
      expect(dual, hasLength(2));
      expect(dual[1].offset, const Offset(-8, -8));

      final retro = ThemeTokens.parseBoxShadow('3px 3px 0 #e2d3b1');
      expect(retro.single.offset, const Offset(3, 3));
      expect(retro.single.blurRadius, 0);
    });
  });

  group('ThemeRepository 载入 assets/themes', () {
    test('7 套主题全部可用且令牌非默认', () async {
      final registry = await const ThemeRepository().loadAll();
      expect(registry.ids, hasLength(7));
      expect(registry.defaultId, 'minimal');

      final cyber = registry.of('cyber');
      expect(cyber.forceDark, isTrue);
      expect(cyber.dark.accent, const Color(0xFFA855F7));

      final ocean = registry.of('ocean');
      expect(ocean.light.accent, const Color(0xFF0284C7));
      expect(ocean.dark.page, const Color(0xFF082033));

      final autumn = registry.of('autumn');
      expect(autumn.light.appFont, isNotNull);
    });

    test('缺失主题回落默认', () async {
      final registry = await const ThemeRepository().loadAll();
      expect(registry.of('does-not-exist').id, 'minimal');
    });
  });
}
