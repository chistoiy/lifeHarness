import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/ledger_calc.dart';
import '../../domain/ledger_txn.dart';
import '../ledger_providers.dart';

/// 记账模块视觉基元（原型 index-ledger.html LIC 线性图标 / .fin-ico / .fin-row /
/// .tag-chip / .chip / .func-b / .kp 键盘 / sheet-panel）。

/// LIC 键 → Material 线性图标（UI 禁 emoji 既定约定；同 HIcons 先例）。
abstract final class LIcons {
  static const _empty = Icons.circle_outlined;
  static IconData resolve(String k) => switch (k) {
    'food' => Icons.restaurant_outlined,
    'car' => Icons.directions_car_outlined,
    'bag' => Icons.shopping_bag_outlined,
    'home' => Icons.home_outlined,
    'film' => Icons.movie_outlined,
    'run' => Icons.directions_run_outlined,
    'book' => Icons.menu_book_outlined,
    'heart' => Icons.favorite_outline,
    'plane' => Icons.flight_takeoff_outlined,
    'gift' => Icons.card_giftcard_outlined,
    'phone' => Icons.smartphone_outlined,
    'paw' => Icons.pets_outlined,
    'repeat' => Icons.repeat_outlined,
    'dots' => Icons.more_horiz,
    'wallet' => Icons.account_balance_wallet_outlined,
    'star' => Icons.star_outline,
    'laptop' => Icons.laptop_outlined,
    'chart' => Icons.insights_outlined,
    'receipt' => Icons.receipt_long_outlined,
    'redpack' => Icons.card_giftcard_outlined,
    'cup' => Icons.local_cafe_outlined,
    'switch' => Icons.swap_horiz_outlined,
    'eye' => Icons.visibility_outlined,
    'eyeoff' => Icons.visibility_off_outlined,
    'target' => Icons.adjust_outlined,
    'pie' => Icons.pie_chart_outline,
    'bars' => Icons.bar_chart_outlined,
    'cal' => Icons.calendar_today_outlined,
    'grid2' => Icons.grid_view_outlined,
    'card' => Icons.credit_card_outlined,
    'cardplus' => Icons.add_card_outlined,
    'chat' => Icons.chat_bubble_outline,
    'arrows' => Icons.swap_horiz_outlined,
    'scale' => Icons.balance_outlined,
    'down' => Icons.expand_more,
    'plus' => Icons.add,
    'trash' => Icons.delete_outline,
    'edit' => Icons.edit_outlined,
    'copy' => Icons.copy_outlined,
    'tag' => Icons.local_offer_outlined,
    'back' => Icons.chevron_left,
    'search' => Icons.search,
    'gear' => Icons.settings_outlined,
    'dl' => Icons.download_outlined,
    'link' => Icons.link_outlined,
    'undo' => Icons.undo_outlined,
    'bell' => Icons.notifications_none,
    'check' => Icons.check,
    'close' => Icons.close,
    'up' => Icons.arrow_upward,
    _ => _empty,
  };
}

/// hex 字符串 → Color（原型 `${c}1a` 半透明底同法）。
Color lColor(String hex, {double alpha = 1}) {
  var s = hex.replaceFirst('#', '');
  if (s.length == 6) {
    final a = (alpha * 255).round().toRadixString(16).padLeft(2, '0');
    s = '$a$s';
  }
  return Color(int.parse(s, radix: 16));
}

/// 底部半屏（原型 .sheet-panel；heightFactor 对应各弹层固定高度口径）。
Future<T?> showLSheet<T>(
  BuildContext context,
  Widget child, {
  double? heightFactor,
}) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height *
            (heightFactor ?? .92),
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetCtx).bottom,
        ),
        child: SafeArea(top: false, child: child),
      ),
    );

/// .fin-ico 分类/账户图标瓦（色底 alpha≈10% + 主色线性图标）。
class LTile extends StatelessWidget {
  const LTile({
    super.key,
    required this.iconKey,
    required this.color,
    this.size = 34,
    this.radius = 12,
    this.iconSize,
  });

  final String iconKey;
  final String color;
  final double size;
  final double radius;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    final c = lColor(color);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(radius),
      ),
      alignment: Alignment.center,
      child: Icon(
        LIcons.resolve(iconKey),
        size: iconSize ?? size * .53,
        color: c,
      ),
    );
  }
}

/// 来源徽标（§4 徽标：周期/账单导入/物品 L12/阅读 L4/借贷）。
class LSourceBadge extends StatelessWidget {
  const LSourceBadge(this.source, {super.key});

  final String source;

  static const _map = {
    LedgerTxn.kSourceRecurring: ('周期', Color(0xFF14B8A6)),
    LedgerTxn.kSourceBill: ('账单导入', Color(0xFF0EA5E9)),
    LedgerTxn.kSourceItem: ('物品 L12', Color(0xFF6366F1)),
    LedgerTxn.kSourceRead: ('阅读 L4', Color(0xFFF59E0B)),
    LedgerTxn.kSourceWish: ('心愿', Color(0xFFF59E0B)),
    LedgerTxn.kSourceDebt: ('借贷', Color(0xFFFB7185)),
  };

  @override
  Widget build(BuildContext context) {
    final e = _map[source];
    if (e == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: e.$2.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        e.$1,
        style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: e.$2),
      ),
    );
  }
}

/// 流水行（原型 txRow：图标+备注/类目行+账户+徽标+标签 | 金额带符号色）。
class LTxRow extends ConsumerWidget {
  const LTxRow({super.key, required this.txn, this.onTap, this.showDateHeader});

  final LedgerTxn txn;
  final VoidCallback? onTap;

  /// 预留：批2 搜索结果行同款（不带头）。
  final bool? showDateHeader;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(ledgerDataProvider).valueOrNull;
    final scheme = Theme.of(context).colorScheme;
    final t = txn;
    final kind = t.kind;
    final cat = kind == LedgerTxn.kTransfer
        ? (name: '转账', icon: 'switch', color: '#64748b')
        : kind == LedgerTxn.kRefund
        ? (name: '退款', icon: 'undo', color: '#10b981')
        : kind == LedgerTxn.kAdjust
        ? (name: '余额调整', icon: 'scale', color: '#94a3b8')
        : (d?.catOf(t.catId) ??
              (name: '其他', icon: 'dots', color: '#94a3b8'));
    final pre = kind == LedgerTxn.kExpense
        ? '−'
        : (kind == LedgerTxn.kIncome || kind == LedgerTxn.kRefund)
        ? '+'
        : kind == LedgerTxn.kAdjust
        ? (t.amt < 0 ? '−' : '+')
        : '';
    final acct = kind == LedgerTxn.kTransfer
        ? '${d?.acct(t.accountId)?.name ?? '?'} → ${d?.acct(t.toAccountId)?.name ?? '?'}'
        : d?.acct(t.accountId)?.name ?? '';
    final amtColor = kind == LedgerTxn.kIncome || kind == LedgerTxn.kRefund
        ? const Color(0xFF10B981)
        : kind == LedgerTxn.kTransfer
        ? scheme.onSurfaceVariant
        : scheme.onSurface;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          children: [
            LTile(iconKey: cat.icon, color: cat.color, size: 32, radius: 11),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.note.isNotEmpty ? t.note : cat.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 1),
                  Row(
                    children: [
                      if (t.catId != null &&
                          kind != LedgerTxn.kTransfer &&
                          kind != LedgerTxn.kAdjust)
                        Text(
                          cat.name + (t.sub.isNotEmpty ? ' · ${t.sub}' : ''),
                          style: TextStyle(
                              fontSize: 9, color: scheme.onSurfaceVariant),
                        ),
                      if (acct.isNotEmpty) ...[
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            acct,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 9,
                                color: scheme.onSurfaceVariant
                                    .withValues(alpha: .7)),
                          ),
                        ),
                      ],
                      const SizedBox(width: 4),
                      LSourceBadge(t.source),
                      if (t.unpaid) ...[
                        const SizedBox(width: 4),
                        const Text('未付款',
                            style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFF59E0B))),
                      ],
                      if (t.nb) ...[
                        const SizedBox(width: 4),
                        Text('不计入',
                            style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.w700,
                                color: scheme.onSurfaceVariant)),
                      ],
                      if (t.tags.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            t.tags.map((x) => '#$x').join(' '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 8, color: Color(0xFF94A3B8)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$pre${amtText(t.amt, hide: d?.hideAmounts ?? false)}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: amtColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// .tag-chip（记一笔子分类 chips / 指标选择 chip；on=accent 实底）。
class LChip extends StatelessWidget {
  const LChip({
    super.key,
    required this.label,
    this.on = false,
    this.onTap,
    this.small = false,
  });

  final String label;
  final bool on;
  final VoidCallback? onTap;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: small ? 8 : 10, vertical: small ? 3 : 5),
        decoration: BoxDecoration(
          color: on ? context.tokens.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: on ? context.tokens.accent : scheme.outlineVariant,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: small ? 10 : 11,
            fontWeight: FontWeight.w700,
            color: on ? Colors.white : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// .func-b 功能格（hero 内五宫格与 L3 四操作共用；fg 可覆盖文字/图标色）。
class LFuncBtn extends StatelessWidget {
  const LFuncBtn({
    super.key,
    required this.iconKey,
    required this.label,
    this.onTap,
    this.fg = Colors.white,
    this.mini = false,
    this.disabled = false,
  });

  final String iconKey;
  final String label;
  final VoidCallback? onTap;
  final Color fg;
  final bool mini;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: disabled ? .35 : 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(mini ? 12 : 16),
        onTap: disabled ? null : onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: mini ? 6 : 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LIcons.resolve(iconKey), size: mini ? 18 : 20, color: fg),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: mini ? 10 : 10.5,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 弹层通用头部（grabber + 标题行 + 右槽）。
class LSheetHead extends StatelessWidget {
  const LSheetHead({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ],
    );
  }
}
