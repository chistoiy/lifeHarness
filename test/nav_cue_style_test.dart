import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/nav/nav_collapse.dart';
import 'package:lifeharness/core/settings/user_settings.dart';

/// 2026-10-18 产品令 · **收起后可见线索扩成三道**：
/// 「双指放大隐藏底部工具栏后，可以不显示箭头或短线，此时行为是双指缩小恢复底部工具栏，
/// 相当于在设置中三个选项，箭头，线，双指缩小」。
///
/// 本组钉四件事：
/// ① 三档的收敛口径（'a' / 'b' / 'none'，脏值回落 'a'，不越界出第四档）；
/// ② 落盘/读盘往返（`toMap`/`fromMap` 与控制器写盘同口径）；
/// ③ **'none' 不是「撤掉按钮」**——壳层命中的语义与击区必须仍在（否则总开关关着时锁死）；
/// ④ 设置页确实给了三档 + 预览框对 'none' 有说明（不是一片空白）。
void main() {
  group('navCueStyleOf：三档收敛', () {
    test('三个合法档原样通过', () {
      expect(navCueStyleOf('a'), 'a');
      expect(navCueStyleOf('b'), 'b');
      expect(navCueStyleOf('none'), 'none');
    });

    test('脏值一律回落 a（V1.65 默认档，界面不出现第四档）', () {
      for (final bad in ['', 'c', 'NONE', 'null', 'none ']) {
        expect(navCueStyleOf(bad), 'a', reason: '脏值「$bad」必须回落默认档');
      }
    });

    test('fromMap 与控制器走同一口径（禁两处各写一份白名单）', () {
      expect(UserSettings.fromMap({'navLineStyle': 'none'}).navLineStyle, 'none');
      expect(UserSettings.fromMap({'navLineStyle': 'b'}).navLineStyle, 'b');
      expect(UserSettings.fromMap({'navLineStyle': 'zzz'}).navLineStyle, 'a');
      expect(UserSettings.fromMap({}).navLineStyle, 'a',
          reason: '没存过＝老用户＝默认细握把');
    });

    test("'none' 能落盘再读回（toMap/fromMap 往返不丢档）", () {
      final s = UserSettings.fromMap({'navLineStyle': 'none'});
      final back = UserSettings.fromMap(s.toMap());
      expect(back.navLineStyle, 'none',
          reason: '往返丢档会让用户每次重启都退回细握把');
    });
  });

  group("'none' 档不许把还原按钮一起撤掉", () {
    final r = File('lib/core/router/app_router.dart').readAsStringSync();

    test('图形只画成透明，命中区与语义仍在', () {
      // 关键判据：'none' 走 Opacity(0)，不是 shrink / 整块不画。
      expect(r, contains("opacity: style == 'none' ? 0 : 1"),
          reason: "'none' 只能隐形——图形撤了命中区连带没了，收起态就回不来");
      // 只查线索组件自己那段，且**先剥注释**（注释里写着「不是 shrink」会自指红）。
      final iHint = r.indexOf('class _NavLineHint');
      expect(iHint, greaterThan(0));
      final hintBody = r
          .substring(iHint)
          .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
          .replaceAll(RegExp(r'//.*'), '');
      expect(hintBody.contains('SizedBox.shrink()'), isFalse,
          reason: '线索段里出现 shrink 会让命中区一起消失');
      expect(r, contains("label: '显示底部导航栏'"),
          reason: '语义必须留住（读屏用户与自动化都靠它还原）');
      expect(r, contains('shell-nav-line-tap'));
    });
  });

  group('设置页三档与预览', () {
    final s =
        File('lib/features/settings/presentation/settings_page.dart')
            .readAsStringSync();

    test('分段控件列了三档（细握把 / 胶囊折角 / 不显示）', () {
      expect(s, contains("(id: 'none', label: '不显示')"),
          reason: '产品要的三个选项：箭头、线、双指缩小');
      expect(s, contains("(id: 'a', label: '细握把')"));
      expect(s, contains("(id: 'b', label: '胶囊折角')"));
    });

    test("预览框对 'none' 有说明文案（不是一片空白）", () {
      expect(s, contains('nav-line-prev-none'));
      expect(s, contains('双指捏合还原底栏'));
    });
  });
}
