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
  late int _keep =
      FileLogSink.readRetentionDays(ref.read(sharedPreferencesProvider));

  /// 落盘文件名清单（新→旧）。未 init 时 dayFiles 返回空列表。
  late final Future<List<String>> _dayFiles = FileLogSink.dayFiles();

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

  /// 当前过滤视图：环形缓冲取最近 [AppLog.displayWindow] 条窗口，再按级别过滤。
  List<LhLogLine> _visibleLines() {
    final lines = AppLog.lines;
    final start = lines.length > AppLog.displayWindow
        ? lines.length - AppLog.displayWindow
        : 0;
    final win = lines.sublist(start);
    return switch (_flt) {
      _LogFlt.all => win,
      _LogFlt.warnUp => win.where((l) => l.level != LhLevel.info).toList(),
      _LogFlt.error => win.where((l) => l.level == LhLevel.error).toList(),
    };
  }

  Future<void> _copyAll() async {
    await Clipboard.setData(ClipboardData(text: AppLog.allText()));
    if (!mounted) return;
    AppToast.show(context, '已复制 ${AppLog.lines.length} 条全量日志 · 凭据已脱敏');
  }

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
                      return ListView.builder(
                        key: const ValueKey('log-list'),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        itemExtent: 18,
                        itemCount: lines.length,
                        itemBuilder: (context, i) {
                          final l = lines[i];
                          return SizedBox(
                            height: 18,
                            child: Text(
                              l.formatted,
                              key: ValueKey(
                                  'log-line-$i-${l.time.microsecondsSinceEpoch}'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10.5,
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
