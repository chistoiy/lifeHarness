import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../domain/ledger_calc.dart';
import '../domain/ledger_models.dart';
import 'ledger_providers.dart';
import 'widgets/ledger_kit.dart';

/// L6 资产总览（原型 p-assets · TITLES ['资产','净资产 · 账户总览']；renderAssets 全量）。
/// 逐元素顺序：净资产渐变头卡（总资产/总负债/净资产三位 + 金额隐藏眼）→
/// 近 6 月净资产走势（原型 SVG polyline 口径 · CustomPaint）→ 账户卡列表（非归档·
/// id 序·信用卡额度进度条/其余「类型 · 本月 N 笔」·点击进 L7·行内编辑）→
/// ＋ 新建账户（S4 表单）→ 已归档分组（恢复/删除守卫）→ 导入账单入口。
class LedgerAssetsPage extends ConsumerWidget {
  const LedgerAssetsPage({super.key});

  static const _slate = Color(0xFF94A3B8);
  static const _rose = Color(0xFFFB7185);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(ledgerDataProvider);
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('资产'),
            Text(
              '净资产 · 账户总览',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.normal,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (d) => _body(context, ref, d),
      ),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref, LedgerData d) {
    final hide = d.hideAmounts;
    final tokens = context.tokens;
    final act = d.accounts.where((a) => !a.archived).toList();
    final arch =
        ref.watch(ledgerArchivedAccountsProvider).valueOrNull ?? const [];
    final nw = netWorthOf([for (final a in act) a.balanceCache]);
    final trend = ref.watch(ledgerNetWorthTrendProvider).valueOrNull ?? const [];
    final tmin = trend.isEmpty
        ? 0.0
        : trend.map((t) => t.value).reduce(math.min);
    final tmax = trend.isEmpty
        ? 0.0
        : trend.map((t) => t.value).reduce(math.max);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        // 净资产渐变头卡
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
          decoration: BoxDecoration(
            gradient: tokens.gradient,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: tokens.g1.withValues(alpha: .2),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    '净资产',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white70,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => _toggleHide(context, ref, d),
                    child: Icon(
                      LIcons.resolve(hide ? 'eyeoff' : 'eye'),
                      size: 14,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                amtText(nw.net, hide: hide),
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '资产 ${amtText(nw.assets, hide: hide)}',
                    style: const TextStyle(fontSize: 11, color: Colors.white),
                  ),
                  const SizedBox(width: 32),
                  Text(
                    '负债 ${amtText(nw.liab, hide: hide)}',
                    style: const TextStyle(fontSize: 11, color: Colors.white),
                  ),
                ],
              ),
            ],
          ),
        ),
        // 近 6 月净资产走势
        Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: context.cardDecoration,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _cardTitle(context, '近 6 月净资产'),
                  const Spacer(),
                  Text(
                    '${amtText(tmin, hide: hide)} ~ ${amtText(tmax, hide: hide)}',
                    style: const TextStyle(fontSize: 9, color: _slate),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 80,
                width: double.infinity,
                child: CustomPaint(
                  painter: _NetTrendPainter(
                    pts: [for (final t in trend) t.value],
                    accent: tokens.accent,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  for (final t in trend)
                    Expanded(
                      child: Text(
                        t.label,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 9, color: _slate),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        // 账户卡列表
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            children: [
              for (final a in act)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _acctCard(context, ref, d, a),
                ),
            ],
          ),
        ),
        _dashedBtn(
          context,
          label: '＋ 新建账户',
          onTap: () => showLAcctForm(context, ref),
        ),
        // 已归档
        if (arch.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 12),
            clipBehavior: Clip.antiAlias,
            decoration: context.cardDecoration,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    '已归档',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: _slate,
                    ),
                  ),
                ),
                for (final a in arch)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Opacity(
                      opacity: .6,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              a.name,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          _miniBtn(
                            context,
                            label: '恢复',
                            onTap: () async {
                              await ref
                                  .read(ledgerRepositoryProvider)
                                  .setAccountArchived(a.id, false);
                              if (!context.mounted) return;
                              _tick(ref);
                              _toast(context, '已恢复账户');
                            },
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => _del(context, ref, a),
                            child: const Text(
                              '删除',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: _rose,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        // 导入账单入口
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => context.push('/ledger/import'),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F9FF).withValues(
                  alpha: Theme.of(context).brightness == Brightness.dark ? .1 : 1,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              alignment: Alignment.center,
              child: const Text(
                '导入支付宝 / 微信账单 ›',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0EA5E9),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _acctCard(
    BuildContext context,
    WidgetRef ref,
    LedgerData d,
    LedgerAccount a,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final hide = d.hideAmounts;
    final bal = a.balanceCache;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: context.cardDecoration,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/ledger/account/${a.id}'),
        child: Row(
          children: [
            LTile(iconKey: a.icon, color: a.color, size: 40, radius: 16),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (a.isCredit)
                    ...[
                      SizedBox(
                        width: 128,
                        height: 4,
                        child: Container(
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: math
                                .max(
                                  0.02,
                                  (a.creditLimit ?? 0) > 0
                                      ? (a.available / a.creditLimit!).clamp(
                                          0.0,
                                          1.0,
                                        )
                                      : 0.02,
                                )
                                .toDouble(),
                            child: Container(
                              decoration: const BoxDecoration(
                                color: _rose,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '已用 ${money(math.max(0, -bal))} / '
                        '${money(a.creditLimit ?? 0)}',
                        style: const TextStyle(fontSize: 9, color: _slate),
                      ),
                    ]
                  else
                    Text(
                      '${_typeWord(a.type)} · 本月 '
                      '${d.monthTxns.where((t) => t.accountId == a.id || t.toAccountId == a.id).length} 笔',
                      style: const TextStyle(fontSize: 9, color: _slate),
                    ),
                ],
              ),
            ),
            Text(
              amtText(bal, hide: hide),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: bal < 0 ? _rose : scheme.onSurface,
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: '编辑',
              visualDensity: VisualDensity.compact,
              icon: Icon(
                LIcons.resolve('edit'),
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
              onPressed: () => showLAcctForm(context, ref, editing: a),
            ),
          ],
        ),
      ),
    );
  }

  /// 原型 renderAssets 非信用卡副行文案口径：cash→现金 / ewallet→电子钱包 /
  /// debit→储蓄卡 / 其余(invest·other)→理财。
  static String _typeWord(String t) => switch (t) {
    LedgerAccount.kCash => '现金',
    LedgerAccount.kEwallet => '电子钱包',
    LedgerAccount.kDebit => '储蓄卡',
    _ => '理财',
  };

  Future<void> _del(BuildContext context, WidgetRef ref, LedgerAccount a) async {
    final r = await ref.read(ledgerRepositoryProvider).delAccountGuarded(a.id);
    if (!context.mounted) return;
    if (!r.ok) {
      _toast(context, '余额未清零 · 先转账归零再删除');
      return;
    }
    _tick(ref);
    _toast(context, '已删除账户');
  }

  Future<void> _toggleHide(
    BuildContext context,
    WidgetRef ref,
    LedgerData d,
  ) async {
    await ref
        .read(ledgerRepositoryProvider)
        .setHideAmounts(!d.hideAmounts);
    if (!context.mounted) return;
    _tick(ref);
    _toast(context, !d.hideAmounts ? '金额已隐藏' : '金额已显示');
  }

  void _tick(WidgetRef ref) => ref.read(ledgerTickProvider.notifier).state++;

  void _toast(BuildContext context, String m) => AppToast.show(context, m);

  Widget _cardTitle(BuildContext context, String t) => Text(
    t,
    style: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w800,
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .7),
    ),
  );

  Widget _dashedBtn(
    BuildContext context, {
    required String label,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: scheme.outlineVariant,
            width: 2,
            strokeAlign: BorderSide.strokeAlignInside,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: _slate,
          ),
        ),
      ),
    );
  }

  Widget _miniBtn(
    BuildContext context, {
    required String label,
    required VoidCallback onTap,
  }) {
    final tokens = context.tokens;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: tokens.accent.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: tokens.accent,
          ),
        ),
      ),
    );
  }
}

/// 近 6 月净资产折线（原型 SVG polyline + circle 口径：6 点均匀横铺、按
/// min~max 归一，当前点更大）。
class _NetTrendPainter extends CustomPainter {
  _NetTrendPainter({required this.pts, required this.accent});

  final List<double> pts;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    if (pts.isEmpty) return;
    final n = pts.length;
    final tmin = pts.reduce(math.min);
    final tmax = pts.reduce(math.max);
    final pad = 12.0;
    final w = size.width;
    final base = size.height - 10;
    final span = 48.0;
    double px(int i) => n < 2 ? w / 2 : pad + i * (w - 2 * pad) / (n - 1);
    double py(double v) =>
        base - (tmax > tmin ? (v - tmin) / (tmax - tmin) * span : span / 2);
    final line = Path();
    for (var i = 0; i < n; i++) {
      if (i == 0) {
        line.moveTo(px(i), py(pts[i]));
      } else {
        line.lineTo(px(i), py(pts[i]));
      }
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    for (var i = 0; i < n; i++) {
      final cur = i == n - 1;
      canvas.drawCircle(
        Offset(px(i), py(pts[i])),
        cur ? 4 : 2.6,
        Paint()..color = accent,
      );
    }
  }

  @override
  bool shouldRepaint(_NetTrendPainter old) =>
      old.pts != pts || old.accent != accent;
}

// ============ S4 账户新建/编辑弹层（原型 sheetLedgerAcctAdd · openAcctSheet） ============

/// 字段=原型实际字段：类型宫格（6·图标由类型派生）/ 名称 / 余额 / 信用额度·
/// 账单日·还款日（仅信用卡·就地内嵌滚轮）。新建：base=录入余额、color 由类型定；
/// 编辑：改名称/类型/图标，录入余额与当前差额生成 adjust，信用卡回写额度·账期。
Future<void> showLAcctForm(
  BuildContext context,
  WidgetRef ref, {
  LedgerAccount? editing,
}) => showLSheet<void>(
  context,
  _AcctForm(editing: editing),
  heightFactor: .92,
);

class _AcctForm extends ConsumerStatefulWidget {
  const _AcctForm({this.editing});

  final LedgerAccount? editing;

  @override
  ConsumerState<_AcctForm> createState() => _AcctFormState();
}

class _AcctFormState extends ConsumerState<_AcctForm> {
  static const _slate = Color(0xFF94A3B8);

  late String _type = widget.editing?.type ?? LedgerAccount.kDebit;
  late final TextEditingController _name =
      TextEditingController(text: widget.editing?.name ?? '');
  late final TextEditingController _bal = TextEditingController(
    text: widget.editing == null
        ? ''
        : widget.editing!.balanceCache
            .toStringAsFixed(2)
            .replaceAll(RegExp(r'\.00$'), ''),
  );
  late final TextEditingController _limit = TextEditingController(
    text: (widget.editing?.creditLimit ?? 0) > 0
        ? '${widget.editing!.creditLimit!.round()}'
        : '',
  );
  late int _bill = widget.editing?.billDay ?? 1;
  late int _repay = widget.editing?.repayDay ?? 1;

  bool get _isCredit => _type == LedgerAccount.kCredit;

  @override
  void dispose() {
    _name.dispose();
    _bal.dispose();
    _limit.dispose();
    super.dispose();
  }

  String _iconFor(String type) => LedgerAccount.types
      .firstWhere((e) => e.$1 == type, orElse: () => LedgerAccount.types.last)
      .$3;

  Future<void> _save() async {
    final repo = ref.read(ledgerRepositoryProvider);
    final n = _name.text.trim().isNotEmpty
        ? _name.text.trim()
        : LedgerAccount.typeLabel(_type);
    // 禁止重名：撞已有账户名（编辑自身除外）则拦下提示，不做隐式合并。
    final d0 = ref.read(ledgerDataProvider).valueOrNull;
    if (d0 != null &&
        d0.accounts.any((a) => a.name == n && a.id != widget.editing?.id)) {
      AppToast.show(context, '已有同名账户「$n」，请换个名字');
      return;
    }
    final bal = double.tryParse(_bal.text.trim()) ?? 0;
    final enteredLimit = double.tryParse(_limit.text.trim());
    final e = widget.editing;
    String? createdToast;
    if (e != null) {
      final patch = <String, Object?>{
        'name': n,
        'type': _type,
        'icon': _iconFor(_type),
      };
      if (_isCredit) {
        patch['credit_limit'] = (enteredLimit != null && enteredLimit > 0)
            ? enteredLimit
            : (e.creditLimit ?? 20000);
        patch['bill_day'] = _bill;
        patch['repay_day'] = _repay;
      }
      await repo.updateAccount(e.id, patch);
      // 录入余额与当前余额差额 → adjust 流水走统一写路径（原型 acctSheetSave）。
      if ((bal - e.balanceCache).abs() > 0.004) {
        await repo.adjustBalance(e.id, bal);
      }
    } else {
      await repo.addAccount(
        LedgerAccount(
          type: _type,
          name: n,
          base: bal,
          icon: _iconFor(_type),
          color: _isCredit ? '#fb7185' : '#0ea5e9',
          creditLimit: _isCredit
              ? ((enteredLimit != null && enteredLimit > 0)
                    ? enteredLimit
                    : 20000)
              : null,
          billDay: _isCredit ? _bill : null,
          repayDay: _isCredit ? _repay : null,
        ),
      );
      createdToast = '已新建账户「$n」';
    }
    if (!mounted) return;
    ref.read(ledgerTickProvider.notifier).state++;
    if (createdToast != null) AppToast.show(context, createdToast);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LSheetHead(title: widget.editing == null ? '新建账户' : '编辑账户'),
            const SizedBox(height: 8),
            // 类型宫格
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (k, nm, ic) in LedgerAccount.types)
                  SizedBox(
                    width: (MediaQuery.sizeOf(context).width - 40 - 12) / 3,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => setState(() => _type = k),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _type == k
                              ? tokens.accent.withValues(alpha: .08)
                              : scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _type == k ? tokens.accent : scheme.outlineVariant,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              LIcons.resolve(ic),
                              size: 18,
                              color: _type == k
                                  ? tokens.accent
                                  : scheme.onSurfaceVariant,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              nm,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: _type == k
                                    ? tokens.accent
                                    : scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _field(_name, '账户名称', maxLength: 12),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _field(_bal, '余额', numeric: true)),
                const SizedBox(width: 10),
                if (_isCredit)
                  Expanded(child: _field(_limit, '信用额度', numeric: true))
                else
                  const Expanded(child: SizedBox.shrink()),
              ],
            ),
            if (_isCredit) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '账单日',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: _slate,
                          ),
                        ),
                        const SizedBox(height: 4),
                        LInlinePicker(
                          height: 110,
                          labels: [
                            for (var d = 1; d <= 28; d++) '账单日 $d 号',
                          ],
                          initialIndex: math.max(0, math.min(27, _bill - 1)),
                          onSelect: (i) => setState(() => _bill = i + 1),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '还款日',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: _slate,
                          ),
                        ),
                        const SizedBox(height: 4),
                        LInlinePicker(
                          height: 110,
                          labels: [
                            for (var d = 1; d <= 28; d++) '还款日 $d 号',
                          ],
                          initialIndex: math.max(0, math.min(27, _repay - 1)),
                          onSelect: (i) => setState(() => _repay = i + 1),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 48,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: tokens.gradient,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: TextButton(
                        onPressed: _save,
                        child: const Text(
                          '保存',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController ctl,
    String hint, {
    bool numeric = false,
    int? maxLength,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: TextField(
        controller: ctl,
        keyboardType: numeric
            ? const TextInputType.numberWithOptions(decimal: true, signed: true)
            : null,
        maxLength: maxLength,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: hint,
          counterText: '',
          border: InputBorder.none,
        ),
      ),
    );
  }
}
