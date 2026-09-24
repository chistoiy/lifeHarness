import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../data/ledger_repository.dart';
import '../domain/ledger_export.dart';
import '../domain/ledger_models.dart';
import 'ledger_providers.dart';

/// L15 数据导出（原型 p-export 1081~1083 行 + exp/renderExport 5381~5401 行；
/// TITLES ['数据导出','CSV · JSON'] 4675 行）。选项逐元素照抄：导出范围四 chip
/// （全部/按月/按账户/按分类）→ acct/cat 二级下拉 · 格式 seg（CSV · Excel 兼容 /
/// JSON · 完整字段）→ 预览卡（N 条流水 + 字段说明 + 「不含账户完整卡号，仅本机
/// 构建摘要」）→ 渐变导出钮「导出 N 条」。
///
/// 执行导出=流式落盘（计划书 §5 批3）：repo.exportTxnsPage 分页取数、
/// [writeLedgerExportFile] 逐页写 IOSink，不整表进内存；目录默认应用文档目录
/// （原型「下载目录」为演示口径），[dirOverride] 供测试注入临时目录。
/// toast 逐字原型 5400：`已导出 ${按月?finMonth:'全量'} 流水 · lifeharness_ledger.$fmt（路径）`。
/// 导入批次「撤销」入口：原型 p-export / p-lset 屏均未出现（仅步骤5 完成页与
/// 导入说明文案提及），本批无登记事项，撤销接线归批3c。
class LedgerExportPage extends ConsumerStatefulWidget {
  const LedgerExportPage({super.key, this.dirOverride});

  /// 导出目录提供者（null=生产：getApplicationDocumentsDirectory；测试注入临时目录）。
  final Future<String> Function()? dirOverride;

  @override
  ConsumerState<LedgerExportPage> createState() => _LedgerExportPageState();
}

class _LedgerExportPageState extends ConsumerState<LedgerExportPage> {
  /// 原型 exp 状态（5381）：默认 scope=all / fmt=csv；acct、cat 预选在首帧
  /// 数据就绪时取默认账户与首个支出大类（原型 'debit'/'food' 同位）。
  String _scope = 'all';
  String _fmt = 'csv';
  int? _acctId;
  int? _catId;
  bool _busy = false;

  LedgerRepository get _repo => ref.read(ledgerRepositoryProvider);

  void _toast(String m) => AppToast.show(context, m);

  /// 查看月（原型 finMonth，L1 与顶部卡共用 [ledgerMonthProvider]）。
  String get _month => ref.read(ledgerMonthProvider);

  Future<void> _run(LedgerData d) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final dir = await widget.dirOverride?.call() ??
          (await getApplicationDocumentsDirectory()).path;
      final r = await writeLedgerExportFile(
        dir: dir,
        fmt: _fmt,
        pageSize: 200,
        fetchPage: (offset, limit) => _repo.exportTxnsPage(
          d.curBook.id,
          month: _scope == 'month' ? _month : null,
          accountId: _scope == 'acct' ? _acctId : null,
          catId: _scope == 'cat' ? _catId : null,
          offset: offset,
          limit: limit,
        ),
        catName: (id) => d.catOf(id).name,
        acctName: (id) => d.acct(id)?.name ?? '?',
      );
      if (mounted) {
        _toast('已导出 ${_scope == 'month' ? _month : '全量'} 流水 · '
            'lifeharness_ledger.$_fmt（${r.path}）');
      }
    } catch (e) {
      if (mounted) _toast('导出失败 · $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = ref.watch(ledgerDataProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('数据导出'),
            Text(
              'CSV · JSON',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.normal),
            ),
          ],
        ),
      ),
      body: d == null
          ? const Center(child: CircularProgressIndicator())
          : _body(d),
    );
  }

  Widget _body(LedgerData d) {
    // 原型 exp.acct='debit' / exp.cat='food' 预选位：默认账户 / 首个支出大类。
    _acctId ??= d.defAcctId ?? d.accounts.firstOrNull?.id;
    final cats =
        d.majors(LedgerCat.kExpense).where((c) => !c.hidden).toList();
    _catId ??= cats.firstOrNull?.id;

    final ts = ledgerExportScope(
      txns: d.txns,
      scope: _scope,
      month: _month,
      acctId: _acctId,
      catId: _catId,
    );
    final scheme = Theme.of(context).colorScheme;
    final accent = context.tokens.accent;

    Widget pickChip(String label, bool on, VoidCallback onTap) => InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(
                  color: on ? accent : scheme.outlineVariant, width: 1.5),
              borderRadius: BorderRadius.circular(12),
              color: on ? accent.withValues(alpha: .08) : null,
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: on ? accent : scheme.onSurfaceVariant,
              ),
            ),
          ),
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      children: [
        // ---- 导出范围 + 格式（原型 5389~5397 行） ----
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: context.cardDecoration,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('导出范围',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final (i, (k, n)) in kLedgerExportScopes.indexed) ...[
                    if (i > 0) const SizedBox(width: 5),
                    Expanded(
                      child: pickChip(n, _scope == k,
                          () => setState(() => _scope = k)),
                    ),
                  ],
                ],
              ),
              if (_scope == 'acct') ...[
                const SizedBox(height: 8),
                DropdownButton<int>(
                  value: _acctId,
                  isExpanded: true,
                  isDense: true,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final a in d.accounts)
                      DropdownMenuItem(
                          value: a.id,
                          child: Text(a.name,
                              style: const TextStyle(fontSize: 12))),
                  ],
                  onChanged: (v) => setState(() => _acctId = v),
                ),
              ],
              if (_scope == 'cat') ...[
                const SizedBox(height: 8),
                DropdownButton<int>(
                  value: _catId,
                  isExpanded: true,
                  isDense: true,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final c in cats)
                      DropdownMenuItem(
                          value: c.id,
                          child: Text(c.name,
                              style: const TextStyle(fontSize: 12))),
                  ],
                  onChanged: (v) => setState(() => _catId = v),
                ),
              ],
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  children: [
                    for (final (k, n) in const [
                      ('csv', 'CSV · Excel 兼容'),
                      ('json', 'JSON · 完整字段'),
                    ])
                      Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(999),
                          onTap: () => setState(() => _fmt = k),
                          child: Container(
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            decoration: BoxDecoration(
                              color: _fmt == k ? scheme.surface : null,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              n,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: _fmt == k
                                    ? accent
                                    : scheme.onSurfaceVariant,
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
        ),
        const SizedBox(height: 12),
        // ---- 预览（原型 5398~5399 行逐字） ----
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: context.cardDecoration,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('预览',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(
                '${ts.length} 条流水 · ${ledgerFieldNote(_fmt)}\n'
                '不含账户完整卡号，仅本机构建摘要',
                style: const TextStyle(
                    fontSize: 11, color: Color(0xFF94A3B8), height: 1.9),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // ---- 导出钮（原型 5400 行 grad 钮「导出 N 条」） ----
        Opacity(
          opacity: _busy ? .5 : 1,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _busy ? null : () => _run(d),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                gradient: context.tokens.gradient,
                borderRadius: BorderRadius.circular(16),
              ),
              alignment: Alignment.center,
              child: Text(
                '导出 ${ts.length} 条',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
