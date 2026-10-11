import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/nav/nav_collapse.dart';

/// V1.65 双指判定纯函数守护（不含 widget，秒级）。
///
/// **方向口径（产品 2026-10-11 裁定）**：轮4 原始需求「双指放大＝底栏消失、
/// 双指捏合＝底栏回来」——即比值 >1.15（两指张开）＝收起底栏，<0.87（捏合）＝还原。
/// 原型样张文案当时写反（写成「捏合收起」），已随本批回改，此闸钉住正确方向。
void main() {
  group('navPinchAction 双指比值判定', () {
    test('张开（比值 >1.15）＝收起底栏', () {
      expect(navPinchAction(1.16), NavPinchAction.hide);
      expect(navPinchAction(1.5), NavPinchAction.hide);
      expect(navPinchAction(3.0), NavPinchAction.hide);
    });

    test('捏合（比值 <0.87）＝还原底栏', () {
      expect(navPinchAction(0.86), NavPinchAction.show);
      expect(navPinchAction(0.5), NavPinchAction.show);
      expect(navPinchAction(0.0), NavPinchAction.show);
    });

    test('中间带与阈值上不动（含正好等于阈值的边界）', () {
      expect(navPinchAction(1.0), NavPinchAction.none);
      expect(navPinchAction(1.15), NavPinchAction.none); // 等于不算张开
      expect(navPinchAction(0.87), NavPinchAction.none); // 等于不算捏合
      expect(navPinchAction(1.149), NavPinchAction.none);
      expect(navPinchAction(0.871), NavPinchAction.none);
    });
  });
}
