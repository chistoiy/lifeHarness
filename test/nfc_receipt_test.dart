import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/shared/widgets/nfc_receipt.dart';

/// 贴卡回执分流判定（批3d · 2026-10-17 真机报障）。
///
/// 背景：批3c 起贴卡走透明中转界面，App 界面全程不出现；此时 Flutter 内的
/// SnackBar 挂在没人看的 widget 树上——真机表现就是「贴完只震动，什么也没有」。
/// 故回执必须按「App 在不在前台」分流到系统横幅。
void main() {
  group('贴卡回执分流（nfcReceiptNeedsBanner）', () {
    test('前台且 host 可用 ⇒ 走应用内 toast，不发横幅', () {
      expect(nfcReceiptNeedsBanner(inApp: true, hostUsable: true), isFalse);
    });

    test('前台但 host 不可用（首帧前/界面已销毁）⇒ 必须发横幅', () {
      expect(nfcReceiptNeedsBanner(inApp: true, hostUsable: false), isTrue);
    });

    test('后台但 host 看似可用（透明中转路径）⇒ 必须发横幅', () {
      // 这正是真机 8166 的坑：widget 树活着、ctx.mounted 为真，但没人看得见。
      expect(nfcReceiptNeedsBanner(inApp: false, hostUsable: true), isTrue);
    });

    test('后台且 host 不可用 ⇒ 必须发横幅', () {
      expect(nfcReceiptNeedsBanner(inApp: false, hostUsable: false), isTrue);
    });
  });
}
