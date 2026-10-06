import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backup/backup_files.dart';
import '../../../core/logging/app_log.dart';
import '../../../core/providers.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/ui_kit.dart';
import 'sync_backup_sheet.dart';

/// /settings/backup-files · B-1 备份文件管理屏（原型 `p-sub-backup` 对译）。
///
/// 规格唯一依据＝`docs/handoff/交棒话术-20261004-备份管理与图片预览批.md` §2 B-1＋§11。
/// 这一屏存在的理由＝**导入主通道**：云同步下载的 `.lhbak` 落在应用内部 `exports/`，
/// 系统选择器（SAF）逛不到那里，「下载下来的包选不到」＝换机恢复断最后一环。
/// 三条口径照工单红线：删除＝物理删**不进回收站**（文件面不混数据软删）；
/// 恢复＝复用 S5 的 校验→口令→二次确认→整库替换 链（不另造一套）；
/// 次通道「从其他位置选择」保留（公共存储里的包仍走 SAF）。
/// 确认弹式走公共原语 [lhConfirm]——批六已钉「确认版式全仓只一份」，此处不再造第二份。

/// 清单数据源（扫描器由 main 组合根注入，测试注入 fake：真实文件 I/O 不进 widget 测试）。
final backupFilesProvider = FutureProvider<List<BackupFileEntry>>(
    (ref) => ref.watch(backupFileScannerProvider).scan());

/// 来源角标配色（原型 BK_SRC：本地导出 sky／云端下载 violet／恢复前自动 amber）。
const _srcColor = {
  BackupFileSource.local: Color(0xFF0EA5E9),
  BackupFileSource.cloud: Color(0xFF8B5CF6),
  BackupFileSource.auto: Color(0xFFF59E0B),
};

class BackupFilesPage extends ConsumerStatefulWidget {
  const BackupFilesPage({super.key});

  @override
  ConsumerState<BackupFilesPage> createState() => _BackupFilesPageState();
}

class _BackupFilesPageState extends ConsumerState<BackupFilesPage> {
  bool _selMode = false;
  Set<String> _sel = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // 真机 6078 走查抓的缺陷：`backupFilesProvider` 是 app 作用域的 FutureProvider，
    // 值会跨屏驻留——刚导出的包／云上下好的包在本屏永远看不到（显示「0 包」），
    // 除非冷启动。进屏即失效重扫，屏才与磁盘一致。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.invalidate(backupFilesProvider);
    });
  }

  void _exitSel() => setState(() {
        _selMode = false;
        _sel.clear();
      });

  void _toast(String msg) {
    if (mounted) AppToast.show(context, msg);
  }

  void _tapRow(BackupFileEntry e) {
    if (!_selMode) return;
    setState(() => _sel.contains(e.path) ? _sel.remove(e.path) : _sel.add(e.path));
  }

  /// 长按进批量（与回收站同一定式：行内两钮收起，头部出「全选／删除 N 项」）。
  void _longPress(BackupFileEntry e) => setState(() {
        _selMode = true;
        _sel
          ..clear()
          ..add(e.path);
      });

  void _selAll(List<BackupFileEntry> visible) => setState(() {
        _sel = _sel.length == visible.length
            ? {}
            : visible.map((e) => e.path).toSet();
      });

  /// 恢复＝把该包送进 S5 既有校验链（预选路径，跳过系统选择器）。
  void _restore(BackupFileEntry e) {
    if (_busy) return;
    showBackupSheet(context, restorePath: e.path);
  }

  Future<void> _askDelete(List<BackupFileEntry> picked) async {
    if (picked.isEmpty || _busy) return;
    final bytes = picked.fold<int>(0, (t, e) => t + e.bytes);
    final auto = picked.where((e) => e.source == BackupFileSource.auto).length;
    // 后果逐条列清（物理删·不进回收站·不可恢复）；回滚资产单独警示。
    final msg = [
      '共 ${picked.length} 个文件 · ${(bytes / 1048576).toStringAsFixed(1)} MB',
      '物理删除 · 不进回收站 · 不可恢复',
      if (auto > 0)
        '其中 $auto 个是恢复前自动备份＝回滚资产，删掉后无法回退到那次恢复前的库',
    ].join('\n');
    final ok = await lhConfirm(context, msg, okLabel: '确认删除');
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final freed = await ref
          .read(backupFileScannerProvider)
          .purge(picked.map((e) => e.path).toList());
      // 破坏性动作落 key 行（L3 口径：日志页要能复盘删了什么、释放多少）。
      AppLog.addKey('备份文件删除：${picked.length} 个 · 释放 '
          '${(freed / 1048576).toStringAsFixed(1)} MB · '
          '${picked.map((e) => e.name).join('、')}');
      _exitSel();
      ref.invalidate(backupFilesProvider);
      _toast('已彻底删除 ${picked.length} 个备份文件 · '
          '${(freed / 1048576).toStringAsFixed(1)} MB 已释放');
    } catch (err) {
      _toast('删除失败，请重试');
      AppLog.add('备份文件删除异常：$err', level: LhLevel.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final entries = ref.watch(backupFilesProvider).valueOrNull ?? const [];
    final bytes = entries.fold<int>(0, (t, e) => t + e.bytes);
    final selItems = entries.where((e) => _sel.contains(e.path)).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('备份文件')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 2),
            child: Row(
              children: [
                Expanded(
                  child: Text.rich(
                    key: const ValueKey('bk-head'),
                    TextSpan(
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                      children: [
                        TextSpan(
                          text: '${entries.length} 包',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF475569)),
                        ),
                        if (entries.isNotEmpty)
                          TextSpan(
                              text: ' · 合计 '
                                  '${(bytes / 1048576).toStringAsFixed(1)} MB'),
                      ],
                    ),
                  ),
                ),
                if (_selMode)
                  TextButton(
                    key: const ValueKey('bk-all'),
                    onPressed: entries.isEmpty
                        ? null
                        : () => _selAll(entries),
                    child: Text(_sel.isNotEmpty && _sel.length == entries.length
                        ? '取消全选'
                        : '全选'),
                  ),
                TextButton(
                  key: const ValueKey('bk-pick'),
                  onPressed:
                      entries.isEmpty ? null : () => _toggleMode(entries),
                  child: Text(_selMode ? '取消' : '选择'),
                ),
                if (_selMode)
                  TextButton(
                    key: const ValueKey('bk-del-batch'),
                    onPressed: selItems.isEmpty ? null : () => _askDelete(selItems),
                    child: Text('删除 ${selItems.length} 项',
                        style: const TextStyle(
                            color: Color(0xFFF43F5E),
                            fontWeight: FontWeight.w800)),
                  ),
              ],
            ),
          ),
          Expanded(
            child: entries.isEmpty
                ? Center(
                    child: EmptyDashRow(
                      key: const ValueKey('bk-empty'),
                      text: '暂无备份文件',
                      onTap: () => showBackupSheet(context),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                    itemCount: entries.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _row(cs, entries[i]),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                key: const ValueKey('bk-second'),
                onPressed: _busy ? null : () => showBackupSheet(context),
                child: const Text('从其他位置选择', style: TextStyle(fontSize: 12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _toggleMode(List<BackupFileEntry> entries) {
    setState(() {
      _selMode = !_selMode;
      if (!_selMode) _sel.clear();
    });
  }

  Widget _row(ColorScheme cs, BackupFileEntry e) {
    final color = _srcColor[e.source]!;
    final checked = _sel.contains(e.path);
    return Container(
      key: ValueKey('bk-row-${e.name}'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: .4)),
      ),
      child: InkWell(
        onLongPress: () => _longPress(e),
        onTap: _selMode ? () => _tapRow(e) : null,
        child: Row(
          children: [
            if (_selMode)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Container(
                  key: ValueKey('bk-pick-${e.name}'),
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: checked ? color : cs.outlineVariant, width: 2),
                    color: checked ? color : Colors.transparent,
                  ),
                ),
              ),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.folder_zip_outlined, size: 18, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text.rich(
                    TextSpan(
                      style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                      children: [
                        TextSpan(text: '${e.sizeText} · ${e.timeText} · '),
                        TextSpan(
                          text: e.source.label,
                          style: TextStyle(
                              color: color, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (!_selMode) ...[
              TextButton(
                key: ValueKey('bk-restore-${e.name}'),
                onPressed: _busy ? null : () => _restore(e),
                child: const Text('恢复', style: TextStyle(fontSize: 12)),
              ),
              TextButton(
                key: ValueKey('bk-del-${e.name}'),
                onPressed: _busy ? null : () => _askDelete([e]),
                child: const Text('删除',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFF43F5E))),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
