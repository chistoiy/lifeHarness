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
        'tpSize': 500, // 上限 160（图2 那类铺屏大字）
        'tpLh': 119, // 步长 5 → 120
        'tpFg': 'red', // 非法色串 → 默认
        'tpBg': '#0A1B2C', // 合法 → 小写
        'tpLed': true,
        'tpText': '稿',
      });
      expect(
        (s.dir, s.speed, s.size, s.lh, s.fg, s.bg, s.led, s.text),
        (kKitTeleDirPort, 65, 160, 120, '#ffffff', '#0a1b2c', true, '稿'),
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
      expect(kitTeleDirLabel(kKitTeleDirLand), '横屏');
      expect(kitTeleDirToast(kKitTeleDirLand), contains('内容转 90°'));
      expect(kitTeleDirToast(kKitTeleDirPort), '显示方向：竖屏');
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

  group('4 · 反馈轮4 效果组（静止/多彩/闪烁/加粗/抖动）', () {
    test('空库默认=滚动 + 纯色背景 + 三效果全关（提词器优先）', () {
      final s = KitTeleState.decode({});
      expect((s.mode, s.grad, s.blink, s.bold, s.shake),
          (kKitTeleModeScroll, 'none', false, false, 0));
      expect(s.isStatic, isFalse);
      expect(s.gradOn, isFalse);
      expect(s.gradColors, isEmpty);
    });

    test('多彩档位表与原型 TP_GRADS 同源 · 脏值回落纯色', () {
      expect(kKitTeleGrads.map((g) => g.id),
          ['none', 'candy', 'dusk', 'mint', 'sea', 'grape']);
      expect(kitTeleGrad('nope').id, 'none');
      expect(kitTeleGrad('candy').label, '糖果');
      expect(kitTeleGrad('candy').colors.length, 2);
      expect(kitTeleGradNext('grape'), 'none');
    });

    test('效果位编解码 round-trip（键名同原型 KITS.tp*）', () {
      final src = KitTeleState.decode({}).copyWith(
        mode: kKitTeleModeStatic,
        grad: 'sea',
        blink: true,
        bold: true,
        shake: 5,
      );
      final j = kitTeleEncode(src);
      expect(j.keys.toList(),
          containsAll(['tpMode', 'tpGrad', 'tpBlink', 'tpBold', 'tpShake']));
      final back = KitTeleState.decode(j);
      expect((back.mode, back.grad, back.blink, back.bold, back.shake),
          (kKitTeleModeStatic, 'sea', true, true, 5));
      expect(back.gradOn, isTrue);
    });

    test('抖动幅度落区间 · 脏值归位（0~8px）', () {
      expect(KitTeleState.decode({'tpShake': 99}).shake, kKitTeleShakeMax);
      expect(KitTeleState.decode({'tpShake': -3}).shake, 0);
      expect(kitTeleShakeText(4), '4 px');
    });

    test('闪烁前半亮、后半暗（原型 steps(1) 两帧）', () {
      expect(kitTeleBlinkOpacity(0), 1);
      expect(kitTeleBlinkOpacity(.49), 1);
      expect(kitTeleBlinkOpacity(.5), kKitTeleBlinkDim);
      expect(kitTeleBlinkOpacity(.99), kKitTeleBlinkDim);
    });

    test('抖动四角关键帧 · px=0 恒为原点', () {
      expect(kitTeleShakeOffset(phase: 0, px: 3), (0.0, 0.0));
      expect(kitTeleShakeOffset(phase: .3, px: 3), (-3.0, 3.0));
      expect(kitTeleShakeOffset(phase: .6, px: 3), (3.0, -3.0));
      expect(kitTeleShakeOffset(phase: .9, px: 3), (-3.0, -3.0));
      expect(kitTeleShakeOffset(phase: .6, px: 0), (0.0, 0.0));
    });

    test('静止态居中位移：内容矮于视口才下移，超高贴顶', () {
      expect(kitTeleStaticTranslateY(bodyHeight: 100, viewportHeight: 500), 200);
      expect(kitTeleStaticTranslateY(bodyHeight: 900, viewportHeight: 500), 0);
    });

    test('方式与背景 toast 同原型文案', () {
      expect(kitTeleModeToast(kKitTeleModeStatic), '显示方式：静止铺屏');
      expect(kitTeleModeToast(kKitTeleModeScroll), '显示方式：向上滚动');
      expect(kitTeleGradToast('mint'), '背景：薄荷');
      expect(kitTeleFxLabel('blink'), '闪烁');
      expect(kitTeleFxLabel('led'), 'LED 点阵');
    });
  });
}
