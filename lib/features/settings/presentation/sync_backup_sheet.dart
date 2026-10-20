import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/backup/lh_bak.dart';
import '../../../core/logging/app_log.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/linkage/export_units.dart';
import '../../../shared/widgets/ui_kit.dart';
import 'export_sheet.dart';

/// 同语义色同源（doclint 守护十色值棘轮）：与 export_sheet 的 _amber 同值。
const Color _amber = Color(0xFFB45309);

/// V1.41 Task 10 · S5「备份导出/导入」半屏（原型 index-sync.html s-backup）。
///
/// 口径（R6 真机反馈修正 + V1.66 批2/装机回知批·需求清单「新包纯明文」）：
/// - 导出：范围勾选（附件/日志）+「导出数据…」开范围面板 showExportSheet
///   （export_sheet.dart·模块 chips × 格式两档 × 预估体积 × ④导出位置）；
///   **「另存到…」已下架**（装机回知批：导出位置持久目录树直达取代，
///   快速全量路径连同 saveCopyToUserLocation 调用面一并撤）。口令入口已下架
///   （导出恒明文）；导入侧口令分支保留（旧口令加密包恢复兼容，红线）。
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

  /// 余量批4：校验通过时一并解出的范围（null＝全量包/老包 → 整库替换）。
  LhBakRestoreScope? _scope;

  /// 恢复钮与确认语的文案随范围切换（全量＝原口径一字不动）。
  bool get _partial => _scope != null;

  /// 覆盖范围的人话（模块标签，长度受限——恢复前必须能一眼看完）。
  String get _scopeLabels {
    final s = _scope;
    if (s == null) return '';
    final labels = [
      for (final id in s.moduleIds) _unitLabel(id),
    ];
    return labels.join('、');
  }

  static String _unitLabel(String id) {
    for (final u in kExportUnits) {
      if (u.id == id) return u.label;
    }
    return id;
  }

  /// `2026-10-15` 形式（只给 UI 看区间，不带时分——时分对「覆盖范围」无意义）。
  static String _dateOf(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

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
      // 余量批4：范围在校验态就解出来——恢复前必须能说出「会覆盖哪几个
      // 模块」，而不是等按了恢复才知道。解析失败（认不出的模块 id）按
      // 校验失败处理：现库不动，用户看得见原因。
      LhBakRestoreScope? scope;
      String? scopeError;
      try {
        scope = LhBakRestoreScope.fromManifest(m);
      } on LhBakException catch (e) {
        scopeError = '${e.code}：${e.message}';
      }
      if (scopeError != null) {
        setState(() {
          _manifest = null;
          _scope = null;
          _needPass = false;
          _verifyError = '范围无法识别（${scopeError!}）';
        });
        return;
      }
      setState(() {
        _manifest = m;
        _scope = scope;
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
        _scope = null;
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
      _toast(
          '恢复完成：${report.tableCount} 表 · ${report.totalRows} 行'
          '${report.isPartial ? ' · 仅覆盖 ${report.scopeModules.map(_unitLabel).join("、")}' : ''}'
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
            // V1.66 装机回知批：「另存到…」下架（导出位置直达取代·「上次另存」
            // 展示行随之撤）——主钮全宽开范围面板，落盘位置由面板④段决定。
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const ValueKey('btn-export'),
                onPressed: _busy
                    ? null
                    : () => showExportSheet(context, withLogs: _withLogs),
                child: const Text('导出数据…'),
              ),
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
                    style: TextStyle(fontSize: 11.5, color: _amber)),
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
                              fontSize: 11.5, color: _amber)),
                    // ---- 余量批4：覆盖范围（AGENTS「点了必须有看得见的
                    // 变化」——恢复前必须说清会覆盖什么、能不能退回）----
                    if (_partial) ...[
                      const SizedBox(height: 8),
                      Container(
                        key: const ValueKey('restore-scope-note'),
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: tokens.cardBorder.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('本次只覆盖：$_scopeLabels',
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text(
                                '其余模块数据保持不动'
                                '${_scope!.from != null ? ' · 包内数据限定 '
                                    '${_dateOf(_scope!.from!)}~${_dateOf(_scope!.to ?? _scope!.from!)}' : ''}',
                                style: const TextStyle(fontSize: 11.5)),
                            const SizedBox(height: 2),
                            const Text(
                                '这几个模块本机数据将被包内版本覆盖 · 恢复前会自动生成备份，可退回',
                                style: TextStyle(
                                    fontSize: 11.5, color: _amber)),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Checkbox(
                          key: const ValueKey('confirm-restore'),
                          value: _confirmed,
                          onChanged: (v) =>
                              setState(() => _confirmed = v ?? false),
                        ),
                        Expanded(
                          child: Text(
                              _partial
                                  ? '恢复将替换上述模块的当前数据'
                                  : '恢复将替换当前数据',
                              style: const TextStyle(fontSize: 12)),
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
                            child: Text(_partial ? '恢复所选模块' : '恢复整库'),
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
