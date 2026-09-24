import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../data/ledger_repository.dart';
import '../domain/ledger_models.dart';
import 'ledger_hero_cfg_sheet.dart';
import 'ledger_pick_sheets.dart';
import 'ledger_providers.dart';
import 'ledger_sheets.dart';
import 'widgets/ledger_kit.dart';

/// L13 记账设置（原型 p-lset · TITLES ['记账设置','']；renderLset 5358~5378 全量）。
///
/// 行序与文案逐字照抄原型 row()：隐藏全部金额 / 默认记账账户 / 记一笔保存后 /
/// 删除流水二次确认 / 预算月起始日 / 预算超支提醒 / 月度小结推送 /
/// 导入支付宝·微信账单 / 分类管理 / 角色管理 / 标签管理 / 商家管理 /
/// 快速记一笔 / 自定义顶部卡片 / 数据导出 / 重置演示数据。
/// 设置键全部落 DB settings 表（`ledger.` 前缀，ADR D11 既定口径，
/// 非计划书 §7 的 SharedPreferences）；开关/分段改动即写库并 ledgerTouch 失效。
/// 撤销导入批次：原型 renderLset 无该行（九·补4 批次表 + repo.undoImportBatch
/// 已备），按「原型没有就不造行」口径不设 UI 行，收口报告登记。
class LedgerSetPage extends ConsumerStatefulWidget {
  const LedgerSetPage({super.key});

  @override
  ConsumerState<LedgerSetPage> createState() => _LedgerSetPageState();
}

class _LedgerSetPageState extends ConsumerState<LedgerSetPage> {
  static const _slate = Color(0xFF94A3B8); // 原型 sub 文案 text-slate-400

  /// §7 默认值：budgetAlert true · monthlyDigest false。
  bool? _alert;
  bool? _digest;

  LedgerRepository get _repo => ref.read(ledgerRepositoryProvider);

  void _tick() => ledgerTouch(ref);

  void _toast(String m) {
    if (mounted) AppToast.show(context, m);
  }

  @override
  void initState() {
    super.initState();
    _loadNotifies();
  }

  Future<void> _loadNotifies() async {
    final alert = await _repo.budgetAlert();
    final digest = await _repo.monthlyDigest();
    if (!mounted) return;
    setState(() {
      _alert = alert;
      _digest = digest;
    });
  }

  // ---- 行内写路径（即改即落库；等价原型 onclick 直改 L.set + renderLset） ----

  Future<void> _setHide(bool v) async {
    await _repo.setHideAmounts(v);
    if (!mounted) return;
    _tick();
    _toast(v ? '金额已隐藏' : '金额已显示');
  }

  Future<void> _setDefaultAcct() async {
    final id = await showLAcctPick(context);
    if (id == null) return;
    await _repo.setDefAcct(id);
    if (!mounted) return;
    _tick();
    _toast('默认账户已切换');
  }

  Future<void> _setAfterSave(String v) async {
    await _repo.setAfterSave(v);
    if (!mounted) return;
    _tick();
  }

  Future<void> _setConfirmDel(bool v) async {
    await _repo.setConfirmDel(v);
    if (!mounted) return;
    _tick();
  }

  Future<void> _setMonthStart(int d) async {
    await _repo.setMonthStart(d);
    if (!mounted) return;
    _tick();
    if (d == 15) {
      _toast('预算与日均分配将按 15 日周期重算（演示）');
    }
  }

  Future<void> _setAlert(bool v) async {
    await _repo.setBudgetAlert(v);
    if (!mounted) return;
    setState(() => _alert = v);
    _toast('超支 80% / 100% 两档本地通知（演示）');
  }

  Future<void> _setDigest(bool v) async {
    await _repo.setMonthlyDigest(v);
    if (!mounted) return;
    setState(() => _digest = v);
    _toast('每月 1 日 09:00 本地推送（演示）');
  }

  /// 原型「重置演示数据 → location.reload()」：Web 演示专属机制，真实版
  /// 无演示库可重载、不做清库（偏差已在收口报告登记）；等价映射为
  /// 重新载入当前数据快照（tick 重取 + 通知类键复读）。
  Future<void> _reload() async {
    _tick();
    await _loadNotifies();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(ledgerDataProvider);
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('记账设置'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败：$e')),
        data: _body,
      ),
    );
  }

  Widget _body(LedgerData d) {
    final defAcct = d.acct(d.defAcctId);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        // 1 隐藏全部金额（原型 toggleHideAmounts：仪表盘与资产页同步生效）
        _row(
          '隐藏全部金额',
          Switch(value: d.hideAmounts, onChanged: _setHide),
          sub: '仪表盘与资产页同步生效',
        ),
        // 2 默认记账账户（openLedgerAcctPick → L.set.defAcct + toast）
        _row(
          '默认记账账户',
          LChip(label: defAcct?.name ?? '选择', onTap: _setDefaultAcct),
        ),
        // 3 记一笔保存后（§4 afterSave=back/stay）
        _row(
          '记一笔保存后',
          _seg<String>(
            const [('back', '回流水页'), ('stay', '继续记录')],
            d.afterSave,
            _setAfterSave,
          ),
        ),
        // 4 删除流水二次确认（L3 双击确认窗口读取本键）
        _row(
          '删除流水二次确认',
          Switch(value: d.confirmDel, onChanged: _setConfirmDel),
        ),
        // 5 预算月起始日（budLeftDays/结转周期口径）
        _row(
          '预算月起始日',
          _seg<int>(
            const [(1, '每月 1 日'), (15, '每月 15 日')],
            d.monthStart,
            _setMonthStart,
          ),
        ),
        // 6 预算超支提醒（原型静态演示开关；真实版落 budgetAlert 键）
        _row(
          '预算超支提醒',
          Switch(value: _alert ?? true, onChanged: _setAlert),
        ),
        // 7 月度小结推送（真实版落 monthlyDigest 键，默认 false）
        _row(
          '月度小结推送',
          Switch(value: _digest ?? false, onChanged: _setDigest),
        ),
        // 8 billGo() → 五步向导（批1d 已开放）
        _row(
          '导入支付宝 / 微信账单',
          LChip(
            label: '五步向导 · 账户匹配 + 勾选导入 ›',
            onTap: () => ledgerNav(context, 'import'),
          ),
        ),
        // 9 navTo('p-cats')（批2d 已开放）
        _row(
          '分类管理',
          LChip(
            label: '两级分类 · 排序改名 ›',
            onTap: () => ledgerNav(context, 'cats'),
          ),
        ),
        // 10 openWhoPick(true)：角色半屏管理态（九·补5「设置页行是管理态入口」）
        _row(
          '角色管理',
          LChip(
            label: '排序 · 改名 · 设默认 ›',
            onTap: () => showLWhoPick(context, value: d.whoDef, mg: true),
          ),
          sub: '记一笔「角色」半屏同源数据 · 当前默认「${d.whoDef}」',
        ),
        // 11 openTagPick(true)
        _row(
          '标签管理',
          LChip(
            label: '分组 + 标签 · 添加排序 ›',
            onTap: () => showLTagPick(context, selected: const [], mg: true),
          ),
        ),
        // 12 openMerchPick(true)
        _row(
          '商家管理',
          LChip(
            label: '添加 · 改名 · 删除 ›',
            onTap: () => showLMerchPick(context, mg: true),
          ),
        ),
        // 13 openQuickCfg()：quick_cats 4 入口宫格
        _row(
          '快速记一笔',
          LChip(
            label: '自定义 4 个入口 ›',
            onTap: () => showLedgerQuickCfgSheet(context),
          ),
          sub: '主页快速记一笔宫格展示的分类',
        ),
        // 14 openHeroCfg()：复用 S12 配置弹层（九·补7 草稿-保存制）
        _row(
          '自定义顶部卡片',
          LChip(
            label: '大数字 + 3 小槽 ›',
            onTap: () => showLedgerHeroCfgSheet(context),
          ),
          sub: '四处均可从今日/本周/本月/本年收支结余 · 预算 · 资产等 '
              '24 项指标中任选',
        ),
        // 15 navTo('p-export')（批3b 已开放）
        _row(
          '数据导出',
          LChip(
            label: 'CSV · JSON ›',
            onTap: () => ledgerNav(context, 'export'),
          ),
        ),
        // 16 location.reload()（Web 演示机制 → 真实版=重新载入数据，见 _reload）
        _row(
          '重置演示数据',
          LChip(label: '重新载入', onTap: _reload),
        ),
      ],
    );
  }

  // ---- 行/分段样式（原型 .card !py-3 !px-4 + seg-on 小药丸） ----

  Widget _row(String title, Widget ctrl, {String? sub}) => Container(
    margin: const EdgeInsets.only(bottom: 12), // space-y-3
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: context.cardDecoration,
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              if (sub != null) ...[
                const SizedBox(height: 2),
                Text(
                  sub,
                  style: const TextStyle(fontSize: 9, color: _slate),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        ctrl,
      ],
    ),
  );

  /// 分段（原型 flex rounded-full bg-slate-100 p-0.5 text-[10px] font-bold，
  /// 选中 seg-on=卡片底+accent 字+小投影；同 debt._segment 手法的小号版）。
  Widget _seg<T>(List<(T, String)> opts, T cur, ValueChanged<T> onPick) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (v, n) in opts)
            InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => onPick(v),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: v == cur ? scheme.surface : null,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: v == cur
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: .12),
                            blurRadius: 4,
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  n,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: v == cur ? tokens.accent : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ================= S11 快速记一笔入口（原型 sheetLedgerQuick · renderQuickCfg） =====

/// 速记入口配置半屏：支出大类宫格点选，**即时落库**（原型 qkTog 直改
/// L.set.quick + renderL1，无保存钮）；守卫=至少 1 / 最多 4（九·补5）。
Future<void> showLedgerQuickCfgSheet(BuildContext context) => showLSheet<void>(
  context,
  const _QuickCfgSheet(),
  heightFactor: .62,
);

class _QuickCfgSheet extends ConsumerStatefulWidget {
  const _QuickCfgSheet();

  @override
  ConsumerState<_QuickCfgSheet> createState() => _QuickCfgSheetState();
}

class _QuickCfgSheetState extends ConsumerState<_QuickCfgSheet> {
  static const _slate = Color(0xFF94A3B8);

  late List<int> _sel = [
    ...?ref.read(ledgerDataProvider).valueOrNull?.quickCats,
  ];

  LedgerRepository get _repo => ref.read(ledgerRepositoryProvider);

  void _toast(String m) {
    if (mounted) AppToast.show(context, m);
  }

  /// 原型 qkTog：已选→移除（末位守卫）；未选→加入（满 4 守卫）；即时落库。
  Future<void> _tog(int id) async {
    final next = [..._sel];
    if (next.contains(id)) {
      if (next.length <= 1) {
        _toast('至少保留 1 个快捷入口');
        return;
      }
      next.remove(id);
    } else {
      if (next.length >= 4) {
        _toast('最多 4 个快捷入口');
        return;
      }
      next.add(id);
    }
    await _repo.setQuickCats(next);
    if (!mounted) return;
    setState(() => _sel = next);
    ledgerTouch(ref);
  }

  @override
  Widget build(BuildContext context) {
    final d = ref.watch(ledgerDataProvider).valueOrNull;
    if (d == null) return const SizedBox.shrink();
    final majors = d.majors(LedgerCat.kExpense);
    final tokens = context.tokens;
    final w = (MediaQuery.sizeOf(context).width - 40 - 4 * 8) / 5;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LSheetHead(
            title: '快速记一笔入口',
            trailing: Text(
              '已选 ${_sel.length} / 4',
              style: const TextStyle(fontSize: 10, color: _slate),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in majors)
                    () {
                      final on = _sel.contains(c.id);
                      return SizedBox(
                        width: w,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => _tog(c.id),
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 140),
                            opacity: on ? 1 : .7,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: on
                                    ? tokens.accent.withValues(alpha: .1)
                                    : null,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: on
                                      ? tokens.accent
                                      : Theme.of(
                                          context,
                                        ).colorScheme.outlineVariant,
                                  width: 2,
                                ),
                              ),
                              child: Column(
                                children: [
                                  LTile(
                                    iconKey: c.icon,
                                    color: c.color,
                                    size: 36,
                                    radius: 12,
                                    iconSize: 18,
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    c.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: on ? tokens.accent : null,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (on) ...[
                                        Icon(
                                          LIcons.resolve('check'),
                                          size: 10,
                                          color: tokens.accent,
                                        ),
                                        const SizedBox(width: 2),
                                      ],
                                      Text(
                                        on ? '已选' : '点选',
                                        style: TextStyle(
                                          fontSize: 8,
                                          fontWeight: FontWeight.w700,
                                          color: on
                                              ? tokens.accent
                                              : _slate,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '点选切换 · 最多 4 个 · 主页快速记一笔按此渲染',
            style: TextStyle(fontSize: 10, color: _slate),
          ),
        ],
      ),
    );
  }
}
