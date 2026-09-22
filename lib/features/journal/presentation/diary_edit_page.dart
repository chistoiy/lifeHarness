import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/linkage/stats_providers.dart';
import '../domain/diary_template.dart';
import '../domain/journal_entry.dart';
import 'journal_providers.dart';
import 'widgets/image_attach.dart';

/// 路由参数：day=新建当天的第 N+1 篇；entryId=编辑既有某一篇（V1.28 一天多篇）。
class DiaryEditArg {
  const DiaryEditArg({this.day, this.entryId});
  final DateTime? day;
  final int? entryId;
}

/// 日记编辑页（原型 p-diaryEdit · V1.29轮12/批2b）：
/// 全屏沉浸头部=返回钮+居中日期（跨年显年月日）；自由书写=flutter_quill 富文本
/// （B/列表/待办/引用直接施加格式·图片内嵌·kind=rich Delta JSON 落库）；
/// 结构化模板分节仍纯文本；今日概览草稿默认折叠；☐ 待办同步（L3）；自动存草稿。
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
  int? _mood;
  JournalEntry? _existing;
  bool _dirty = false;
  Timer? _debounce;

  /// 当前模板（自由书写=单富文本；structured=分节卡·分节仍纯文本）。
  DiaryTemplate _tpl = DiaryTemplate.freeWrite;
  List<TextEditingController> _secCtrls = const [];

  /// 批2b：自由书写富文本（与笔记 rich 同构·Delta JSON·图片 BlockEmbed.image）。
  QuillController? _richCtl;
  final _richFocus = FocusNode();
  final _richScroll = ScrollController();
  String _lastRichJson = '';

  /// 轮12-1：今日概览草稿默认折叠，点标题行展开。
  bool _sumOpen = false;

  @override
  void initState() {
    super.initState();
    _day = JournalEntry.dayStart(widget.day ?? DateTime.now());
    // 首帧同步建空文档，_load 完成后回填（避免 QuillEditor 空控制器断言）
    _richCtl = _newRich('');
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(journalRepositoryProvider);
    JournalEntry? e;
    if (widget.entryId != null) {
      e = await repo.open(widget.entryId!); // 含分节装配
    }
    if (!mounted) return;
    setState(() {
      _existing = e;
      _mood = e?.mood;
      if (e != null && e.sections.isNotEmpty) {
        _applySections(
            e.sections.map((s) => TemplateSection(title: s.title)).toList(),
            bodies: e.sections.map((s) => s.body).toList());
        _tpl = DiaryTemplate(
            id: e.templateId, name: '模板', sections: const []); // 名称由列表刷新回填
      }
    });
    _rebuildRich(e == null || e.kind != 'rich'
        ? _seedRichFromPlain(e)
        : e.content);
    if (e != null && e.id != null) {
      await repo.markViewed(e.id!);
      ref.invalidate(journalsProvider);
    }
  }

  /// 旧纯文本篇 → 富文本种子 Delta：正文一段 + 图片语法行逐个转内嵌 image。
  static String _seedRichFromPlain(JournalEntry? e) {
    if (e == null || e.content.trim().isEmpty) return '';
    final body = JournalEntry.bodyWithoutImages(e.content);
    final ops = <Map<String, dynamic>>[];
    if (body.isNotEmpty) {
      ops.add({
        'insert': body.endsWith('\n') ? body : '$body\n'
      });
    }
    for (final p in e.imagePaths) {
      ops.add({
        'insert': {'image': p}
      });
      ops.add({'insert': '\n'});
    }
    return jsonEncode(ops);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _richCtl?.removeListener(_onRichChanged);
    _richCtl?.dispose();
    _richFocus.dispose();
    _richScroll.dispose();
    for (final c in _secCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  /// 应用模板：structured=生成分节控制器；自由书写=回富文本单区（内容保留）。
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

  /// 轮13：删除本篇（确认弹层；分节随删·图片文件保留应用目录）。
  Future<void> _confirmDelete() async {
    final id = _existing?.id;
    if (id == null) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (bc) => AlertDialog(
        title: const Text('删除这篇日记？'),
        content: const Text('删除后不可恢复。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(bc).pop(false),
              child: const Text('取消')),
          TextButton(
            key: const ValueKey('diary-del-ok'),
            onPressed: () => Navigator.of(bc).pop(true),
            child: const Text('删除',
                style: TextStyle(color: Color(0xFFF43F5E))),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    _dirty = false;
    await ref.read(journalRepositoryProvider).remove(id);
    if (!mounted) return;
    ref.invalidate(journalsProvider);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
          content: Text('日记已删除'),
          duration: Duration(milliseconds: 1400)));
    Navigator.of(context).pop();
  }

  bool get _isToday => JournalEntry.sameDay(_day, DateTime.now());

  /// 轮12-8：头部=居中「MM-DD 周几」；跨年历史篇补显年份。
  String get _headerDate {
    final wd = _weekdays[_day.weekday - 1];
    final ymd = '${_day.year}-${_two(_day.month)}-${_two(_day.day)}';
    return _day.year == DateTime.now().year
        ? '${_two(_day.month)}-${_two(_day.day)} 周$wd'
        : '$ymd 周$wd';
  }

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
  }

  /// 当前富文本 Delta JSON（未初始化/空文档=空串）。
  String get _richJson => _richCtl == null
      ? ''
      : jsonEncode(_richCtl!.document.toDelta().toJson());

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
      // 批2b：自由书写=富文本 Delta JSON（kind=rich·图片为内嵌 embed）；
      // 结构化篇 content 由仓储按分节渲染快照，kind 回落 ''。
      content: secs.isEmpty ? _richJson : '',
      templateId: secs.isEmpty ? null : _tpl.id,
      sections: secs,
      kind: secs.isEmpty ? 'rich' : '',
      createdAt: _existing?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    ));
    _existing = saved;
    if (notify) ref.invalidate(journalsProvider);
    return saved;
  }

  /// L3：正文中的 ☐ 行同步为待办（按标题去重，默认落「重要不紧急」·
  /// 富文本经 richToPlain 把 list=todo 属性还原为 ☐ 前缀）。
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
        ? '日记已保存 · ${_tpl.name}（${entry.sections.length} 节）'
        : '日记已保存';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(n > 0 ? '$head · ☐ 待办已同步（$n 条）' : head),
          duration: const Duration(milliseconds: 1600)));
    Navigator.of(context).pop();
  }

  /* ---------- 批2b · 富文本（与笔记 rich 同构·note_edit_page 同款手法） ---------- */

  Document _richDocFromContent(String content) {
    if (content.trim().isNotEmpty) {
      try {
        final data = jsonDecode(content);
        if (data is List) return Document.fromJson(data);
      } catch (_) {}
    }
    return Document.fromJson([
      {'insert': content.isEmpty ? '\n' : '$content\n'}
    ]);
  }

  QuillController _newRich(String content) => QuillController(
      document: _richDocFromContent(content),
      selection: const TextSelection.collapsed(offset: 0))
    ..addListener(_onRichChanged);

  /// 载入回填：换文档重建控制器（旧实例摘监听后释放），不标脏。
  void _rebuildRich(String content) {
    final old = _richCtl;
    old?.removeListener(_onRichChanged);
    final c = _newRich(content);
    _lastRichJson = jsonEncode(c.document.toDelta().toJson());
    setState(() => _richCtl = c);
    old?.dispose();
  }

  /// Quill 变更 → Delta JSON 比对过滤（选区变化也 notify），走既有防抖自动存草稿。
  void _onRichChanged() {
    if (!mounted) return;
    final c = _richCtl;
    if (c == null) return;
    final json = jsonEncode(c.document.toDelta().toJson());
    if (json == _lastRichJson) return;
    _lastRichJson = json;
    _onChanged(json);
  }

  void _richToggle(Attribute<dynamic> attr) {
    final c = _richCtl;
    if (c == null) return;
    final has = c.getSelectionStyle().attributes.containsKey(attr.key);
    c.formatSelection(has ? Attribute.clone(attr, null) : attr);
  }

  /// ≡ 列表：已是项目符号则还原，其余直切。
  void _richListAs(Attribute target) {
    final c = _richCtl;
    if (c == null) return;
    final cur = c.getSelectionStyle().attributes['list'];
    c.formatSelection(cur == target ? Attribute.clone(target, null) : target);
  }

  /// ☑ 键：无列表→待办(未勾)→已勾→清；其他列表型→待办。
  void _richTask() {
    final c = _richCtl;
    if (c == null) return;
    final cur = c.getSelectionStyle().attributes['list'];
    if (cur == null || cur == Attribute.ul || cur == Attribute.ol) {
      c.formatSelection(Attribute.unchecked);
    } else if (cur == Attribute.unchecked) {
      c.formatSelection(Attribute.checked);
    } else {
      c.formatSelection(Attribute.clone(Attribute.checked, null));
    }
  }

  /// 拍照/相册插图：公共链直取来源（跳过选择弹层）→ 当前选区内嵌 image embed。
  Future<void> _richImage({ImageSource? direct}) async {
    final tokens = context.tokens;
    final dest = await pickAndStoreImage(context,
        bg: tokens.card,
        fg: Theme.of(context).colorScheme.onSurface,
        direct: direct);
    if (dest == null || !mounted) return;
    final c = _richCtl;
    if (c == null) return;
    final idx = c.selection.baseOffset < 0
        ? c.document.length - 1
        : c.selection.baseOffset;
    c.replaceText(idx, 0, BlockEmbed.image(dest),
        TextSelection.collapsed(offset: idx + 1));
  }

  /// 概览插入正文：当前光标处逐行插入纯文本。
  void _insertAtCursor(String text) {
    final c = _richCtl;
    if (c == null) return;
    final pos = c.selection.baseOffset < 0 ? c.document.length - 1 : c.selection.baseOffset;
    c.replaceText(pos, 0, text,
        TextSelection.collapsed(offset: pos + text.length));
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

    return Scaffold(
      // 轮12-6/8：头部仅返回钮 + 居中日期周几（无标题/篇序/字数/保存态/搜索）
      appBar: AppBar(
        centerTitle: true,
        title: Text(_headerDate,
            key: const ValueKey('diary-head-date'),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        // 轮13：既有篇可删（确认弹层）；新篇未落库不显示
        actions: [
          if (_existing?.id != null)
            IconButton(
              key: const ValueKey('diary-del'),
              tooltip: '删除本篇',
              onPressed: _confirmDelete,
              icon: const Icon(Icons.delete_outline, size: 22),
            ),
        ],
      ),
      body: Column(
        children: [
          // 心情 7 表情（轮12-8：图标缩小）
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var i = 0; i < kJournalMoods.length; i++)
                  GestureDetector(
                    key: ValueKey('jm-$i'),
                    onTap: () => setState(() => _mood = i + 1),
                    child: AnimatedScale(
                      scale: _mood == i + 1 ? 1.2 : 1,
                      duration: const Duration(milliseconds: 150),
                      child: Opacity(
                        opacity: _mood == null || _mood == i + 1 ? 1 : .45,
                        child: Text(kJournalMoods[i].$1,
                            style: const TextStyle(fontSize: 17)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _secCtrls.isEmpty
                ? _freeWriteBody(context, tokens, scheme, todos, events)
                : _structuredBody(context, tokens, scheme, todos, events),
          ),
        ],
      ),
    );
  }

  /// 自由书写：编辑器卡（快捷栏+Quill）占满余下空间，概览/模板行固定在底部。
  Widget _freeWriteBody(BuildContext context, tokens, scheme,
      List<Todo> todos, List<CalEvent> events) {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Container(
              decoration: BoxDecoration(
                color: tokens.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: tokens.cardBorder),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
                    child: Row(
                      children: [
                        // 轮12-9：快捷栏按钮直接施加富文本格式（非 MD 语法）
                        _fmt('diary-bold', 'B', '加粗',
                            () => _richToggle(Attribute.bold)),
                        _fmt('diary-ul', '≡', '列表',
                            () => _richListAs(Attribute.ul)),
                        _fmt('diary-task', '☑', '待办勾选', _richTask),
                        _fmtIcon('diary-cam', Icons.photo_camera_outlined, '拍照',
                            () => _richImage(direct: ImageSource.camera)),
                        _fmtIcon('diary-album', Icons.image_outlined, '相册',
                            () => _richImage(direct: ImageSource.gallery)),
                        _fmtIcon(
                            'diary-mic',
                            Icons.mic_none,
                            '语音 V1.x',
                            () => _soon('语音 · V1.x'),
                            dim: true),
                        _fmt('diary-quote', '❝', '引用',
                            () => _richToggle(Attribute.blockQuote)),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                      child: QuillEditor(
                        key: const ValueKey('diary-rich-editor'),
                        controller: _richCtl!,
                        focusNode: _richFocus,
                        scrollController: _richScroll,
                        config: QuillEditorConfig(
                          padding: EdgeInsets.zero,
                          expands: true,
                          embedBuilders: const [NoteImageEmbedBuilder()],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            children: [
              if (_isToday) ...[
                _summaryCard(context, tokens, scheme, todos, events),
                const SizedBox(height: 12),
              ],
              _tplRow(context, tokens, scheme),
            ],
          ),
        ),
      ],
    );
  }

  /// 结构化模板：分节卡 ListView（分节仍纯文本）。
  Widget _structuredBody(BuildContext context, tokens, scheme,
      List<Todo> todos, List<CalEvent> events) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
      children: [
        Text('📋 ${_tpl.name} · ${_secCtrls.length} 节 · 各节独立保存',
            key: const ValueKey('tpl-applied'),
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w800, color: tokens.accent)),
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
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                  child: Text(_tpl.sections[i].title,
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: scheme.onSurfaceVariant)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                  child: TextField(
                    controller: _secCtrls[i],
                    minLines: 2,
                    maxLines: 6,
                    keyboardType: TextInputType.multiline,
                    style: const TextStyle(fontSize: 13.5, height: 1.7),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      hintText:
                          _tpl.sections[i].placeholder ?? '写点什么…',
                    ),
                    onChanged: (_) => setState(() => _dirty = true),
                  ),
                ),
              ],
            ),
          ),
        if (_isToday) ...[
          const SizedBox(height: 12),
          _summaryCard(context, tokens, scheme, todos, events),
        ],
        const SizedBox(height: 12),
        _tplRow(context, tokens, scheme),
      ],
    );
  }

  /// 轮12-1：今日概览草稿卡=默认折叠，点标题行展开/收起。
  Widget _summaryCard(BuildContext context, tokens, scheme,
      List<Todo> todos, List<CalEvent> events) {
    return Container(
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tokens.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            key: const ValueKey('diary-sum-head'),
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() => _sumOpen = !_sumOpen),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text('今日概览草稿（自动生成 · 联动 L2）',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: scheme.onSurfaceVariant)),
                  ),
                  Icon(_sumOpen ? Icons.expand_less : Icons.expand_more,
                      size: 18, color: scheme.onSurfaceVariant),
                ],
              ),
            ),
          ),
          if (_sumOpen)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _summaryLines(todos, events).join('\n'),
                    style: TextStyle(
                        fontSize: 11.5,
                        height: 1.7,
                        color: scheme.onSurfaceVariant),
                  ),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () {
                          _insertAtCursor(_summaryText(todos, events));
                          _richFocus.requestFocus();
                        },
                        child: const Text('插入正文 ↑',
                            style: TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w800)),
                      ),
                      TextButton(
                        onPressed: () =>
                            _soon('AI 反思草稿 · 规划 V1.1（M3）'),
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
      ),
    );
  }

  /// 模板选择行 + 保存钮（两种模式共用）。
  Widget _tplRow(BuildContext context, tokens, scheme) {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            key: const ValueKey('tpl-open-sheet'),
            onTap: _openTplSheet,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
              decoration: BoxDecoration(
                color: tokens.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: tokens.cardBorder),
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
            padding:
                const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
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
    );
  }

  Widget _fmt(String key, String icon, String? tip, VoidCallback onTap) {
    return IconButton(
      key: ValueKey(key),
      tooltip: tip,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 32),
      onPressed: onTap,
      icon: Text(icon, style: const TextStyle(fontSize: 15)),
    );
  }

  /// 线性图标版工具钮（拍照/相册/语音·禁 emoji）。
  Widget _fmtIcon(String key, IconData icon, String? tip, VoidCallback onTap,
      {bool dim = false}) {
    return IconButton(
      key: ValueKey(key),
      tooltip: tip,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 32),
      onPressed: onTap,
      icon: Opacity(
        opacity: dim ? .45 : 1,
        child: Icon(icon, size: 17),
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
