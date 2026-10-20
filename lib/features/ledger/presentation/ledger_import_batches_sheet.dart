import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/app_log.dart';
import '../../../shared/widgets/ui_kit.dart';
import 'ledger_providers.dart';

/// R15-1 / V1.56 导入记录与整批撤销（原型 `sheetLedgerBatches` + `sheetLedgerUndo`）。
///
/// 三项拍板（2026-09-30）：入口＝完成页钮＋本列表两处都要 · 账户回收＝默认不勾（给勾选项）·
/// 可撤销范围＝**仅最近一批**（列表倒序后只有首行挂撤销钮，旧批只读）。
///
/// 撤销语义照 `LedgerRepository.undoImportBatch` 既有实现，本文件只加 UI 与 key 行日志：
/// 删本批流水 → 按档回收「本批新建 且 已无流水引用 且 余额 0」的账户 → 删批次行 → 重算余额。
Future<void> showLedgerImportBatches(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .72,
      ),
      builder: (_) => const _Batches(),
    );

/// 「导入记录 · N 批 ›」行（原型 biHome 与导入完成屏同款入口，两处共用）。
class LedgerImportRecordsRow extends ConsumerWidget {
  const LedgerImportRecordsRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      key: const ValueKey('lib-open'),
      borderRadius: BorderRadius.circular(16),
      onTap: () => showLedgerImportBatches(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: .35),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                '导入记录',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
            ),
            FutureBuilder<List<Map<String, Object?>>>(
              key: const ValueKey('lib-count'),
              future: ref.watch(ledgerRepositoryProvider).importBatches(),
              builder: (_, s) => Text(
                (s.data ?? const []).isEmpty ? '' : '${s.data!.length} 批',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 18, color: scheme.outline),
          ],
        ),
      ),
    );
  }
}

/// 单批撤销的二次确认弹层（列表页与导入完成页共用同一形制）。
Future<String?> showLedgerUndoSheet(
  BuildContext context,
  Map<String, Object?> batch,
) => showModalBottomSheet<String>(
  context: context,
  backgroundColor: Theme.of(context).colorScheme.surface,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (_) => _Undo(batch: batch),
);

/// 导入完成页的「撤销本批」钮（原型 biDone 主描边红钮）。
/// 撤完由 [onUndone] 回报文案并让页面回第 1 步；批次已被别处撤掉时如实提示。
class LedgerImportUndoButton extends ConsumerWidget {
  const LedgerImportUndoButton({
    super.key,
    required this.batchId,
    this.onUndone,
  });

  final int? batchId;
  final void Function(String msg)? onUndone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return OutlinedButton(
      key: const ValueKey('li-undo'),
      onPressed: batchId == null
          ? null
          : () async {
              final rows = await ref
                  .read(ledgerRepositoryProvider)
                  .importBatches();
              if (!context.mounted) return;
              Map<String, Object?>? b;
              for (final r in rows) {
                if (r['id'] == batchId) b = r;
              }
              if (b == null) {
                AppToast.show(context, '该批次已不可撤销');
                return;
              }
              final msg = await showLedgerUndoSheet(context, b);
              if (msg != null) onUndone?.call(msg);
            },
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFFEF4444),
        side: const BorderSide(color: Color(0xFFFCA5A5)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: const Text('撤销本批'),
    );
  }
}

class _Batches extends ConsumerStatefulWidget {
  const _Batches();

  @override
  ConsumerState<_Batches> createState() => _BatchesState();
}

class _BatchesState extends ConsumerState<_Batches> {
  List<Map<String, Object?>> _rows = const [];
  String? _status;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await ref.read(ledgerRepositoryProvider).importBatches();
    if (mounted) setState(() => _rows = rows);
  }

  Future<void> _undo(Map<String, Object?> b) async {
    final r = await showLedgerUndoSheet(context, b);
    if (r == null || !mounted) return;
    // 撤完留在列表：行消失、撤销钮下移到新的最近一批——条数变化当场可见。
    setState(() => _status = r);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final newest = _rows.isEmpty ? null : _rows.first['id'];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
        child: Column(
          key: const ValueKey('sheetLedgerBatches'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text(
              '导入记录',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
            if (_status != null)
              Padding(
                key: const ValueKey('lib-status'),
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _status!,
                  style: TextStyle(fontSize: 11.5, color: scheme.primary),
                ),
              ),
            Flexible(
              child: _rows.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 28),
                      child: Center(
                        child: Text(
                          '暂无导入记录',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: _rows.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, i) =>
                          _row(_rows[i], _rows[i]['id'] == newest),
                    ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('关闭'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(Map<String, Object?> b, bool canUndo) {
    final scheme = Theme.of(context).colorScheme;
    final made = _ids(b['new_account_ids']);
    return Container(
      key: ValueKey('lib-row-${b['id']}'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (b['file_name'] as String?)?.isNotEmpty == true
                      ? b['file_name'] as String
                      : '账单文件',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${b['platform']} · ${_ts(b['created_at'])} · 写入 ${b['written']} 条'
                  '${made.isEmpty ? '' : ' · 新建账户 ${made.length} 个'}',
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          // 可撤销范围＝仅最近一批（2026-09-30 拍板）；旧批只读，不给钮也不写解释句。
          if (canUndo)
            OutlinedButton(
              key: ValueKey('lib-undo-${b['id']}'),
              onPressed: () => _undo(b),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFEF4444),
                side: const BorderSide(color: Color(0xFFFCA5A5)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              child: const Text('撤销', style: TextStyle(fontSize: 12.5)),
            ),
        ],
      ),
    );
  }
}

class _Undo extends ConsumerStatefulWidget {
  const _Undo({required this.batch});

  final Map<String, Object?> batch;

  @override
  ConsumerState<_Undo> createState() => _UndoState();
}

class _UndoState extends ConsumerState<_Undo> {
  bool _reclaim = false;

  List<int> get _made => _ids(widget.batch['new_account_ids']);

  Future<void> _yes() async {
    final id = widget.batch['id']! as int;
    final repo = ref.read(ledgerRepositoryProvider);
    final had = (await repo.accounts(
      includeArchived: true,
    )).map((a) => a.id).toSet();
    final n = await repo.undoImportBatch(id, reclaimAccounts: _reclaim);
    final left = (await repo.accounts(
      includeArchived: true,
    )).map((a) => a.id).toSet();
    final m = _made.where((x) => had.contains(x) && !left.contains(x)).length;
    AppLog.addKey('账单整批撤销：批次 $id · 删流水 $n 条 · 回收账户 $m 个');
    ledgerTouch(ref);
    if (!mounted) return;
    Navigator.of(
      context,
    ).pop('已撤销批次 $id · 删除 $n 条流水${m == 0 ? '' : ' · 移除 $m 个账户'}');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final b = widget.batch;
    return SafeArea(
      child: Padding(
        key: const ValueKey('sheetLedgerUndo'),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '撤销本批导入',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              '将删除 ${b['written']} 条流水 · ${b['platform']} · '
              '${(b['file_name'] as String?)?.isNotEmpty == true ? b['file_name'] : '账单文件'}',
              style: const TextStyle(fontSize: 12.5, height: 1.6),
            ),
            Text(
              '报表、分类占比与资产页同步重算',
              style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
            ),
            if (_made.isNotEmpty)
              CheckboxListTile(
                key: const ValueKey('lib-reclaim'),
                value: _reclaim,
                onChanged: (v) => setState(() => _reclaim = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text(
                  '同时移除本批新建且已无引用的账户',
                  style: TextStyle(fontSize: 12.5),
                ),
                subtitle: Text(
                  '本批新建账户 ${_made.length} 个',
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    key: const ValueKey('lib-yes'),
                    onPressed: _yes,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFEF4444),
                    ),
                    child: const Text('确认撤销'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 批次新建账户 id 列表（`new_account_ids` 列存 JSON 数组文本）。
List<int> _ids(Object? raw) {
  if (raw is! String || raw.isEmpty) return const [];
  try {
    final l = jsonDecode(raw);
    return l is List ? l.whereType<int>().toList() : const [];
  } on FormatException {
    AppLog.add('导入批次 new_account_ids 解析失败：$raw', level: LhLevel.warn);
    return const [];
  }
}

/// 批次时间显示口径 `MM-dd HH:mm`（列表副行）。
String _ts(Object? ms) {
  if (ms is! int) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  String p(int n) => n.toString().padLeft(2, '0');
  return '${p(d.month)}-${p(d.day)} ${p(d.hour)}:${p(d.minute)}';
}
