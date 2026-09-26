import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/logging/app_log.dart';

void main() {
  setUp(AppLog.reset);

  test('环形缓冲上限300，丢最旧', () {
    for (var i = 0; i < 350; i++) {
      AppLog.add('line$i');
    }
    expect(AppLog.lines.length, 300);
    expect(AppLog.lines.first.text, 'line50');
    expect(AppLog.lines.last.text, 'line349');
  });

  test('formatted 含毫秒时间戳、级别与来源段', () {
    AppLog.add('boom', level: LhLevel.error);
    final f = AppLog.lines.single.formatted;
    // V1.43.2 起行式多一段来源（调用帧自动归类；本调用来自测试文件 → 系统）。
    expect(
        RegExp(r'^\d{2}:\d{2}:\d{2}\.\d{3} \[E\] \[[^\]]+\] boom$').hasMatch(f),
        isTrue);
    expect(f, endsWith('[系统] boom'));
  });

  test('reportError 防递归：重入直接吞掉', () {
    AppLog.onReport = (l) => AppLog.reportError('re-enter'); // 模拟记录时再触发
    AppLog.reportError('first');
    expect(AppLog.lines.any((l) => l.text == 'first'), isTrue); // 不栈溢出、不死循环
    AppLog.onReport = null;
  });

  test('reportError 500ms 内合并限频', () {
    AppLog.reportError('a');
    AppLog.reportError('b');
    expect(AppLog.lines.where((l) => l.text == 'b').length, 0);
  });

  test('堆栈截断：前14行压单行', () {
    final st = List.generate(40, (i) => '#$i frame').join('\n');
    AppLog.addStack(st);
    final t = AppLog.lines.last.text;
    expect(t.split(' | ').length, 14);
    expect(t, isNot(contains('\n')));
  });

  test('allText 全量300行，displayWindow 只给120', () {
    for (var i = 0; i < 300; i++) {
      AppLog.add('l$i');
    }
    expect(AppLog.allText().split('\n').length, 300);
    expect(AppLog.windowText(1000).split('\n').length, AppLog.displayWindow);
  });
}
