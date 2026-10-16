> 状态：**活（结论件·已否决引入）** ｜ 类型：第三方能力评估 ｜ 日期：2026-10-05 ｜ 会话：「开工」批二＋6067 判定同轮
> 触发：产品问「图标能否换成 flutter_morphing_icons，能否自行切换状态」。

# flutter_morphing_icons 评估结论（2026-10-05 · 否决引入）

## 1 · 结论一句话

**不引入。** 该包不做真正的图标形变（内部只是 `AnimatedSwitcher` 的淡入/缩放/旋转/平移四预设），而我们全仓图标是 Material **字体字形**、没有轮廓路径数据，形变的前置条件本就不成立；想要「两态切换有过渡」用框架自带的 `AnimatedSwitcher` 即可，零新依赖。

## 2 · 实测依据（源码级，非读 README）

拉包解档核对（`pub.dev/api/archives/flutter_morphing_icons-0.2.0.tar.gz`）：

- 体量＝`lib/` 4 文件 **637 行**；`grep` 全库 **零** `Path` / `CustomPaint` / `dart:ui` / `clipPath` —— 无任何路径插值实现。
- 动画实现＝`AnimatedSwitcher` ＋ `FadeTransition` / `Tween<Offset>` / 旋转角度 `Tween`（`lib/src/morphing_icon.dart` 181–340 行区间）。
- 元数据＝0.2.0 · 2025-11-09 发布，约 11 个月未更新；单人维护（带 sponsor 链接）；无第三方依赖；约束 `sdk >=3.8.0` / `flutter >=3.32.0`（本工程 3.38.9 兼容，**接入门槛不是问题**，问题在能力对不上）。
- README 自称 "smooth icon morphing"，与实际实现不符——按 memory「外部 AI/包方案须逐条识别再采纳」，以读到的源码为准。

## 3 · 「能否自行切换状态」＝能，但要点明口径

- `MorphingIcon(states: [...])` / `MorphingIcon.icons(icons: [IconData...])` 有 `didUpdateWidget`（117 行），**外部把业务状态映射成索引传进去即可驱动**，改变时播一次过渡动画。
- 另有 `MorphingIconController`（`next/previous/goTo/toggle/goToFirst/goToLast`）与回调 `onStateChanged` / `onAnimationComplete`。
- 坑：`autoAnimate` 默认 **true** 且支持自动轮播——那是演示行为，接业务必须关掉，状态一律由数据（是否打卡/是否收藏）驱动，不许控制器自转。

## 4 · 与本仓图标体系的冲突点（这才是真正的墙）

- 全仓 `Icons.*` **608 处**（Material 字体字形）＋习惯侧 `HIcons.resolve` 字符串映射（`features/habit/presentation/widgets/habit_kit.dart`），**也是字形**。
- 仓库**无 `flutter_svg` 依赖**（`pubspec.yaml` 实测），SVG 只存在于原型 HTML；字形没有可用的轮廓 path，故「真形变」在这套体系下无从插值。
- 结论：换包≠换能力；要形变得先动图标体系（608 处字形＋包体＋原型同源），属专项而非一次依赖引入。

## 5 · 若日后确实要「图标活起来」

按代价从低到高三档，**任何一档动手前都要先改原型并经产品确认**（AGENTS UI 条）：

| 目标 | 做法 | 代价 | 状态 |
|---|---|---|---|
| 点了必须有反应 | 批二落地的 `Pressable`（按下微缩，Listener 不进手势竞技场） | 已完成 | 已交付（`8d034f5`） |
| 两态切换有过渡 | 框架自带 `AnimatedSwitcher`（等价于该包效果） | 数行，零依赖 | 待产品点头选点 |
| 真·形变（勾选长出对勾等） | 目标图标改 path 来源：`vector_graphics_compiler` 把原型 SVG 编成 `Path`，或手写少量 path，再自研顶点插值 | 先动图标体系＝专项 | 建议先做单控件可行性验证（习惯打卡钮一枚），不铺全量 |

## 6 · 关联

- 交互整改批二落地记录＝`docs/handoff/交互整改开发计划-20261003.md` 文末「批二落地记录（2026-10-05）」。
- 6067 真机判定＝`docs/archive/交棒话术-20261004-备份管理与图片预览批.md` §10。
- 评估纪律出处（跨项目）：外部方案须「已实现/吸收/否决」三段对照，以读到的源码而非宣传词定论。
