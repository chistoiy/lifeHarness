import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/journal_entry.dart';
import 'journal_layout_kit.dart';

/// 日记改版批1a · 月历图墙（7 列格，只为「哪天写过」服务）；批1c 起支持**翻月**。
///
/// 三态次序**不可对调**（工单 §2 硬口径 3）：无日记＝只有数字 ＞ 有日记无图＝淡色圆底＋深字
/// ＞ 有日记有图＝淡色圆底＋深字＋右上角小方块。图墙**不做图片浏览、不做点击进图**——
/// 点格只做一件事：看当天（当天多篇给选择弹层）。
///
/// 批2e 按原型 `dwRenderWall` 重做观感（原实现是「每格描边＋高饱和实心＋白字」，
/// 真机上一屏 31 个描边方块＝噪点源，与原型差得最远）：
/// - 空白格**去边框**，只留淡数字（原型注释原话：虚线网格是主要噪点来源）；
/// - 有日记格改**圆形淡底＋深字**（`journalAccentStep` 派生，四主题跟随）；
/// - 说明文案**移出卡片**（放在日历内部既挤占空间、颜色又偏重）；
/// - 选中日＝主色光晕，不填色。
///
/// 翻月口径（原型 `dwMonthStep`）：只往**过去**翻，范围 `[本月-24, 本月]`；不给未来月——
/// 未来的日子不可能有日记，翻过去只会看到一整屏空格，白费一次点击。
class JournalWall extends StatefulWidget {
  const JournalWall({
    super.key,
    required this.month,
    required this.byDayFirst,
    required this.onTapDay,
    this.onMonthStep,
    this.minMonthOffset = -kWallMaxMonthBack,
    this.showCaption = true,
  });

  /// 展示的月份。
  final DateTime month;

  /// 当日首篇（同日多篇取最新一篇来判「有没有图」，与列表卡头同源）。
  final Map<int, JournalEntry> byDayFirst;
  final void Function(int day) onTapDay;

  /// 翻月回调：`-1` 上一月、`+1` 下一月。为 null 时不显示翻月钮（1a 旧调用点保持原样）。
  final void Function(int delta)? onMonthStep;

  /// 允许往前翻的最多个月数（负数）。默认 −24 与原型一致。
  final int minMonthOffset;

  /// 是否自带说明行（原型把它放在卡片**外**）。嵌在别处的调用点可关掉。
  final bool showCaption;

  @override
  State<JournalWall> createState() => _JournalWallState();
}

class _JournalWallState extends State<JournalWall> {
  /// 选中日（当月日号，null＝未选）。原型 `dwWallSel` 同口径：点过之后留一圈光晕，
  /// 让用户知道「刚看的是哪一天」——不是填色（填色会与「有日记」的淡底混淆）。
  int? _selDay;

  @override
  void didUpdateWidget(covariant JournalWall old) {
    super.didUpdateWidget(old);
    // 翻月后日号含义变了，选中态必须清掉，否则「3 号」的光晕会跟到下个月。
    if (old.month.year != widget.month.year ||
        old.month.month != widget.month.month) {
      _selDay = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final month = widget.month;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final lead = DateTime(month.year, month.month, 1).weekday - 1;
    final total = wallCellCount(month);
    return Column(
      key: const ValueKey('diary-wall'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 原型 `rounded-2xl card p-3`：日历自带卡片底（说明行在卡片**外**，见类注释）。
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: tokens.card,
            borderRadius: BorderRadius.circular(tokens.cardRadius),
            border: Border.all(color: tokens.cardBorder),
            boxShadow: tokens.cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 月份标题 + 翻月钮（批1c）。原型 `dwRenderWall` 同构：标题吃满左边、两枚钮在右。
              // 「下一月」在当月置灰：不能翻到未来（见类注释）。
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        // 原型：`${y}年${m}月 · 图墙`——后缀不是装饰，
                        // 三档切换时它告诉用户「这块是日历不是列表」。
                        '${month.year}年${month.month}月 · 图墙',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (widget.onMonthStep != null) ...[
                      _WallNavBtn(
                        key: const ValueKey('wall-prev'),
                        icon: Icons.chevron_left,
                        label: '上一月',
                        onTap: () => widget.onMonthStep!(-1),
                      ),
                      _WallNavBtn(
                        key: const ValueKey('wall-next'),
                        icon: Icons.chevron_right,
                        label: '下一月',
                        // 只在「还没到本月」时可点：未来月份不可能有日记，翻过去只会看到一屏空格。
                        enabled: !_isThisMonth(month),
                        onTap: () => widget.onMonthStep!(1),
                      ),
                    ],
                  ],
                ),
              ),
              // 星期表头（周一开头，与日期块「周一」同源）。原型 9px。
              Row(
                children: [
                  for (final w in const ['一', '二', '三', '四', '五', '六', '日'])
                    Expanded(
                      child: Center(
                        child: Text(
                          w,
                          style: TextStyle(
                              fontSize: 9,
                              color: scheme.onSurfaceVariant
                                  .withValues(alpha: .8)),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              for (var r = 0; r < total ~/ 7; r++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      for (var c = 0; c < 7; c++)
                        Expanded(
                          child: () {
                            final idx = r * 7 + c;
                            final day = idx - lead + 1;
                            if (idx < lead || day > daysInMonth) {
                              return const SizedBox(height: 34);
                            }
                            final e = widget.byDayFirst[day];
                            final state = wallCellStateOf(e);
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 2),
                              child: _WallCell(
                                key: ValueKey('wall-day-$day'),
                                day: day,
                                state: state,
                                mood: e?.mood,
                                selected: _selDay == day,
                                onTap: () {
                                  setState(() => _selDay = day);
                                  widget.onTapDay(day);
                                },
                              ),
                            );
                          }(),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (widget.showCaption)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              // 原型文案：说明的是**底色深浅**，不是「实心」——观感改回淡底后旧文案已不成立。
              '底色越深，当日情绪越低落 · 点格看当天',
              style: TextStyle(
                  fontSize: 10,
                  color: scheme.onSurfaceVariant.withValues(alpha: .75)),
            ),
          ),
      ],
    );
  }
}

class _WallCell extends StatelessWidget {
  const _WallCell({
    super.key,
    required this.day,
    required this.state,
    required this.onTap,
    this.mood,
    this.selected = false,
  });

  final int day;
  final WallCellState state;
  final VoidCallback onTap;

  /// 当日首篇的心情（1~7，null＝没记）。
  final int? mood;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final written = state != WallCellState.empty;
    final dark =
        ThemeData.estimateBrightnessForColor(tokens.page) == Brightness.dark;
    final depth = journalMoodDepth(mood);
    // 有日记：淡底 = 主色阶（越负面越深）；深字 = 同族加深（深色档反过来提亮）。
    final tint = !written
        ? null
        : depth == null
            // 没记心情＝中性灰（原型 `#8a94a6` 口径），**不与「无日记」混同**：
            // 无日记那格压根没有底色。
            ? Color.lerp(tokens.card, tokens.text2, dark ? .26 : .16)
            : journalAccentStep(tokens, .16 + .58 * depth);
    final ink = !written
        ? null
        : depth == null
            ? tokens.text2
            : (dark
                ? Color.lerp(tokens.accent, Colors.white, .55)!
                : Color.lerp(tokens.accent, tokens.text1, .55)!);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 34,
        decoration: BoxDecoration(
          // 原型 `rounded-full`：34 高、宽约 34~40 ⇒ 视觉是圆/胶囊，不是圆角方块。
          borderRadius: BorderRadius.circular(999),
          color: tint,
          boxShadow: selected
              ? [
                  // 原型 `.dw-wall-on`：`0 0 0 2px accent-42, 0 0 10px accent-28`。
                  BoxShadow(
                      color: tokens.accent.withValues(alpha: .42),
                      spreadRadius: 2),
                  BoxShadow(
                      color: tokens.accent.withValues(alpha: .28),
                      blurRadius: 10),
                ]
              : null,
        ),
        child: Stack(
          children: [
            Center(
              child: Text(
                '$day',
                style: TextStyle(
                  // 原型 12px：旧实现 11 在白字/淡底上都偏小。
                  fontSize: 12,
                  fontWeight: written ? FontWeight.w700 : FontWeight.w500,
                  color: written
                      ? ink
                      : scheme.onSurfaceVariant.withValues(alpha: .55),
                ),
              ),
            ),
            if (state == WallCellState.writtenWithImage)
              Positioned(
                top: 3,
                right: 3,
                // 原型是 7px 的 `▣` 字形。这里换成等大实心小方：字形在部分安卓机型上
                // 会落到 fallback 字体、行高把位置顶歪（同仓「emoji/符号别当图形用」的教训）。
                child: Container(
                  key: ValueKey('wall-img-dot-$day'),
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: (ink ?? scheme.onSurfaceVariant)
                        .withValues(alpha: .55),
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 当前是否为「本月」（决定「下一月」是否可点）。
bool _isThisMonth(DateTime m) {
  final now = DateTime.now();
  return m.year == now.year && m.month == now.month;
}

/// 图墙最多往前翻几个月（原型 `dwMonthStep` 的 `-24` 下界）。
const int kWallMaxMonthBack = 24;

/// 翻月钮：24×24 触摸面，图标 18（48dp 触控是列表级规范，图墙标题行放不下）。
class _WallNavBtn extends StatelessWidget {
  const _WallNavBtn({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: InkResponse(
        onTap: enabled ? onTap : null,
        radius: 18,
        child: SizedBox(
          width: 28,
          height: 28,
          child: Icon(
            icon,
            size: 18,
            color: scheme.onSurfaceVariant.withValues(alpha: enabled ? .9 : .3),
          ),
        ),
      ),
    );
  }
}
