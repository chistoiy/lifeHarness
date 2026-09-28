import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/ai_call_store.dart';
import '../../../core/ai/ai_providers.dart';
import '../../../core/logging/app_log.dart';
import '../../../shared/widgets/ui_kit.dart';

/// AI 使用记录（V1.53 · 原型 p-aiUsage）：全屏明细页，与日志页同一交互语言。
///
/// 版式按产品负责人三轮指令定稿：**无底栏**、统计与破坏性动作上移到列表外、
/// 时间/状态/模块三条件收成一行胶囊（点开才横向弹该组选项），其余高度全给列表。
/// 隐私：正文只在关闭「记录输入与输出正文」时留空；API Key 永不入库。
class AiUsagePage extends ConsumerStatefulWidget {
  const AiUsagePage({super.key});

  @override
  ConsumerState<AiUsagePage> createState() => _AiUsagePageState();
}

class _AiUsagePageState extends ConsumerState<AiUsagePage> {
  final _kw = TextEditingController();

  /// 筛选态（与原型 auD/auSt/auMod/auKw 同口径；默认「今日」与原型一致）。
  int? _sinceDays = 0; // null=全部，0=今日
  String? _status; // null=全部
  String? _module; // null/''=全部
  String _pop = ''; // 当前展开选项组的胶囊 key（''=都收起）

  List<AiCallRecord> _rows = const [];
  List<(String, int)> _modules = const [];
  AiCallSum _sum = const AiCallSum();
  AiCallSum _today = const AiCallSum();
  int _week = 0;
  int _total = 0;
  int? _openId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  @override
  void dispose() {
    _kw.dispose();
    super.dispose();
  }

  AiCallStore? get _store => ref.read(aiCallStoreProvider);

  AiCallFilter get _filter => AiCallFilter(
        sinceDays: _sinceDays,
        status: _status,
        // 「全部」在选项条里是空串（与原型 'all' 同位），落到查询里＝不加条件。
        module: (_module == null || _module!.isEmpty) ? null : _module,
        keyword: _kw.text.trim().isEmpty ? null : _kw.text.trim(),
      );

  Future<void> _reload() async {
    final store = _store;
    if (store == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final cfg = ref.read(aiConfigProvider);
    await store.prune(cfg.callKeepDays); // 打开即按保留天数收口（0=不限）
    final rows = await store.query(_filter);
    final sum = await store.sumOf(_filter);
    final today = await store.sumOf(const AiCallFilter(sinceDays: 0));
    final week = await store.sumOf(const AiCallFilter(sinceDays: 7));
    final all = await store.sumOf(const AiCallFilter());
    final mods = await store.moduleCounts(_sinceDays);
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _sum = sum;
      _today = today;
      _week = week.n;
      _total = all.n;
      _modules = mods;
      _loading = false;
    });
  }

  void _toast(String msg) => AppToast.show(context, msg);

  void _copy(String text, String doneMsg) {
    if (text.isEmpty) {
      _toast('没有可复制的正文');
      return;
    }
    Clipboard.setData(ClipboardData(text: text));
    _toast(doneMsg);
  }

  String _lineSum(AiCallRecord r) =>
      '[${_fmtTs(r.ts)}] ${r.module} · ${r.name} · ${_statusLabel(r.status)}'
      ' · 入${r.inTok}/出${r.outTok} · ${_ms(r.ms)}';

  Future<void> _deleteOne(AiCallRecord r) async {
    final store = _store;
    if (store == null || r.id == null) return;
    await store.deleteOne(r.id!);
    AppLog.add('AI 使用记录删除 1 条（${r.name}）', level: LhLevel.info);
    await _reload();
    if (mounted) _toast('已删除「${r.name}」1 条');
  }

  Future<void> _deleteFiltered() async {
    final store = _store;
    if (store == null) return;
    if (_rows.isEmpty) {
      _toast('当前筛选没有记录');
      return;
    }
    final n = _rows.length;
    await store.deleteFiltered(_filter);
    await _reload();
    if (!mounted) return;
    _toast('已删除筛选结果 $n 条');
  }

  /// 破坏性动作统一二次确认（与原型「再点一次确认」同语义，Flutter 侧用对话框）。
  Future<bool> _confirm(String title, String body, String okLabel) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: const TextStyle(fontSize: 15)),
        content: Text(body, style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            key: const ValueKey('ai-usage-confirm-ok'),
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(okLabel),
          ),
        ],
      ),
    );
    return ok == true;
  }

  void _openPop(String key) =>
      setState(() => _pop = _pop == key ? '' : key);

  void _pick(int? days, String? status, String? module) {
    setState(() {
      if (days != null) _sinceDays = days;
      if (status != null) _status = status;
      if (module != null) _module = module;
      _pop = '';
    });
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final store = _store;
    return Scaffold(
      appBar: AppBar(title: const Text('AI 使用记录')),
      body: store == null
          ? const Center(
              child: Text('本机还没有可用的记录库',
                  style: TextStyle(fontSize: 12, color: Colors.grey)))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 12, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '筛选 ${_sum.n} 条 · 入 ${_sum.inTok}/出 ${_sum.outTok} tokens'
                          ' · 未成功 ${_sum.bad} · 今日 ${_today.n} 次',
                          key: const ValueKey('ai-usage-sum'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 10.5, color: Colors.grey),
                        ),
                      ),
                      _mini('记录设置', 'ai-usage-cfg', _openCfg),
                      _mini('复制', 'ai-usage-copy', () {
                        if (_rows.isEmpty) {
                          _toast('当前筛选没有记录');
                          return;
                        }
                        _copy(_rows.map(_lineSum).join('\n'),
                            '已复制 ${_rows.length} 条摘要');
                      }),
                      _mini('删除筛选结果', 'ai-usage-del-all', () async {
                        if (_rows.isEmpty) {
                          _toast('当前筛选没有记录');
                          return;
                        }
                        if (!await _confirm('删除筛选结果',
                            '删除当前筛选出的 ${_rows.length} 条记录？不影响后续调用与新记录。',
                            '删除')) {
                          return;
                        }
                        _deleteFiltered();
                      },
                          danger: true),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _pill('time', '时间', _timeLabel, 'ai-usage-pill-time'),
                          _pill('status', '状态', _statusLabel2,
                              'ai-usage-pill-status'),
                          _pill('module', '模块', _moduleLabel,
                              'ai-usage-pill-module'),
                        ],
                      ),
                      if (_pop.isNotEmpty) _optionStrip(),
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: TextField(
                          key: const ValueKey('ai-usage-kw'),
                          controller: _kw,
                          style: const TextStyle(fontSize: 12),
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText: '搜能力名 / 输入内容 / 输出内容…',
                          ),
                          onSubmitted: (_) => _reload(),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _loading
                      ? const Center(
                          child: CircularProgressIndicator(),
                        )
                      : _list(),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                  child: Text(
                    _total == 0
                        ? '还没有 AI 调用记录 · 各模块用一次 AI 就会在这里留一行'
                        : '共 $_total 条 · 近 7 天 $_week 次 · 点一行展开输入与输出全文',
                    key: const ValueKey('ai-usage-hint'),
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _list() {
    if (_rows.isEmpty) {
      return const Center(
        child: Text('该范围暂无 AI 调用记录\n换时间范围或清掉关键词再看',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: Colors.grey, height: 1.6)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      itemCount: _rows.length,
      itemBuilder: (ctx, i) => _row(_rows[i]),
    );
  }

  Widget _row(AiCallRecord r) {
    final open = _openId == r.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        key: ValueKey('ai-usage-row-${r.id}'),
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              key: ValueKey('ai-usage-head-${r.id}'),
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(
                  () => _openId = open ? null : r.id),
              onLongPress: () => _copy(_lineSum(r), '已复制该行记录'),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  children: [
                    Text(_hm(r.ts),
                        style: const TextStyle(
                            fontSize: 10.5,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w700)),
                    const SizedBox(width: 6),
                    Text(_statusLabel(r.status),
                        key: ValueKey('ai-usage-st-${r.id}'),
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: _statusColor(r.status))),
                    const SizedBox(width: 6),
                    Flexible(
                        child: Text('${r.module} · ${r.name}',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11.5, fontWeight: FontWeight.w700))),
                    Text(
                        ' ${(r.inTok == 0 && r.outTok == 0) ? '—' : '入${r.inTok}/出${r.outTok}'} · ${_ms(r.ms)}',
                        style: const TextStyle(fontSize: 10, color: Colors.grey)),
                  ],
                ),
              ),
            ),
            if (open) _detail(r),
          ],
        ),
      ),
    );
  }

  Widget _detail(AiCallRecord r) {
    final segs = <Widget>[];
    if (r.err.isNotEmpty) {
      segs.add(_seg(r.ok ? '提示' : '原因', r.err, danger: !r.ok));
    }
    if (r.sys.isNotEmpty) segs.add(_seg('System · 发送设定', r.sys));
    if (r.usr.isNotEmpty) {
      segs.add(_seg('User · 本次输入', r.usr + (r.cut ? ' …已截断（上限 8000 字）' : '')));
    }
    if (r.out.isNotEmpty) segs.add(_seg('输出', r.out));
    if (segs.isEmpty) {
      segs.add(const Padding(
        padding: EdgeInsets.only(top: 6),
        child: Text('本条未存正文（记录设置里「记录输入与输出正文」已关闭）',
            style: TextStyle(fontSize: 10, color: Colors.grey)),
      ));
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...segs,
          Row(
            children: [
              _mini('复制输入', 'ai-usage-copy-in-${r.id}', () => _copy(
                  r.sys.isEmpty ? r.usr : '${r.sys}\n\n${r.usr}', '已复制输入内容')),
              _mini('复制输出', 'ai-usage-copy-out-${r.id}',
                  () => _copy(r.out, '已复制输出内容')),
              _mini('复制全部', 'ai-usage-copy-all-${r.id}', () => _copy(
                  '[_${_fmtTs(r.ts)}] ${r.module} · ${r.name} · ${_statusLabel(r.status)}'
                  '\n--- System ---\n${r.sys}\n--- User ---\n${r.usr}'
                  '\n--- 输出 ---\n${r.out}${r.err.isEmpty ? '' : '\n--- 原因 ---\n${r.err}'}',
                  '已复制整条记录')),
              _mini('删除本条', 'ai-usage-del-one-${r.id}',
                  () => _deleteOne(r),
                  danger: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _seg(String label, String text, {bool danger = false}) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.grey)),
            const SizedBox(height: 2),
            SelectableText(text,
                key: ValueKey('ai-usage-body-${label.hashCode}'),
                style: TextStyle(
                    fontSize: 10.5,
                    height: 1.5,
                    fontFamily: 'monospace',
                    color: danger ? const Color(0xFFF43F5E) : null),
                maxLines: 12),
          ],
        ),
      );

  /// 条件胶囊：点开=横向弹该组选项，再点同一枚收起（同时只开一组）。
  Widget _pill(String key, String title, String value, String testKey) {
    final on = _pop == key;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: TextButton(
        key: ValueKey(testKey),
        onPressed: () => _openPop(key),
        style: TextButton.styleFrom(
          backgroundColor: on
              ? Colors.grey.withValues(alpha: 0.28)
              : Colors.grey.withValues(alpha: 0.14),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: null,
        ),
        child: Text('$title · $value ${on ? '▾' : '▸'}',
            style: const TextStyle(
                fontSize: 10.5, fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _optionStrip() {
    final opts = <(String label, void Function() onTap, bool on)>[];
    if (_pop == 'time') {
      opts.addAll([
        ('今日', () => _pick(0, null, null), _sinceDays == 0),
        ('7 天', () => _pick(7, null, null), _sinceDays == 7),
        ('30 天', () => _pick(30, null, null), _sinceDays == 30),
        ('全部', () => _pick(null, null, null), _sinceDays == null),
      ]);
    } else if (_pop == 'status') {
      for (final (v, l) in [
        (null, '全部'),
        (AiCallStore.statusOk, '成功'),
        (AiCallStore.statusFail, '失败'),
        (AiCallStore.statusCancel, '取消'),
        (AiCallStore.statusDenied, '未启用'),
      ]) {
        opts.add((l, () => _pick(null, v, null), _status == v));
      }
    } else {
      opts.add(('全部 ${_modules.fold(0, (a, m) => a + m.$2)}',
          () => _pick(null, null, ''), _module == null));
      for (final (m, n) in _modules) {
        opts.add(('$m $n', () => _pick(null, null, m), _module == m));
      }
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: SizedBox(
        height: 30,
        child: ListView(
          key: const ValueKey('ai-usage-options'),
          scrollDirection: Axis.horizontal,
          children: [
            for (final o in opts)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: TextButton(
                  key: ValueKey('ai-usage-opt-$_pop-${o.$1}'),
                  onPressed: o.$2,
                  style: TextButton.styleFrom(
                    backgroundColor: o.$3
                        ? Colors.grey.withValues(alpha: 0.34)
                        : Colors.grey.withValues(alpha: 0.14),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: null,
                  ),
                  child: Text(o.$1,
                      style: const TextStyle(
                          fontSize: 10.5, fontWeight: FontWeight.w700)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openCfg() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetCtx) => SafeArea(
          child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
              child: _CfgSheet(onChanged: _reload))),
    );
    await _reload();
  }

  String get _timeLabel {
    switch (_sinceDays) {
      case 0:
        return '今日';
      case 7:
        return '7 天';
      case 30:
        return '30 天';
      default:
        return '全部';
    }
  }

  String get _statusLabel2 => switch (_status) {
        null => '全部',
        AiCallStore.statusOk => '成功',
        AiCallStore.statusFail => '失败',
        AiCallStore.statusCancel => '取消',
        _ => '未启用',
      };

  String get _moduleLabel =>
      _module == null ? '全部' : (_module!.isEmpty ? '全部' : _module!);

  Color _statusColor(String st) => switch (st) {
        AiCallStore.statusOk => const Color(0xFF10B981),
        AiCallStore.statusFail => const Color(0xFFF43F5E),
        AiCallStore.statusCancel => const Color(0xFFF59E0B),
        _ => Colors.grey,
      };

  static String _statusLabel(String st) => switch (st) {
        AiCallStore.statusOk => '成功',
        AiCallStore.statusFail => '失败',
        AiCallStore.statusCancel => '取消',
        _ => '未启用',
      };
}

/// 记录设置弹层（原型 sheetAiUsageCfg）。
class _CfgSheet extends ConsumerStatefulWidget {
  const _CfgSheet({required this.onChanged});

  final VoidCallback onChanged;

  @override
  ConsumerState<_CfgSheet> createState() => _CfgSheetState();
}

class _CfgSheetState extends ConsumerState<_CfgSheet> {
  int _bytes = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _size());
  }

  Future<void> _size() async {
    final store = ref.read(aiCallStoreProvider);
    if (store == null) return;
    final b = await store.bodyBytes();
    if (!mounted) return;
    setState(() => _bytes = b);
  }

  Future<void> _setBody(bool on) async {
    await ref.read(aiConfigProvider.notifier).setRecordBody(on);
    if (!mounted) return;
    AppToast.show(context,
        on ? '开始记录输入与输出正文' : '已停记正文：新调用只记用量');
  }

  Future<void> _setKeep(int days) async {
    await ref.read(aiConfigProvider.notifier).setCallKeepDays(days);
    final store = ref.read(aiCallStoreProvider);
    final gone = store == null ? 0 : await store.prune(days);
    if (!mounted) return;
    if (days > 0 && gone > 0) {
      AppToast.show(context, '保留 $days 天：丢弃超期 $gone 条');
    }
    widget.onChanged();
  }

  Future<void> _clearBodies() async {
    if (!await _confirmSheet('清除已存正文',
        '只清三段正文与原因，能力点·状态·token·耗时的用量记录保留。')) {
      return;
    }
    final store = ref.read(aiCallStoreProvider);
    await store?.clearBodies();
    if (!mounted) return;
    AppToast.show(context, '已清除正文，用量记录保留');
    widget.onChanged();
    _size();
  }

  Future<void> _clearAll() async {
    if (!await _confirmSheet('清空全部 AI 使用记录', '清空后无法恢复（本机数据库）。')) {
      return;
    }
    final store = ref.read(aiCallStoreProvider);
    await store?.clearAll();
    if (!mounted) return;
    AppToast.show(context, '已清空全部 AI 使用记录');
    Navigator.pop(context);
    widget.onChanged();
  }

  Future<bool> _confirmSheet(String title, String body) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: const TextStyle(fontSize: 15)),
        content: Text(body, style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            key: const ValueKey('ai-usage-cfg-confirm'),
            style:
                FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(aiConfigProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('AI 记录设置',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        Row(
          children: [
            const Expanded(
                child: Text('记录输入与输出正文', style: TextStyle(fontSize: 12.5))),
            Switch(
              key: const ValueKey('ai-cfg-body'),
              value: cfg.recordBody,
              onChanged: (v) async {
                await _setBody(v);
                widget.onChanged();
              },
            ),
          ],
        ),
        const Text('关闭后只记用量（能力点 · 状态 · token · 耗时），不再留存发送内容与返回正文；'
            '已存的正文可用下方按钮单独清除。',
            style: TextStyle(fontSize: 10, color: Colors.grey, height: 1.5)),
        const SizedBox(height: 12),
        const Text('保留天数',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (d, l) in [
              (7, '7 天'),
              (15, '15 天'),
              (30, '30 天'),
              (90, '90 天'),
              (0, '不限'),
            ])
              PillChip(
                key: ValueKey('ai-cfg-keep-$d'),
                label: l,
                selected: cfg.callKeepDays == d,
                onTap: () => _setKeep(d),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
            '超期记录自动丢弃；单条正文超过 ${AiCallStore.maxBodyChars} 字按上限截断并标「已截断」。'
            '当前占用 ${(_bytes / 1048576).toStringAsFixed(1)} MB。',
            key: const ValueKey('ai-cfg-size'),
            style: const TextStyle(fontSize: 10, color: Colors.grey, height: 1.5)),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            key: const ValueKey('ai-cfg-clear-body'),
            onPressed: _clearBodies,
            child: const Text('清除已存正文（保留用量记录）',
                style: TextStyle(fontSize: 12)),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            key: const ValueKey('ai-cfg-clear-all'),
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444)),
            onPressed: _clearAll,
            child: const Text('清空全部 AI 使用记录'),
          ),
        ),
        const SizedBox(height: 10),
        const Text('隐私：记录只写在本机数据库（ai_calls 表），随本地备份与云同步快照一起走；'
            'API Key 存系统加密区，永不出现在记录、日志与备份明文中。',
            style: TextStyle(fontSize: 10, color: Colors.grey, height: 1.5)),
      ],
    );
  }
}

Widget _mini(String label, String testKey, VoidCallback onTap,
        {bool danger = false}) =>
    TextButton(
      key: ValueKey(testKey),
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: danger ? const Color(0xFFEF4444) : null,
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label, style: const TextStyle(fontSize: 10.5)),
    );

String _hm(int ts) {
  final d = DateTime.fromMillisecondsSinceEpoch(ts);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.hour)}:${two(d.minute)}';
}

String _fmtTs(int ts) {
  final d = DateTime.fromMillisecondsSinceEpoch(ts);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}

String _ms(int ms) => ms >= 1000 ? '${(ms / 1000).toStringAsFixed(1)}s' : '${ms}ms';
