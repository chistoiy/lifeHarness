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

  // V1.42 真机反馈①：模块被设进底栏后，其主页与今天页同语义（提醒→退出）。
  test('inNav=true：底栏栏目页首次 remind、2s 内二次 exit；底栏外仍 goToday', () {
    final t0 = DateTime(2026, 9, 26, 1, 0, 0);
    expect(shellBackAction('/items', inNav: true, lastBackAt: null, at: t0),
        'remind');
    expect(
        shellBackAction('/days',
            inNav: true, lastBackAt: t0, at: t0.add(const Duration(seconds: 1))),
        'exit');
    expect(shellBackAction('/goals', inNav: true, dashEditing: true), 'endEdit');
    expect(shellBackAction('/care', inNav: false, lastBackAt: t0, at: t0),
        'goToday');
  });

  // V1.46 真机反馈⑥：从主页(go)进入的模块页，返回先回主页——含被设进底栏的
  // 栏目（待办/设置等）；只有底栏点进的（enteredFromToday=false）才二次退出。
  test('enteredFromToday：底栏内栏目从主页进入也 goToday；底栏点进仍 remind/exit',
      () {
    final t0 = DateTime(2026, 9, 27, 3, 0, 0);
    expect(
        shellBackAction('/todo',
            inNav: true, enteredFromToday: true, lastBackAt: t0, at: t0),
        'goToday');
    expect(
        shellBackAction('/settings',
            inNav: true, enteredFromToday: true, lastBackAt: t0, at: t0),
        'goToday');
    // 底栏点进（非主页来路）保持栏目语义。
    expect(
        shellBackAction('/todo',
            inNav: true, enteredFromToday: false, lastBackAt: null, at: t0),
        'remind');
    // 今天页自身不受 enteredFromToday 影响。
    expect(
        shellBackAction('/',
            inNav: true, enteredFromToday: true, lastBackAt: null, at: t0),
        'remind');
  });
}
