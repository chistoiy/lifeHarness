import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/features/mindmap/presentation/mindmap_canvas_page.dart';

/// 思维导图批P5 · 气泡落位**纯几何**守护（不泵页面，直接喂委托）。
///
/// 为什么单开一个文件：让位那几档的屏幕坐标会被视口留白与四边夹取抹平，
/// 「按几何反推走了哪一档」很容易写出两边恒等的假用例（本批真踩过）。这里
/// 直接把节点矩形、气泡尺寸、子级净空喂给落位委托，读它算出的结果。
///
/// 纵向树的真实约束（决定了哪些档能靠真实布局触发）：
/// 行高 40 + 纵向间距 14 = 54，气泡高 36 ⇒ 正居中时下沿落在节点上沿 +38，
/// 本来就比第一个子级上沿（+54）低 16dp。所以「不许压子级」这条天花板
/// **只有在节点被撑成两行以上（行高 > 54）时才起作用**。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 跑一次落位：`node`＝节点矩形，`child`＝气泡尺寸（宽按真实两枚按钮估）。
  (Offset, String) place({
    required Rect node,
    double? childTop,
    Size child = const Size(168, 36),
    Size canvas = const Size(800, 544),
  }) {
    final p = debugBubbleDelegate(
      nodeLeft: node.left,
      nodeTop: node.top,
      nodeW: node.width,
      nodeH: node.height,
      gap: 10,
      inset: 10,
      ceiling: childTop == null ? null : childTop - node.top,
      canvas: canvas,
      childSize: child,
    );
    return (p.position, p.tier);
  }
  test('首选：节点上下都宽敞时贴在上沿外侧，水平对齐节点中心', () {
    final node = Rect.fromLTWH(300, 200, 120, 40);
    final (pos, tier) = place(node: node);
    expect(tier, 'top');
    expect(pos.dy + 36, lessThan(node.top), reason: '整块在节点上沿之外');
    expect(node.top - (pos.dy + 36), 10,
        reason: '净距＝gap（10dp），贴着但不粘');
    expect(pos.dx + 168 / 2, closeTo(node.center.dx, .01),
        reason: '整块水平居中于节点');
  });

  test('贴顶：上方放不下 → 让到节点右侧（第二档）', () {
    // nodeTop 12：节点自己还在 inset(10) 之内，但上方只剩 12dp、塞不下 36dp 气泡。
    final node = Rect.fromLTWH(300, 12, 120, 40);
    final (pos, tier) = place(node: node);
    expect(tier, 'right');
    expect(pos.dx, node.right + 10, reason: '右侧净距 gap');
    expect(pos.dy, closeTo(node.center.dy - 18, .01), reason: '纵向与节点居中');
  });

  test('贴顶且右侧也没位置 → 让到左侧（第三档）', () {
    // 节点离右边只剩 5dp：右侧塞不下 168dp 的气泡，只能去左边。
    final node = Rect.fromLTWH(715, 12, 80, 40);
    final (pos, tier) = place(node: node);
    expect(tier, 'left');
    expect(pos.dx + 168, closeTo(node.left - 10, .01), reason: '左侧净距 gap');
  });

  test('左右都放不下 → 才压到节点下方（第四档，最后手段）', () {
    // 画布窄到放不下两倍气泡宽：左右都塞不进，只能往下压。
    final node = Rect.fromLTWH(100, 12, 100, 40);
    final (pos, tier) =
        place(node: node, canvas: const Size(200, 544));
    expect(tier, 'below');
    expect(pos.dy, node.bottom + 10, reason: '压在下方时净距也是 gap');
  });

  test('不让位时天花板不参与：节点够宽敞就正居中，子级怎么近都不管', () {
    final node = Rect.fromLTWH(300, 200, 120, 40);
    final (pos, tier) =
        place(node: node, childTop: node.bottom + 2);
    expect(tier, 'top');
    expect(pos.dy + 36, lessThan(node.top));
  });

  test('让位时天花板生效：下沿不许越过第一个子级的上沿', () {
    // 多行节点（高 80）+ 子级离得很近（上沿只在下 60dp 处）＝正居中会压到子级。
    // 这正是纵向树里「长标题/多行」才会撞上的那格。
    final node = Rect.fromLTWH(300, 12, 120, 80);
    final kidTop = node.top + 60;
    final (pos, tier) = place(node: node, childTop: kidTop);
    expect(tier, 'right', reason: '上方放不下 → 侧面');
    expect(pos.dy + 36, lessThanOrEqualTo(kidTop + .01),
        reason: '气泡下沿收在子级上沿之上');
  });

  test('子级上沿太近（收不下一个气泡）→ 落回「压下方」，不在侧面横跨子级', () {
    final node = Rect.fromLTWH(300, 12, 120, 80);
    final kidTop = node.top + 30; // 30 < 气泡高 36，侧面怎么收都会越界
    final (pos, tier) = place(node: node, childTop: kidTop);
    expect(tier, 'below', reason: '收不下就别在侧面横跨子级');
    expect(pos.dy, node.bottom + 10);
  });

  test('没有可见子级时正居中（ceiling 为 null）', () {
    final node = Rect.fromLTWH(300, 12, 120, 80);
    final (pos, tier) = place(node: node);
    expect(tier, 'right');
    expect(pos.dy, closeTo(node.center.dy - 18, .01),
        reason: '没有子级要躲，就老老实实与节点居中');
  });

  test('四边一律夹在画布内 10dp（贴左沿的节点）', () {
    final node = Rect.fromLTWH(2, 200, 60, 40);
    final (pos, _) = place(node: node);
    expect(pos.dx, greaterThanOrEqualTo(10), reason: '左边夹到 inset');
    expect(pos.dx + 168, lessThanOrEqualTo(800 - 10), reason: '右边不越界');
  });
}
