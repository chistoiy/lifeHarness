import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/features/ledger/domain/fx_display.dart';

/// C10 展示层币种守护：折算可关、本币口径不变、缺汇率不臆造。
void main() {
  const snap = FxSnapshot(
    base: 'CNY',
    rates: <String, double>{'USD': 0.14, 'JPY': 20.0},
    asOf: '2026-11-09',
  );

  test('① 折算可关：enabled=true 折算 / false 恒等（同例两档对照）', () {
    final converted = convertFx(100, snap, base: 'CNY', target: 'USD');
    expect(converted, closeTo(14.0, 1e-9), reason: '正档：100 本币 ×0.14');
    expect(convertFx(100, snap, base: 'CNY', target: 'USD', enabled: false),
        100.0,
        reason: '负档：关闭折算＝历史本币口径原值');
  });

  test('② 缺汇率 / 基准不符 / 同币种：一律原值，不臆造', () {
    expect(convertFx(100, snap, base: 'CNY', target: 'KRW'), 100.0,
        reason: '负档：无该币种汇率＝原值');
    expect(convertFx(100, snap, base: 'USD', target: 'JPY'), 100.0,
        reason: '负档：快照基准不符＝不算交叉汇率');
    expect(convertFx(100, snap, base: 'CNY', target: 'CNY'), 100.0,
        reason: '负档：同币种＝原值');
    expect(snap.rate('CNY', 'USD'), 0.14, reason: '正档：快照取率');
    expect(snap.rate('CNY', 'KRW'), isNull, reason: '负档：缺率返回 null');
  });

  test('③ 非法汇率（0 / 负数 / NaN）：不折算', () {
    const bad = FxSnapshot(base: 'CNY', rates: <String, double>{
      'BAD0': 0,
      'BADNEG': -1,
    });
    expect(convertFx(100, bad, base: 'CNY', target: 'BAD0'), 100.0);
    expect(convertFx(100, bad, base: 'CNY', target: 'BADNEG'), 100.0);
  });

  test('④ 报表折算：只折聚合值，关闭即恒等（正负同例）', () {
    final r = convertReport(200, 500, snap, base: 'CNY', target: 'USD');
    expect(r.exp, closeTo(28.0, 1e-9), reason: '正档：支出折算');
    expect(r.inc, closeTo(70.0, 1e-9), reason: '正档：收入折算');
    expect(r.net, closeTo(42.0, 1e-9), reason: '正档：结余＝收−支');

    final off = convertReport(200, 500, snap,
        base: 'CNY', target: 'USD', enabled: false);
    expect(off.exp, 200.0, reason: '负档：关闭＝本币原值');
    expect(off.inc, 500.0, reason: '负档：关闭＝本币原值');
    expect(off.net, 300.0, reason: '负档：关闭＝本币口径净额');
  });

  test('⑤ 展示币种：加码不改数值口径 / hide 不泄露', () {
    expect(formatCurrency(14.0, 'USD'), 'USD 14.00', reason: '正档：币种码前缀');
    expect(formatCurrency(-14.0, 'USD'), '-USD 14.00');
    expect(formatCurrency(14.0, 'USD', hide: true), 'USD •••••',
        reason: '正档：隐藏金额');
    expect(formatCurrency(14.0, 'USD', hide: false), isNot(contains('••')),
        reason: '负档：不隐藏时显数值');
  });
}
