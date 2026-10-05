import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/logging/app_log.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../domain/ledger_calc.dart';
import '../domain/ledger_models.dart';
import '../domain/ledger_txn.dart';
import 'ledger_date_sheet.dart';
import 'ledger_notify.dart';
import 'ledger_pick_sheets.dart';
import 'ledger_providers.dart';
import 'widgets/ledger_kit.dart';

/// 记一笔第四 tab「借贷」的表单态伪 kind（不产生流水，直写 ledger_debts）。
const String txTabDebt = 'debt';

/// L2 记一笔（原型 p-txAdd V1.33 图1版式 · TITLES ['记一笔','支出 · 收入 · 转账']）。
/// 四 tab（支出/收入/转账/借贷）+ 分类行与子分类 chips 轨 + 付款账户 + 备注 +
/// meta chips 行 + 四则运算键盘（⌗ 轮插 + − × ÷，先乘除后加减）。
class LedgerAddPage extends ConsumerStatefulWidget {
  const LedgerAddPage({
    super.key,
    this.editId,
    this.copyId,
    this.kind,
    this.catId,
    this.date,
    this.note,
  });

  /// 编辑既有流水（openL2({editId})）。
  final int? editId;

  /// 复制：以该流水字段预填新条目（L3 复制钮）。
  final int? copyId;
  final String? kind;
  final int? catId;
  final String? date;
  final String? note;

  @override
  ConsumerState<LedgerAddPage> createState() => _LedgerAddPageState();
}

/// 表单内部状态（原型 txState 一一对应）。
class _TxForm {
  String kind = LedgerTxn.kExpense;
  int cat = 101; // 餐饮
  String sub = '';
  String expr = '';
  String note = '';
  List<String> tags = [];
  String who = '自己';
  String merchant = '';
  bool paid = true;
  bool incB = true;
  bool reim = false;
  String debtDir = 'lend';
  String person = '';
  String date = dayKey(DateTime.now());
  String time = '';
  int? acct;
  int? to;
}

class _LedgerAddPageState extends ConsumerState<LedgerAddPage> {
  final _f = _TxForm();
  final _noteCtl = TextEditingController();
  final _personCtl = TextEditingController();
  bool _inited = false;
  int _opIdx = 0;

  // T9（交互整改批三）：校验落字段旁（null=无错）＋保存/再记防重入。
  String? _personErr;
  String? _amtErr;
  String? _acctErr;
  bool _saving = false;

  /// 失焦刷新：仅在已亮错时复核当前值（不在用户第一次离开空字段时提前催）。
  late final FocusNode _personFocus = FocusNode()
    ..addListener(() {
      if (_personFocus.hasFocus || _personErr == null || !mounted) return;
      setState(
          () => _personErr = _f.person.trim().isEmpty ? _personErr : null);
    });

  static const _ops = ['+', '−', '×', '÷'];

  @override
  void dispose() {
    _noteCtl.dispose();
    _personCtl.dispose();
    _personFocus.dispose();
    super.dispose();
  }

  void _toast(String m) => AppToast.show(context, m);

  void _initFrom(LedgerData d) {
    _f.who = d.whoDef;
    _f.acct = d.defAcctId;
    final other = [
      for (final a in d.accounts)
        if (!a.archived && a.id != _f.acct) a,
    ];
    _f.to = other.isEmpty ? _f.acct : other.first.id;
    final now = DateTime.now();
    _f.time = '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';
    if (widget.kind != null) _applyKind(widget.kind!);
    if (widget.catId != null) _f.cat = widget.catId!;
    if (widget.date != null) _f.date = widget.date!;
    if (widget.note != null && widget.note!.isNotEmpty) {
      _f.note = widget.note!;
      _noteCtl.text = widget.note!;
    }
    final srcId = widget.editId ?? widget.copyId;
    if (srcId != null) {
      final hits = d.txns.where((x) => x.id == srcId).toList();
      if (hits.isNotEmpty) {
        final t = hits.first;
        _applyKind(
          t.kind == LedgerTxn.kRefund ? LedgerTxn.kExpense : t.kind,
        );
        _f.cat = t.catId ?? _f.cat;
        _f.sub = t.sub;
        _f.expr =
            t.amt == t.amt.roundToDouble() ? '${t.amt.toInt()}' : '${t.amt}';
        _f.note = t.note;
        _noteCtl.text = t.note;
        _f.tags = [...t.tags];
        _f.acct = t.accountId;
        _f.to = t.toAccountId ?? _f.to;
        _f.date = t.date;
        _f.merchant = t.merchant ?? '';
        _f.who = t.who ?? d.whoDef;
        _f.paid = !t.unpaid;
        _f.incB = !t.nb;
        _f.reim = t.tags.contains('报销');
      }
    }
    _inited = true;
  }

  void _applyKind(String k) {
    _f.kind = k;
    _f.cat = switch (k) {
      LedgerTxn.kIncome => 201,
      txTabDebt => 114,
      _ => 101,
    };
    _f.sub = '';
    // 换 tab 时旧校验不残留（各 tab 必填面不同）。
    _personErr = null;
    _amtErr = null;
    _acctErr = null;
  }

  // ---- 键盘（§4：数字追加/小数点唯一/段长限 9；运算符经 ⌗ 轮插） ----

  void _key(String k) {
    setState(() {
      if (k == 'del') {
        if (_f.expr.isNotEmpty) {
          _f.expr = _f.expr.substring(0, _f.expr.length - 1);
        }
      } else if (k == 'op') {
        final tail =
            _f.expr.isEmpty ? '' : _f.expr[_f.expr.length - 1];
        if (_f.expr.isEmpty || _ops.contains(tail)) _f.expr += '0';
        _f.expr += _ops[_opIdx % _ops.length];
        _opIdx++;
      } else if (RegExp(r'[0-9.]').hasMatch(k)) {
        final tail = _f.expr.split(RegExp(r'[+−×÷]')).last;
        if (k == '.' && tail.contains('.')) return;
        if (tail.length >= 9) return;
        _f.expr += k;
      }
      // 金额一有值就把「请输入金额」那行撤掉（就地报错只反映当前态）。
      if (_amtErr != null && exprVal(_f.expr) > 0) _amtErr = null;
    });
  }

  double get _amt => exprVal(_f.expr);

  /// T9：保存前逐字段就地校验（文案沿用原提示条短句，只换呈现位置）。
  /// 返回是否仍有错；调用方负责 setState 重绘。
  bool _markErrors(double amt) {
    _personErr = _f.kind == txTabDebt && _f.person.trim().isEmpty
        ? '请填写对方'
        : null;
    _amtErr = amt > 0
        ? null
        : _f.kind == LedgerTxn.kTransfer
            ? '请输入转账金额'
            : '请输入金额';
    _acctErr = _f.kind == LedgerTxn.kTransfer && _f.acct == _f.to
        ? '转出与转入账户不能相同'
        : null;
    return _personErr != null || _amtErr != null || _acctErr != null;
  }

  // ---- 保存（§4 校验 + 统一写路径五处联动） ----

  Future<void> _save({bool stay = false}) async {
    if (_saving) return;
    final d = ref.read(ledgerDataProvider).valueOrNull;
    if (d == null) return;
    final repo = ref.read(ledgerRepositoryProvider);
    final amt = _amt;
    if (_markErrors(amt)) {
      setState(() {});
      return;
    }
    setState(() => _saving = true);
    try {
      if (_f.kind == txTabDebt) {
        await repo.addDebt(
          bk: d.curBook.id,
          side: _f.debtDir,
          person: _f.person.trim(),
          total: amt,
          note: _f.note.trim().isEmpty ? '记一笔借贷' : _f.note.trim(),
        );
        ledgerTouch(ref);
        _toast('${_f.debtDir == 'lend' ? '借出' : '借入'} ${money(amt)} 已记入借贷'
            ' · ${_f.person.trim()}');
        if (mounted) context.go('/ledger');
        return;
      }
      final tags = [..._f.tags];
      if (_f.reim && !tags.contains('报销')) tags.add('报销');
      final isEdit = widget.editId != null;
      final note = _f.note.trim();
      final txn = LedgerTxn(
        id: isEdit ? widget.editId! : 0,
        kind: _f.kind,
        amt: amt,
        catId: _f.kind == LedgerTxn.kTransfer ? 114 : _f.cat,
        sub: _f.kind == LedgerTxn.kTransfer ? '' : _f.sub,
        accountId: _f.acct!,
        toAccountId: _f.kind == LedgerTxn.kTransfer ? _f.to : null,
        date: _f.date,
        time: _f.time,
        note: note.isEmpty && _f.kind == LedgerTxn.kTransfer
            ? '${d.acct(_f.acct)?.name} → ${d.acct(_f.to)?.name}'
            : note,
        tags: tags,
        bk: d.curBook.id,
        unpaid: !_f.paid,
        nb: !_f.incB,
        merchant: _f.merchant.isEmpty ? null : _f.merchant,
        who: _f.who == d.whoDef ? null : _f.who,
      );
      if (isEdit) {
        await repo.editTxn(txn.id, txn.toRow()..remove('id'));
        _toast('已更新流水 · 各视图同步回算');
      } else {
        await repo.addTxn(txn);
        _toast('已记一笔 · ${money(amt)} · ${d.curBook.name}');
      }
      // V1.57 B 批：本笔落库后检查预算 80%/100% 档（同档期各一次 · 免打扰顺延）。
      try {
        await checkBudgetAlert(repo,
            dnd: ref.read(settingsRepositoryProvider).load().notify.dnd);
      } catch (e) {
        AppLog.add('预算超支提醒检查失败：$e',
            level: LhLevel.warn, src: '记账');
      }
      ledgerTouch(ref);
      // 再记=必留；保存=按 afterSave 设置（back 回 L1 · stay 清金额留表单）。
      final back = !stay && d.afterSave == 'back';
      if (back) {
        if (mounted) context.go('/ledger');
        return;
      }
      setState(() {
        _f.expr = '';
        _f.note = '';
        _noteCtl.clear();
        _amtErr = null;
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(ledgerDataProvider);
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(async.valueOrNull?.curBook.name ?? '记一笔'),
            Text(
              '记一笔',
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
        data: (d) {
          if (!_inited) _initFrom(d);
          return _body(d);
        },
      ),
    );
  }

  Widget _body(LedgerData d) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    final isTr = _f.kind == LedgerTxn.kTransfer;
    final isDbt = _f.kind == txTabDebt;
    final amtColor = switch (_f.kind) {
      LedgerTxn.kIncome => const Color(0xFF10B981),
      LedgerTxn.kTransfer => tokens.accent,
      _ => const Color(0xFFFB7185),
    };
    final acct = d.acct(_f.acct);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        // 四 tab（支出/收入/转账/借贷）
        Container(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
          ),
          child: Row(
            children: [
              for (final (k, n) in const [
                (LedgerTxn.kExpense, '支出'),
                (LedgerTxn.kIncome, '收入'),
                (LedgerTxn.kTransfer, '转账'),
                (txTabDebt, '借贷'),
              ])
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _applyKind(k)),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            width: 3,
                            color: _f.kind == k
                                ? tokens.accent
                                : Colors.transparent,
                          ),
                        ),
                      ),
                      child: Text(
                        n,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: _f.kind == k
                              ? tokens.accent
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (!isTr && !isDbt) ..._expenseIncomeBody(d, amtColor),
        if (isDbt) ...debtBody(scheme),
        if (isTr) ...transferBody(d),
        if (!isTr && !isDbt)
          InkWell(
            onTap: () async {
              final id = await showLAcctPick(context, title: '选择付款账户');
              if (id != null) setState(() => _f.acct = id);
            },
            child: Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '付款账户',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (acct != null)
                    Row(
                      children: [
                        Icon(
                          LIcons.resolve(acct.icon),
                          size: 16,
                          color: lColor(acct.color),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          acct.name,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: lColor(acct.color),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        // 备注 + 图片附件占位
        Container(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _noteCtl,
                  onChanged: (v) => _f.note = v,
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(
                    hintText: '备注…',
                    border: InputBorder.none,
                  ),
                ),
              ),
              IconButton(
                tooltip: '添加图片附件',
                icon: const Icon(Icons.image_outlined, size: 20),
                onPressed: () => _toast('添加图片附件（模拟）'),
              ),
            ],
          ),
        ),
        if (!isDbt) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _metaChip(
                _f.date == dayKey(DateTime.now())
                    ? '今天 周${wdOf(_f.date)}'
                    : _f.date.substring(5),
                false,
                () async {
                  final v = await showLDateSheet(
                    context,
                    mode: 'day',
                    value: _f.date,
                  );
                  if (v != null) setState(() => _f.date = v);
                },
              ),
              _metaChip(_f.time, false, () async {
                final v = await showLDateSheet(
                  context,
                  mode: 'time',
                  value: _f.time,
                );
                if (v != null) setState(() => _f.time = v);
              }),
              _metaChip(_f.who, false, () async {
                final v = await showLWhoPick(context, value: _f.who);
                if (v != null) setState(() => _f.who = v);
              }),
              _metaChip(
                _f.tags.isEmpty ? '无标签' : '标签·${_f.tags.length}',
                _f.tags.isNotEmpty,
                () async {
                  final v = await showLTagPick(context, selected: _f.tags);
                  if (v != null) setState(() => _f.tags = v);
                },
              ),
              _metaChip(
                _f.merchant.isEmpty ? '无商家' : '商家·${_f.merchant}',
                _f.merchant.isNotEmpty,
                () async {
                  final v = await showLMerchPick(context, value: _f.merchant);
                  if (v != null) setState(() => _f.merchant = v);
                },
              ),
              if (!isTr) ...[
                _metaChip(
                  _f.reim ? '报销' : '非报销',
                  _f.reim,
                  () => setState(() => _f.reim = !_f.reim),
                ),
                _metaChip(
                  '无退款',
                  false,
                  () => _toast('退款 · 在流水详情页对原支出操作'),
                ),
                _metaChip(
                  _f.paid ? '已付款' : '未付款',
                  !_f.paid,
                  () => setState(() => _f.paid = !_f.paid),
                ),
                _metaChip(
                  _f.incB ? '计入收支和预算' : '不计入收支预算',
                  !_f.incB,
                  () => setState(() => _f.incB = !_f.incB),
                ),
              ],
            ],
          ),
        ],
        const SizedBox(height: 12),
        _Keypad(
          onKey: _key,
          onAgain: () => _save(stay: true),
          onSave: () => _save(),
        ),
      ],
    );
  }

  /// 支出/收入形态：分类入口行 + chips 轨。
  List<Widget> _expenseIncomeBody(LedgerData d, Color amtColor) {
    return [
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () async {
                final r = await showLCatPick(
                  context,
                  kind: _f.kind == LedgerTxn.kIncome
                      ? LedgerCat.kIncome
                      : LedgerCat.kExpense,
                  selCat: _f.cat,
                  selSub: _f.sub,
                );
                if (r != null) {
                  setState(() {
                    _f.cat = r.catId;
                    _f.sub = r.sub;
                  });
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    LTile(
                      iconKey: d.catOf(_f.cat).icon,
                      color: d.catOf(_f.cat).color,
                      size: 36,
                      radius: 12,
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        d.catOf(_f.cat).name +
                            (_f.sub.isNotEmpty ? ' · ${_f.sub}' : ''),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const Text(' ›'),
                  ],
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                d.hideAmounts ? '••••' : _amt.toStringAsFixed(2),
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.5,
                  color: amtColor,
                ),
              ),
              // T9：金额校验落金额旁（就地，不叠提示条）。
              FieldError(_amtErr),
              if (RegExp(r'[+−×÷]').hasMatch(_f.expr))
                Text(
                  '${_f.expr} =',
                  style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ],
      ),
      const SizedBox(height: 10),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final (label, cid, sn) in _railChips(d))
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: LChip(
                  label: label,
                  on: cid == _f.cat && sn == _f.sub,
                  onTap: () => setState(() {
                    _f.cat = cid;
                    _f.sub = sn;
                  }),
                ),
              ),
          ],
        ),
      ),
    ];
  }

  List<Widget> debtBody(ColorScheme scheme) {
    return [
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            for (final (k, n) in const [
              ('lend', '借出 · 别人欠我'),
              ('borrow', '借入 · 我欠别人'),
            ])
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _f.debtDir = k),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _f.debtDir == k ? scheme.surface : null,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: _f.debtDir == k
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
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _personCtl,
        focusNode: _personFocus,
        onChanged: (v) {
          _f.person = v;
          if (_personErr != null && v.trim().isNotEmpty) {
            setState(() => _personErr = null);
          }
        },
        style: const TextStyle(fontSize: 13),
        decoration:
            InputDecoration(hintText: '对方（如：老王）', errorText: _personErr),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          const Text('金额 ', style: TextStyle(fontSize: 13)),
          Text(
            money(_amt),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          // T9：金额校验落金额旁。
          FieldError(_amtErr),
        ],
      ),
    ];
  }

  List<Widget> transferBody(LedgerData d) {
    return [
      const SizedBox(height: 12),
      for (final (idx, label) in [(0, '选出'), (1, '转入')])
        Padding(
          padding: EdgeInsets.only(bottom: idx == 0 ? 8 : 0),
          child: _AcctCard(
            d: d,
            account: idx == 0 ? d.acct(_f.acct) : d.acct(_f.to),
            label: label,
            amount: _amt,
            onTap: () async {
              final id = await showLAcctPick(
                context,
                title: label == '选出' ? '选出账户' : '转入账户',
              );
              if (id != null) {
                setState(() {
                  if (idx == 0) {
                    _f.acct = id;
                  } else {
                    _f.to = id;
                  }
                  _acctErr = null;
                });
              }
            },
          ),
        ),
      // T9：金额与「同账户互斥」都落在卡片下方，不再只弹提示条。
      FieldError(_amtErr),
      FieldError(_acctErr),
    ];
  }

  /// chips 轨：首=当前大类（未细分）；该大类有子分类→其子分类；
  /// 无→收藏∪近30天高频（当前收支树过滤，§4 与九·补1/2）。
  List<(String, int, String)> _railChips(LedgerData d) {
    final major = d.catById[_f.cat];
    final out = <(String, int, String)>[
      if (major != null) (major.name, major.id, ''),
    ];
    final subs = d.subsOf(_f.cat);
    if (subs.isNotEmpty) {
      out.addAll(subs.map((s) => (s.name, _f.cat, s.name)));
      return out;
    }
    final wantKind = _f.kind == LedgerTxn.kIncome
        ? LedgerCat.kIncome
        : LedgerCat.kExpense;
    final treeIds = {
      for (final c in d.cats)
        if (c.kind == wantKind) c.id,
    };
    for (final (cid, sn) in recentFavChips(
      last30: d.last30(),
      favs: d.favs,
      treeCatIds: treeIds,
    )) {
      final label =
          sn.isEmpty ? d.catOf(cid).name : '${d.catOf(cid).name}·$sn';
      out.add((label, cid, sn));
      if (out.length >= 13) break;
    }
    return out;
  }

  Widget _metaChip(String label, bool on, VoidCallback onTap) =>
      LChip(label: label, on: on, onTap: onTap);
}

// ---- 四则键盘（原型 txPad 栅格：保存纵向占两格） ----

class _Keypad extends StatelessWidget {
  const _Keypad({
    required this.onKey,
    required this.onAgain,
    required this.onSave,
  });

  final ValueChanged<String> onKey;
  final VoidCallback onAgain;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget cell(
      String content, {
      required VoidCallback onTap,
      bool op = false,
      bool big = false,
    }) =>
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onTap,
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: op ? scheme.surfaceContainerHighest : scheme.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Text(
                  content,
                  style: TextStyle(
                    fontSize: big ? 15 : 17,
                    fontWeight: FontWeight.w800,
                    color: op ? scheme.onSurfaceVariant : scheme.onSurface,
                  ),
                ),
              ),
            ),
          ),
        );
    final rows = const [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['op', '0', '.'],
    ];
    return LayoutBuilder(
      builder: (context, cons) {
        final cellW = (cons.maxWidth - 3 * 8) / 4;
        final h = cellW / 2.05;
        return SizedBox(
          height: h * 4 + 8,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  children: [
                    for (final r in rows)
                      Expanded(
                        child: Row(
                          children: [
                            for (final k in r)
                              cell(
                                k == 'op' ? '⌗' : k,
                                op: k == 'op',
                                onTap: () => onKey(k),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Column(
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: _topKey(context, '⌫', () => onKey('del')),
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: _topKey(
                                context,
                                '再记',
                                onAgain,
                                small: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: context.tokens.gradient,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: onSave,
                              child: const Center(
                                child: Text(
                                  '保存',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _topKey(
    BuildContext context,
    String label,
    VoidCallback onTap, {
    bool small = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: small ? 13 : 17,
            fontWeight: FontWeight.w800,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// 转账账户卡。
class _AcctCard extends StatelessWidget {
  const _AcctCard({
    required this.d,
    required this.account,
    required this.label,
    required this.amount,
    required this.onTap,
  });

  final LedgerData d;
  final LedgerAccount? account;
  final String label;
  final double amount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final a = account;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: context.cardDecoration,
        child: Row(
          children: [
            LTile(
              iconKey: a?.icon ?? 'dots',
              color: a?.color ?? '#94a3b8',
              size: 34,
              radius: 12,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a?.name ?? '选择账户',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    '$label · 余额 ${amtText(a?.balanceCache ?? 0, hide: d.hideAmounts)}',
                    style: TextStyle(
                      fontSize: 9,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              amtText(amount, hide: d.hideAmounts),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}
