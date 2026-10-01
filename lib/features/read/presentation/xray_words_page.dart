/// V1.54.1 批2 · X-Ray 词库管理页（原型 p-xrwords）。
///
/// GLOBAL 养成词库全量增删改查：列表（词/类型/动作/时间）＋改名/改动作/删除
/// ＋新增置顶＋类型筛选；「启用养成词库」开关行（`read.xrUserDict`，默认开；
/// 关＝纯预置视角：面板隐藏我的词条并恢复被屏蔽词、解析不叠加用户层；
/// 已物化状态行不回滚，重开即恢复）。导入导出随批3。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/logging/app_log.dart';

import '../data/xray/xray_dao.dart';
import '../../../core/database/schema/xray.dart' as xs;
import 'reader/reader_xray_learn_sheets.dart' show xrGuessType;
import 'reader/reader_xray_panel.dart' show kXrTypes;
import 'read_providers.dart';
import 'read_sheets.dart' show readToast;

const _xrMuted = Color(0xFF94A3B8);
const _xrAccent = Color(0xFF6366F1);
const _xrRose = Color(0xFFF43F5E);
const _xrViolet = Color(0xFF7C3AED);

/// 类型徽着色（与面板 _Badge 六类同表）。
const _typeColor = {
  'per': Color(0xFF6366F1),
  'loc': Color(0xFF059669),
  'org': Color(0xFFB45309),
  'term': Color(0xFF0284C7),
  'abbr': Color(0xFF475569),
  'book': Color(0xFFDB2777),
};

String _typeLabel(String t) =>
    kXrTypes.firstWhere((x) => x.$1 == t, orElse: () => ('', t)).$2;

/// 养成词库开关的统一读口（管理页与面板头共用一个键）。
bool xrUserDictOn(WidgetRef ref) =>
    ref.watch(readKvProvider(('read.xrUserDict', 'true'))).valueOrNull != 'false';

class XrayWordsPage extends ConsumerStatefulWidget {
  const XrayWordsPage({super.key});

  @override
  ConsumerState<XrayWordsPage> createState() => _XrayWordsPageState();
}

class _XrayWordsPageState extends ConsumerState<XrayWordsPage> {
  List<XrayDictRow> _rows = const [];
  bool _loading = true;
  String _type = 'all';
  String _q = '';
  final _addCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _addCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final rows = await ref.read(xrayDaoProvider).listGlobalDict();
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  Future<void> _flipUserDict() async {
    // 回调内只能 read（watch 仅限 build）；键值即取即翻。
    final onNow =
        ref.read(readKvProvider(('read.xrUserDict', 'true'))).valueOrNull !=
            'false';
    final next = onNow ? 'false' : 'true';
    await ref.read(readRepositoryProvider).setKv('read.xrUserDict', next);
    ref.read(readTickProvider.notifier).state++;
    if (mounted) {
      readToast(
        context,
        next == 'true'
            ? '养词库已开启 · 我的词条与屏蔽恢复生效'
            : '已切纯预置视角 · 已整理状态不回滚，重开即恢复',
      );
    }
  }

  Future<void> _add() async {
    final w = _addCtrl.text.trim();
    if (w.isEmpty) {
      readToast(context, '先输入词');
      return;
    }
    if (_rows.any((r) => r.word == w)) {
      readToast(context, '该词已在词库');
      return;
    }
    await ref.read(xrayDaoProvider).putUserWord(
          scope: xs.xrayScopeGlobal,
          word: w,
          action: xs.xrayActAdd,
          type: xrGuessType(w),
        );
    _addCtrl.clear();
    await _load();
    if (mounted) readToast(context, '已养入「$w」· 重解析与补扫时生效');
  }

  Future<void> _rename(XrayDictRow r) async {
    final ctrl = TextEditingController(text: r.word);
    final nn = await showDialog<String>(
      context: context,
      builder: (sc) => AlertDialog(
        title: const Text('改名', style: TextStyle(fontSize: 15)),
        content: TextField(
          key: const ValueKey('xrwRenameIn'),
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(sc), child: const Text('取消')),
          TextButton(
              key: const ValueKey('xrwRenameGo'),
              onPressed: () => Navigator.pop(sc, ctrl.text.trim()),
              child: const Text('确定')),
        ],
      ),
    );
    if (nn == null || nn.isEmpty || nn == r.word) return;
    await ref.read(xrayDaoProvider)
        .updateGlobalDict(word: r.word, action: r.action, newWord: nn);
    await _load();
    if (mounted) readToast(context, '已改名「$nn」');
  }

  Future<void> _flipAction(XrayDictRow r) async {
    await ref.read(xrayDaoProvider).updateGlobalDict(
          word: r.word,
          action: r.action,
          toAction:
              r.action == xs.xrayActAdd ? xs.xrayActForbid : xs.xrayActAdd,
        );
    await _load();
    if (mounted) readToast(context, '已更新动作');
  }

  Future<void> _del(XrayDictRow r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (sc) => AlertDialog(
        title: const Text('删除养成词', style: TextStyle(fontSize: 15)),
        content: Text('「${r.word}」将从全局词库移除（各书已索引不受影响）。',
            style: const TextStyle(fontSize: 12.5)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(sc, false),
              child: const Text('取消')),
          TextButton(
            key: const ValueKey('xrwDelGo'),
            onPressed: () => Navigator.pop(sc, true),
            child: const Text('删除', style: TextStyle(color: _xrRose)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(xrayDaoProvider).deleteGlobalDict(r.word, action: r.action);
    await _load();
    if (mounted) readToast(context, '已删除「${r.word}」');
  }

  // ---------------------------------------------- 批3 · .xrwords 导入导出

  Future<void> _export() async {
    final saved = await ref.read(xrayWordsIoProvider).exportWords();
    if (!mounted) return;
    readToast(context,
        saved == null ? '已取消导出' : '已导出 ${_rows.length} 条 · $saved');
  }

  Future<void> _import() async {
    Map<String, Object?>? bundle;
    try {
      bundle = await ref.read(xrayWordsIoProvider).readPick();
    } on FormatException catch (e) {
      AppLog.add('xrwords 导入拒收：${e.message}', level: LhLevel.warn);
      if (!mounted) return;
      readToast(context, e.message);
      return;
    } catch (e) {
      AppLog.add('xrwords 导入读取失败：$e', level: LhLevel.warn);
      if (!mounted) return;
      readToast(context, '读取失败：$e');
      return;
    }
    if (bundle == null) {
      if (!mounted) return;
      readToast(context, '已取消导入');
      return;
    }
    if (!mounted) return;
    final (entries, parseSkipped) =
        ref.read(xrayWordsIoProvider).parseEntries(bundle);
    // 预检计数：对照当前 GLOBAL 行算新增/覆盖，确认后才落库。
    final keys = _rows.map((r) => '${r.word}|${r.action}').toSet();
    var add = 0, upd = 0;
    for (final e in entries) {
      keys.contains('${e.word}|${e.action}') ? upd++ : add++;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (sc) => AlertDialog(
        title: const Text('导入养成词', style: TextStyle(fontSize: 15)),
        content: Text(
          '包内 ${entries.length + parseSkipped} 条 · 新增 $add · 覆盖 $upd'
          '${parseSkipped > 0 ? ' · 跳过 $parseSkipped' : ''}\n'
          '合并进全局词库（同名同动作覆盖），不影响按书词条。',
          style: const TextStyle(fontSize: 12.5),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(sc, false),
              child: const Text('取消')),
          TextButton(
            key: const ValueKey('xrwImpGo'),
            onPressed: () => Navigator.pop(sc, true),
            child: const Text('导入', style: TextStyle(color: _xrAccent)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final r = await ref.read(xrayDaoProvider).importGlobalDict(entries);
    await _load();
    if (mounted) {
      readToast(context,
          '导入完成 · 新增 ${r.added} · 覆盖 ${r.updated} · 跳过 ${r.skipped + parseSkipped}');
    }
  }

  List<XrayDictRow> get _filtered {
    final q = _q.trim();
    return _rows.where((r) {
      if (_type != 'all' && r.type != _type) return false;
      return q.isEmpty || r.word.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final on = xrUserDictOn(ref);
    final rows = _filtered;
    return Scaffold(
      appBar: AppBar(centerTitle: true, title: const Text('X-Ray 词库管理')),
      body: ListView(
        key: const ValueKey('xrwScroll'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Container(
            key: const ValueKey('xrwToggleCard'),
            padding: const EdgeInsets.all(14),
            decoration: _card(cs),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('启用养成词库',
                          style: TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                        '关＝纯预置视角：隐藏我的词条并恢复被屏蔽词 · 已整理状态不回滚，重开即恢复',
                        style:
                            TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Switch(
                  key: const ValueKey('xrwToggle'),
                  value: on,
                  onChanged: (_) => _flipUserDict(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            key: const ValueKey('xrwIoCard'),
            padding: const EdgeInsets.all(14),
            decoration: _card(cs),
            child: Column(
              children: [
                GestureDetector(
                  key: const ValueKey('xrwExp'),
                  behavior: HitTestBehavior.opaque,
                  onTap: _export,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        const Text('导出养成词库（.xrwords）',
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w700)),
                        const Spacer(),
                        Text('${_rows.length} 条 · 预置指纹随包',
                            style: TextStyle(
                                fontSize: 10, color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ),
                GestureDetector(
                  key: const ValueKey('xrwImp'),
                  behavior: HitTestBehavior.opaque,
                  onTap: _import,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        const Text('从文件导入',
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w700)),
                        const Spacer(),
                        Text('合并进全局词库 · 覆盖需确认',
                            style: TextStyle(
                                fontSize: 10, color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: _card(cs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${_rows.length} 个养成词 · ${on ? '养词库生效中' : '纯预置视角（开关已关）'}',
                    key: const ValueKey('xrwSum'),
                    style: TextStyle(
                        fontSize: 11, color: cs.onSurfaceVariant)),
                const SizedBox(height: 8),
                TextField(
                  key: const ValueKey('xrwSearchIn'),
                  onChanged: (v) => setState(() => _q = v),
                  style: const TextStyle(fontSize: 12),
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: '搜索养入的词…',
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 30,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final t in [('all', '全部'), ...kXrTypes])
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: GestureDetector(
                            key: ValueKey('xrw-tp-${t.$1}'),
                            onTap: () => setState(() => _type = t.$1),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 11, vertical: 5),
                              decoration: BoxDecoration(
                                color: _type == t.$1
                                    ? _xrAccent
                                    : const Color(0x2994A3B8),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '${t.$2} · ${t.$1 == 'all' ? _rows.length : _rows.where((r) => r.type == t.$1).length}',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  color: _type == t.$1
                                      ? Colors.white
                                      : const Color(0xFF64748B),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('xrwAddInp'),
                        controller: _addCtrl,
                        onSubmitted: (_) => _add(),
                        style: const TextStyle(fontSize: 12),
                        decoration: const InputDecoration(
                          isDense: true,
                          hintText: '新增养入词…',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      key: const ValueKey('xrwAddGo'),
                      onPressed: _add,
                      child: const Text('添加',
                          style: TextStyle(
                              fontSize: 11.5, fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Text(
                _rows.isEmpty ? '还没有养成词 · 阅读中长按选词即可养入' : '该筛选没有养成词',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, color: _xrMuted),
              ),
            )
          else
            for (final (i, r) in rows.indexed)
              Container(
                key: ValueKey('xrw-row-$i-${r.word}-${r.action}'),
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: _card(cs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(r.word,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800)),
                        ),
                        const SizedBox(width: 6),
                        _badge(
                          r.type == null ? '词' : _typeLabel(r.type!),
                          color:
                              _typeColor[r.type] ?? _xrAccent,
                        ),
                        const SizedBox(width: 4),
                        _badge(
                          r.action == xs.xrayActAdd ? '加词' : '屏蔽',
                          color: r.action == xs.xrayActAdd
                              ? _xrViolet
                              : _xrRose,
                        ),
                        const Spacer(),
                        Text(_fmtTime(r.createTime),
                            style: TextStyle(
                                fontSize: 9, color: cs.onSurfaceVariant)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        TextButton(
                          key: ValueKey('xrw-rn-$i'),
                          onPressed: () => _rename(r),
                          child:
                              const Text('改名', style: TextStyle(fontSize: 11)),
                        ),
                        TextButton(
                          key: ValueKey('xrw-fl-$i'),
                          onPressed: () => _flipAction(r),
                          child: Text(
                            r.action == xs.xrayActAdd ? '改屏蔽' : '改加词',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          key: ValueKey('xrw-del-$i'),
                          onPressed: () => _del(r),
                          child: const Text('删除',
                              style:
                                  TextStyle(fontSize: 11, color: _xrRose)),
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

  static String _fmtTime(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  static BoxDecoration _card(ColorScheme cs) => BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: .5)),
      );

  static Widget _badge(String text, {required Color color}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 8.5, fontWeight: FontWeight.w900, color: color)),
      );
}
