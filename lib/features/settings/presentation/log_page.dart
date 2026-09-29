import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/app_log.dart';
import '../../../core/logging/file_log_sink.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart';

/// 日志级别过滤档（原型 logLvSet：全部 / 警告+ / 错误）。
enum _LogFlt { all, warnUp, error }

/// V1.50 批3.6 · 日志页（原型 p-logs，V4 风格 + V5 三点）。
///
/// 保真口径：
/// - 顶栏「日志管理」+ 齿轮 → 底部弹层「筛选与配置」（分段 Tab：筛选 | 配置）；
/// - 页头信息条一行（窗口120·缓冲300·落盘按天·单文件5MB·最新在上）+ 复制全部；
/// - 通底 `.logline` **单栏行内流**（V1.53.4 R14-11 去分栏）：时间戳灰 / 级别色 /
///   来源胶囊 / 正文同一段，长内容占满整行回流；**倒序**（最新在上）；
///   堆栈行默认折一行可展开；WARN·ERROR 整行淡底，长按一行复制该行；
/// - 配置：日志字号（9 档 10-20，落 prefs `log.fontSize` 实时生效）、
///   落盘保留（横滑 7/14/30）、归档管理（归档/清理/归档包查看·复制·删除）。
/// 渲染只给最近 [AppLog.displayWindow] 条窗口、复制永远全量；
/// 仅窗口列表与复制钮订阅 [AppLog.version] 局部件，页面主体不整页重建。
class LogPage extends ConsumerStatefulWidget {
  const LogPage({super.key});

  @override
  ConsumerState<LogPage> createState() => _LogPageState();
}

class _LogPageState extends ConsumerState<LogPage> {
  // 档位与 sink 白名单同源（readRetentionDays 读侧也按它钳制）。
  static const List<int> _keepOptions = FileLogSink.retentionOptions;
  static const List<String> _keepLabels = ['7 天', '14 天', '30 天'];

  /// 日志字号档位（原型 logFont hReg，默认 11px）。
  static const List<int> _fontOptions = [10, 11, 12, 13, 14, 15, 16, 18, 20];
  static const String _fontKey = 'log.fontSize';
  static const int _fontDefault = 11;

  /// 级别展示文本（原型 .ll 用 INFO/WARN/ERR 三态）。
  static String _levelText(LhLevel lv) => switch (lv) {
        LhLevel.info => 'INFO',
        LhLevel.warn => 'WARN',
        LhLevel.error => 'ERR',
      };
  static Color _levelColor(LhLevel lv) => switch (lv) {
        LhLevel.info => const Color(0xFF0EA5E9),
        LhLevel.warn => const Color(0xFFF59E0B),
        LhLevel.error => const Color(0xFFEF4444),
      };

  _LogFlt _flt = _LogFlt.all;

  /// 来源筛选（null＝全部来源）与关键词（一眼看出是谁报的错、能筛）。
  String? _src;
  final TextEditingController _kwCtl = TextEditingController();

  late int _keep =
      FileLogSink.readRetentionDays(ref.read(sharedPreferencesProvider));
  late int _font = _readFont();

  int _readFont() {
    final v = ref.read(sharedPreferencesProvider).getInt(_fontKey);
    return _fontOptions.contains(v) ? v! : _fontDefault;
  }

  /// 窗口列表刷新计数（齿轮弹层筛选态变化时，主页在模态下仍重绘列表）。
  @override
  void initState() {
    super.initState();
    _kwCtl.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _kwCtl.dispose();
    super.dispose();
  }

  late Future<List<String>> _dayFiles = FileLogSink.dayFiles();
  late Future<List<LhArchiveEntry>> _archives = FileLogSink.archives();

  void _refreshFiles() {
    setState(() {
      _dayFiles = FileLogSink.dayFiles();
      _archives = FileLogSink.archives();
    });
  }

  Future<void> _setKeep(int days) async {
    if (days == _keep) return;
    setState(() => _keep = days);
    try {
      await FileLogSink.saveRetentionDays(
          ref.read(sharedPreferencesProvider), days);
    } catch (e) {
      AppLog.add('保留天数保存失败: $e', level: LhLevel.warn);
    }
  }

  Future<void> _setFont(int px) async {
    if (px == _font) return;
    setState(() => _font = px);
    try {
      await ref.read(sharedPreferencesProvider).setInt(_fontKey, px);
    } catch (e) {
      AppLog.add('日志字号保存失败: $e', level: LhLevel.warn);
    }
  }

  /// 当前过滤视图：环形缓冲取最近 [AppLog.displayWindow] 条窗口，
  /// 再按「级别 × 来源 × 关键词」三重过滤，**倒序返回（最新在上 · R14-11）**。
  List<LhLogLine> _visibleLines() {
    final lines = AppLog.lines;
    final start = lines.length > AppLog.displayWindow
        ? lines.length - AppLog.displayWindow
        : 0;
    Iterable<LhLogLine> win = lines.sublist(start);
    if (_src != null) win = win.where((l) => l.src == _src);
    final kw = _kwCtl.text.trim();
    if (kw.isNotEmpty) win = win.where((l) => l.text.contains(kw));
    final out = switch (_flt) {
      _LogFlt.all => win.toList(),
      _LogFlt.warnUp => win.where((l) => l.level != LhLevel.info).toList(),
      _LogFlt.error => win.where((l) => l.level == LhLevel.error).toList(),
    };
    return out.reversed.toList();
  }

  /// 窗口里出现过的来源（按条数多→少，「系统」永远收尾）——筛选胶囊候选集。
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

  Future<void> _copyLine(LhLogLine l) async {
    await Clipboard.setData(ClipboardData(text: l.formatted));
    if (!mounted) return;
    AppToast.show(context, '已复制该行日志');
  }

  // ==================== 日志管理（归档 / 清理 · 弹层配置区） ====================

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
                    backgroundColor: danger ? const Color(0xFFEF4444) : null),
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
    final ok = await _confirm('删除归档', '删除归档包 ${a.name} · ${_fmtBytes(a.bytes)}？',
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

  // ==================== 齿轮弹层：筛选与配置 ====================

  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          // 弹层与主页列表双重建：弹层管自身选中态高亮，主页管通底列表刷新。
          void sync(VoidCallback fn) {
            setState(fn);
            setSheet(() {});
          }

          return _SettingsSheet(
            flt: _flt,
            src: _src,
            kwCtl: _kwCtl,
            font: _font,
            keep: _keep,
            sources: _sources(),
            onFlt: (v) => sync(() => _flt = v),
            onSrc: (s) => sync(() => _src = _src == s ? null : s),
            onAllSrc: () => sync(() => _src = null),
            onKw: () => sync(() {}),
            onFont: (px) async {
              await _setFont(px);
              setSheet(() {});
            },
            onKeep: (d) async {
              await _setKeep(d);
              setSheet(() {});
            },
            onArchive: () async {
              await _archive();
              setSheet(() {});
            },
            onPurge: () async {
              await _purge();
              setSheet(() {});
            },
            onViewArchive: _viewArchive,
            onDelArchive: (a) async {
              await _delArchive(a);
              setSheet(() {});
            },
            archives: _archives,
            dayFiles: _dayFiles,
          );
        },
      ),
    );
  }

  // ==================== 页面主体 ====================

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('日志'),
        actions: [
          IconButton(
            key: const ValueKey('log-settings-gear'),
            tooltip: '日志筛选与配置',
            onPressed: _openSettings,
            icon: const Icon(CupertinoIcons.slider_horizontal_3),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // 页头信息条一行 + 复制全部（原型 #logBoxWrap 上方一行 10px）。
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Expanded(
                    child: Text(
                      '窗口 120 条 · 缓冲 300 · 落盘按天 · 单文件 5 MB · 最新在上',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 10, color: Color(0xFF64748B)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 仅钮面计数订阅版本信号（局部订阅）。
                  ValueListenableBuilder<int>(
                    valueListenable: AppLog.version,
                    builder: (context, _, _) => GestureDetector(
                      key: const ValueKey('log-copy-all'),
                      onTap: _copyAll,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: tokens.accent.withValues(alpha: .08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '复制全部',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: tokens.accent),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 通底日志窗（原型 .card overflow-hidden max-height:100vh-158）。
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(10, 4, 10, 10),
                decoration: context.cardDecoration,
                clipBehavior: Clip.antiAlias,
                child: ValueListenableBuilder<int>(
                  valueListenable: AppLog.version,
                  builder: (context, _, _) {
                    final lines = _visibleLines();
                    if (lines.isEmpty) {
                      return Center(
                        child: Text('无匹配日志',
                            style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant)),
                      );
                    }
                    return ListView.builder(
                      key: const ValueKey('log-list'),
                      padding: EdgeInsets.zero,
                      itemCount: lines.length,
                      itemBuilder: (context, i) {
                        final l = lines[i];
                        return _LogLine(
                          line: l,
                          font: _font.toDouble(),
                          levelText: _levelText(l.level),
                          levelColor: _levelColor(l.level),
                          onLongPress: () => _copyLine(l),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 单条日志行（原型 `.logline` V1.53.4 R14-11）：**不分栏**——时间戳/级别/来源/
/// 正文同一段行内流，长内容占满整行自然回流；WARN·ERROR 整行淡底，长按复制该行。
/// 堆栈行（`addStack` 压平的 ` | #N ` 序列）默认只显首段，可展开看全文。
class _LogLine extends StatefulWidget {
  const _LogLine({
    required this.line,
    required this.font,
    required this.levelText,
    required this.levelColor,
    required this.onLongPress,
  });

  final LhLogLine line;
  final double font;
  final String levelText;
  final Color levelColor;
  final VoidCallback onLongPress;

  @override
  State<_LogLine> createState() => _LogLineState();
}

class _LogLineState extends State<_LogLine> {
  /// 堆栈段展开态（仅堆栈行有意义）。
  bool _open = false;

  String get _ts {
    final t = widget.line.time;
    String two(int n) => n.toString().padLeft(2, '0');
    String three(int n) => n.toString().padLeft(3, '0');
    return '${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}:'
        '${two(t.second)}.${three(t.millisecond)}';
  }

  /// 堆栈行判据：`AppLog.addStack` 把多行压成 `帧 | 帧` 的一行，帧以 `#N` 起头。
  bool get _isStack {
    final t = widget.line.text;
    final i = t.indexOf(' | #');
    return t.startsWith('#') || (i > 0 && RegExp(r'#\d').hasMatch(t.substring(i + 4)));
  }

  /// 堆栈行的「摘要 / 全文」切分：摘要＝帧列表之前的正文（整行皆帧时为空）。
  (String, String) get _split {
    final t = widget.line.text;
    final i = t.indexOf('#0');
    if (i < 0) return (t, '');
    return (t.substring(0, i).trimRight(), t.substring(i));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final line = widget.line;
    final font = widget.font;
    final mono = TextStyle(
        fontSize: font,
        fontFamily: 'monospace',
        height: 1.7,
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFFE2E8F0)
            : const Color(0xFF0F172A));
    final tint = switch (line.level) {
      LhLevel.warn => const Color(0xFFF59E0B).withValues(alpha: .05),
      LhLevel.error => const Color(0xFFEF4444).withValues(alpha: .06),
      _ => Colors.transparent,
    };
    final (head, stack) = _isStack ? _split : (line.text, '');
    final base = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: tint,
        border: Border(
            bottom: BorderSide(color: tokens.cardBorder.withValues(alpha: .6))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              style: mono,
              children: [
                TextSpan(
                    text: '$_ts ',
                    style: const TextStyle(color: Color(0xFF94A3B8))),
                TextSpan(
                    text: '${widget.levelText} ',
                    style: TextStyle(
                        fontWeight: FontWeight.w800, color: widget.levelColor)),
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: tokens.accent.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(line.src,
                        style: TextStyle(
                            fontSize: font < 11 ? 8.5 : font - 2,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF64748B))),
                  ),
                ),
                if (head.isNotEmpty) TextSpan(text: head),
              ],
            ),
          ),
          // 堆栈段独立成块：折叠时整段不建 Text（toPlainText 不会把隐藏内容带出来）。
          if (stack.isNotEmpty) ...[
            if (_open)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(stack,
                    key: const ValueKey('log-stack'),
                    style: mono.copyWith(color: const Color(0xFF94A3B8))),
              ),
            GestureDetector(
              key: ValueKey(_open ? 'log-stk-close' : 'log-stk-open'),
              onTap: () => setState(() => _open = !_open),
              child: Text(
                _open ? '收起堆栈' : '展开堆栈',
                style: TextStyle(
                    fontSize: font - 2,
                    fontWeight: FontWeight.w800,
                    color: tokens.accent),
              ),
            ),
          ],
        ],
      ),
    );
    return GestureDetector(
      key: ValueKey('log-line-$_ts-${line.text.hashCode}'),
      behavior: HitTestBehavior.opaque,
      onLongPress: widget.onLongPress,
      child: base,
    );
  }
}

/// 齿轮弹层：分段 Tab 筛选 | 配置（字号 / 保留 / 归档管理）。
class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet({
    required this.flt,
    required this.src,
    required this.kwCtl,
    required this.font,
    required this.keep,
    required this.sources,
    required this.onFlt,
    required this.onSrc,
    required this.onAllSrc,
    required this.onKw,
    required this.onFont,
    required this.onKeep,
    required this.onArchive,
    required this.onPurge,
    required this.onViewArchive,
    required this.onDelArchive,
    required this.archives,
    required this.dayFiles,
  });

  final _LogFlt flt;
  final String? src;
  final TextEditingController kwCtl;
  final int font;
  final int keep;
  final List<String> sources;
  final ValueChanged<_LogFlt> onFlt;
  final ValueChanged<String> onSrc;
  final VoidCallback onAllSrc;
  final VoidCallback onKw;
  final ValueChanged<int> onFont;
  final ValueChanged<int> onKeep;
  final Future<void> Function() onArchive;
  final Future<void> Function() onPurge;
  final void Function(LhArchiveEntry) onViewArchive;
  final Future<void> Function(LhArchiveEntry) onDelArchive;
  final Future<List<LhArchiveEntry>> archives;
  final Future<List<String>> dayFiles;

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  static const List<String> _fontItems = ['10', '11', '12', '13', '14', '15', '16', '18', '20'];
  bool _tabConfig = false;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final keepLabels = _LogPageState._keepLabels;
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom, left: 18, right: 18),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                        color: scheme.onSurfaceVariant.withValues(alpha: .3),
                        borderRadius: BorderRadius.circular(2)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text('日志筛选与配置',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              // 分段 Tab：筛选 | 配置。
              _Seg(
                labels: const ['筛选', '配置'],
                selected: _tabConfig ? 1 : 0,
                onSel: (i) => setState(() => _tabConfig = i == 1),
              ),
              const SizedBox(height: 8),
              if (!_tabConfig) ...[
                // 级别。
                const _GroupLabel('级别'),
                _Seg(
                  labels: const ['全部', '警告+', '错误'],
                  selected: switch (widget.flt) {
                    _LogFlt.all => 0,
                    _LogFlt.warnUp => 1,
                    _LogFlt.error => 2,
                  },
                  onSel: (i) => widget.onFlt(switch (i) {
                    0 => _LogFlt.all,
                    1 => _LogFlt.warnUp,
                    _ => _LogFlt.error,
                  }),
                ),
                const _GroupLabel('来源'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    PillChip(
                        key: const ValueKey('log-src-all'),
                        label: '全部',
                        selected: widget.src == null,
                        onTap: widget.onAllSrc),
                    for (final s in widget.sources)
                      PillChip(
                          key: ValueKey('log-src-$s'),
                          label: s,
                          selected: widget.src == s,
                          onTap: () => widget.onSrc(s)),
                  ],
                ),
                const _GroupLabel('关键词'),
                SizedBox(
                  height: 38,
                  child: TextField(
                    key: const ValueKey('log-kw'),
                    controller: widget.kwCtl,
                    style: const TextStyle(fontSize: 12),
                    onChanged: (_) => widget.onKw(),
                    decoration: InputDecoration(
                      hintText: '搜关键词...',
                      hintStyle: const TextStyle(fontSize: 12),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      filled: true,
                      fillColor: scheme.surfaceContainerHighest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ] else ...[
                // 配置：字号 / 保留 / 归档管理。
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const _GroupLabel('日志字号', tight: true),
                    Text(
                      '${widget.font}px',
                      key: const ValueKey('log-font-current'),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: tokens.accent),
                    ),
                  ],
                ),
                HPick(
                  key: const ValueKey('log-font-pick'),
                  items: _fontItems,
                  index: _fontItems.indexOf('${widget.font}').clamp(0, 8),
                  onChanged: (i) {
                    widget.onFont(int.parse(_fontItems[i]));
                    setState(() {});
                  },
                ),
                const SizedBox(height: 4),
                const _GroupLabel('落盘日志保留', tight: true),
                HPick(
                  key: const ValueKey('keep-days-wheel'),
                  items: keepLabels,
                  index: _LogPageState._keepOptions
                      .indexOf(widget.keep)
                      .clamp(0, keepLabels.length - 1),
                  onChanged: (i) {
                    widget.onKeep(_LogPageState._keepOptions[i]);
                    setState(() {});
                  },
                ),
                const SizedBox(height: 12),
                // 归档管理（V1.43 能力，V5 收进配置弹层）。
                Row(
                  children: [
                    _ToolBtn(
                      key: const ValueKey('log-archive-btn'),
                      icon: Icons.folder_zip_outlined,
                      label: '归档落盘日志',
                      onTap: () => widget.onArchive(),
                    ),
                    const SizedBox(width: 10),
                    _ToolBtn(
                      key: const ValueKey('log-clear-btn'),
                      icon: Icons.delete_sweep_outlined,
                      label: '清理日志',
                      danger: true,
                      onTap: () => widget.onPurge(),
                    ),
                  ],
                ),
                FutureBuilder<List<LhArchiveEntry>>(
                  future: widget.archives,
                  builder: (context, snap) {
                    final list = snap.data ?? const <LhArchiveEntry>[];
                    if (list.isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 10),
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
                                        '${a.name} · ${_LogPageState._fmtBytes(a.bytes)} · '
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
                                      onPressed: () => widget.onViewArchive(a)),
                                  IconButton(
                                      key: ValueKey('log-arch-del-${a.name}'),
                                      tooltip: '删除归档',
                                      visualDensity: VisualDensity.compact,
                                      icon: const Icon(Icons.delete_outline,
                                          size: 17, color: Color(0xFFEF4444)),
                                      onPressed: () =>
                                          widget.onDelArchive(a)),
                                ],
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 10),
                FutureBuilder<List<String>>(
                  future: widget.dayFiles,
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
              ],
              const SizedBox(height: 18),
            ],
          ),
        ),
      ),
    );
  }
}

/// 分组小标题（原型 text-xs font-bold slate-500）。
class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text, {this.tight = false});
  final String text;
  final bool tight;
  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(0, tight ? 10 : 12, 0, 6),
        child: Text(text,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF64748B))),
      );
}

/// 分段控件（原型 .seg-on 全局分段观感）。
class _Seg extends StatelessWidget {
  const _Seg(
      {required this.labels,
      required this.selected,
      required this.onSel});
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSel;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF1E293B)
            : const Color(0xFFE7EAEE),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                key: ValueKey('seg-${labels[i]}'),
                onTap: () => onSel(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  decoration: BoxDecoration(
                    color: i == selected ? tokens.card : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: i == selected
                        ? [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: .06),
                                blurRadius: 3,
                                offset: const Offset(0, 1))
                          ]
                        : null,
                  ),
                  child: Text(labels[i],
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              i == selected ? FontWeight.w800 : FontWeight.w600,
                          color: i == selected
                              ? Theme.of(context).colorScheme.onSurface
                              : const Color(0xFF64748B))),
                ),
              ),
            ),
        ],
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
  final Future<void> Function() onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final fg = danger ? const Color(0xFFEF4444) : tokens.accent;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => onTap(),
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
                style: TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w700, color: fg)),
          ],
        ),
      ),
    );
  }
}
