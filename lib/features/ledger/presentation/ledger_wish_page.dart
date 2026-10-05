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

/// L10 心愿单（原型 p-wish · TITLES ['心愿单','为想要的攒一攒']；renderWish 全量）。
/// 心愿进度头卡（Σ已存 / Σ目标 + 渐变条）→ 未实现心愿卡（星标图标 / 名称 /
/// 目标 money + 达成态「 · 已达成，可兑换」 / 进度条 saved·percent /
/// 存入 · 取出 · 兑换记账 三钮[兑换 saved≥target 才可用，否则禁用 opacity.4]）→
/// ＋ 新建心愿 → 已实现分组（✓ + 名称 + doneDate）。
///
/// 写路径（以原型代码为准）：
/// - 存入/取出仅记进度、**不落流水**（§10 U-2 · repo.bumpWishSaved，wishSave/wishTake 5273~5274）；
/// - 兑换走 openLedgerAcctPick → 统一 addTxn 生成 expense（source=wish、归类购物、
///   金额=target、账户=所选）并回写 done/done_date/done_txn 且 saved 归零
///   （wishRedeem 5277~5279 · repo.redeemWish）。
/// 新建/编辑为本批按交付物内嵌表单（原型 prompt 采集名称/目标，Flutter 改文本框 +
/// 金额滚轮；编辑为规格扩展，逐字保留原型新建字段与顺序）。
class LedgerWishPage extends ConsumerStatefulWidget {
  const LedgerWishPage({super.key});

  @override
  ConsumerState<LedgerWishPage> createState() => _LedgerWishPageState();
}

class _LedgerWishPageState extends ConsumerState<LedgerWishPage> {
  static const _slate = Color(0xFF94A3B8);
  static const _amber = Color(0xFFF59E0B); // 原型 #f59e0b（star / 已存 / 存入）
  static const _amberTxt = Color(0xFFD97706); // amber-600（存入文字）
  static const _amberTxtD = Color(0xFFFBBF24); // amber-400（未达成进度条）
  static const _emerald = Color(0xFF10B981); // emerald-500（达成 / 已实现）

  /// 内嵌新建/编辑表单（原型 wishAdd 字段：名称 / 目标金额）。
  bool _formOpen = false;
  int? _editId;
  final _name = TextEditingController();
  double _target = 0;

  // T9（交互整改批三）：校验落在字段旁，不再叠提示条；保存钮防重入。
  String? _nameErr;
  String? _targetErr;
  bool _saving = false;

  /// 失焦刷新：仅在已亮错时复核当前值（不在用户第一次离开空字段时提前催）。
  late final FocusNode _nameFocus = FocusNode()
    ..addListener(() {
      if (_nameFocus.hasFocus || _nameErr == null || !mounted) return;
      setState(() => _nameErr = _name.text.trim().isEmpty ? _nameErr : null);
    });

  @override
  void dispose() {
    _name.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  LedgerRepository get _repo => ref.read(ledgerRepositoryProvider);

  void _tick() => ref.read(ledgerTickProvider.notifier).state++;

  void _toast(String m) => AppToast.show(context, m);

  void _closeForm() => setState(() {
        _formOpen = false;
        _editId = null;
        _name.clear();
        _target = 0;
        _nameErr = null;
        _targetErr = null;
      });

  void _openCreate() => setState(() {
        _editId = null;
        _formOpen = true;
        _name.clear();
        _target = 0;
        _nameErr = null;
        _targetErr = null;
      });

  void _openEdit(LedgerWish w) => setState(() {
        _editId = w.id;
        _formOpen = true;
        _name.text = w.name;
        _target = w.target;
        _nameErr = null;
        _targetErr = null;
      });

  /// T9：逐字段就地校验（原合并句「请填写名称与目标金额」拆到两枚字段旁）。
  void _validate() {
    _nameErr = _name.text.trim().isEmpty ? '请填写心愿名称' : null;
    _targetErr = _target <= 0 ? '请填写目标金额' : null;
  }

  Future<void> _save(LedgerData d) async {
    if (_saving) return;
    _validate();
    if (_nameErr != null || _targetErr != null) {
      setState(() {});
      return;
    }
    setState(() => _saving = true);
    final n = _name.text.trim();
    try {
      if (_editId == null) {
        await _repo.addWish(bk: d.curBook.id, name: n, target: _target);
      } else {
        await _repo.updateWish(_editId!, name: n, target: _target);
      }
      _closeForm();
      _tick();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 原型 wishSave：金额滚轮 → saved += v（不落流水）。
  Future<void> _deposit(LedgerWish w) async {
    final v = await showLAmountWheel(context, title: '「${w.name}」存入', value: 0);
    if (v == null || v <= 0) return;
    await _repo.bumpWishSaved(w.id, v);
    _tick();
    _toast('已存入 ${money(v)}');
  }

  /// 原型 wishTake：金额滚轮 → saved = max(0, saved − v)（不落流水）。
  Future<void> _take(LedgerWish w) async {
    final v = await showLAmountWheel(context, title: '「${w.name}」取出', value: 0);
    if (v == null || v <= 0) return;
    await _repo.bumpWishSaved(w.id, -v);
    _tick();
    _toast('已取出 ${money(v)}');
  }

  /// 原型 wishRedeem：选账户 → 生成 expense（source=wish）+ 归档。
  Future<void> _redeem(LedgerWish w) async {
    final acct = await showLAcctPick(context, title: '兑换账户');
    if (acct == null) return;
    final ok = await _repo.redeemWish(w.id, accountId: acct);
    _tick();
    if (ok) _toast('已生成支出流水并归档心愿');
  }

  Future<void> _del(LedgerWish w) async {
    await _repo.delWish(w.id);
    _tick();
  }

  @override
  Widget build(BuildContext context) {
    final dA = ref.watch(ledgerDataProvider);
    final wA = ref.watch(ledgerWishProvider);
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('心愿单'),
            Text(
              '为想要的攒一攒',
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
        data: (d) => wA.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('加载失败：$e')),
          data: (ws) => TabularNums(child: _body(d, ws)),
        ),
      ),
    );
  }

  Widget _body(LedgerData d, List<LedgerWish> all) {
    final open = all.where((w) => !w.done).toList();
    final done = all.where((w) => w.done).toList();
    final hide = d.hideAmounts;
    // 进度头（原型 tt=Σtarget、ss=Σmin(saved,target)，仅未实现组）。
    final tt = open.fold<double>(0, (s, w) => s + w.target);
    final ss = open.fold<double>(
        0, (s, w) => s + (w.saved > w.target ? w.target : w.saved));
    final hpct = tt > 0 ? (ss / tt * 100).clamp(0.0, 100.0) : 0.0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      children: [
        _headCard(ss, tt, hpct, hide),
        const SizedBox(height: 10),
        for (final w in open) _wishCard(d, w),
        if (_formOpen)
          _formCard(d)
        else
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: EmptyDashRow(text: '＋ 新建心愿', onTap: _openCreate),
          ),
        if (done.isNotEmpty) _doneGroup(done),
      ],
    );
  }

  // ---- 进度头卡（原型首卡：心愿进度 + 渐变条） ----

  Widget _headCard(double ss, double tt, double hpct, bool hide) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: context.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text('心愿进度',
              style: TextStyle(fontSize: 10, color: _slate)),
          const SizedBox(height: 2),
          RichText(
            text: TextSpan(
              style: DefaultTextStyle.of(context).style,
              children: [
                TextSpan(
                  text: amtText(ss, hide: hide),
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.w800),
                ),
                TextSpan(
                  text: ' / ${amtText(tt, hide: hide)}',
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _slate),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _bar(hpct / 100, gradient: true, height: 8),
        ],
      ),
    );
  }

  // ---- 心愿卡（原型 open.map：star 图标 / 名称 + 目标 + 达成态 / 进度条 /
  //      saved·percent / 存入·取出·兑换记账） ----

  Widget _wishCard(LedgerData d, LedgerWish w) {
    final achieved = w.achieved;
    final pct = w.progressPct;
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      // 卡片空白处点按进入编辑（新建/编辑表单为交付项；按钮内命中各自处理）。
      onTap: () => _openEdit(w),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: context.cardDecoration,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const LTile(
                    iconKey: 'star', color: '#f59e0b', size: 34, radius: 12),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(w.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700)),
                      Text(
                        '目标 ${money(w.target)}${achieved ? ' · 已达成，可兑换' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 9, color: _slate),
                      ),
                    ],
                  ),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _del(w),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(LIcons.resolve('trash'),
                        size: 16, color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _bar(pct / 100, color: achieved ? _emerald : _amberTxtD, height: 8),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(amtText(w.saved, hide: d.hideAmounts),
                    style: const TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w800)),
                Text('${pct.round()}%',
                    style: const TextStyle(fontSize: 10, color: _slate)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _actionBtn(
                    label: '存入',
                    bg: _amber.withValues(alpha: .10),
                    fg: _amberTxt,
                    bold: true,
                    onTap: () => _deposit(w),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _actionBtn(
                    label: '取出',
                    bg: scheme.surfaceContainerHighest,
                    fg: scheme.onSurface,
                    onTap: () => _take(w),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _actionBtn(
                    label: '兑换记账',
                    gradient: context.tokens.gradient,
                    fg: Colors.white,
                    bold: true,
                    disabled: !achieved,
                    onTap: () => _redeem(w),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---- 已实现分组（原型 done.length 卡：✓ + 名称 + doneDate） ----

  Widget _doneGroup(List<LedgerWish> done) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      clipBehavior: Clip.antiAlias,
      decoration: context.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('已实现',
                style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w700, color: _slate)),
          ),
          for (final w in done)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(LIcons.resolve('check'), size: 14, color: _emerald),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(w.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                  Text(w.doneDate ?? '',
                      style: const TextStyle(fontSize: 10, color: _slate)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ---- 内嵌新建/编辑表单（字段=原型 wishAdd：名称 / 目标金额） ----

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
          Text(_editId == null ? '新建心愿' : '编辑心愿',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
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
                    controller: _name,
                    focusNode: _nameFocus,
                    maxLength: 12,
                    style: const TextStyle(fontSize: 12),
                    onChanged: (v) {
                      if (_nameErr != null && v.trim().isNotEmpty) {
                        setState(() => _nameErr = null);
                      }
                    },
                    decoration: InputDecoration(
                      hintText: '心愿名称',
                      counterText: '',
                      errorText: _nameErr,
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
                          title: '目标金额', value: _target);
                      if (v != null) {
                        setState(() {
                          _target = v;
                          if (v > 0) _targetErr = null;
                        });
                      }
                    },
                    child: chip(
                      SizedBox(
                        width: 100,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          child: Text(
                              _target > 0 ? '目标 ${money(_target)}' : '目标金额',
                              style: const TextStyle(fontSize: 12)),
                        ),
                      ),
                    ),
                  ),
                  // 滚轮控件没有失焦语义，错误落在它自己下面一行（LH-K32）。
                  FieldError(_targetErr),
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

  /// 进度条（track surfaceContainerHighest + fill 纯色/渐变；对齐原型 rounded-full）。
  Widget _bar(double frac, {Color? color, bool gradient = false, double height = 8}) {
    final scheme = Theme.of(context).colorScheme;
    final w = frac.clamp(0.0, 1.0);
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, box) {
          return Stack(
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
                      gradient: gradient ? context.tokens.gradient : null,
                      color: gradient ? null : (color ?? _amberTxtD),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _actionBtn({
    required String label,
    Color? bg,
    required Color fg,
    Gradient? gradient,
    bool bold = false,
    bool disabled = false,
    required VoidCallback onTap,
  }) {
    final child = Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        gradient: gradient,
        color: gradient == null ? bg : null,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
            fontSize: 11, fontWeight: bold ? FontWeight.w800 : FontWeight.w700, color: fg),
      ),
    );
    return Opacity(
      opacity: disabled ? .4 : 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: disabled ? null : onTap,
        child: child,
      ),
    );
  }
}
