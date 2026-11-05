import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lifeharness/features/ledger/domain/ledger_calc.dart';

/// 金额隐藏泄漏守护（2026-11-05 · 查漏补缺第三批）。
///
/// 需求口径：金额隐藏开关打开时，**展示真实数据金额**的位置一律走 amtText。
/// 本批对齐 14 行 / 15 次调用；toast、输入态、通知文案、刻度、导入预览
/// 不属展示位，仍可用 money（勿把这些也一并改成隐藏，会破坏录入体验）。
/// 变异刀靶点＝把任一展示位改回 money(...)，本文件必须报红。
const _guarded = <String, List<String>>{
  'ledger_page.dart': [
    'money(st.exp - b.total)',
    'money(b.total)',
  ],
  'ledger_tx_detail_page.dart': [
    'money(rel.amt)',
    'money(refunds.fold<double>(0, (a, x) => a + x.amt))',
  ],
  'ledger_budget_page.dart': [
    'money(exp - b.total)',
    r'立即结转 +${money(carryAmt)}',
    'money(lim)',
    'money(used - lim)',
  ],
  'ledger_debt_page.dart': ['money(t.left)'],
  'ledger_wish_page.dart': ['money(w.target)'],
  'ledger_account_detail_page.dart': [
    'money(a.creditLimit ?? 0)',
    'money((a.creditLimit ?? 0) + bal)',
  ],
  'ledger_assets_page.dart': [
    'money(math.max(0, -bal))',
    r"'${money(a.creditLimit ?? 0)}'",
  ],
  'ledger_pick_sheets.dart': ['money(a.available)'],
};

String _read(String name) => File(
        'lib/features/ledger/presentation/$name')
    .readAsStringSync();

void main() {
  test('amtText 隐藏档不泄漏真实金额（正向契约）', () {
    expect(amtText(12345.67, hide: true), '¥•••••');
    expect(amtText(12345.67), money(12345.67));
    expect(signedAmt(-88, hide: true), '-¥•••••');
  });

  test('14 行展示位不再绕过金额隐藏开关', () {
    for (final entry in _guarded.entries) {
      final src = _read(entry.key);
      for (final bad in entry.value) {
        expect(src.contains(bad), isFalse,
            reason: '${entry.key} 的展示位仍在直出 $bad，隐藏开关会泄漏真实金额');
      }
    }
  });

  test('展示位改走 amtText 且传入当前作用域的 hide 值', () {
    expect(_read('ledger_page.dart')
        .contains('amtText(st.exp - b.total, hide: d.hideAmounts)'), isTrue);
    expect(_read('ledger_assets_page.dart')
        .contains('amtText(math.max(0, -bal), hide: hide)'), isTrue);
    expect(_read('ledger_budget_page.dart')
        .contains('amtText(used - lim, hide: hide)'), isTrue);
    expect(_read('ledger_wish_page.dart')
        .contains('amtText(w.target, hide: d.hideAmounts)'), isTrue);
  });
}
