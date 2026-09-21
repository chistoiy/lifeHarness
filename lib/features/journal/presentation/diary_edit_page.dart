import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/linkage/stats_providers.dart';
import '../domain/diary_template.dart';
import '../domain/journal_entry.dart';
import 'journal_providers.dart';
import 'widgets/ins_card.dart';

/// 路由参数：day=新建当天的第 N+1 篇；entryId=编辑既有某一篇（V1.28 一天多篇）。
class DiaryEditArg {
  const DiaryEditArg({this.day, this.entryId});
  final DateTime? day;
  final int? entryId;
}

/// 日记编辑页（原型 p-diaryEdit）：一天多篇 · 每篇各带心情 · 纯文本/真结构分节模板
/// + 模板管理底部弹层（内置+自定义 · ＋新建）+ 今日概览草稿（L2）+ ☐ 待办同步（L3）
/// + 自动存草稿 + INS 卡片流预览。
class DiaryEditPage extends ConsumerStatefulWidget {
  const DiaryEditPage({super.key, this.day, this.entryId});

  final DateTime? day;
  final int? entryId;

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

  /// 本篇当日序号（1 起）；新建=当日篇数+1。
  int _entryNo = 1;

  /// 当前模板（null/自由书写=单文本；structured=分节卡）。
  DiaryTemplate _tpl = DiaryTemplate.freeWrite;
  List<TextEditingController> _secCtrls = const [];

  @override
  void initState() {
    super.initState();
    _day = JournalEntry.dayStart(widget.day ?? DateTime.now());
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(journalRepositoryProvider);
    final dayEntries = await repo.listByDay(_day); // 新→旧
    JournalEntry? e;
    var no = dayEntries.length + 1; // 新建=第 N+1 篇
    if (widget.entryId != null) {
      e = await repo.open(widget.entryId!); // 含分节装配
      final asc = dayEntries.reversed.toList(); // 旧→新，最早=第 1 篇
      no = asc.indexWhere((x) => x.id == widget.entryId) + 1;
      if (no <= 0) no = 1;
    }
    if (!mounted) return;
    setState(() {
      _existing = e;
      _ctl.text = e?.content ?? '';
      _mood = e?.mood;
      _entryNo = no;
      if (e != null && e.sections.isNotEmpty) {
        _applySections(
            e.sections.map((s) => TemplateSection(title: s.title)).toList(),
            bodies: e.sections.map((s) => s.body).toList());
        _tpl = DiaryTemplate(
            id: e.templateId, name: '模板', sections: const []); // 名称由列表刷新回填
      }
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
    for (final c in _secCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  /// 应用模板：structured=生成分节控制器；自由书写=回单文本（正文保留）。
  void _applySections(List<TemplateSection> secs, {List<String>? bodies}) {
    for (final c in _secCtrls) {
      c.dispose();
    }
    _secCtrls = [
      for (var i = 0; i < secs.length; i++)
        TextEditingController(text: bodies != null && i < bodies.length ? bodies[i] : '')
    ];
  }

  void _pickTemplate(DiaryTemplate t) {
    setState(() {
      _tpl = t;
      if (t.structured) {
        _applySections(t.sections);
      } else {
        for (final c in _secCtrls) {
          c.dispose();
        }
        _secCtrls = const [];
      }
    });
  }

  /// 模板管理底部弹层（原型 sheetDiaryTpl）：应用/删除/＋新建。
  Future<void> _openTplSheet() async {
    final dao = ref.read(diaryTemplateDaoProvider);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (bc) => StatefulBuilder(
        builder: (bc2, setLocal) => FutureBuilder(
          key: ValueKey(_tplListKey),
          future: dao.list(),
          builder: (ctx, snap) {
            final tpls = <DiaryTemplate>[
              DiaryTemplate.freeWrite,
              ...?snap.data,
            ];
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('📋 日记模板',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 10),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final t in tpls)
                          GestureDetector(
                            key: ValueKey('tpl-row-${t.id ?? 'free'}'),
                            onTap: () {
                              _pickTemplate(t);
                              Navigator.of(bc2).pop();
                            },
                            child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: bc2.tokens.card,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: t.id == _tpl.id ||
                                          (t.id == null && _tpl.id == null)
                                      ? bc2.tokens.accent
                                      : bc2.tokens.cardBorder,
                                  width: t.id == _tpl.id ||
                                          (t.id == null && _tpl.id == null)
                                      ? 2
                                      : 1),
                            ),
                            child: Row(children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(t.id == null ? '自由书写' : t.name,
                                        style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800)),
                                    Text(
                                        t.structured
                                            ? '${t.sections.length} 节 · 结构化分节'
                                            : '单文本 · 自由书写',
                                        style: TextStyle(
                                            fontSize: 10,
                                            color: Theme.of(bc2).colorScheme.onSurfaceVariant)),
                                  ],
                                ),
                              ),
                              if (t.id != null && !t.builtin)
                                TextButton(
                                  key: ValueKey('tpl-del-${t.id}'),
                                  onPressed: () async {
                                    await dao.remove(t.id!);
                                    setLocal(() => _tplListKey++);
                                    ref.invalidate(diaryTemplatesProvider);
                                  },
                                  child: const Text('删除',
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFFF43F5E))),
                                ),
                              if (t.id == _tpl.id ||
                                  (t.id == null && _tpl.id == null))
                                Text('✓',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        color: bc2.tokens.accent)),
                            ]),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    key: const ValueKey('tpl-new'),
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () async {
                        Navigator.of(bc2).pop();
                        await _openTplCreateSheet();
                      },
                      child: const Text('＋ 新建模板',
                          style:
                              TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
    // 弹层关闭后同步当前模板快照（可能被删）
    final kept = await dao.list();
    if (!mounted) return;
    if (_tpl.id != null && !kept.any((t) => t.id == _tpl.id)) {
      _pickTemplate(DiaryTemplate.freeWrite);
    }
  }

  int _tplListKey = 0;

  /// 新建模板弹层（原型 sheetDiaryTplEdit）：名称 + 分节增删。
  Future<DiaryTemplate?> _openTplCreateSheet() async {
    final dao = ref.read(diaryTemplateDaoProvider);
    final nameCtl = TextEditingController();
    final secTitle = [TextEditingController(), TextEditingController()];
    final secPh = [TextEditingController(), TextEditingController()];
    final tokens = context.tokens;
    var addTick = 0;
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (bc) => StatefulBuilder(
        builder: (bc2, setLocal) => Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16,
              24 + MediaQuery.viewInsetsOf(bc2).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('新建模板',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('tpl-name'),
                controller: nameCtl,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                    isDense: true, hintText: '模板名称，如：每日三省'),
              ),
              const SizedBox(height: 10),
              Text('分节',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: tokens.accent)),
              const SizedBox(height: 6),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (var i = 0; i < secTitle.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          key: ValueKey('tpl-sec-$i-$addTick'),
                          children: [
                            Expanded(
                              child: TextField(
                                controller: secTitle[i],
                                style: const TextStyle(fontSize: 12.5),
                                decoration: InputDecoration(
                                    isDense: true,
                                    hintText: '分节 ${i + 1} 标题，如：今日高光'),
                              ),
                            ),
                            IconButton(
                              onPressed: () {
                                if (secTitle.length <= 1) return;
                                setLocal(() {
                                  secTitle[i].dispose();
                                  secPh[i].dispose();
                                  secTitle.removeAt(i);
                                  secPh.removeAt(i);
                                  addTick++;
                                });
                              },
                              icon: const Icon(Icons.close, size: 16),
                            ),
                          ],
                        ),
                      ),
                    TextButton(
                      key: const ValueKey('tpl-add-sec'),
                      onPressed: () => setLocal(() {
                        secTitle.add(TextEditingController());
                        secPh.add(TextEditingController());
                        addTick++;
                      }),
                      child: const Text('＋ 添加分节',
                          style:
                              TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                        onPressed: () => Navigator.of(bc2).pop(false),
                        child: const Text('取消')),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      key: const ValueKey('tpl-save'),
                      onTap: () async {
                        final name = nameCtl.text.trim();
                        final secs = [
                          for (var i = 0; i < secTitle.length; i++)
                            if (secTitle[i].text.trim().isNotEmpty)
                              TemplateSection(
                                  title: secTitle[i].text.trim(),
                                  placeholder: secPh[i].text.trim().isEmpty
                                      ? null
                                      : secPh[i].text.trim()),
                        ];
                        if (name.isEmpty || secs.isEmpty) {
                          ScaffoldMessenger.of(bc2).showSnackBar(const SnackBar(
                              content: Text('请填写模板名称与至少一个分节'),
                              duration: Duration(milliseconds: 1400)));
                          return;
                        }
                        final id = await dao
                            .create(DiaryTemplate(name: name, sections: secs));
                        if (!bc2.mounted) return;
                        Navigator.of(bc2).pop(true);
                        if (bc2.mounted) {
                          ScaffoldMessenger.of(bc2)
                            ..hideCurrentSnackBar()
                            ..showSnackBar(SnackBar(
                                content: Text('模板已创建 · $name'),
                                duration:
                                    const Duration(milliseconds: 1400)));
                        }
                        // 直接应用新模板
                        final all = await dao.list();
                        final created2 = all.firstWhere((t) => t.id == id);
                        _pickTemplate(created2);
                      },
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(
                            gradient: tokens.gradient,
                            borderRadius: BorderRadius.circular(12)),
                        child: const Text('保存模板',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 13)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (created == true) {
      _tplListKey++;
      ref.invalidate(diaryTemplatesProvider);
    }
    return null;
  }

  bool get _isToday => JournalEntry.sameDay(_day, DateTime.now());

  /// 字数：单文本=正文；结构化=各节合计。
  int get _totalChars => _secCtrls.isEmpty
      ? _ctl.text.length
      : _secCtrls.fold(0, (a, c) => a + c.text.length);

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
    final secs = [
      for (var i = 0; i < _secCtrls.length; i++)
        DiarySection(
            title: i < _tpl.sections.length
                ? _tpl.sections[i].title
                : '分节 ${i + 1}',
            body: _secCtrls[i].text),
    ];
    final saved = await repo.save(JournalEntry(
      id: _existing?.id,
      day: _day,
      mood: _mood,
      content: _ctl.text,
      templateId: secs.isEmpty ? null : _tpl.id,
      sections: secs,
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
    final head = entry.structured
        ? '日记已保存 · 今天第 $_entryNo 篇 · ${_tpl.name}（${entry.sections.length} 节）'
        : '日记已保存 · 今天第 $_entryNo 篇';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(n > 0 ? '$head · ☐ 待办已同步（$n 条）' : head),
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
            const SizedBox(width: 8),
            Text('第 $_entryNo 篇',
                key: const ValueKey('entry-no'),
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: tokens.accent)),
            const Spacer(),
            Text('$_totalChars 字',
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
                        Text('本篇心情：${moodLabel(_mood)}',
                            style: TextStyle(
                                fontSize: 10, color: tokens.accent)),
                      const SizedBox(height: 10),
                      if (_secCtrls.isEmpty) ...[
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
                      ] else ...[
                      // 结构化模板：分节卡（各节独立保存 · 原型「N 节 · 各节独立保存」）
                      Text('📋 ${_tpl.name} · ${_secCtrls.length} 节 · 各节独立保存',
                          key: const ValueKey('tpl-applied'),
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: tokens.accent)),
                      for (var i = 0; i < _secCtrls.length; i++)
                        Container(
                          key: ValueKey('sec-$i'),
                          margin: const EdgeInsets.only(top: 8),
                          decoration: BoxDecoration(
                            color: tokens.card,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: tokens.cardBorder),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(12, 10, 12, 0),
                                child: Text(_tpl.sections[i].title,
                                    style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w800,
                                        color: scheme.onSurfaceVariant)),
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(12, 4, 12, 10),
                                child: TextField(
                                  controller: _secCtrls[i],
                                  minLines: 2,
                                  maxLines: 6,
                                  keyboardType: TextInputType.multiline,
                                  style: const TextStyle(
                                      fontSize: 13.5, height: 1.7),
                                  decoration: InputDecoration(
                                    border: InputBorder.none,
                                    isDense: true,
                                    hintText: _tpl.sections[i].placeholder ??
                                        '写点什么…',
                                  ),
                                  onChanged: (_) =>
                                      setState(() => _dirty = true),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
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
                            child: GestureDetector(
                              key: const ValueKey('tpl-open-sheet'),
                              onTap: _openTplSheet,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 15),
                                decoration: BoxDecoration(
                                  color: tokens.card,
                                  borderRadius: BorderRadius.circular(12),
                                  border:
                                      Border.all(color: tokens.cardBorder),
                                ),
                                child: Text(
                                  '📋 模板：${_tpl.id == null ? '自由书写' : _tpl.name} ▾',
                                  key: const ValueKey('tpl-label'),
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: scheme.onSurface),
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
