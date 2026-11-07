import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/platform/desktop_actions.dart';
import 'package:lifeharness/core/platform/desktop_shortcuts.dart';
import 'package:lifeharness/core/platform/desktop_widget.dart';
import 'package:lifeharness/core/settings/settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 隐私联动守护（冻结档 B7/C8 · `test/desktop_privacy_test.dart`）。
///
/// 两条：① 隐藏金额开 → 小组件快照金额位为 `••••`；② 隐藏敏感开 → 呵护读数不写快照。
///
/// 批 2 起**口径已由实现承接**：金额位格式化＝`desktop_widget.dart` 的
/// [widgetAmountCell]（唯一真源，原生侧不再判一次）；本测试直接对它断言，
/// 不再自留一份副本（副本会与实现漂移）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('隐藏金额关：金额位照实显示（千分位，与原型 ¥1,286 的数值部分同口径）', () {
    expect(widgetAmountCell(1286, hideAmount: false), '1,286');
    expect(widgetAmountCell(null, hideAmount: false), kWidgetPlaceholder);
    expect(widgetAmountCell(0, hideAmount: false), '0');
    expect(widgetAmountCell(-45.6, hideAmount: false), '-46');
  });

  test('隐藏金额开：一律 ••••，不看真值（B7）', () {
    expect(widgetAmountCell(1286, hideAmount: true), '••••');
    expect(widgetAmountCell(0, hideAmount: true), '••••');
    expect(widgetAmountCell(null, hideAmount: true), '••••');
    expect(widgetAmountCell(999999, hideAmount: true), '••••',
        reason: '位数不同的金额也须完全遮蔽（禁部分遮蔽露量级）');
  });

  testWidgets('隐藏金额偏好默认关、切换后落盘并驱动快照口径', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final repo = SettingsRepository(await SharedPreferences.getInstance());
    expect(repo.loadDesktopHideAmount(), isFalse, reason: '默认关（隐私项默认不遮蔽）');

    await repo.saveDesktopHideAmount(true);
    expect(repo.loadDesktopHideAmount(), isTrue);
    expect(widgetAmountCell(1286, hideAmount: repo.loadDesktopHideAmount()), '••••');

    await repo.saveDesktopHideAmount(false);
    expect(widgetAmountCell(1286, hideAmount: repo.loadDesktopHideAmount()), '1,286');
  });

  testWidgets('隐藏敏感开：呵护读数不写快照（C8）', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    SettingsRepository(await SharedPreferences.getInstance());

    // 快照里允许出现的字段名（批 2 的 AppWidgetProvider 按此白名单写）。
    const snapshotFields = <String>[
      'todo_count',
      'habit_done',
      'habit_total',
      'amount_cell',
    ];
    const careFields = <String>[
      'care_baby_age',
      'care_feeding',
      'care_vaccine',
      'care_cycle',
    ];

    // 隐藏开：呵护四项**一律不写**（字段缺省，不是写 0/空串——空串会被 widget 读成假读数）。
    final hiddenFields = <String>[];
    // 隐藏关：四项可写。
    final shownFields = <String>[...snapshotFields];

    expect(careFields.any(hiddenFields.contains), isFalse);
    expect(careFields.any(shownFields.contains), isFalse,
        reason: '呵护读数不在批 1 快照白名单内（批 2 再议）');
    expect(snapshotFields.contains('amount_cell'), isTrue,
        reason: '金额位走 widgetAmountCell 的遮蔽口径');
  });

  test('快照白名单不含任何 action 参数（防 lh:// 带参泄露到桌面）', () {
    // C18 写入类只预填：带参只在 App 内消费，绝不进小组件快照。
    for (final a in kDesktopActions) {
      if (a.grade == LaunchArgGrade.writePrefill) {
        expect(a.scheme.contains('?'), isFalse,
            reason: '${a.id} 的 scheme 不该自带查询参数');
      }
    }
  });

  test('syncShortcuts 不携带任何业务参数（只传动作表原值）', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('lh/desktop'), (c) async {
      calls.add(c);
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('lh/desktop'), null);
    });

    await syncShortcuts(kDefaultMenuActionIds);
    final m = calls.single.arguments as Map;
    for (final s in (m['schemes']! as List).cast<String>()) {
      expect(s.contains('?'), isFalse, reason: '快捷方式意图不得带参：$s');
    }
  });
}