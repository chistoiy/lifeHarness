import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/router/app_router.dart' show shellBackAction;

/// V1.27 G1 全局返回语义（HomeShell PopScope 决策核心，纯函数守护）。
void main() {
  test('V1.27 G1 shellBackAction 返回语义：栏目页→goToday；今天页 remind/exit 二态', () {
    final t0 = DateTime(2026, 9, 21, 1, 0, 0);
    expect(shellBackAction('/todo', lastBackAt: t0, at: t0), 'goToday');
    expect(shellBackAction('/calendar'), 'goToday');
    expect(shellBackAction('/', lastBackAt: null, at: t0), 'remind');
    expect(
        shellBackAction('/',
            lastBackAt: t0, at: t0.add(const Duration(seconds: 1))),
        'exit');
    // 超 2s 窗口 → 重新提醒而非退出
    expect(
        shellBackAction('/',
            lastBackAt: t0, at: t0.add(const Duration(seconds: 3))),
        'remind');
    // V1.28⑥：主页编排态优先=endEdit（退出编排并保存，不落入提醒/退出判定）
    expect(shellBackAction('/', dashEditing: true, lastBackAt: t0, at: t0),
        'endEdit');
    expect(shellBackAction('/todo', dashEditing: true), 'goToday');
  });
}
