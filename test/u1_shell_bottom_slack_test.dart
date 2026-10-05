import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/app.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/core/router/app_router.dart' show shellBottomSlack;
import 'package:lifeharness/core/theme/theme_repository.dart';
import 'package:lifeharness/shared/linkage/timer_bar_overlay.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

/// U1（UX 审计真机批）壳内底部余量＝原型 `.safe-pb` 口径的机器闸。
///
/// 现象（真机 ea028260 铁证）：「我的」页滚到底，「外观」行**文字区**（y2370/2400）
/// 点不动、行下部（y2430/2450）才生效；中部行（运行日志 y1145）始终可点，同一条上滑
/// 一格也立刻可点——末行贴着视口下沿停住时，命中区与语义标签错位。
/// 整改＝壳层 body 统一垫 `shellBottomSlack`（原型 96 减掉 Scaffold 已预留的 70dp 底栏），
/// 一处改覆盖全部壳内屏。本用例钉几何：页面可视区下沿必须停在底栏上沿之上 ≥26dp。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('壳内页面可视区停在底栏上方 shellBottomSlack（贴底行不再压视口下沿）',
      (tester) async {
    // 刻意**不**收窄视口：测试字体把每个字形画成 1em 方块，390dp 下「¥ 0.00」这类
    // 短金额会被放大到横向溢出 15px（真机 Inter/Noto 下正常），跟着假象改布局就错了。
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final registry = await const ThemeRepository().loadAll();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        themeRegistryProvider.overrideWithValue(registry),
      ],
      child: const LifeHarnessApp(),
    ));
    await settle5(tester);

    // 底栏高度（原型 nav 70px，测试环境无系统安全区 inset）；
    // 底栏 Container 还带 1px 上描边（`Border(top: BorderSide(navBorder))`），
    // 所以可视区下沿实测＝屏高−70−1−余量，容差按 1.5 收在描边上。
    const navH = 70.0;
    const h = 600.0; // 默认测试视口高
    final pageRect = tester.getRect(find.byType(TimerBarOverlay));
    expect(
      pageRect.bottom,
      closeTo(h - navH - shellBottomSlack, 1.5),
      reason: '壳内可视区下沿应＝屏高−底栏−余量；垫高被摘掉就会顶到 '
          '${h - navH}（＝贴底行压视口下沿的原始形态）。',
    );
    // 余量本身不许被顺手改成 0（改了上面那条也红，这里给一句直白的归属）
    expect(shellBottomSlack, 26, reason: '口径＝原型 .safe-pb 96 − 底栏 70');
    await drainLogTimer(tester);
  });
}
