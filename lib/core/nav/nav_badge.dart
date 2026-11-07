import 'package:flutter/material.dart';

/// T11 底栏角标（事实源＝壳原型 `prototype/index.html` 的 `.navbadge`，
/// 批六出样张、2026-10-05 产品过门「照修后版式接」）。
///
/// 三条口径照抄原型，别顺手优化掉：
///  · **进入即清**：`seen` 命中该栏目路径就不显——清的是「已读标记」，不是数据，
///    逾期读数本身不动（原型 `navSeen` 是内存对象，冷启动会重新出现）。
///  · **>99 收敛**成 `99+`：胶囊用 `minWidth`＋横向 padding 撑开，不裁字。
///  · **配色两档都过 WCAG AA 小字 4.5**：亮色 `#E11D48` 压白字＝4.70，
///    深色 `#FB7185` 压深字＝6.63。旧版（亮 `#F43F5E` 白字 3.67、深色白字 2.69）
///    是内置浏览器逐屏量出来的缺陷，改回去会被守护用例判红。
///
/// 数字必须**正体**：原型容器当初写成 `<i>` 标签，被浏览器默认斜体化（3 倍放大才看得见），
/// 这里显式钉 `FontStyle.normal`。
class NavBadge extends StatelessWidget {
  const NavBadge({
    super.key,
    required this.count,
    required this.child,
    this.badgeKey,
  });

  /// 未读数；<=0 时不渲染角标（原样返回 [child]）。
  final int count;

  /// 被挂角标的图元（底栏那一枚图标）。
  final Widget child;

  /// 角标本体的 key（测试与真机走查锚点）。
  final Key? badgeKey;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return child;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          top: -4,
          right: -10,
          child: Container(
            key: badgeKey,
            constraints: const BoxConstraints(minWidth: 15),
            height: 15,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: dark ? const Color(0xFFFB7185) : const Color(0xFFE11D48),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              navBadgeText(count),
              style: TextStyle(
                fontSize: 9,
                height: 1,
                fontStyle: FontStyle.normal,
                fontWeight: FontWeight.w800,
                color: dark ? const Color(0xFF0F172A) : Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 该栏目该显几：进过就清零，没登记数据源的栏目恒为 0。
int navBadgeCount(String path,
        {required Map<String, int> sources, required Set<String> seen}) =>
    seen.contains(path) ? 0 : (sources[path] ?? 0);

/// 超过 99 收敛（与原型 `bn>99?'99+':bn` 一字不差）。
String navBadgeText(int count) => count > 99 ? '99+' : '$count';
