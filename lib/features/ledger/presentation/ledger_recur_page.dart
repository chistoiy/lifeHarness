import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/linkage/ledger_mounts.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../data/ledger_repository.dart';
import '../domain/ledger_calc.dart';
import '../domain/ledger_models.dart';
import 'ledger_date_sheet.dart';
import 'ledger_pick_sheets.dart';
import 'ledger_providers.dart';
import 'widgets/ledger_kit.dart';

/// L9 周期账单/订阅中心（原型 p-recur · TITLES ['周期账单','订阅 · 房租 · 定投']；
/// renderRecur 全量：到期横幅（今日到期 N 笔 · 共 ¥X + 名称行 + 「生成」钮）→
/// 周期行列表（图标/名称/已暂停徽/频率·子类·账户·下次日·到期倒计时/金额/启停/删）→
/// 内嵌新建表单（名称/金额/分类(含子)/频率/账户/下次日/保存/取消）→ 底部提示逐字。
///
/// 生成触发路径（以原型代码为准）：无自动批量入口——L1 横幅「去生成 ›」跳本页，
/// 本页到期横幅「生成」钮调 recGenDue 批量落账 + tick；单笔启停/删除即时无确认。
/// 编辑为本批次按任务规格扩展（点行开同一表单，原型仅新建；文案新建部分逐字保留）。
class LedgerRecurPage extends ConsumerStatefulWidget {
  const LedgerRecurPage({super.key});

  @override
  ConsumerState<LedgerRecurPage> createState() => _LedgerRecurPageState();
}

class _LedgerRecurPageState extends ConsumerState<LedgerRecurPage> {
  /// 原型 recAddOpen + ra* 表单域；_editId!=null 为编辑态（规格扩展）。
  bool _addOpen = false;
  int? _editId;
  final _name = TextEditingController();
  double _amt = 0;
  int? _catId;
  String _sub = '';
  String _freq = 'month';
  int? _acctId;
  String? _next;

  // T9（交互整改批三）：校验落在字段旁，不再叠提示条；保存钮防重入。
  String? _nameErr;
  String? _amtErr;
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

  String get _today => dayKey(DateTime.now());

  void _closeForm() => setState(() {
        _addOpen = false;
        _editId = null;
        _name.clear();
        _amt = 0;
        _catId = null;
        _sub = '';
        _freq = 'month';
        _acctId = null;
        _next = null;
        _nameErr = null;
        _amtErr = null;
      });

  void _openCreate(LedgerData d) => setState(() {
        _editId = null;
        _addOpen = true;
        _name.clear();
        _amt = 0;
        _nameErr = null;
        _amtErr = null;
        final first = d.majors(LedgerCat.kExpense).where((c) => !c.hidden).firstOrNull;
        _catId = first?.id;
        _sub = '';
        _freq = 'month';
        _acctId = d.defAcctId ?? d.accounts.firstOrNull?.id;
        _next = _today;
      });

  void _openEdit(LedgerRecur r) => setState(() {
        _editId = r.id;
        _addOpen = true;
        _name.text = r.name;
        _amt = r.amt;
        _catId = r.catId;
        _sub = r.sub;
        _freq = r.freq;
        _acctId = r.accountId;
        _next = r.nextDate;
        _nameErr = null;
        _amtErr = null;
      });

  /// T9：逐字段就地校验（原合并句「请填写名称与金额」拆到两枚字段旁）。
  void _validate() {
    _nameErr = _name.text.trim().isEmpty ? '请填写名称' : null;
    _amtErr = _amt <= 0 ? '请填写金额' : null;
  }

  /// 原型 recAddSave（编辑态走 updateRecur）。
  Future<void> _save(LedgerData d) async {
    if (_saving) return;
    _validate();
    if (_nameErr != null || _amtErr != null) {
      setState(() {});
      return;
    }
    setState(() => _saving = true);
    final n = _name.text.trim();
    final r = LedgerRecur(
      id: _editId ?? 0,
      bk: d.curBook.id,
      name: n,
      amt: _amt,
      catId: _catId,
      sub: _sub,
      accountId: _acctId ?? d.accounts.first.id,
      freq: _freq,
      nextDate: _next ?? _today,
      active: true,
    );
    try {
      if (_editId == null) {
        await _repo.addRecur(r);
        _toast('周期账单已创建');
      } else {
        final old =
            (await _repo.recurs(d.curBook.id)).firstWhere((x) => x.id == _editId);
        await _repo.updateRecur(_editId!, r.copyWithKeepBk(old));
        _toast('周期账单已更新');
      }
      _closeForm();
      _tick();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 原型 recGenDue：批量生成到期行（next 推进一个周期），toast 逐字。
  Future<void> _genDue(LedgerData d, List<LedgerRecur> due) async {
    if (due.isEmpty) {
      _toast('今日无到期账单');
      return;
    }
    final n = await _repo.genDueRecur(d.curBook.id, _today);
    _tick();
    _toast(ledgerRecurBatchGenToast(n));
  }

  Future<void> _toggle(LedgerRecur r) async {
    await _repo.setRecurActive(r.id, !r.active);
    _tick();
    _toast('周期账单已${r.active ? '暂停' : '恢复'}');
  }

  Future<void> _del(LedgerRecur r) async {
    await _repo.delRecur(r.id);
    _tick();
  }

  @override
  Widget build(BuildContext context) {
    final dA = ref.watch(ledgerDataProvider);
    final rA = ref.watch(ledgerRecurProvider);
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('周期账单'),
            Text(
              '订阅 · 房租 · 定投',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.normal),
            ),
          ],
        ),
      ),
      body: dA.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: (d) => rA.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('加载失败：$e')),
          data: (rs) => _body(d, rs),
        ),
      ),
    );
  }

  Widget _body(LedgerData d, List<LedgerRecur> rs) {
    final due = rs.where((r) => r.active && r.nextDate.compareTo(_today) <= 0).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      children: [
        if (due.isNotEmpty) _dueBanner(d, due),
        for (final r in rs) _recurRow(d, r),
        if (rs.isEmpty && !_addOpen)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text('暂无周期账单',
                  style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
            ),
          ),
        if (_addOpen)
          _formCard(d)
        else
          Padding(
            padding: EdgeInsets.only(top: due.isNotEmpty || rs.isEmpty ? 0 : 4),
            child: EmptyDashRow(text: '＋ 新建周期账单', onTap: () => _openCreate(d)),
          ),
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text(
            '周期账单不预生成流水，扣日当天确认后入账（可整月回看）· 自动关联续费提醒日程（L8）',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 9, color: Color(0xFF94A3B8), height: 1.6),
          ),
        ),
      ],
    );
  }

  // ---- 到期横幅（原型 renderRecur due 卡：amber 底 + 生成钮） ----

  Widget _dueBanner(LedgerData d, List<LedgerRecur> due) {
    final total = due.fold<double>(0, (s, r) => s + r.amt);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withValues(alpha: .08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: .35)),
      ),
      child: Row(
        children: [
          Icon(LIcons.resolve('bell'), size: 20, color: const Color(0xFFF59E0B)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '今日到期 ${due.length} 笔 · 共 ${amtText(total, hide: d.hideAmounts)}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                ),
                Text(
                  due.map((r) => r.name).join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _genDue(d, due),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                '生成',
                style: TextStyle(
                    color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---- 周期行 ----

  Widget _recurRow(LedgerData d, LedgerRecur r) {
    final c = d.catOf(r.catId);
    final left = recurDaysLeft(_today, r.nextDate);
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _openEdit(r),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: context.cardDecoration,
        child: Row(
          children: [
            LTile(iconKey: c.icon, color: c.color, size: 32, radius: 11),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(r.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w800)),
                      ),
                      if (!r.active)
                        Container(
                          margin: const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '已暂停',
                            style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.w700,
                                color: scheme.onSurfaceVariant),
                          ),
                        ),
                    ],
                  ),
                  Text(
                    '${recurFreqName(r.freq)}'
                    '${r.sub.isNotEmpty ? ' · ${r.sub}' : ''}'
                    ' · ${d.acct(r.accountId)?.name ?? ''}'
                    ' · ${r.nextDate}'
                    '${left <= 0 ? ' 已到期' : ' 还有 $left 天'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 9, color: Color(0xFF94A3B8)),
                  ),
                ],
              ),
            ),
            Text(amtText(r.amt, hide: d.hideAmounts),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
            const SizedBox(width: 4),
            Switch(
              value: r.active,
              activeThumbColor: context.tokens.accent,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: (v) => _toggle(r),
            ),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _del(r),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(LIcons.resolve('trash'),
                    size: 16, color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- 内嵌新建/编辑表单（原型 recAddOpen 卡：字段/按钮逐行对应） ----

  Widget _formCard(LedgerData d) {
    final scheme = Theme.of(context).colorScheme;
    final cats = d.majors(LedgerCat.kExpense).where((c) => !c.hidden).toList();
    final catLabel = _catId == null
        ? '分类'
        : '${d.catOf(_catId).name}${_sub.isNotEmpty ? ' · $_sub' : ''}';
    Widget fieldLabel(String text) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Text(text, style: const TextStyle(fontSize: 12)),
        );
    Widget chip(Widget child) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: child,
        );
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: context.cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_editId == null ? '新建周期账单' : '编辑周期账单',
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
                      hintText: '名称 · 如 爱奇艺会员',
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
                          title: '周期账单金额', value: _amt);
                      if (v != null) {
                        setState(() {
                          _amt = v;
                          if (v > 0) _amtErr = null;
                        });
                      }
                    },
                    child: chip(
                      SizedBox(
                          width: 88,
                          child: fieldLabel(
                              _amt > 0 ? money(_amt) : '金额')),
                    ),
                  ),
                  // 滚轮控件没有失焦语义，错误落在它自己下面一行（LH-K32）。
                  FieldError(_amtErr),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: chip(InkWell(
                  onTap: cats.isEmpty
                      ? null
                      : () async {
                          final picked = await showLCatPick(
                            context,
                            kind: LedgerCat.kExpense,
                            selCat: _catId ?? cats.first.id,
                            selSub: _sub,
                          );
                          if (picked != null) {
                            setState(() {
                              _catId = picked.catId;
                              _sub = picked.sub;
                            });
                          }
                        },
                  child: fieldLabel(catLabel),
                )),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: chip(
                  DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _freq,
                      isExpanded: true,
                      items: [
                        for (final (k, n) in recurFreqs)
                          DropdownMenuItem(value: k, child: Text(n,
                              style: const TextStyle(fontSize: 12))),
                      ],
                      onChanged: (v) => setState(() => _freq = v ?? _freq),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: chip(
                  DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: _acctId,
                      isExpanded: true,
                      items: [
                        for (final a in d.accounts.where((x) => !x.archived))
                          DropdownMenuItem(value: a.id, child: Text(a.name,
                              style: const TextStyle(fontSize: 12))),
                      ],
                      onChanged: (v) => setState(() => _acctId = v),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: chip(InkWell(
                  onTap: () async {
                    final v = await showLDateSheet(context,
                        mode: 'day', value: _next ?? _today);
                    if (v != null) setState(() => _next = v);
                  },
                  child: fieldLabel(_next ?? _today),
                )),
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
              const SizedBox(width: 8),
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
                  child: const Text('取消',
                      style: TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 编辑保存时保持原行 id/bk/启停态（表单不暴露这两项）。
extension on LedgerRecur {
  LedgerRecur copyWithKeepBk(LedgerRecur old) => LedgerRecur(
        id: old.id,
        bk: old.bk,
        name: name,
        amt: amt,
        catId: catId,
        sub: sub,
        accountId: accountId,
        freq: freq,
        nextDate: nextDate,
        active: old.active,
        note: old.note,
      );
}
