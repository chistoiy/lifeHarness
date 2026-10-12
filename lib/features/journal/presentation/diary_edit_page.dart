import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/ai/ai_review.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/linkage/stats_providers.dart';
import '../../../shared/weather/weather.dart';
import '../../../shared/weather/weather_visual.dart';
import '../domain/diary_template.dart';
import '../domain/journal_entry.dart';
import 'journal_providers.dart';
import 'widgets/diary_tpl_create_sheet.dart';
import 'widgets/mm_card_block.dart';
import '../../../shared/widgets/image_attach.dart';
import '../../../shared/widgets/ui_kit.dart' show AppToast;

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
  bool _saving = false; // 修复批（评估件 #5）：保存防重入，双击不出重篇
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

  /// 批2e：本篇天气快照（自动=当天抓一次落库 · 手动=覆盖后不再自动更新）。
  int? _wxCode;
  double? _wxMax;
  double? _wxMin;
  bool _wxManual = false;

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
    // 修复批（评估件 #1·P0）：既有结构化篇先按 templateId 回填模板名与分节定义
    // 再 setState（旧实现置空分节并注释「名称由列表刷新回填」，但全文件无回填，
    // 重开必在 _structuredBody 取标题处越界）。
    final defs =
        (e == null || e.sections.isEmpty) ? null : await _tplDefsFor(e);
    if (!mounted) return;
    setState(() {
      _existing = e;
      _mood = e?.mood;
      _wxCode = e?.weatherCode;
      _wxMax = e?.tempMax;
      _wxMin = e?.tempMin;
      _wxManual = e?.weatherManual ?? false;
      if (defs != null) {
        _applySections(
            defs.$2, bodies: e!.sections.map((s) => s.body).toList());
        _tpl = DiaryTemplate(
            id: e.templateId, name: defs.$1, sections: defs.$2);
      }
    });
    _rebuildRich(e == null || e.kind != 'rich'
        ? _seedRichFromPlain(e)
        : e.content);
    // 演示残留批（2026-10-12）：设置·记录管理「默认新建模板」= 新建时预选。
    // '纯文本'=维持自由书写；其余按名查模板（查无/无分节=回落，界面不出空模板）。
    // _pickTemplate 自带迁移防抖与 setState，此处无旧文不会误标脏。
    if (e == null) {
      final want = ref.read(settingsControllerProvider).journalDefaultTpl;
      if (want != '纯文本') {
        final tpls = await ref.read(diaryTemplateDaoProvider).list();
        for (final t in tpls) {
          if (t.name == want && t.sections.isNotEmpty) {
            _pickTemplate(t);
            break;
          }
        }
      }
    }
    if (e != null && e.id != null) {
      await repo.markViewed(e.id!);
      // 语义断链批 #26：回望计数单篇补丁（原整表 invalidate·每次打开全量重拉）。
      ref.read(journalsProvider.notifier).patch(e.copyWith(viewCount: e.viewCount + 1));
    }
    _ensureTodayWeather();
  }

  /// 既有结构化篇的分节定义解析（修复批 #1）：优先按 templateId 查 DAO 模板
  /// （回填真名与占位）；查无（模板已删/被改）或节数对不上 → 以既有篇存储分节补齐，
  /// 保证返回 defs.length == e.sections.length（_secCtrls 与 _tpl.sections
  /// 等长不变量由此建立，取标题/占位处不再越界）。
  Future<(String, List<TemplateSection>)> _tplDefsFor(JournalEntry e) async {
    final stored =
        e.sections.map((s) => TemplateSection(title: s.title)).toList();
    final tid = e.templateId;
    if (tid != null) {
      final tpls = await ref.read(diaryTemplateDaoProvider).list();
      for (final t in tpls) {
        if (t.id == tid && t.sections.isNotEmpty) {
          return (
            t.name,
            [
              for (var i = 0; i < stored.length; i++)
                i < t.sections.length ? t.sections[i] : stored[i],
            ],
          );
        }
      }
    }
    return ('模板', stored);
  }

  /// 批2e：写日记当天自动抓一次天气（城市未设置/已手动/已有快照=跳过；
  /// 无网由服务静默返回 null，不阻塞写作）。落库走 attachWeather 不打乱 updated_at。
  Future<void> _ensureTodayWeather() async {
    if (_wxManual || _wxCode != null || !_isToday || !mounted) return;
    final city =
        WeatherCity.decode(ref.read(settingsControllerProvider).weatherCity);
    if (city == null) return;
    final w = await ref.read(weatherServiceProvider).day(_day, city);
    if (w == null || !mounted) return;
    setState(() {
      _wxCode = w.code;
      _wxMax = w.tmax;
      _wxMin = w.tmin;
    });
    final id = _existing?.id;
    if (id != null) {
      await ref
          .read(journalRepositoryProvider)
          .attachWeather(id, code: w.code, tmax: w.tmax, tmin: w.tmin);
      if (!mounted) return;
      // #26：天气快照单篇补丁（原整表 invalidate）。
      ref.read(journalsProvider.notifier).patch(_existing!.copyWith(
          weatherCode: w.code, tempMax: w.tmax, tempMin: w.tmin));
    }
    // 修复批（评估件 #6·拍板「打开不落库」）：新草稿天气快照仅存页内态，
    // 随首次落库（输入自动存/退出 flush/手动保存）一并写入——
    // 不再打开编辑页即建空篇（列表幽灵篇源头）。
  }

  /// chip 点按：手动覆盖七选项（选后本篇不再自动更新）/ 恢复自动。
  Future<void> _openWxSheet() async {
    final r = await showWeatherPickSheet(context,
        current: _wxCode, manual: _wxManual, isToday: _isToday);
    if (r == null || !mounted) return;
    setState(() {
      if (r.restore) {
        _wxManual = false;
        _wxCode = null; // 恢复自动：当天重抓（城市未设置则保持空）
      } else {
        _wxCode = r.code;
        _wxManual = true;
      }
    });
    final id = _existing?.id;
    if (id != null) {
      await ref.read(journalRepositoryProvider).attachWeather(id,
          code: _wxCode, tmax: _wxMax, tmin: _wxMin, manual: _wxManual);
      // #26：手动覆盖单篇补丁；无 id（新草稿）走 _persist 落库，列表尚无该篇不需补。
      ref.read(journalsProvider.notifier).patch(_existing!.copyWith(
          weatherCode: _wxCode,
          tempMax: _wxMax,
          tempMin: _wxMin,
          weatherManual: _wxManual));
    } else {
      await _persist(notify: false);
    }
    if (!mounted) return;
    // UI/UX批（2026-10-12）：裸 SnackBar → AppToast 统一口径（下同，全文件共 6 处）。
    AppToast.show(context,
        r.restore ? '已恢复自动获取' : '本篇天气已手动设置 · 不再自动更新',
        ms: 1300);
    if (r.restore) _ensureTodayWeather();
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

  void _applySections(List<TemplateSection> secs, {List<String>? bodies}) {
    for (final c in _secCtrls) {
      c.dispose();
    }
    _secCtrls = [
      for (var i = 0; i < secs.length; i++)
        TextEditingController(text: bodies != null && i < bodies.length ? bodies[i] : '')
    ];
  }

  /// 应用模板：structured=生成分节控制器；自由书写=回富文本单区。
  /// 修复批（评估件 #4·拍板「旧文并入」）：切模板不弃稿——
  /// 结构化→结构化按节顺序搬（溢出非空节并入末节）；→自由书写合并为一段替换富文本
  /// （替换式回填：往返切换不重复叠加）；自由书写→结构化：富文本纯文进首节。
  /// 有迁移即标脏走既有防抖自动存。
  void _pickTemplate(DiaryTemplate t) {
    var migrated = false;
    final oldTexts = [for (final c in _secCtrls) c.text];
    _tpl = t;
    if (t.structured) {
      final bodies = List<String>.filled(t.sections.length, '');
      if (oldTexts.isNotEmpty) {
        for (var i = 0; i < oldTexts.length; i++) {
          if (oldTexts[i].trim().isEmpty) continue;
          migrated = true;
          if (i < bodies.length) {
            bodies[i] = oldTexts[i];
          } else {
            bodies[bodies.length - 1] = bodies[bodies.length - 1].isEmpty
                ? oldTexts[i]
                : '${bodies[bodies.length - 1]}\n${oldTexts[i]}';
          }
        }
      } else {
        final plain = _richCtl?.document.toPlainText().trim() ?? '';
        if (plain.isNotEmpty) {
          bodies[0] = plain;
          migrated = true;
        }
      }
      _applySections(t.sections, bodies: bodies);
    } else {
      final merged = oldTexts.where((s) => s.trim().isNotEmpty).join('\n');
      for (final c in _secCtrls) {
        c.dispose();
      }
      _secCtrls = const [];
      if (merged.isNotEmpty) {
        migrated = true;
        _rebuildRich('$merged\n');
      }
    }
    if (migrated) {
      _dirty = true;
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 900), _autoSave);
    }
    setState(() {});
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
  /// 格面在同目录 `diary_tpl_create_sheet.dart`（思维导图批2 面5 · 本页已登记
  /// size_budget 1370 且只许减，故弹层抽走、本方法只留三行接线）。
  Future<void> _openTplCreateSheet() async {
    await showDiaryTplCreateSheet(
      context,
      dao: ref.read(diaryTemplateDaoProvider),
      onCreated: _pickTemplate,
      onListChanged: () {
        _tplListKey++;
        ref.invalidate(diaryTemplatesProvider);
      },
    );
  }

  /// 轮13 → 语义断链批（2026-10-12）：删除改进回收站（第八类），文案同步。
  /// 分节随篇保留（恢复可回）；图片文件保留应用目录。
  Future<void> _confirmDelete() async {
    final id = _existing?.id;
    if (id == null) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (bc) => AlertDialog(
        title: const Text('删除这篇日记？'),
        content: const Text('删除后进回收站，可随时恢复。'),
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
    AppToast.show(context, '已删除 · 回收站可恢复', ms: 1400);
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

  /// 批2e：心情行右侧天气 chip（线性图标+「晴 20~30°」·手动态加后缀；
  /// 未设置且不可抓=以「天气」空壳入口保留可点性）。
  Widget _wxChip(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final txt = _wxCode == null
        ? '天气'
        : '${weatherText(_wxCode!, tmax: _wxMax, tmin: _wxMin)}${_wxManual ? ' ·手动' : ''}';
    return InkWell(
      key: const ValueKey('diary-wx-chip'),
      borderRadius: BorderRadius.circular(999),
      onTap: _openWxSheet,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(_wxCode == null ? Icons.add : weatherIcon(_wxCode!),
              size: 14, color: scheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(txt,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant)),
        ]),
      ),
    );
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
    final titles = _secTitles(); // 修复批 #1：标题一律带回落（模板/既有篇/占位）
    final secs = [
      for (var i = 0; i < _secCtrls.length; i++)
        DiarySection(title: titles[i], body: _secCtrls[i].text),
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
      // 批2e：天气快照随保存携带（自动抓取/手动覆盖的当前态）
      weatherCode: _wxCode,
      tempMax: _wxMax,
      tempMin: _wxMin,
      weatherManual: _wxManual,
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

  /// 保存钮（manual=true）与返回拦截共用出口：flush 防抖尾稿 → 落库 → ☐ 同步 → 退。
  /// 修复批（评估件 #3 退出不保尾 + #5 防重入）：对齐笔记编辑页批3 同款；
  /// 空页点保存不落空篇（评估件 #6 同源）。
  Future<void> _save() => _saveAndExit(manual: true);

  bool get _hasInput =>
      _mood != null ||
      _secCtrls.any((c) => c.text.trim().isNotEmpty) ||
      (_richCtl?.document.toPlainText().trim().isNotEmpty ?? false);

  Future<void> _saveAndExit({bool manual = false}) async {
    if (_saving) return;
    _saving = true;
    try {
      if (manual && _existing?.id == null && !_dirty && !_hasInput) {
        if (!mounted) return;
        Navigator.of(context).pop(); // 空页保存=直接退，不建幽灵篇
        return;
      }
      _debounce?.cancel();
      if (manual || _dirty) {
        final entry = await _persist(notify: true);
        final n = await _syncTodoLines(entry.todoLines());
        _dirty = false;
        if (!mounted) return;
        if (manual) {
          final head = entry.structured
              ? '日记已保存 · ${_tpl.name}（${entry.sections.length} 节）'
              : '日记已保存';
          AppToast.show(
              context, n > 0 ? '$head · ☐ 待办已同步（$n 条）' : head);
        } else if (n > 0) {
          AppToast.show(context, '已自动保存 · ☐ 待办已同步');
        }
      }
      if (!mounted) return;
      // canPop=false 只拦系统返回（maybePop）；页内 pop 为强退，不再回环。
      Navigator.of(context).pop();
    } finally {
      _saving = false;
    }
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

  /// 连接点② 插导图卡片（批2 面5）：挑图 → 正文插 BlockEmbed（只存 map_id）。
  Future<void> _insertMmCard() async {
    final c = _richCtl;
    if (c == null) return;
    final mapId = await showMmCardPickSheet(context);
    if (mapId == null || !mounted) return;
    final idx =
        c.selection.baseOffset < 0 ? c.document.length - 1 : c.selection.baseOffset;
    c.replaceText(idx, 0, mmCardEmbed(mapId),
        TextSelection.collapsed(offset: idx + 1));
    c.replaceText(idx + 1, 0, '\n', TextSelection.collapsed(offset: idx + 2));
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

  /* ---------- 批4-B · AI 反思草稿（journal.reflect 能力点接线） ---------- */

  void _toast(String msg) {
    AppToast.show(context, msg);
  }

  /// 各节标题（编辑既有篇时 _tpl.sections 可能为空，回落既有篇/占位名）。
  List<String> _secTitles() => [
        for (var i = 0; i < _secCtrls.length; i++)
          if (i < _tpl.sections.length)
            _tpl.sections[i].title
          else if (_existing != null && i < _existing!.sections.length)
            _existing!.sections[i].title
          else
            '分节 ${i + 1}',
      ];

  /// 当日已写内容：结构化=各节非空正文（带节名）；自由书写=富文本纯文。
  String _writtenTodayText() {
    if (_secCtrls.isNotEmpty) {
      final titles = _secTitles();
      return [
        for (var i = 0; i < _secCtrls.length; i++)
          if (_secCtrls[i].text.trim().isNotEmpty)
            '${titles[i]}：${_secCtrls[i].text.trim()}',
      ].join('\n');
    }
    return _richCtl?.document.toPlainText().trim() ?? '';
  }

  bool _aiReflectBusy = false;

  /// AI 生成反思草稿：当日已写内容（今日再加概览行）→ journal.reflect 审阅弹层
  /// → aiConfirmWrite 确认 → 有「反思/复盘」节直填该节，无则进正文
  /// （自由书写=光标处插富文本；结构化=尾部追加「反思」节），标注「AI 生成 · 可编辑」。
  Future<void> _genReflection() async {
    if (_aiReflectBusy) return;
    final body = _writtenTodayText();
    if (body.trim().isEmpty) {
      _toast('先写下今天的所见所感，AI 才有反思素材');
      return;
    }
    _aiReflectBusy = true;
    try {
      final todos = ref.read(todosProvider).valueOrNull ?? const <Todo>[];
      final events = ref.read(eventsProvider).valueOrNull ?? const <CalEvent>[];
      final content = [
        body,
        if (_isToday) ..._summaryLines(todos, events),
      ].join('\n');
      final res = await aiRunWithReview(context, ref,
          taskId: 'journal.reflect', vars: {'content': content});
      if (res == null) return; // 审阅取消或调用失败（已 toast 归因）
      final draft = (res.text ?? '').trim();
      if (draft.isEmpty) {
        _toast('AI 反思草稿为空 · 未写入');
        return;
      }
      if (!mounted) return;
      final marked = 'AI 生成 · 可编辑\n$draft';
      final ok =
          await aiConfirmWrite(context, title: '写入反思草稿', preview: marked);
      if (!ok || !mounted) return;
      setState(() {
        final titles = _secTitles();
        final i = titles
            .indexWhere((t) => t.contains('反思') || t.contains('复盘'));
        if (_secCtrls.isNotEmpty) {
          if (i >= 0) {
            final cur = _secCtrls[i].text.trimRight();
            _secCtrls[i].text = cur.isEmpty ? marked : '$cur\n\n$marked';
          } else {
            // 无反思节：正文尾部插入新「反思」节（先按现标题补齐模板分节定义）。
            _tpl = DiaryTemplate(
                id: _tpl.id,
                name: _tpl.name,
                sections: [
                  for (var k = 0; k < _secCtrls.length; k++)
                    TemplateSection(title: titles[k]),
                  const TemplateSection(title: '反思'),
                ]);
            _secCtrls = [
              ..._secCtrls,
              TextEditingController(text: marked),
            ];
          }
          _dirty = true; // 程序化改控制器不触发 onChanged：手动走既有防抖自动存
          _debounce?.cancel();
          _debounce = Timer(const Duration(milliseconds: 900), _autoSave);
        } else {
          _insertAtCursor('\n$marked\n'); // 自由书写：进富文本正文（监听器自动存草稿）
        }
      });
      _toast('AI 反思草稿已写入 · 可编辑');
    } finally {
      _aiReflectBusy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final todos = ref.watch(todosProvider).valueOrNull ?? const <Todo>[];
    final events = ref.watch(eventsProvider).valueOrNull ?? const <CalEvent>[];

    return PopScope(
      // 修复批（评估件 #3）：退出拦截 flush 尾稿（对齐笔记编辑页批3 同款）。
      // canPop=false 只拦系统返回（maybePop → _saveAndExit flush 后强退）；
      // 页内 pop（保存钮/删除后退出）为强退，直接真退不回环。
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _saveAndExit();
      },
      child: Scaffold(
      // 轮12-6/8：头部仅返回钮 + 居中日期周几（无标题/篇序/字数/保存态/搜索）
      appBar: AppBar(
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
          // 心情 7 表情（轮12-8：图标缩小）+ 批2e 右侧天气小 chip
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
            child: Row(
              children: [
                Expanded(
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
                const SizedBox(width: 8),
                _wxChip(context),
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
                        _fmtIcon('diary-mm-card', Icons.account_tree_outlined,
                            '导图卡片', _insertMmCard),
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
                          embedBuilders: const [
                            NoteImageEmbedBuilder(),
                            MmCardEmbedBuilder(),
                          ],
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
    final titles = _secTitles(); // 修复批 #1：带回落统一取，不裸下标
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
                  child: Text(titles[i],
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
                      hintText: i < _tpl.sections.length
                          ? (_tpl.sections[i].placeholder ?? '写点什么…')
                          : '写点什么…',
                    ),
                    // 修复批（评估件 #2）：结构化分节同走防抖自动存
                    // （旧实现只置脏不排 Timer，「输入即存」在结构化模式失效）。
                    onChanged: _onChanged,
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
                        key: const ValueKey('diary-ai-reflect'),
                        onPressed: _genReflection,
                        child: Text('AI 生成反思草稿',
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
    AppToast.show(context, '$what · 敬请期待', ms: 1500);
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
}
