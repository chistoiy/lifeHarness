import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/features/ledger/domain/merchant_suggest.dart';

void main() {
  group('C03 商户名归一化', () {
    test('空格/括号/尾号归一到同一键', () {
      expect(normalizeMerchant('星巴克(南京西路店)'), '星巴克');
      expect(normalizeMerchant(' 星巴克 001 '), '星巴克');
      expect(normalizeMerchant('星巴克（旗舰）'), '星巴克');
      expect(normalizeMerchant('星巴克-消费'), '星巴克');
    });
  });

  group('C03 规则学习', () {
    test('出现 ≥2 次且分类一致才采纳', () {
      final rules = learnMerchantRules([
        const MerchantSample('星巴克(店A)', 12),
        const MerchantSample('星巴克 002', 12),
        const MerchantSample('楼下咖啡馆', 13),
      ]);
      expect(rules['星巴克'], 12);
      expect(rules.containsKey('楼下咖啡馆'), isFalse,
          reason: '只出现一次的不得固化成规则');
      expect(suggestCategory('星巴克 003', rules), 12);
      expect(suggestCategory('没见过的小店', rules), isNull);
    });

    test('分类冲突并列第一 → 不猜', () {
      final rules = learnMerchantRules([
        const MerchantSample('便利店', 12),
        const MerchantSample('便利店', 13),
      ]);
      expect(rules.containsKey('便利店'), isFalse);
    });

    test('空商户名与无分类样本被跳过', () {
      final rules = learnMerchantRules([
        const MerchantSample('   ', 12),
        const MerchantSample('无名', null),
        const MerchantSample('有分类', 7),
        const MerchantSample('有分类', 7),
      ]);
      expect(rules, {'有分类': 7});
    });
  });
}
