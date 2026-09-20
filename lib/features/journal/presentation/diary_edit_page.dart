import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/linkage/stats_providers.dart';
import 'widgets/ins_card.dart';

/// 日记编辑页（原型 p-diaryEdit）：纯文本 + 7 表情心情 + 今日概览草稿（联动 L2）
/// + ☐ 待办行保存同步（联动 L3）+ 模板 + 自动存草稿 + INS 卡片流预览。
class DiaryEditPage extends ConsumerStatefulWidget {
  const DiaryEditPage({super.key, this.day});

  final DateTime? day;

  @override
  ConsumerState<DiaryEditPage> createState() => _DiaryEditPageState();
}

class _DiaryEditPageState extends ConsumerState<DiaryEditPage> {
  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  late final DateTime _day;
  final _ctl = TextEditingController();
  final _focus = FocusNode();
  int? _mood;
  JournalEntry? _existing;
  bool _insMode = false;
  bool _dirty = false;
  bool _savedDraft = false;
  Timer? _debounce;
  String _template = '模板：自由书写';

  @override
  void initState() {
    super.initState();
    _day = JournalEntry.dayStart(widget.day ?? DateTime.now());
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(journalRepositoryProvider);
    final e = await repo.byDay(_day);
    if (!mounted) return;
    setState(() {
      _existing = e;
      _ctl.text = e?.content ?? '';
      _mood = e?.mood;
    });
    if (e != null && e.id != null) {
      await repo.markViewed(e.id!);
      ref.invalidate(journalsProvider);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctl.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _isToday => JournalEntry.sameDay(_day, DateTime.now());

  void _onChanged(String v) {
    setState(() {
      _dirty = true;
    });
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 900), _autoSave);
  }

  Future<void> _autoSave() async {
    if (!_dirty || !mounted) return;
    await _persist(notify: false);
    if (mounted) setState(() => _savedDraft = true);
  }

  Future<JournalEntry> _persist({bool notify = true}) async {
    final repo = ref.read(journalRepositoryProvider);
    final saved = await repo.save(JournalEntry(
      day: _day,
      mood: _mood,
      content: _ctl.text,
      createdAt: _existing?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    ));
    _existing = saved;
    if (notify) ref.invalidate(journalsProvider);
    return saved;
  }

  /// L3：正文中的 ☐ 行同步为待办（按标题去重，默认落「重要不紧急」）。
  Future<int> _syncTodoLines(List<String> lines) async {
    if (lines.isEmpty) return 0;
    final todoRepo = ref.read(todoRepositoryProvider);
    final existing = await todoRepo.list();
    final titles = existing.map((t) => t.title).toSet();
    var created = 0;
    for (final t in lines.toSet()) {
      if (titles.contains(t)) continue;
      await todoRepo.add(Todo(title: t, quadrant: Quadrant.q2, tag: '日记'));
      created++;
    }
    if (created > 0) ref.invalidate(todosProvider);
    return created;
  }

  Future<void> _save() async {
    final entry = await _persist();
    final n = await _syncTodoLines(entry.todoLines());
    _dirty = false;
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(n > 0
              ? '日记已保存 · 文中 ☐ 待办已同步至任务列表（$n 条）'
              : '日记已保存'),
          duration: const Duration(milliseconds: 1600)));
    Navigator.of(context).pop();
  }

  void _insertAtCursor(String text) {
    final sel = _ctl.selection;
    final pos = sel.isValid ? sel.start : _ctl.text.length;
    final prefix = _ctl.text.substring(0, pos);
    final suffix = _ctl.text.substring(pos);
    final join = (prefix.isEmpty || prefix.endsWith('\n')) ? '' : '\n';
    _ctl.value = TextEditingValue(
      text: '$prefix$join$text$suffix',
      selection: TextSelection.collapsed(offset: prefix.length + join.length + text.length),
    );
    _onChanged(_ctl.text);
  }

  /// 概览明细行（不含标题）。
  List<String> _summaryLines(List<Todo> todos, List<CalEvent> events) {
    final doneToday = todos.where((t) => t.done && _sameDayNow(t.updatedAt)).length;
    final open = todos.where((t) => !t.done && !t.dropped).length;
    final todayEvents =
        events.where((e) => JournalEntry.sameDay(e.start, _day)).toList();
    final lines = <String>[
      '✅ 待办：今日完成 $doneToday · 未完成 $open',
      if (todayEvents.isEmpty)
        '📅 日程：今天没有安排'
      else
        for (final e in todayEvents.take(3))
          '📅 ${e.start.hour.toString().padLeft(2, '0')}:${e.start.minute.toString().padLeft(2, '0')} ${e.title}',
    ];
    return lines;
  }

  String _summaryText(List<Todo> todos, List<CalEvent> events) =>
      '【今日概览 · 自动生成】\n${_summaryLines(todos, events).join('\n')}\n';

  bool _sameDayNow(DateTime? a) =>
      a != null && JournalEntry.sameDay(a, DateTime.now());

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final todos = ref.watch(todosProvider).valueOrNull ?? const <Todo>[];
    final events = ref.watch(eventsProvider).valueOrNull ?? const <CalEvent>[];
    final entries = ref.watch(journalsProvider).valueOrNull ?? const <JournalEntry>[];
    final wd = _weekdays[_day.weekday - 1];

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 4,
        title: Row(
          children: [
            Text('${_day.year}-${_two(_day.month)}-${_two(_day.day)} 周$wd',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            const Spacer(),
            Text('${_ctl.text.length} 字',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.normal,
                    color: scheme.onSurfaceVariant)),
            const SizedBox(width: 8),
            AnimatedOpacity(
              opacity: _savedDraft ? 1 : 0,
              duration: const Duration(milliseconds: 250),
              child: Text('● 已自动保存草稿',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.normal,
                      color: const Color(0xFF10B981))),
            ),
            const SizedBox(width: 12),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Row(
              children: [
                _chip('📖 文档模式', !_insMode, () => setState(() => _insMode = false)),
                const SizedBox(width: 8),
                _chip('📱 INS 卡片流', _insMode, () => setState(() => _insMode = true)),
                const Spacer(),
                Text('布局切换',
                    style: TextStyle(
                        fontSize: 10, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          Expanded(
            child: _insMode
                ? ListView(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                    children: [
                      for (final e in entries)
                        InsDiaryCard(entry: e, onOpen: () {}),
                      const SizedBox(height: 6),
                      Center(
                        child: Text('📱 INS 卡片流 · 切回「📖 文档模式」继续编辑',
                            style: TextStyle(
                                fontSize: 10,
                                color: scheme.onSurfaceVariant)),
                      ),
                    ],
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                    children: [
                      // 心情 7 表情
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          for (var i = 0; i < kJournalMoods.length; i++)
                            GestureDetector(
                              key: ValueKey('jm-$i'),
                              onTap: () => setState(() => _mood = i + 1),
                              child: AnimatedScale(
                                scale: _mood == i + 1 ? 1.25 : 1,
                                duration: const Duration(milliseconds: 150),
                                child: Opacity(
                                  opacity:
                                      _mood == null || _mood == i + 1 ? 1 : .45,
                                  child: Text(kJournalMoods[i].$1,
                                      style: const TextStyle(fontSize: 24)),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      if (_mood != null)
                        Text('心情：${moodLabel(_mood)}',
                            style: TextStyle(
                                fontSize: 10, color: tokens.accent)),
                      const SizedBox(height: 10),
                      // 编辑器卡（工具条 + 纯文本）
                      Container(
                        decoration: BoxDecoration(
                          color: tokens.card,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: tokens.cardBorder),
                        ),
                        child: Column(
                          children: [
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(10, 4, 10, 4),
                              child: Row(
                                children: [
                                  _fmt('☑', '插入 ☐ 待办行', () {
                                    _insertAtCursor('☐ ');
                                    _focus.requestFocus();
                                  }),
                                  _fmt('🖼', null,
                                      () => _soon('图片附件 · 规划 V0.5')),
                                  _fmt('B', null,
                                      () => _soon('纯文本阶段 · 排版 M1 开放')),
                                  _fmt('≡', null,
                                      () => _soon('纯文本阶段 · 排版 M1 开放')),
                                  _fmt('❝', null,
                                      () => _soon('纯文本阶段 · 排版 M1 开放')),
                                  _fmt('M↓', null,
                                      () => _soon('Markdown · 规划 V0.5')),
                                ],
                              ),
                            ),
                            const Divider(height: 1),
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: TextField(
                                controller: _ctl,
                                focusNode: _focus,
                                minLines: 10,
                                maxLines: null,
                                keyboardType: TextInputType.multiline,
                                style: const TextStyle(
                                    fontSize: 14, height: 1.8),
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  hintText: '今天发生了什么？\n\n提示：输入 ☐ 可插入待办，保存后自动同步至任务列表',
                                ),
                                onChanged: _onChanged,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // 今日概览草稿（联动 L2 · 仅今天生成）
                      if (_isToday) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: tokens.card,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: tokens.cardBorder),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('今日概览草稿（自动生成 · 联动 L2）',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: scheme.onSurfaceVariant)),
                              const SizedBox(height: 6),
                              Text(
                                _summaryLines(todos, events).join(' ｜ '),
                                style: TextStyle(
                                    fontSize: 11.5,
                                    height: 1.7,
                                    color: scheme.onSurfaceVariant),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  TextButton(
                                    onPressed: () {
                                      _insertAtCursor(
                                          _summaryText(todos, events));
                                      _focus.requestFocus();
                                    },
                                    child: const Text('插入正文 ↑',
                                        style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800)),
                                  ),
                                  TextButton(
                                    onPressed: () => _soon(
                                        'AI 反思草稿 · 规划 V1.1（M3）'),
                                    child: Text('🤖 AI 生成反思草稿',
                                        style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            color: tokens.accent)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      // 图片占位三格
                      Row(
                        children: [
                          Expanded(
                            child: _mediaSlot('＋ 拍照',
                                () => _soon('图片附件 · 规划 V0.5')),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _mediaSlot('＋ 相册',
                                () => _soon('图片附件 · 规划 V0.5')),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Opacity(
                              opacity: .45,
                              child: Container(
                                height: 72,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                      color: tokens.cardBorder,
                                      style: BorderStyle.solid),
                                ),
                                child: const Text('🎙 语音 V1.x',
                                    style: TextStyle(fontSize: 11)),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12),
                              decoration: BoxDecoration(
                                color: tokens.card,
                                borderRadius: BorderRadius.circular(12),
                                border:
                                    Border.all(color: tokens.cardBorder),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _template,
                                  isExpanded: true,
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: scheme.onSurface),
                                  items: const [
                                    DropdownMenuItem(
                                        value: '模板：自由书写',
                                        child: Text('模板：自由书写')),
                                    DropdownMenuItem(
                                        value: '模板：感恩三件事',
                                        child: Text('模板：感恩三件事')),
                                    DropdownMenuItem(
                                        value: '模板：KPT 复盘',
                                        child: Text('模板：KPT 复盘')),
                                  ],
                                  onChanged: (v) {
                                    if (v == null) return;
                                    setState(() => _template = v);
                                    if (v.contains('感恩')) {
                                      _insertAtCursor(
                                          '感恩三件事：\n1. \n2. \n3. \n');
                                    } else if (v.contains('KPT')) {
                                      _insertAtCursor(
                                          'K 保持：\nP 问题：\nT 尝试：\n');
                                    }
                                  },
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          GestureDetector(
                            key: const ValueKey('diary-save'),
                            onTap: _save,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 28, vertical: 14),
                              decoration: BoxDecoration(
                                  gradient: tokens.gradient,
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: tokens.cardShadow),
                              child: const Text('保存',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, bool on, VoidCallback onTap) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: on ? tokens.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: on ? tokens.accent : tokens.cardBorder),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: on ? Colors.white : scheme.onSurface)),
      ),
    );
  }

  Widget _fmt(String icon, String? tip, VoidCallback onTap) {
    return IconButton(
      tooltip: tip,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 32),
      onPressed: onTap,
      icon: Text(icon, style: const TextStyle(fontSize: 15)),
    );
  }

  Widget _mediaSlot(String label, VoidCallback onTap) {
    final tokens = context.tokens;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 72,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: tokens.cardBorder.withValues(alpha: .25),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ),
    );
  }

  void _soon(String what) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text('$what · 敬请期待'),
          duration: const Duration(milliseconds: 1500)));
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
}
