import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../data/ledger_repository.dart';
import '../domain/ledger_calc.dart';
import '../domain/ledger_models.dart';
import 'ledger_date_sheet.dart';
import 'ledger_pick_sheets.dart';
import 'ledger_providers.dart';
import 'widgets/ledger_kit.dart';

/// L11 借出 / 借入（原型 p-debt · TITLES ['借出 · 借入','往来清晰']；renderDebt 全量）。
/// 分段筛选（全部 / 借出·别人欠我 / 借入·我欠别人）→ 汇总双栏卡（借出未收 sky /
/// 借入未还 rose，均按全账本 side 集合 Σleft 计，不随分段变）→ 借贷卡
/// （图标方向色 / person + side·note / 剩余未收·未还 or 已结清 / AMT(total) /
/// 进度条 paid·total[达成 emerald 否则方向色] / 记还款 · 结清[剩余≤0 禁用] · 删）→
/// ＋ 记一笔借出 / 借入。
///
/// 写路径（以原型代码为准）：
/// - 记还款 debtPay(5308~5312)：金额滚轮 → 生成实际流水（source=debt、账户=默认账户
///   `a:L.set.defAcct`）+ paid=min(total,paid+v)；借出收款 income「其他收入」、
///   借入还款 expense「其他支出」；
/// - 结清 debtClose(5313~5316)：openLedgerAcctPick 选账户 → 剩余 left>0 才补一笔
///   实际流水（source=debt）→ paid=total；
/// - 新建 debtAdd(5317~5319)：与 L2 记一笔借贷 tab 同表互认（repo.addDebt）。
/// 本金不落流水、不计入净资产（§10 U-3，FinMetricCtx 总资产/负债口径不动）。
class LedgerDebtPage extends ConsumerStatefulWidget {
  const LedgerDebtPage({super.key});

  @override
  ConsumerState<LedgerDebtPage> createState() => _LedgerDebtPageState();
}

class _LedgerDebtPageState extends ConsumerState<LedgerDebtPage> {
  static const _slate = Color(0xFF94A3B8);
  static const _sky = Color(0xFF0EA5E9); // 借出（别人欠我）
  static const _rose = Color(0xFFFB7185); // 借入（我欠别人）
  static const _emerald = Color(0xFF10B981);

  /// 原型 debtSide（all / lend / borrow）。
  String _side = 'all';

  /// 内嵌新建表单（原型 debtAdd：side / person / total）。
  bool _formOpen = false;
  String _newSide = 'lend';
  final _person = TextEditingController();
  double _amount = 0;

  // T9（交互整改批三）：校验落在字段旁，不再叠提示条；保存钮防重入。
  String? _personErr;
  String? _amtErr;
  bool _saving = false;

  /// 失焦刷新：仅在已亮错时复核当前值（不在用户第一次离开空字段时提前催）。
  late final FocusNode _personFocus = FocusNode()
    ..addListener(() {
      if (_personFocus.hasFocus || _personErr == null || !mounted) return;
      setState(() => _personErr =
          _person.text.trim().isEmpty ? _personErr : null);
    });

  @override
  void dispose() {
    _person.dispose();
    _personFocus.dispose();
    super.dispose();
  }

  LedgerRepository get _repo => ref.read(ledgerRepositoryProvider);

  void _tick() => ref.read(ledgerTickProvider.notifier).state++;

  void _toast(String m) => AppToast.show(context, m);

  void _closeForm() => setState(() {
        _formOpen = false;
        _newSide = 'lend';
        _person.clear();
        _amount = 0;
        _personErr = null;
        _amtErr = null;
      });

  void _openCreate() => setState(() {
        _formOpen = true;
        _newSide = 'lend';
        _person.clear();
        _amount = 0;
        _personErr = null;
        _amtErr = null;
      });

  /// T9：逐字段就地校验（文案与 L2 借贷 tab 同句），返回是否可落库。
  void _validate() {
    _personErr = _person.text.trim().isEmpty ? '请填写对方' : null;
    _amtErr = _amount <= 0 ? '请输入金额' : null;
  }

  /// 原型 debtAdd：side + person + amount（错误落字段旁 · 保存防重入）。
  Future<void> _save(LedgerData d) async {
    if (_saving) return;
    _validate();
    if (_personErr != null || _amtErr != null) {
      setState(() {});
      return;
    }
    setState(() => _saving = true);
    try {
      await _repo.addDebt(
        bk: d.curBook.id,
        side: _newSide,
        person: _person.text.trim(),
        total: _amount,
      );
      _closeForm();
      _tick();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 原型 debtPay：金额滚轮 → 记还款流水 + paid 回写。
  Future<void> _pay(LedgerDebt t) async {
    final v = await showLAmountWheel(context,
        title: '「${t.person}」还款金额', value: 0);
    if (v == null || v <= 0) return;
    final ok = await _repo.payDebt(t.id, v);
    _tick();
    if (ok) _toast('已记还款流水 · 进度更新');
  }

  /// 原型 debtClose：选账户 → 结清流水 + paid=total。
  Future<void> _close(LedgerDebt t) async {
    final acct = await showLAcctPick(context, title: '结清账户');
    if (acct == null) return;
    final ok = await _repo.settleDebt(t.id, accountId: acct);
    _tick();
    if (ok) _toast('已结清');
  }

  Future<void> _del(LedgerDebt t) async {
    await _repo.delDebt(t.id);
    _tick();
  }

  @override
  Widget build(BuildContext context) {
    final dA = ref.watch(ledgerDataProvider);
    final tA = ref.watch(ledgerDebtProvider);
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('借出 · 借入'),
            Text(
              '往来清晰',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.normal,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      body: dA.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (d) => tA.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('加载失败：$e')),
          data: (ts) => _body(d, ts),
        ),
      ),
    );
  }

  Widget _body(LedgerData d, List<LedgerDebt> all) {
    final hide = d.hideAmounts;
    // 汇总恒按全账本 side 集合（原型 lend/bor 不过滤 debtSide）。
    final lend = all.where((t) => t.isLend);
    final bor = all.where((t) => !t.isLend);
    double sumLeft(Iterable<LedgerDebt> xs) =>
        xs.fold<double>(0, (s, t) => s + (t.left > 0 ? t.left : 0));
    final lOut = sumLeft(lend);
    final bIn = sumLeft(bor);
    final f = _side == 'all'
        ? all
        : all.where((t) => (_side == 'lend') == t.isLend).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      children: [
        _segment(),
        const SizedBox(height: 10),
        _sumCard(lOut, bIn, hide),
        const SizedBox(height: 10),
        for (final t in f) _debtCard(d, t),
        if (_formOpen)
          _formCard(d)
        else
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: EmptyDashRow(
                text: '＋ 记一笔借出 / 借入', onTap: _openCreate),
          ),
      ],
    );
  }

  // ---- 分段筛选（原型 seg-on 圆角药丸） ----

  Widget _segment() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          for (final (k, n) in const [
            ('all', '全部'),
            ('lend', '借出 · 别人欠我'),
            ('borrow', '借入 · 我欠别人'),
          ])
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _side = k),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _side == k ? scheme.surface : null,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: _side == k
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: .06),
                              blurRadius: 3,
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    n,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---- 汇总双栏卡 ----

  Widget _sumCard(double lOut, double bIn, bool hide) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: context.cardDecoration,
      child: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                const Text('借出未收',
                    style: TextStyle(fontSize: 10, color: _slate)),
                const SizedBox(height: 2),
                Text(amtText(lOut, hide: hide),
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: _sky)),
              ],
            ),
          ),
          Expanded(
            child: Column(
              children: [
                const Text('借入未还',
                    style: TextStyle(fontSize: 10, color: _slate)),
                const SizedBox(height: 2),
                Text(amtText(bIn, hide: hide),
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: _rose)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---- 借贷卡 ----

  Widget _debtCard(LedgerData d, LedgerDebt t) {
    final lend = t.isLend;
    final accent = lend ? _sky : _rose;
    final pct = t.progressPct;
    final settled = t.settled;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: context.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              LTile(
                iconKey: lend ? 'arrows' : 'scale',
                color: lend ? '#0ea5e9' : '#fb7185',
                size: 34,
                radius: 12,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${t.person} '
                      '${lend ? '借出' : '借入'} · ${t.note}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      settled
                          ? '已结清'
                          : '剩余 ${money(t.left)} 未${lend ? '收' : '还'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 9, color: _slate),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Text(amtText(t.total, hide: d.hideAmounts),
                  style:
                      const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 8),
          _bar(pct / 100, color: settled ? _emerald : accent, height: 6),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _actionBtn(
                  label: lend ? '记还款（收）' : '记还款（还）',
                  bg: scheme.surfaceContainerHighest,
                  onTap: () => _pay(t),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _actionBtn(
                  label: '结清',
                  bg: scheme.surfaceContainerHighest,
                  disabled: settled,
                  onTap: () => _close(t),
                ),
              ),
              const SizedBox(width: 8),
              _actionBtn(
                label: '删',
                bg: scheme.surfaceContainerHighest,
                paddingH: 16,
                onTap: () => _del(t),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---- 内嵌新建表单（原型 debtAdd：side / person / total） ----

  Widget _formCard(LedgerData d) {
    final scheme = Theme.of(context).colorScheme;
    Widget chip(Widget child) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: child,
        );
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(12),
      decoration: context.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('记一笔借出 / 借入',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          // side 方向选择（同 L2 借贷 tab 二段）
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                for (final (k, n) in const [
                  ('lend', '借出 · 别人欠我'),
                  ('borrow', '借入 · 我欠别人'),
                ])
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _newSide = k),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _newSide == k ? scheme.surface : null,
                          borderRadius: BorderRadius.circular(9),
                          boxShadow: _newSide == k
                              ? [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: .06),
                                    blurRadius: 3,
                                  ),
                                ]
                              : null,
                        ),
                        child: Text(n,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: TextField(
                    controller: _person,
                    focusNode: _personFocus,
                    maxLength: 12,
                    style: const TextStyle(fontSize: 12),
                    onChanged: (v) {
                      if (_personErr != null && v.trim().isNotEmpty) {
                        setState(() => _personErr = null);
                      }
                    },
                    decoration: InputDecoration(
                      hintText: '对方',
                      counterText: '',
                      errorText: _personErr,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () async {
                      final v = await showLAmountWheel(context,
                          title: '借贷金额', value: _amount);
                      if (v != null) {
                        setState(() {
                          _amount = v;
                          if (v > 0) _amtErr = null;
                        });
                      }
                    },
                    child: chip(
                      SizedBox(
                        width: 100,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          child: Text(_amount > 0 ? money(_amount) : '金额',
                              style: const TextStyle(fontSize: 12)),
                        ),
                      ),
                    ),
                  ),
                  // 滚轮控件没有失焦语义，错误落在它自己下面一行（LH-K32）。
                  FieldError(_amtErr),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Spacer(),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _closeForm,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text('取消', style: TextStyle(fontSize: 12)),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _save(d),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: context.tokens.gradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text('保存',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---- 局部小件 ----

  Widget _bar(double frac, {required Color color, double height = 6}) {
    final scheme = Theme.of(context).colorScheme;
    final w = frac.clamp(0.0, 1.0);
    return SizedBox(
      height: height,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          if (w > 0)
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: w,
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _actionBtn({
    required String label,
    required Color bg,
    bool disabled = false,
    double paddingH = 0,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final child = Container(
      padding: EdgeInsets.symmetric(
          horizontal: paddingH > 0 ? paddingH : 0, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(9),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: scheme.onSurface),
      ),
    );
    return Opacity(
      opacity: disabled ? .4 : 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: disabled ? null : onTap,
        child: paddingH > 0
            ? child
            : SizedBox(width: double.infinity, child: child),
      ),
    );
  }
}
