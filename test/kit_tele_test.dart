import 'package:flutter_test/flutter_test.dart';

import 'package:lifeharness/features/kits/domain/kit_tele.dart';

/// V1.47 批3d · 提词器域层（参数区间/步长/回卷/扫描线口径）。
void main() {
  group('1 · 参数与文案', () {
    test('空库回落原型默认值', () {
      final s = KitTeleState.decode({});
      expect(
        (s.dir, s.speed, s.size, s.lh, s.fg, s.bg, s.led, s.text),
        (kKitTeleDirLand, 60, 40, 155, '#ffffff', '#000000', false, ''),
      );
      expect(s.horizontal, isTrue);
      expect(s.lineHeightFactor, closeTo(1.55, 1e-9));
    });

    test('脏值按区间与步长归位', () {
      final s = KitTeleState.decode({
        'tpOri': 'port',
        'tpSpeed': 67, // 步长 5 → 65
        'tpSize': 500, // 上限 96
        'tpLh': 119, // 步长 5 → 120
        'tpFg': 'red', // 非法色串 → 默认
        'tpBg': '#0A1B2C', // 合法 → 小写
        'tpLed': true,
        'tpText': '稿',
      });
      expect(
        (s.dir, s.speed, s.size, s.lh, s.fg, s.bg, s.led, s.text),
        (kKitTeleDirPort, 65, 96, 120, '#ffffff', '#0a1b2c', true, '稿'),
      );
      expect(s.horizontal, isFalse);
    });

    test('编解码 round-trip · copyWith 只改传入项', () {
      final s = KitTeleState.decode(kitTeleEncode(
        KitTeleState.decode({}).copyWith(speed: 120, text: '开场'),
      ));
      expect((s.speed, s.text), (120, '开场'));
      expect((s.dir, s.size, s.lh), (kKitTeleDirLand, 40, 155));
    });

    test('chip 与提示文案同原型', () {
      expect(kitTeleDirLabel(kKitTeleDirLand), '横向（手机横过来）');
      expect(kitTeleDirToast(kKitTeleDirLand), contains('内容转 90°'));
      expect(kitTeleDirToast(kKitTeleDirPort), '显示方向：竖向滚动');
      expect(kitTeleSpeedText(60), '60 px/s');
      expect(kitTeleSizeText(40), '40 px');
      expect(kitTeleLhText(155), '155%');
      expect(kitTeleLedNote(true), contains('扫描线'));
      expect(kitTeleLedToast(false), 'LED 已关 · 普通文字模式');
    });
  });

  group('2 · 滚动与 LED 几何', () {
    test('单帧推进按 px/s 且 dt 上限 80ms', () {
      expect(kitTeleAdvance(pxPerSec: 60, dtMs: 500), closeTo(4.8, 1e-9));
      expect(kitTeleAdvance(pxPerSec: 100, dtMs: 16), closeTo(1.6, 1e-9));
      expect(kitTeleAdvance(pxPerSec: 300, dtMs: 1000), closeTo(24, 1e-9));
    });

    test('越尾回卷到视口上方 · 未越尾原样', () {
      expect(
        kitTeleWrap(y: 900, bodyHeight: 800, viewportHeight: 600),
        closeTo(-560, 1e-9),
      );
      expect(kitTeleWrap(y: 840, bodyHeight: 800, viewportHeight: 600), 840);
      expect(kitTeleWrap(y: 100, bodyHeight: 800, viewportHeight: 600), 100);
    });

    test('扫描线按 3.6s 周期归一', () {
      expect(kitTeleScanFraction(0), 0);
      expect(kitTeleScanFraction(1800), closeTo(.5, 1e-9));
      expect(kitTeleScanFraction(3600), 0);
      expect(kitTeleScanFraction(4500), closeTo(.25, 1e-9));
    });

    test('颗粒半径 = 间距 30%（原型 radial 30% 实心）', () {
      expect(kitTeleDotRadius(), closeTo(1.8, 1e-9));
      expect(kitTeleDotRadius(cell: 10), closeTo(3, 1e-9));
    });
  });

  group('3 · 讲稿', () {
    test('演示稿六段 · 空行分隔', () {
      final t = kitTeleDemoScript();
      expect(t.split('\n\n').length, 6);
      expect(t, startsWith('各位好，欢迎参加本次产品复盘。'));
      expect(t, contains('工具应该让人更自由'));
    });

    test('笔记导入未接线时给明确口径', () {
      expect(kKitTeleNotePending, contains('笔记选择器待接入'));
    });
  });
}
