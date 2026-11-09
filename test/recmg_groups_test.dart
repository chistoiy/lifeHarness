import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/providers.dart';
import 'package:lifeharness/features/settings/presentation/recmg_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

/// F5-3（轮5③·原型已过门）·「记录管理 › 通用 · 回收站自动清理」整组撤出本页。
///
/// 档位入口挪到回收站屏右上角图标钮（用例见 `test/trash_page_test.dart` 的 F5-3 三条），
/// 本文件只钉**减法不越界**：四组标题仍在、档位行与其文案不再出现、
/// 且不得留「删了入口忘了读数来源」的暗坑（期限仍由 `lh.trash_keep_days` 唯一驱动）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'lh.trash_keep_days': 90});
    prefs = await SharedPreferences.getInstance();
  });

  Widget app() => ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const MaterialApp(home: RecmgSettingsPage()),
      );

  testWidgets('四组标题在册，「通用」组与档位行整块撤出', (tester) async {
    await tester.pumpWidget(app());
    await settle5(tester);
    // 列表懒构建：默认 600 高视口装不下末组，先垫高再逐组断言（不是没渲染≠不存在）
    await useSurface(tester);
    await settle5(tester);
    for (final label in ['日记', '笔记', '阅读', '影音游']) {
      expect(find.text(label), findsOneWidget, reason: '缺组：$label');
    }
    expect(find.text('通用'), findsNothing);
    expect(find.text('回收站自动清理'), findsNothing);
    expect(find.byKey(const ValueKey('trash-days')), findsNothing);
    expect(
        find.textContaining('删除的内容统一进回收站，按此期限自动彻底删除'),
        findsNothing,
        reason: '说明行随组一起撤，不留无主文案');
  });

  testWidgets('拖到底也不出现档位入口（不是懒构建没滚到）', (tester) async {
    await tester.pumpWidget(app());
    await settle5(tester);
    for (var i = 0; i < 8; i++) {
      await tester.drag(find.byType(ListView).last, const Offset(0, -260));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('回收站自动清理'), findsNothing);
    expect(find.text('影音游'), findsWidgets, reason: '已滚到末组，断言不是没渲染');
  });
}
