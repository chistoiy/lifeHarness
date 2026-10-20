import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;
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
    this.dialogMode = false,
    this.onDialogClose,
  });

  /// 编辑既有流水（openL2({editId})）。
  final int? editId;

  /// 复制：以该流水字段预填新条目（L3 复制钮）。
  final int? copyId;
  final String? kind;
  final int? catId;
  final String? date;
  final String? note;

  /// 弹窗形态（工单 §7.1 · 2026-10-18 拍板 A 路）：**同一份表单换容器**——
  /// 无 AppBar、按内容收高、保存/取消即关窗。只允许差两处：容器与高度。
  /// 四类型 tab／分类行／子类 chips／四则键盘逐字复用，禁另造一套样式。
  final bool dialogMode;

  /// 弹窗形态的关窗回调（null ⇒ [SystemNavigator.pop] 直接收掉宿主 Activity）。
  final VoidCallback? onDialogClose;

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
      setState(() => _personErr = _f.person.trim().isEmpty ? _personErr : null);
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
    _f.time =
        '${now.hour.toString().padLeft(2, '0')}:'
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
        _applyKind(t.kind == LedgerTxn.kRefund ? LedgerTxn.kExpense : t.kind);
        _f.cat = t.catId ?? _f.cat;
        _f.sub = t.sub;
        _f.expr = t.amt == t.amt.roundToDouble()
            ? '${t.amt.toInt()}'
            : '${t.amt}';
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
        final tail = _f.expr.isEmpty ? '' : _f.expr[_f.expr.length - 1];
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

  /// 离开记一笔：整页形态回 L1；弹窗形态关窗（收掉宿主 Activity，不进最近任务）。
  void _leave() {
    if (widget.dialogMode) {
      final close = widget.onDialogClose;
      if (close != null) {
        close();
      } else {
        SystemNavigator.pop();
      }
      return;
    }
    context.go('/ledger');
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
        _toast(
          '${_f.debtDir == 'lend' ? '借出' : '借入'} ${money(amt)} 已记入借贷'
          ' · ${_f.person.trim()}',
        );
        if (mounted) _leave();
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
        await checkBudgetAlert(
          repo,
          dnd: ref.read(settingsRepositoryProvider).load().notify.dnd,
        );
      } catch (e) {
        AppLog.add('预算超支提醒检查失败：$e', level: LhLevel.warn, src: '记账');
      }
      ledgerTouch(ref);
      // 再记=必留；保存=按 afterSave 设置（back 回 L1 · stay 清金额留表单）。
      final back = !stay && d.afterSave == 'back';
      if (back) {
        if (mounted) _leave();
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
    if (widget.dialogMode) return _dialogShell(async);
    return Scaffold(
      appBar: AppBar(
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
          return TabularNums(child: _body(d));
        },
      ),
    );
  }

  /// 弹窗形态外壳（工单 §7.1）：**版式基准＝原型 `#qpDlg` 真弹窗**。
  ///
  /// 2026-10-18 真机二次报障「记一笔的页面是拉长版的，跟高保真不一样」根因：
  /// 上一版把**整页**表单塞进 `maxHeight 88%` 的壳里，页面专属的那几段（付款账户、
  /// 备注＋图片附件、日期/时间/谁/标签/商家/报销/退款/付款/计入预算九枚 meta chips）
  /// 全在，内容高度直接顶到上限 ⇒ 观感就是「切了个全屏页」。
  ///
  /// 现按原型样张收口（样张 38/38 已过门，是验收基准）：
  ///  · 卡片宽 ≤322dp、圆角 20、内边距 13/14/12，四周留白 24（宿主给）；
  ///  · 头部「记一笔」14/w800 ＋ 26dp 圆形 ✕；
  ///  · 四类型 tab → 分类行 → 子类 chips 轨 → 备注 → 15 键键盘（保存跨两行）；
  ///  · **页面专属 chrome 不进弹窗**（付款账户/日期/时间/谁/标签/商家/报销/退款/
  ///    付款/计入预算/图片附件）——弹窗是「快速记一笔」，这些回 App 内改；
  ///  · 高度按内容收（`mainAxisSize.min`），上限 72% 屏高只作安全闸。
  Widget _dialogShell(AsyncValue<LedgerData> async) {
    final scheme = Theme.of(context).colorScheme;
    final maxH = MediaQuery.sizeOf(context).height * 0.72;
    return Material(
      key: const ValueKey<String>('ledger-add-card'),
      color: scheme.surface,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 322, maxHeight: maxH),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '记一笔',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: _leave,
                    child: Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: scheme.onSurfaceVariant.withValues(alpha: .12),
                      ),
                      child: Text(
                        '✕',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          height: 1,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Flexible(
                child: async.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('加载失败：$e')),
                  data: (d) {
                    if (!_inited) _initFrom(d);
                    return TabularNums(child: _dialogBody(d));
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 弹窗正文：**可滚的字段区 ＋ 钉底的键盘**。
  ///
  /// 键盘不进滚动区：软键盘顶起窗口时（`adjustResize`）宁可上面那段滚，
  /// 也不能把保存键挤出屏幕（拍板件 §五「小窗/IME」正是这条路要过的关）。
  Widget _dialogBody(LedgerData d) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _formSections(d, compact: true),
            ),
          ),
        ),
        const SizedBox(height: 9),
        _Keypad(
          onKey: _key,
          onAgain: () => _save(stay: true),
          onSave: () => _save(),
        ),
      ],
    );
  }

  /// 整页正文（L2）：字段区 ＋ 键盘同处一个 `ListView`（键盘跟着内容滚）。
  Widget _body(LedgerData d) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        ..._formSections(d),
        const SizedBox(height: 12),
        _Keypad(
          onKey: _key,
          onAgain: () => _save(stay: true),
          onSave: () => _save(),
        ),
      ],
    );
  }

  /// 表单各段（整页与弹窗**同一份** widget 树，禁两套样式）。
  ///
  /// [compact] 只做两件事：① 尺寸收一档（tab 8/12.5、金额 23、分类名 14…）；
  /// ② **去掉页面专属 chrome**——付款账户行、图片附件、九枚 meta chips
  /// （日期/时间/谁/标签/商家/报销/退款/付款/计入预算）。那几段在原型弹窗样张
  /// `#qpDlg` 里本来就没有，留着必然把卡片撑成整页（真机报障「拉长版」根因）。
  List<Widget> _formSections(LedgerData d, {bool compact = false}) {
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
    return [
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
                    padding: EdgeInsets.symmetric(vertical: compact ? 8 : 10),
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
                        fontSize: compact ? 12.5 : 13,
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
      if (!isTr && !isDbt) ..._expenseIncomeBody(d, amtColor, compact: compact),
      if (isDbt) ...debtBody(scheme, compact: compact, hide: d.hideAmounts),
      if (isTr) ...transferBody(d, compact: compact),
      if (!compact && !isTr && !isDbt)
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
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
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
      // 备注：整页带图片附件占位；弹窗只留一行输入（原型 `.qp-note` 无附件钮）
      if (compact)
        Container(
          margin: const EdgeInsets.only(top: 9),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
          ),
          child: TextField(
            controller: _noteCtl,
            onChanged: (v) => _f.note = v,
            style: const TextStyle(fontSize: 12),
            decoration: const InputDecoration(
              hintText: '备注…',
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 7),
            ),
          ),
        )
      else
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
      if (!compact && !isDbt) ...[
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
              _metaChip('无退款', false, () => _toast('退款 · 在流水详情页对原支出操作')),
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
    ];
  }

  /// 支出/收入形态：分类入口行 + chips 轨（原型 `.qp-catrow` / `.qp-rail`）。
  List<Widget> _expenseIncomeBody(
    LedgerData d,
    Color amtColor, {
    bool compact = false,
  }) {
    return [
      SizedBox(height: compact ? 11 : 12),
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
                      size: compact ? 34 : 36,
                      radius: compact ? 11 : 12,
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        d.catOf(_f.cat).name +
                            (_f.sub.isNotEmpty ? ' · ${_f.sub}' : ''),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: compact ? 14 : 15,
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
                  fontSize: compact ? 23 : 26,
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
                  small: compact,
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

  /// 借贷形态（原型 `.qp-dseg` ＋ 对方输入 ＋ `.qp-amrow` 右对齐金额）。
  List<Widget> debtBody(
    ColorScheme scheme, {
    bool compact = false,
    bool hide = false,
  }) {
    return [
      SizedBox(height: compact ? 9 : 12),
      Container(
        padding: EdgeInsets.all(compact ? 3 : 4),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(compact ? 12 : 18),
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
                    padding: EdgeInsets.symmetric(vertical: compact ? 6 : 8),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _f.debtDir == k ? scheme.surface : null,
                      borderRadius: BorderRadius.circular(compact ? 9 : 14),
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
                      style: TextStyle(
                        fontSize: compact ? 11 : 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      SizedBox(height: compact ? 8 : 10),
      TextField(
        controller: _personCtl,
        focusNode: _personFocus,
        onChanged: (v) {
          _f.person = v;
          if (_personErr != null && v.trim().isNotEmpty) {
            setState(() => _personErr = null);
          }
        },
        style: TextStyle(fontSize: compact ? 12.5 : 13),
        decoration: InputDecoration(
          hintText: '对方（如：老王）',
          errorText: _personErr,
          isDense: compact,
          filled: compact,
          fillColor: compact
              ? scheme.onSurfaceVariant.withValues(alpha: .08)
              : null,
          contentPadding: compact
              ? const EdgeInsets.symmetric(horizontal: 9, vertical: 8)
              : null,
          border: compact
              ? OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                )
              : null,
        ),
      ),
      SizedBox(height: compact ? 10 : 12),
      Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!compact) const Text('金额 ', style: TextStyle(fontSize: 13)),
          if (!compact)
            Text(
              money(_amt),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          // T9：金额校验落金额旁。
          if (compact)
            Expanded(child: _amountRow(compact: true, hide: hide))
          else
            FieldError(_amtErr),
        ],
      ),
    ];
  }

  /// 金额行（原型 `.qp-amrow`）：右对齐「¥ ＋ 23dp 金额」，校验文案挂其后。
  Widget _amountRow({bool compact = false, bool hide = false}) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          '¥',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 3),
        Text(
          hide ? '••••' : _amt.toStringAsFixed(2),
          style: TextStyle(
            fontSize: compact ? 23 : 26,
            fontWeight: FontWeight.w800,
            letterSpacing: -.5,
          ),
        ),
        FieldError(_amtErr),
      ],
    );
  }

  /// 转账形态（原型：转出/转入两张账户卡 ＋ 金额行）。
  List<Widget> transferBody(LedgerData d, {bool compact = false}) {
    return [
      SizedBox(height: compact ? 9 : 12),
      for (final (idx, label) in [(0, '选出'), (1, '转入')])
        Padding(
          padding: EdgeInsets.only(bottom: idx == 0 ? (compact ? 6 : 8) : 0),
          child: _AcctCard(
            d: d,
            account: idx == 0 ? d.acct(_f.acct) : d.acct(_f.to),
            label: label,
            amount: compact ? null : _amt,
            compact: compact,
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
      if (compact) _amountRow(compact: true, hide: d.hideAmounts),
      // T9：金额与「同账户互斥」都落在卡片下方，不再只弹提示条。
      if (!compact) FieldError(_amtErr),
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
      final label = sn.isEmpty ? d.catOf(cid).name : '${d.catOf(cid).name}·$sn';
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
    }) => Expanded(
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

/// 转账账户卡（整页带右侧金额；弹窗紧凑态只留「图标＋名称＋标签·余额」）。
class _AcctCard extends StatelessWidget {
  const _AcctCard({
    required this.d,
    required this.account,
    required this.label,
    required this.amount,
    required this.onTap,
    this.compact = false,
  });

  final LedgerData d;
  final LedgerAccount? account;
  final String label;

  /// 右侧金额（弹窗紧凑态传 null ⇒ 不显示，金额统一走下方 `.qp-amrow`）。
  final double? amount;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final a = account;
    return InkWell(
      borderRadius: BorderRadius.circular(compact ? 12 : 16),
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 9 : 14,
          vertical: compact ? 8 : 12,
        ),
        decoration: compact
            ? BoxDecoration(
                color: scheme.onSurfaceVariant.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(12),
              )
            : context.cardDecoration,
        child: Row(
          children: [
            LTile(
              iconKey: a?.icon ?? 'dots',
              color: a?.color ?? '#94a3b8',
              size: compact ? 30 : 34,
              radius: compact ? 10 : 12,
            ),
            SizedBox(width: compact ? 8 : 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a?.name ?? '选择账户',
                    style: TextStyle(
                      fontSize: compact ? 12.5 : 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    '$label · 余额 ${amtText(a?.balanceCache ?? 0, hide: d.hideAmounts)}',
                    style: TextStyle(
                      fontSize: compact ? 9.5 : 9,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (amount != null)
              Text(
                amtText(amount!, hide: d.hideAmounts),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
