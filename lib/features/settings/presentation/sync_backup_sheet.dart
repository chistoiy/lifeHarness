import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/backup/lh_bak.dart';
import '../../../core/logging/app_log.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart';
import 'export_sheet.dart';

/// V1.41 Task 10 · S5「备份导出/导入」半屏（原型 index-sync.html s-backup）。
///
/// 口径（R6 真机反馈修正 + V1.66 批2·需求清单「新包纯明文」）：
/// - 导出：范围勾选（附件/日志）+「导出数据…」开范围面板 showExportSheet
///   （export_sheet.dart·模块 chips × 格式两档 × 预估体积，原型 sheetExport）；
///   「另存到…」= 快速全量导出（带投影成员）再经 saveCopyToUserLocation 弹
///   系统保存层，取消不追加任何后续调用；成功 toast「已导出：<文件名>」。
///   **口令入口已下架**（导出恒明文·纯明文落 UI）；导入侧口令分支保留
///   （旧口令加密包恢复兼容，红线）。
/// - 导入：pickBackupFile → inspect 校验报告态（含 skippedLarge「N 个超大
///   附件未入包」行）→ 勾选「恢复将替换当前数据」二次确认 → 才可调
///   importBackup（恢复按钮置于确认勾选之后）；恢复报告补「口径设置已还原」。
/// - 文案一律功能标签式，无教学句（UI 规范）。
Future<void> showBackupSheet(BuildContext context, {String? restorePath}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => BackupSheet(restorePath: restorePath),
  );
}

/// S5 弹层组件（/sync 空壳页与批5 同步主页共用入口）。
///
/// B-1：[restorePath] 非空＝从「备份文件」屏带着某个包进来——跳过系统选择器，
/// 直接落进既有的 **校验 → 口令 → 二次确认 → 整库替换** 链（同一套 UI 与文案，不另造一份）。
class BackupSheet extends ConsumerStatefulWidget {
  const BackupSheet({super.key, this.restorePath});

  /// 预选包的绝对路径（null＝走原「选择 .lhbak 文件」路径）。
  final String? restorePath;

  @override
  ConsumerState<BackupSheet> createState() => _BackupSheetState();
}

class _BackupSheetState extends ConsumerState<BackupSheet> {
  bool _withAttach = true;
  bool _withLogs = true;
  bool _busy = false;

  /// 轮7：「正在导出…」只跟导出动作本身。_busy 是整屏共用（导出/选择/校验/
  /// 恢复都置位），此前导入校验期间导出钮也显示「正在导出…」＝误导（真机反馈）。
  bool _exporting = false;

  // 导入侧状态
  final TextEditingController _importPass = TextEditingController();
  String? _pickedPath;
  LhBakManifest? _manifest;
  String? _verifyError; // 非 needPassphrase 的校验失败 code

  /// F-10（方案 A·产品 2026-10-07 点头）：从「备份文件」屏带包进来＝为了恢复，
  /// 但本面板上半屏是导出段，校验卡沉在最底＝进来先看到不相干的一半。
  /// 校验成功后把校验卡滚到可见（导出段仍在，往上滑就是，不拆第二种形态）。
  final GlobalKey _verifyCardKey = GlobalKey();
  bool _needPass = false;
  bool _confirmed = false;

  @override
  void initState() {
    super.initState();
    final path = widget.restorePath;
    if (path == null) return;
    _pickedPath = path;
    // 帧后再校验：校验要读盘解包，且在 initState 里跑异步会撞上弹层尚未挂载。
    WidgetsBinding.instance.addPostFrameCallback((_) => _verify());
  }

  @override
  void dispose() {
    _importPass.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (mounted) AppToast.show(context, msg);
  }

  /// 快速全量导出（「另存到…」路径；V1.66 起恒明文＋带投影成员）。
  Future<void> _doExport({bool alsoSave = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _exporting = true;
    });
    final svc = ref.read(backupServiceProvider);
    String? srcPath;
    try {
      final res = await svc.exportBackup(
        withLogs: _withLogs,
        withAttachments: _withAttach,
        withProjection: true,
      );
      _toast('已导出：${p.basename(res.file.path)}');
      srcPath = res.file.path;
    } on LhBakException catch (e) {
      _toast('导出失败：${e.code}');
    } catch (e) {
      // 轮6：非容器类导出异常同样必须可见（此前顺 async 通道蒸发）。
      _toast('导出失败，详情见日志');
      AppLog.add('备份导出异常（弹层兜底）：$e', level: LhLevel.error);
    }
    if (mounted) setState(() => _exporting = false);
    if (alsoSave && srcPath != null) {
      try {
        final saved = await svc.saveCopyToUserLocation(srcPath);
        _toast(saved == null
            ? '另存已取消 · 包保留在应用导出目录'
            : '已另存：$saved');
      } catch (e) {
        // 轮6：系统保存层失败（provider 无输出流等）不再静默。
        _toast('另存失败，包仍保留在应用导出目录');
        AppLog.add('备份另存异常：$e', level: LhLevel.error);
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _doPick() async {
    if (_busy) return;
    setState(() => _busy = true);
    final svc = ref.read(backupServiceProvider);
    try {
      final path = await svc.pickBackupFile();
      if (path == null) return; // 取消选择：静默回原态
      setState(() {
        _pickedPath = path;
        _manifest = null;
        _verifyError = null;
        _needPass = false;
        _confirmed = false;
      });
      await _verify();
    } catch (e) {
      // 2026-10-04 缺陷根治配套：选择器异常必须可见（此前 PlatformException
      // 顺 async 通道蒸发＝「点了没反应」）。人话提示＋技术细节落日志页。
      _toast('系统选择器打开失败，请重试');
      AppLog.add('备份选择器异常：$e', level: LhLevel.warn);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    final path = _pickedPath;
    if (path == null) return;
    final svc = ref.read(backupServiceProvider);
    final pass = _importPass.text.isEmpty ? null : _importPass.text;
    try {
      final m = await svc.inspect(path, passphrase: pass);
      if (!mounted) return;
      setState(() {
        _manifest = m;
        _verifyError = null;
        _needPass = false;
        _confirmed = false;
      });
      // F-10：带包进来（restorePath 非空）＝目标是恢复，校验卡滚到可见。
      if (widget.restorePath != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = _verifyCardKey.currentContext;
          if (!mounted || ctx == null) return;
          Scrollable.ensureVisible(ctx,
              alignment: 0.08,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut);
        });
      }
    } on LhBakException catch (e) {
      if (!mounted) return;
      setState(() {
        _manifest = null;
        _needPass = e.code == LhBakException.codeNeedPassphrase;
        _verifyError = _needPass ? null : e.code;
      });
    }
  }

  Future<void> _doRestore() async {
    final path = _pickedPath;
    final m = _manifest;
    if (path == null || m == null || !_confirmed || _busy) return;
    setState(() => _busy = true);
    final svc = ref.read(backupServiceProvider);
    try {
      final report = await svc.importBackup(
          path,
          passphrase: _importPass.text.isEmpty ? null : _importPass.text);
      _toast('恢复完成：${report.tableCount} 表 · ${report.totalRows} 行'
          '${report.configRestored ? ' · 口径设置已还原（部分项重启后生效）' : ''}');
    } on LhBakException catch (e) {
      _toast('恢复失败：${e.code}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final svc = ref.read(backupServiceProvider);
    final m = _manifest;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('备份导出/导入',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text('可读的包 · db.sqlite 权威 · md 投影 · 口径设置 · 纯明文',
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 14),
            // ---- 导出范围 ----
            const Text('导出范围',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
              value: true,
              onChanged: null,
              title: const Text('数据库快照 db.sqlite',
                  style: TextStyle(fontSize: 13)),
            ),
            CheckboxListTile(
              key: const ValueKey('chk-attach'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
              value: _withAttach,
              onChanged: (v) => setState(() => _withAttach = v ?? true),
              title: const Text('附件 attachments/',
                  style: TextStyle(fontSize: 13)),
            ),
            CheckboxListTile(
              key: const ValueKey('chk-logs'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
              value: _withLogs,
              onChanged: (v) => setState(() => _withLogs = v ?? true),
              title: const Text('附带日志 logs/', style: TextStyle(fontSize: 13)),
            ),
            // ---- 上次另存目标（仅展示，R6：目标位置两态行已并入按钮语义）----
            const SizedBox(height: 6),
            if (svc.lastSaveHint != null)
              Text('上次另存：${p.basename(svc.lastSaveHint!)}',
                  style: const TextStyle(fontSize: 10.5, color: Colors.grey)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('btn-export'),
                    onPressed: _busy
                        ? null
                        : () => showExportSheet(context,
                            withLogs: _withLogs),
                    // V1.66 批2：主钮开范围面板（原型 sheetExport 口径）；
                    // _exporting 只属「另存到…」的快速全量路径。
                    child: Text(_exporting ? '正在导出…' : '导出数据…'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('btn-export-save'),
                    onPressed:
                        _busy ? null : () => _doExport(alsoSave: true),
                    child: const Text('另存到…'),
                  ),
                ),
              ],
            ),
            const Divider(height: 28),
            // ---- 导入恢复 ----
            const Text('导入恢复',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const ValueKey('btn-pick-backup'),
              onPressed: _busy ? null : _doPick,
              child: const Text('选择 .lhbak 文件'),
            ),
            if (_verifyError != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('校验失败：$_verifyError',
                    style: const TextStyle(
                        fontSize: 11.5, color: Color(0xFFDC2626))),
              ),
            if (_needPass) ...[
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('加密包需口令',
                    style: TextStyle(fontSize: 11.5, color: Color(0xFFF59E0B))),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('import-pass'),
                      controller: _importPass,
                      obscureText: true,
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                          labelText: '口令', isDense: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const ValueKey('btn-verify-import'),
                    onPressed: _busy ? null : _verify,
                    child: const Text('校验'),
                  ),
                ],
              ),
            ],
            if (m != null) ...[
              const SizedBox(height: 10),
              Container(
                key: _verifyCardKey,
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: tokens.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: tokens.cardBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                              p.basename(_pickedPath ?? ''),
                              style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'monospace')),
                        ),
                        const Text('manifest 校验通过',
                            style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF10B981))),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text('${m.tables.length} 表 · '
                        '${m.tables.values.fold<int>(0, (a, t) => a + t.rows)} 行',
                        style: const TextStyle(fontSize: 11.5)),
                    if (m.excludedTables.isNotEmpty)
                      Text('排除表：${m.excludedTables.join('、')}',
                          style: const TextStyle(fontSize: 11.5)),
                    if (m.encrypted)
                      const Text('已加密', style: TextStyle(fontSize: 11.5)),
                    if ((m.skippedLarge?.isNotEmpty ?? false))
                      Text('${m.skippedLarge!.length} 个超大附件未入包',
                          style: const TextStyle(
                              fontSize: 11.5, color: Color(0xFFF59E0B))),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Checkbox(
                          key: const ValueKey('confirm-restore'),
                          value: _confirmed,
                          onChanged: (v) =>
                              setState(() => _confirmed = v ?? false),
                        ),
                        const Expanded(
                          child: Text('恢复将替换当前数据',
                              style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            key: const ValueKey('btn-restore'),
                            onPressed:
                                (_confirmed && !_busy) ? _doRestore : null,
                            child: const Text('恢复整库'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
