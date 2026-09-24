import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../data/ledger_repository.dart';
import '../domain/ledger_models.dart';
import 'ledger_providers.dart';
import 'widgets/ledger_kit.dart';

/// 记账后续批次入口的统一去向（保真：入口不删，未开放者仅提示）。
/// 已开放：/ledger/import（批1d）、/ledger/report 与 /ledger/yearly（批2a）、
/// /ledger/budget（批2b）、/ledger/assets（批2c·L6/L7）、
/// /ledger/cats 与 /ledger/recur（批2d·L8/L9）、/ledger/wish 与 /ledger/debt
/// （批3a·L10/L11）、/ledger/search 与 /ledger/export（批3b·L12/L15）；
/// 其余按计划 §5 批3 落地后补映射。
void ledgerNav(BuildContext context, String key) {
  const done = <String, String>{
    'import': '/ledger/import',
    'report': '/ledger/report',
    'yearly': '/ledger/yearly',
    'budget': '/ledger/budget',
    'assets': '/ledger/assets',
    'cats': '/ledger/cats',
    'recur': '/ledger/recur',
    'wish': '/ledger/wish',
    'debt': '/ledger/debt',
    'search': '/ledger/search',
    'export': '/ledger/export',
  };
  const names = {
    'cats': '分类管理',
    'wish': '心愿单',
    'debt': '借出 · 借入',
    'search': '搜索流水',
    'import': '账单导入',
    'export': '数据导出',
    'yearly': '年度总结',
    'lset': '记账设置',
    'assets': '资产',
    'budget': '预算中心',
    'report': '统计报表',
    'recur': '周期账单',
  };
  final r = done[key];
  if (r != null) {
    context.push(r);
    return;
  }
  AppToast.show(context, '${names[key] ?? key} · 即将开放');
}

/// sheetLedgerMore：记账管理八宫格（原型 grid-cols-4 · 4×2）。
Future<void> showLedgerMoreSheet(BuildContext context) => showLSheet<void>(
  context,
  Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const LSheetHead(title: '记账管理'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (k, ic, n) in const [
              ('cats', 'tag', '分类管理'),
              ('wish', 'star', '心愿单'),
              ('debt', 'arrows', '借出·借入'),
              ('search', 'search', '搜索筛选'),
              ('import', 'dl', '账单导入'),
              ('export', 'copy', '数据导出'),
              ('yearly', 'cal', '年度总结'),
              ('lset', 'gear', '记账设置'),
            ])
              SizedBox(
                width: (MediaQuery.sizeOf(context).width - 40 - 3 * 8) / 4,
                child: Container(
                  decoration: context.cardDecoration,
                  child: LFuncBtn(
                    iconKey: ic,
                    label: n,
                    fg: Theme.of(context).colorScheme.onSurface,
                    onTap: () {
                      Navigator.pop(context);
                      ledgerNav(context, k);
                    },
                  ),
                ),
              ),
          ],
        ),
      ],
    ),
  ),
  heightFactor: .55,
);

/// S7 账本切换/管理（原型 sheetLedgerBooks）。
Future<void> showLedgerBooksSheet(BuildContext context) =>
    showLSheet<void>(context, const _BooksSheet(), heightFactor: .68);

class _BooksSheet extends ConsumerStatefulWidget {
  const _BooksSheet();

  @override
  ConsumerState<_BooksSheet> createState() => _BooksSheetState();
}

class _BooksSheetState extends ConsumerState<_BooksSheet> {
  LedgerRepository get _repo => ref.read(ledgerRepositoryProvider);

  void _toast(String m) => AppToast.show(context, m);

  void _tick() => ref.read(ledgerTickProvider.notifier).state++;

  Future<String?> _askName({String? initial}) async {
    final ctl = TextEditingController(text: initial ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (bc) => AlertDialog(
        title: Text(initial == null ? '新建账本' : '账本名称'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          maxLength: 12,
          decoration: const InputDecoration(counterText: ''),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(bc, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(bc, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    final n = ctl.text.trim();
    ctl.dispose();
    return (ok == true && n.isNotEmpty) ? n : null;
  }

  Future<void> _add() async {
    final n = await _askName();
    if (n == null) return;
    final id = await _repo.addBook(n);
    await _repo.setCurBook(id);
    _tick();
    _toast('已创建并进入「$n」');
  }

  Future<void> _rename(LedgerBook b) async {
    final n = await _askName(initial: b.name);
    if (n == null) return;
    await _repo.renameBook(b.id, n);
    _tick();
  }

  Future<void> _del(LedgerBook b) async {
    final r = await _repo.delBook(b.id);
    _tick();
    if (r.txns == -1) {
      _toast('至少保留一个账本');
    } else if (r.txns > 0) {
      _toast('「${b.name}」还有 ${r.txns} 笔流水 · 不能删除');
    }
  }

  Future<void> _pick(LedgerBook b) async {
    await _repo.setCurBook(b.id);
    _tick();
    if (mounted) Navigator.pop(context);
    final d = ref.read(ledgerDataProvider).valueOrNull;
    _toast('已切换到「${d?.curBook.name ?? b.name}」· 账本间流水独立');
  }

  @override
  Widget build(BuildContext context) {
    final d = ref.watch(ledgerDataProvider).valueOrNull;
    if (d == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LSheetHead(title: '我的账本'),
          const SizedBox(height: 8),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final b in d.books)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    decoration: BoxDecoration(
                      color: b.id == d.curBook.id
                          ? context.tokens.accent.withValues(alpha: .07)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => _pick(b),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 10,
                              ),
                              child: Row(
                                children: [
                                  const LTile(
                                    iconKey: 'book',
                                    color: '#6366f1',
                                    size: 32,
                                    radius: 11,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          b.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        Text(
                                          '${d.txnsOfBook(b.id)} 笔流水 · 账户共用',
                                          style: TextStyle(
                                            fontSize: 9,
                                            color: scheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (b.id == d.curBook.id)
                                    Icon(
                                      LIcons.resolve('check'),
                                      size: 16,
                                      color: context.tokens.accent,
                                    ),
                                  const SizedBox(width: 4),
                                ],
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: '重命名',
                          icon: Icon(
                            LIcons.resolve('edit'),
                            size: 16,
                            color: scheme.onSurfaceVariant,
                          ),
                          onPressed: () => _rename(b),
                        ),
                        IconButton(
                          tooltip: '删除',
                          icon: Icon(
                            LIcons.resolve('trash'),
                            size: 16,
                            color: scheme.onSurfaceVariant,
                          ),
                          onPressed: () => _del(b),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          EmptyDashRow(text: '＋ 新建账本', onTap: _add),
        ],
      ),
    );
  }
}
