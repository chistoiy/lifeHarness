import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/app_log.dart';
import '../../../core/logging/file_log_sink.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart';

/// 日志级别过滤档（原型 p-log chips：全部 / 警告+ / 错误）。
enum _LogFlt { all, warnUp, error }

/// V1.41 Task 6 · 日志查看页（原型 index-sync.html p-log）。
///
/// 口径（设计稿 §2 / R6/R7/R11）：渲染只给最近 120 条窗口、复制永远全量；
/// 仅「窗口列表 + 复制钮计数」两处订阅 [AppLog.version] 局部件，页面主体不整页重建；
/// 保留天数就地滚轮（7/14/30），读写走 SharedPreferences `log.retentionDays`；
/// 底部文件日志行取 [FileLogSink.dayFiles]（页面不碰 path_provider）。
class LogPage extends ConsumerStatefulWidget {
  const LogPage({super.key});

  @override
  ConsumerState<LogPage> createState() => _LogPageState();
}

class _LogPageState extends ConsumerState<LogPage> {
  // 档位与 sink 白名单同源（readRetentionDays 读侧也按它钳制）。
  static const List<int> _keepOptions = FileLogSink.retentionOptions;
  static const List<String> _keepLabels = ['7 天', '14 天', '30 天'];

  _LogFlt _flt = _LogFlt.all;

  /// 来源筛选（null＝全部来源）与关键词（真机反馈：一眼看出是谁报的错、能筛）。
  String? _src;
  final TextEditingController _kwCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    // 关键词是即时过滤：输入即重建过滤视图（列表本身仍只在 version 变化时局部刷）。
    _kwCtl.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _kwCtl.dispose();
    super.dispose();
  }
  late int _keep =
      FileLogSink.readRetentionDays(ref.read(sharedPreferencesProvider));

  /// 落盘文件名清单（新→旧）。未 init 时 dayFiles 返回空列表。
  late Future<List<String>> _dayFiles = FileLogSink.dayFiles();

  /// 归档包清单（新→旧；归档/删除动作后整体重取）。
  late Future<List<LhArchiveEntry>> _archives = FileLogSink.archives();

  void _refreshFiles() {
    setState(() {
      _dayFiles = FileLogSink.dayFiles();
      _archives = FileLogSink.archives();
    });
  }

  /// 滚轮定位档：读侧已按白名单钳制（readRetentionDays），indexOf 必命中；
  /// 仍保留异常值就近落默认 14 档（index 1）的守卫。
  int _keepIndex() {
    final i = _keepOptions.indexOf(_keep);
    return i < 0 ? 1 : i;
  }

  Future<void> _setKeep(int days) async {
    if (days == _keep) return;
    setState(() => _keep = days);
    try {
      // 评审修复轮1：await 落盘 + 吞异常——保存失败仅记日志（UI 已本地回显，
      // 下次启动仍以旧值生效），日志基建的异常绝不抛给页面。
      await FileLogSink.saveRetentionDays(
          ref.read(sharedPreferencesProvider), days);
    } catch (e) {
      AppLog.add('保留天数保存失败: $e', level: LhLevel.warn);
    }
  }

  /// 当前过滤视图：环形缓冲取最近 [AppLog.displayWindow] 条窗口，
  /// 再按「级别 × 来源 × 关键词」三重过滤（真机反馈：混在一屏里找不到是谁报的错）。
  List<LhLogLine> _visibleLines() {
    final lines = AppLog.lines;
    final start = lines.length > AppLog.displayWindow
        ? lines.length - AppLog.displayWindow
        : 0;
    Iterable<LhLogLine> win = lines.sublist(start);
    if (_src != null) win = win.where((l) => l.src == _src);
    final kw = _kwCtl.text.trim();
    if (kw.isNotEmpty) win = win.where((l) => l.text.contains(kw));
    return switch (_flt) {
      _LogFlt.all => win.toList(),
      _LogFlt.warnUp => win.where((l) => l.level != LhLevel.info).toList(),
      _LogFlt.error => win.where((l) => l.level == LhLevel.error).toList(),
    };
  }

  /// 窗口里出现过的来源（按条数多→少，「系统」永远收尾）——筛选 chips 的候选集。
  List<String> _sources() {
    final counts = <String, int>{};
    for (final l in AppLog.lines) {
      counts[l.src] = (counts[l.src] ?? 0) + 1;
    }
    final out = counts.keys.toList()
      ..sort((a, b) {
        if (a == LhLogLine.srcSystem) return 1;
        if (b == LhLogLine.srcSystem) return -1;
        final c = counts[b]!.compareTo(counts[a]!);
        return c != 0 ? c : a.compareTo(b);
      });
    return out;
  }

  Future<void> _copyAll() async {
    await Clipboard.setData(ClipboardData(text: AppLog.allText()));
    if (!mounted) return;
    AppToast.show(context, '已复制 ${AppLog.lines.length} 条全量日志 · 凭据已脱敏');
  }

  // ==================== 日志管理（归档 / 清理 · V1.42 增强包） ====================

  Future<bool?> _confirm(String title, String message,
      {String okLabel = '归档', bool danger = false}) =>
      showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title, style: const TextStyle(fontSize: 15)),
          content: Text(message, style: const TextStyle(fontSize: 13)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
                key: const ValueKey('log-confirm-ok'),
                style: FilledButton.styleFrom(
                    backgroundColor:
                        danger ? const Color(0xFFEF4444) : null),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(okLabel)),
          ],
        ),
      );

  Future<void> _archive() async {
    final ok = await _confirm('确认归档',
        '将当前落盘日志全部打包为归档并删除原文件（归档包最多保留 ${FileLogSink.maxArchives} 份）');
    if (ok != true || !mounted) return;
    try {
      final r = await FileLogSink.archive();
      if (!mounted) return;
      AppToast.show(
          context,
          r == null
              ? '暂无落盘日志可归档'
              : '已归档 ${r.name} · ${r.files} 个文件 · ${_fmtBytes(r.bytes)}',
          ms: 2200);
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, '归档失败：$e', ms: 2600);
    }
    if (mounted) _refreshFiles();
  }

  Future<void> _purge() async {
    final ok = await _confirm('确认清理', '删除全部落盘日志并清空内存缓冲（归档包保留）',
        okLabel: '清理', danger: true);
    if (ok != true || !mounted) return;
    try {
      final n = await FileLogSink.purgeDisk();
      AppLog.clearMemory();
      if (!mounted) return;
      AppToast.show(context, '已清理 $n 个落盘文件 · 缓冲已清空');
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, '清理失败：$e', ms: 2600);
    }
    if (mounted) _refreshFiles();
  }

  Future<void> _viewArchive(LhArchiveEntry a) async {
    final String text;
    try {
      text = await FileLogSink.archiveText(a.name);
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, '归档打开失败：$e', ms: 2600);
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(a.name,
            style: const TextStyle(fontSize: 13, fontFamily: 'monospace')),
        content: SizedBox(
          width: 460,
          height: 320,
          child: SingleChildScrollView(
            child: SelectableText(
                text.isEmpty ? '（归档为空）' : text,
                style: const TextStyle(
                    fontSize: 10.5, fontFamily: 'monospace', height: 1.5)),
          ),
        ),
        actions: [
          TextButton(
            key: ValueKey('log-arch-copy-${a.name}'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) AppToast.show(context, '已复制归档内容');
            },
            child: const Text('复制'),
          ),
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
        ],
      ),
    );
  }

  Future<void> _delArchive(LhArchiveEntry a) async {
    final ok = await _confirm('删除归档',
        '删除归档包 ${a.name} · ${_fmtBytes(a.bytes)}？',
        okLabel: '删除', danger: true);
    if (ok != true || !mounted) return;
    await FileLogSink.deleteArchive(a.name);
    if (!mounted) return;
    AppToast.show(context, '归档已删除');
    _refreshFiles();
  }

  static String _fmtBytes(int b) => b >= 1024 * 1024
      ? '${(b / (1024 * 1024)).toStringAsFixed(1)} MB'
      : b >= 1024
          ? '${(b / 1024).toStringAsFixed(1)} KB'
          : '$b B';

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('日志')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              // 工具卡：窗口/缓冲/落盘说明 chips + 复制全部钮 · 级别过滤 chips
              Container(
                decoration: context.cardDecoration,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: const [
                              PillChip(label: '窗口 · 最近 120'),
                              PillChip(label: '环形缓冲 300'),
                              PillChip(label: '落盘 logs/ · 按天 · 单文件封顶 5 MB'),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        // 仅钮面计数订阅版本信号（R7 局部订阅）。
                        ValueListenableBuilder<int>(
                          valueListenable: AppLog.version,
                          builder: (context, _, _) => TextButton(
                            onPressed: _copyAll,
                            style: TextButton.styleFrom(
                              backgroundColor:
                                  tokens.accent.withValues(alpha: .08),
                            ),
                            child: Text(
                              '复制全部（${AppLog.lines.length}）',
                              style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: tokens.accent),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        PillChip(
                            label: '全部',
                            selected: _flt == _LogFlt.all,
                            onTap: () => setState(() => _flt = _LogFlt.all)),
                        const SizedBox(width: 6),
                        PillChip(
                            label: '警告+',
                            selected: _flt == _LogFlt.warnUp,
                            onTap:
                                () => setState(() => _flt = _LogFlt.warnUp)),
                        const SizedBox(width: 6),
                        PillChip(
                            label: '错误',
                            selected: _flt == _LogFlt.error,
                            onTap: () => setState(() => _flt = _LogFlt.error)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // 来源筛选 + 关键词：来源由代码路径自动归类（原型 p-log srcChips）。
                    ValueListenableBuilder<int>(
                      valueListenable: AppLog.version,
                      builder: (context, _, _) {
                        final shown = _visibleLines().length;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                PillChip(
                                    key: const ValueKey('log-src-all'),
                                    label: '全部来源',
                                    selected: _src == null,
                                    onTap: () => setState(() => _src = null)),
                                for (final s in _sources())
                                  PillChip(
                                      key: ValueKey('log-src-$s'),
                                      label: s,
                                      selected: _src == s,
                                      onTap: () => setState(
                                          () => _src = _src == s ? null : s)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: SizedBox(
                                    height: 34,
                                    child: TextField(
                                      key: const ValueKey('log-kw'),
                                      controller: _kwCtl,
                                      style: const TextStyle(fontSize: 11.5),
                                      decoration: InputDecoration(
                                        hintText: '搜关键词',
                                        hintStyle: const TextStyle(
                                            fontSize: 11.5),
                                        isDense: true,
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 10, vertical: 9),
                                        filled: true,
                                        fillColor: scheme.surfaceContainerHighest,
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          borderSide: BorderSide.none,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '$shown 条 · 窗口 ${AppLog.displayWindow}',
                                  key: const ValueKey('log-count'),
                                  style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: scheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    // 日志管理动作：归档=搬家保历史 · 清理=删落盘+清缓冲（均二次确认）。
                    Row(
                      children: [
                        _ToolBtn(
                          key: const ValueKey('log-archive-btn'),
                          icon: Icons.folder_zip_outlined,
                          label: '归档落盘日志',
                          onTap: _archive,
                        ),
                        const SizedBox(width: 8),
                        _ToolBtn(
                          key: const ValueKey('log-clear-btn'),
                          icon: Icons.delete_sweep_outlined,
                          label: '清理日志',
                          danger: true,
                          onTap: _purge,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              // 窗口列表卡：唯一整块订阅 version 的区域，行 key=行号+时间防重建风暴。
              Expanded(
                child: Container(
                  decoration: context.cardDecoration,
                  clipBehavior: Clip.antiAlias,
                  child: ValueListenableBuilder<int>(
                    valueListenable: AppLog.version,
                    builder: (context, _, _) {
                      final lines = _visibleLines();
                      // 原型 .logline .lm{word-break:break-all}：长消息换行看全文，
                      // 不做单行截断（真机反馈 2026-09-27：截断看不到尾部）。
                      return ListView.builder(
                        key: const ValueKey('log-list'),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        itemCount: lines.length,
                        itemBuilder: (context, i) {
                          final l = lines[i];
                          return Text(
                            l.formatted,
                            key: ValueKey(
                                'log-line-$i-${l.time.microsecondsSinceEpoch}'),
                            softWrap: true,
                            style: TextStyle(
                              fontSize: 10.5,
                              height: 1.6,
                              fontFamily: 'monospace',
                              fontWeight: l.level == LhLevel.info
                                  ? FontWeight.w500
                                  : FontWeight.w700,
                              color: switch (l.level) {
                                LhLevel.info => scheme.onSurfaceVariant,
                                LhLevel.warn => const Color(0xFFF59E0B),
                                LhLevel.error => const Color(0xFFEF4444),
                              },
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // 保留天数卡：就地滚轮（禁止点击→弹层两段式），样式同 wheel 系组件。
              Container(
                decoration: context.cardDecoration,
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                            child: Text('保留天数',
                                style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800))),
                        Text(
                          '落盘日志保留 · 超期按天删除 · 当前 ',
                          style: TextStyle(
                              fontSize: 10.5, color: scheme.onSurfaceVariant),
                        ),
                        Text(
                          '$_keep 天',
                          key: const ValueKey('keep-days-current'),
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: tokens.accent),
                        ),
                      ],
                    ),
                    _RetentionWheel(
                      key: const ValueKey('keep-days-wheel'),
                      labels: _keepLabels,
                      index: _keepIndex(),
                      onSel: (i) => _setKeep(_keepOptions[i]),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // 归档包清单（有档才显；行内查看/复制/删除）。
              FutureBuilder<List<LhArchiveEntry>>(
                future: _archives,
                builder: (context, snap) {
                  final list = snap.data ?? const <LhArchiveEntry>[];
                  if (list.isEmpty) return const SizedBox.shrink();
                  return Container(
                    decoration: context.cardDecoration,
                    padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('归档包',
                            style: TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.w800)),
                        for (final a in list)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                      '${a.name} · ${_fmtBytes(a.bytes)} · '
                                      '${a.created.month}-${a.created.day} '
                                      '${a.created.hour.toString().padLeft(2, '0')}:'
                                      '${a.created.minute.toString().padLeft(2, '0')}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 10.5,
                                          fontFamily: 'monospace')),
                                ),
                                IconButton(
                                    key: ValueKey('log-arch-view-${a.name}'),
                                    tooltip: '查看归档',
                                    visualDensity: VisualDensity.compact,
                                    icon: const Icon(Icons.visibility_outlined,
                                        size: 17),
                                    onPressed: () => _viewArchive(a)),
                                IconButton(
                                    key: ValueKey('log-arch-del-${a.name}'),
                                    tooltip: '删除归档',
                                    visualDensity: VisualDensity.compact,
                                    icon: const Icon(Icons.delete_outline,
                                        size: 17, color: Color(0xFFEF4444)),
                                    onPressed: () => _delArchive(a)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              // 底部文件日志行：最近 3 个落盘文件名（新→旧）。
              SizedBox(
                width: double.infinity,
                child: FutureBuilder<List<String>>(
                  future: _dayFiles,
                  builder: (context, snap) {
                    final files = snap.data ?? const <String>[];
                    return Text(
                      key: const ValueKey('file-log-row'),
                      files.isEmpty
                          ? '文件日志：未启用落盘'
                          : '文件日志：${files.take(3).join(' · ')}',
                      style: const TextStyle(
                          fontSize: 10.5,
                          fontFamily: 'monospace',
                          color: Colors.grey),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 日志管理动作钮（线性图标 + 短标签；danger=玫红语义，禁 emoji 纪律同款）。
class _ToolBtn extends StatelessWidget {
  const _ToolBtn({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final fg = danger ? const Color(0xFFEF4444) : tokens.accent;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: fg.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: fg.withValues(alpha: .35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: fg),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: fg)),
          ],
        ),
      ),
    );
  }
}

/// 单列保留天数滚轮：StatefulWidget 自持 controller + didUpdateWidget 等值守卫
/// （同 core/widgets/wheel_date.dart `_ColWheel` 防自激重建回环口径）。
class _RetentionWheel extends StatefulWidget {
  const _RetentionWheel({
    super.key,
    required this.labels,
    required this.index,
    required this.onSel,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onSel;

  @override
  State<_RetentionWheel> createState() => _RetentionWheelState();
}

class _RetentionWheelState extends State<_RetentionWheel> {
  static const double _itemExtent = 34;

  late final FixedExtentScrollController _ctl = FixedExtentScrollController(
      initialItem: widget.index.clamp(0, widget.labels.length - 1));

  @override
  void didUpdateWidget(_RetentionWheel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index &&
        _ctl.hasClients &&
        _ctl.selectedItem != widget.index) {
      _ctl.jumpTo(widget.index.clamp(0, widget.labels.length - 1) *
          _itemExtent);
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return SizedBox(
      height: _itemExtent * 3,
      child: CupertinoPicker(
        scrollController: _ctl,
        itemExtent: _itemExtent,
        diameterRatio: 1.5,
        backgroundColor: Colors.transparent,
        onSelectedItemChanged: widget.onSel,
        children: [
          for (var i = 0; i < widget.labels.length; i++)
            Center(
              child: Text(
                widget.labels[i],
                style: TextStyle(
                  fontSize: i == widget.index ? 19 : 12,
                  fontWeight:
                      i == widget.index ? FontWeight.w800 : FontWeight.w600,
                  color: i == widget.index
                      ? tokens.accent
                      : const Color(0xFF94A3B8),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
