import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/azw3_import.dart';
import '../../data/ebook_exception.dart';
import '../../data/mobi_import.dart';
import '../../data/offline_meta.dart';
import '../../data/plain_book_import.dart';
import '../../data/read_import.dart';
import '../../data/text_import.dart';
import '../read_providers.dart';
import '../read_sheets.dart';
import '../reader/epub_state_ui.dart' show brStartPreload;

/// 导入向导（原型 p-readimport · 计划 §5）：五类渠道 chips + 渠道卡 +
/// 粘贴解析预览（三级去重逐行标 新增/已存在/将建档）+ 整批导入 + 撤销本批 +
/// 按清单建书。渠道格式全部来自 assets/read_import 数据包，不改码即可扩渠道。
class ReadImportPage extends ConsumerStatefulWidget {
  const ReadImportPage({super.key});

  @override
  ConsumerState<ReadImportPage> createState() => _ReadImportPageState();
}

class _ReadImportPageState extends ConsumerState<ReadImportPage> {
  ImportPack? _pack;
  String _cat = 'file';
  String _chId = 'kindle';
  final _text = TextEditingController();
  List<ImportRow>? _rows;

  /// 逐条勾选（预览行下标）。解析完默认全选「非重复」项——用户要的是
  /// 「先看再挑」，不是「要么全导要么别导」（2026-10-29 产品报障）。
  Set<int> _picked = <int>{};
  List<int>? _lastBatch; // 撤销本批的摘录 id
  bool _busy = false;

  // ---- C09 离线元数据批量粘贴（纯本地解析，零请求）----
  final _metaText = TextEditingController();
  List<({String title, String author, String? isbn})>? _metaRows;
  List<ExternalIdEntry> _metaExt = const [];
  String _metaSource = '离线粘贴';
  bool _metaBusy = false;

  // ---- C12 TXT / FB2 本地文本导入（纯 Dart 解析 → 最小 EPUB）----
  final _docText = TextEditingController();
  String _docFmt = 'TXT';
  String _docName = '';
  String _docEncoding = 'utf-8';
  String? _docWarn;
  TextBookDraft? _docDraft;
  bool _docBusy = false;

  ImportChannel? get _ch => _pack?.byId(_chId);

  @override
  void initState() {
    super.initState();
    ImportPack.load().then((p) {
      if (mounted) setState(() => _pack = p);
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _metaText.dispose();
    _docText.dispose();
    super.dispose();
  }

  void _pickCat(String c) => setState(() {
    _cat = c;
    final first = _pack?.ofCat(c).firstOrNull;
    if (first != null) _pick(first.id);
  });

  void _pick(String id) => setState(() {
    _chId = id;
    _rows = null;
    _lastBatch = null;
    _text.clear();
  });

  Future<void> _parse() async {
    final ch = _ch;
    if (ch == null || _text.text.trim().isEmpty) return;
    setState(() => _busy = true);
    final rows = await ref.read(readRepositoryProvider).previewImport(
      ch,
      _text.text,
    );
    if (mounted) {
      setState(() {
        _rows = rows;
        _picked = {
          for (var i = 0; i < rows.length; i++)
            if (!rows[i].dup) i,
        };
        _busy = false;
      });
    }
  }

  Future<void> _run() async {
    final ch = _ch;
    if (ch == null) return;
    setState(() => _busy = true);
    final out = await ref
        .read(readRepositoryProvider)
        .commitImport(ch, _text.text, only: _picked);
    if (!mounted) return;
    setState(() {
      _lastBatch = out.ids;
      _busy = false;
    });
    _parse();
    ref.read(readTickProvider.notifier).state++;
    readToast(
      context,
      '已导入 ${out.added} 条 · 跳过重复 ${out.skipped} 条'
      '${out.booksCreated > 0 ? ' · 新建 ${out.booksCreated} 本' : ''} · 来源 ${ch.name}',
    );
  }

  Future<void> _undo() async {
    final ids = _lastBatch;
    if (ids == null || ids.isEmpty) return;
    final n = await ref.read(readRepositoryProvider).undoImportBatch(ids);
    if (!mounted) return;
    setState(() => _lastBatch = null);
    _parse();
    ref.read(readTickProvider.notifier).state++;
    readToast(context, '已撤销本批 · 移除 $n 条摘录');
  }

  Future<void> _allBooks() async {
    final ch = _ch;
    if (ch == null || _text.text.trim().isEmpty) return;
    setState(() => _busy = true);
    final r = await ref
        .read(readRepositoryProvider)
        .importBookList(_text.text, ch: ch);
    if (!mounted) return;
    setState(() => _busy = false);
    ref.read(readTickProvider.notifier).state++;
    readToast(
      context,
      '已按清单建 ${r.created} 本（想读）· 跳过重复 ${r.skipped} 条 · 同名同 ISBN 不重复建',
    );
  }

  // ==================== C09 离线元数据（批量粘贴 · 本地解析） ====================

  void _parseMeta() {
    final raw = _metaText.text;
    final metas = parseClipboardBatch(raw);
    final src = metas
        .map((m) => m.source)
        .firstWhere((s) => s.isNotEmpty, orElse: () => '');
    setState(() {
      _metaRows = clipboardBookRows(metas);
      _metaExt = parseExternalIdBatch(raw);
      _metaSource = clipboardSourceLabel(src);
    });
  }

  Future<void> _commitMeta() async {
    final rows = _metaRows;
    if (rows == null || rows.isEmpty) return;
    setState(() => _metaBusy = true);
    final r = await ref.read(readRepositoryProvider).importBookRows(
      [
        for (final x in rows)
          ParsedBookRow(title: x.title, author: x.author, isbn: x.isbn),
      ],
      source: _metaSource,
    );
    if (!mounted) return;
    setState(() {
      _metaBusy = false;
      _metaRows = null;
      _metaExt = const [];
      _metaSource = '离线粘贴';
      _metaText.clear();
    });
    ref.read(readTickProvider.notifier).state++;
    readToast(
      context,
      '离线元数据已写入 · 新建 ${r.created} 本 · 跳过重复 ${r.skipped} 条',
    );
  }

  // ==================== C12 TXT / FB2（本地文本 → 可读书籍） ====================

  Future<void> _pickDocFile() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['txt', 'fb2', 'azw3', 'mobi'],
      withData: true,
    );
    if (r == null || r.files.isEmpty) return;
    final f = r.files.first;
    final bytes = f.bytes;
    if (bytes == null || bytes.isEmpty) {
      if (!mounted) return;
      readToast(context, '文件读取失败或为空，请重新选择');
      return;
    }
    final ext = (f.extension ?? '').toLowerCase();
    if (ext == 'azw3' || ext == 'mobi') {
      await _openBinaryDoc(f.name, bytes, ext);
      return;
    }
    final dec = decodeBookBytes(bytes);
    if (!mounted) return;
    setState(() {
      _docName = f.name;
      _docFmt = ext == 'fb2' ? 'FB2' : 'TXT';
      _docText.text = dec.text;
      _docEncoding = dec.encoding;
      _docWarn = dec.warning;
      _docDraft = null;
    });
  }

  /// AZW3 / MOBI：二进制容器，直接解析成草稿（不经过可编辑文本框）。
  Future<void> _openBinaryDoc(String name, List<int> bytes, String ext) async {
    setState(() => _docBusy = true);
    try {
      final draft = ext == 'azw3'
          ? parseAzw3Draft(bytes, fileName: name)
          : parseMobiDraft(bytes, fileName: name);
      if (!mounted) return;
      setState(() {
        _docBusy = false;
        _docName = name;
        _docFmt = draft.format;
        _docText.clear();
        _docEncoding = draft.encoding;
        _docWarn = draft.warnings.isEmpty ? null : draft.warnings.join('\n');
        _docDraft = draft;
      });
    } on EbookFormatException catch (e) {
      // catch-ok: 坏包/DRM/不支持压缩必须把明确原因原样给用户，不静默降级。
      if (!mounted) return;
      setState(() {
        _docBusy = false;
        _docDraft = null;
        _docWarn = null;
      });
      readToast(context, '无法导入 $name：${e.reason}');
    } catch (_) {
      // catch-ok: 兜底防崩，仍给出可操作提示（纯本地解析，无网络副作用）。
      if (!mounted) return;
      setState(() {
        _docBusy = false;
        _docDraft = null;
        _docWarn = null;
      });
      readToast(context, '解析 $name 失败：文件可能损坏，请换 EPUB / TXT 重试');
    }
  }

  void _parseDoc() {
    if (_docFmt == 'AZW3' || _docFmt == 'MOBI') {
      readToast(context, '$_docFmt 是二进制容器，请点右上「选择文件」导入');
      return;
    }
    final raw = _docText.text;
    if (raw.trim().isEmpty) {
      setState(() => _docDraft = null);
      readToast(context, '先粘贴全文或选择 TXT / FB2 文件');
      return;
    }
    final draft = _docFmt == 'FB2'
        ? parseFb2Draft(
            raw,
            fileName: _docName.isEmpty ? null : _docName,
            encoding: _docEncoding,
            warnings: [if (_docWarn != null) _docWarn!],
          )
        : parseTxtDraft(
            raw,
            fileName: _docName.isEmpty ? null : _docName,
            encoding: _docEncoding,
            warnings: [if (_docWarn != null) _docWarn!],
          );
    setState(() => _docDraft = draft);
  }

  Future<void> _commitDoc() async {
    final draft = _docDraft;
    if (draft == null || draft.isEmpty) return;
    setState(() => _docBusy = true);
    try {
      final b = await PlainBookImportService(
        ref.read(readRepositoryProvider),
      ).commit(draft);
      if (!mounted) return;
      setState(() {
        _docBusy = false;
        _docDraft = null;
        _docText.clear();
        _docName = '';
        _docFmt = 'TXT';
        _docWarn = null;
      });
      ref.read(readTickProvider.notifier).state++;
      brStartPreload(ref, b, context);
      readToast(
        context,
        '《${b.title}》已由 ${draft.format} 本地转换并加入书架 · '
        '${draft.chapters.length} 章 · 正在后台预载',
      );
    } catch (_) {
      // catch-ok: 写盘/建书失败已在屏上 toast 明示，导入页不中断（纯本地，无网络）。
      if (!mounted) return;
      setState(() => _docBusy = false);
      readToast(context, '生成书籍失败，请检查文件内容后重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    final pack = _pack;
    final ch = _ch;
    return Scaffold(
      appBar: AppBar(title: const Text('导入其他平台读书笔记')),
      body: pack == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _card(
                  cs,
                  tokens,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _title(cs, tokens, '导入方式'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final c in ImportPack.catOrder)
                            _chip(
                              cs,
                              tokens,
                              keyName: 'imp-cat-$c',
                              label: ImportPack.catLabels[c]!,
                              on: _cat == c,
                              onTap: () => _pickCat(c),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final x in pack.ofCat(_cat))
                            _channelCard(cs, tokens, x),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                _metaCard(cs, tokens),
                const SizedBox(height: 10),
                _docCard(cs, tokens),
                const SizedBox(height: 10),
                if (ch != null && ch.parser == 'none')
                  _card(
                    cs,
                    tokens,
                    child: Column(
                      key: const ValueKey('imp-hint'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _title(cs, tokens, ch.name),
                        const SizedBox(height: 6),
                        Text(
                          ch.hint,
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.6,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  )
                else if (ch != null) ...[
                  _card(
                    cs,
                    tokens,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _title(cs, tokens, '粘贴导出内容'),
                            const Spacer(),
                            TextButton(
                              key: const ValueKey('imp-sample'),
                              onPressed: () => setState(() {
                                _text.text = ch.sample;
                                _rows = null;
                              }),
                              child: Text(
                                '填入示例',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: tokens.accent,
                                ),
                              ),
                            ),
                          ],
                        ),
                        TextField(
                          key: const ValueKey('imp-text'),
                          controller: _text,
                          maxLines: 6,
                          style: const TextStyle(fontSize: 12),
                          decoration: InputDecoration(
                            hintText: '${ch.name} · ${ch.fmt}',
                            hintStyle: TextStyle(
                              fontSize: 11.5,
                              color: cs.onSurfaceVariant,
                            ),
                            filled: true,
                            fillColor: cs.surfaceContainerHighest
                                .withValues(alpha: .35),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton(
                                key: const ValueKey('imp-parse'),
                                onPressed: _busy ? null : _parse,
                                child: const Text('解析预览'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (_rows != null) _previewCard(cs, tokens, ch, _rows!),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          key: const ValueKey('imp-all'),
                          onPressed: _busy ? null : _allBooks,
                          icon: const Icon(Icons.playlist_add, size: 16),
                          label: const Text('按清单建书'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          key: const ValueKey('imp-undo'),
                          onPressed: (_lastBatch?.isNotEmpty ?? false) &&
                                  !_busy
                              ? _undo
                              : null,
                          icon: const Icon(Icons.undo, size: 16),
                          label: const Text('撤销本批'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '导入只写本地库；原文与想法分列存储，位置自动折算为百分比进度。',
                    style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                  ),
                ],
                const SizedBox(height: 10),
                _unsupportedCard(cs, tokens),
              ],
            ),
    );
  }

  /// C09：批量粘贴 → 本地正则解析 → 预览 → 确认写入书架（不联网）。
  Widget _metaCard(ColorScheme cs, ThemeTokens tokens) {
    final rows = _metaRows;
    return _card(
      cs,
      tokens,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title(cs, tokens, '批量粘贴 · 离线元数据'),
          const SizedBox(height: 4),
          Text(
            '粘贴书目信息（书名 / 作者 / ISBN / 页码）或影音游「来源:id」清单 · '
            '纯本地解析，零请求',
            style: TextStyle(fontSize: 10.5, height: 1.5, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('imp-meta-text'),
            controller: _metaText,
            maxLines: 5,
            style: const TextStyle(fontSize: 12),
            decoration: InputDecoration(
              hintText: '《书名》\n作者：张三\nISBN 9787111000000',
              hintStyle: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              filled: true,
              fillColor: cs.surfaceContainerHighest.withValues(alpha: .35),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('imp-meta-parse'),
                  onPressed: _metaBusy ? null : _parseMeta,
                  child: const Text('解析预览'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  key: const ValueKey('imp-meta-commit'),
                  onPressed: _metaBusy || rows == null || rows.isEmpty
                      ? null
                      : _commitMeta,
                  child: Text(rows == null ? '确认写入' : '写入 ${rows.length} 本'),
                ),
              ),
            ],
          ),
          if (rows != null) ...[
            const SizedBox(height: 8),
            Text(
              '书目 ${rows.length} 条 · 来源 $_metaSource · '
              '影音游 external_id ${_metaExt.length} 条',
              key: const ValueKey('imp-meta-sum'),
              style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
            ),
            for (var i = 0; i < rows.length && i < 20; i++)
              Container(
                key: ValueKey('imp-meta-row-$i'),
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: .35),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        rows[i].author.isEmpty
                            ? rows[i].title
                            : '${rows[i].title} · ${rows[i].author}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (rows[i].isbn != null)
                      Text(
                        rows[i].isbn!,
                        style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
            if (rows.length > 20)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '… 其余 ${rows.length - 20} 条将在确认写入时一并创建',
                  style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                ),
              ),
            if (_metaExt.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '影音游映射：${_metaExt.take(4).map((e) => '${e.source}:${e.id}').join(' · ')}'
                  '${_metaExt.length > 4 ? ' …等 ${_metaExt.length} 条' : ''}'
                  ' · 仅本地预览（媒体库写入侧本轮未开放）',
                  key: const ValueKey('imp-meta-ext'),
                  style: TextStyle(
                    fontSize: 10,
                    height: 1.5,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  /// C12：TXT / FB2 粘贴或选文件 → 解析预览 → 生成可读书籍（最小 EPUB）。
  Widget _docCard(ColorScheme cs, ThemeTokens tokens) {
    final d = _docDraft;
    return _card(
      cs,
      tokens,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _title(cs, tokens, '本地书籍 · TXT / FB2 / AZW3 / MOBI'),
              const Spacer(),
              TextButton(
                key: const ValueKey('imp-doc-pick'),
                onPressed: _docBusy ? null : _pickDocFile,
                child: Text(
                  '选择文件',
                  style: TextStyle(fontSize: 11.5, color: tokens.accent),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '纯 Dart 解析（UTF-8 / GBK 自动识别）· AZW3 / MOBI 为实验性支持，'
            'DRM 加密仍拒绝 · 本地转成可读书籍，不上传、不联网',
            style: TextStyle(fontSize: 10.5, height: 1.5, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            children: [
              for (final f in const ['TXT', 'FB2', 'AZW3', 'MOBI'])
                _chip(
                  cs,
                  tokens,
                  keyName: 'imp-doc-fmt-$f',
                  label: f,
                  on: _docFmt == f,
                  onTap: () => setState(() {
                    _docFmt = f;
                    _docDraft = null;
                  }),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('imp-doc-text'),
            controller: _docText,
            maxLines: 5,
            enabled: _docFmt != 'AZW3' && _docFmt != 'MOBI',
            style: const TextStyle(fontSize: 12),
            decoration: InputDecoration(
              hintText: switch (_docFmt) {
                'FB2' => '粘贴 FB2（XML）全文，或点右上「选择文件」',
                'AZW3' => 'AZW3 是 ZIP 容器，请点右上「选择文件」',
                'MOBI' => 'MOBI 是二进制容器，请点右上「选择文件」',
                _ => '粘贴 TXT 全文，或点右上「选择文件」',
              },
              hintStyle: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              filled: true,
              fillColor: cs.surfaceContainerHighest.withValues(alpha: .35),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          if (_docName.isNotEmpty || _docWarn != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                [
                  if (_docName.isNotEmpty) '文件：$_docName · 编码 $_docEncoding',
                  if (_docWarn != null) _docWarn!,
                ].join('\n'),
                key: const ValueKey('imp-doc-warn'),
                style: TextStyle(
                  fontSize: 10,
                  height: 1.5,
                  color: _docWarn == null ? cs.onSurfaceVariant : cs.error,
                ),
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('imp-doc-parse'),
                  onPressed: _docBusy ? null : _parseDoc,
                  child: const Text('解析预览'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  key: const ValueKey('imp-doc-commit'),
                  onPressed: _docBusy || d == null || d.isEmpty
                      ? null
                      : _commitDoc,
                  child: Text(_docBusy ? '生成中…' : '生成书籍'),
                ),
              ),
            ],
          ),
          if (d != null)
            Container(
              key: const ValueKey('imp-doc-preview'),
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: .35),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '《${d.title}》${d.author.isEmpty ? '' : ' · ${d.author}'}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${d.format} · 章节 ${d.chapters.length} · ${d.charCount} 字 · '
                    '编码 ${d.encoding}',
                    style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                  ),
                  if (d.chapters.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      d.chapterSummary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                    ),
                  ],
                  for (final w in d.warnings)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        w,
                        style: TextStyle(fontSize: 10, height: 1.4, color: cs.error),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// C13 口径：真不支持与「实验性支持」分列（不静默降级、不建空书）。
  Widget _unsupportedCard(ColorScheme cs, ThemeTokens tokens) {
    final unsupported = kUnsupportedReadFormats
        .where((f) => !f.experimental)
        .toList(growable: false);
    final experimental = kUnsupportedReadFormats
        .where((f) => f.experimental)
        .toList(growable: false);
    return _card(
      cs,
      tokens,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.block, size: 14, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              _title(cs, tokens, '不支持的格式（不静默降级）'),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '以下格式本页不解析、不建空书、不冒充成功；请先转成 EPUB / TXT / FB2。',
            style: TextStyle(fontSize: 10.5, height: 1.5, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          for (final f in unsupported)
            Padding(
              key: ValueKey('imp-unsup-${f.ext}'),
              padding: const EdgeInsets.only(top: 4),
              child: _formatRow(cs, f, tag: '.${f.ext}'),
            ),
          if (experimental.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.science_outlined, size: 14, color: tokens.accent),
                const SizedBox(width: 6),
                _title(cs, tokens, '实验性支持（已接入解析）'),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '可尝试导入；遇到 DRM 加密或 HUFF/CDIC 压缩会明确拒绝并说明原因。',
              style: TextStyle(fontSize: 10.5, height: 1.5, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            for (final f in experimental)
              Padding(
                key: ValueKey('imp-exp-${f.ext}'),
                padding: const EdgeInsets.only(top: 4),
                child: _formatRow(cs, f, tag: '实验 · ${f.ext}'),
              ),
          ],
        ],
      ),
    );
  }

  Widget _formatRow(ColorScheme cs, UnsupportedReadFormat f, {required String tag}) =>
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              tag,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${f.name} · ${f.reason}',
              style: TextStyle(
                fontSize: 10,
                height: 1.45,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      );

  Widget _channelCard(ColorScheme cs, ThemeTokens tokens, ImportChannel x) {
    final on = x.id == _chId;
    return GestureDetector(
      key: ValueKey('imp-ch-${x.id}'),
      onTap: () => _pick(x.id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: on
              ? tokens.accent.withValues(alpha: .08)
              : cs.surfaceContainerHighest.withValues(alpha: .3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: on ? tokens.accent : cs.outlineVariant.withValues(alpha: .5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              x.name,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
            Text(
              x.fmt,
              style: TextStyle(fontSize: 9.5, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _previewCard(
    ColorScheme cs,
    ThemeTokens tokens,
    ImportChannel ch,
    List<ImportRow> rows,
  ) {
    final dup = rows.where((r) => r.dup).length;
    return _card(
      cs,
      tokens,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _title(cs, tokens, '${ch.name} · 解析预览'),
              const Spacer(),
              Text(
                '${rows.length} 条 · 重复 $dup 条',
                key: const ValueKey('imp-sum'),
                style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '去重键：${ch.dedupKey}${ch.fields.isNotEmpty ? ' · 可带字段：${ch.fields}' : ''}',
            style: TextStyle(fontSize: 10.5, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '已选 ${_picked.length}/${rows.where((r) => !r.dup).length}',
                key: const ValueKey('imp-picked'),
                style: TextStyle(fontSize: 10.5, color: cs.onSurfaceVariant),
              ),
              const Spacer(),
              TextButton(
                key: const ValueKey('imp-pick-all'),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 28),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                onPressed: () => setState(() {
                  final all = <int>{
                    for (var i = 0; i < rows.length; i++)
                      if (!rows[i].dup) i,
                  };
                  _picked = _picked.length == all.length ? <int>{} : all;
                }),
                child: Text(
                  _picked.length == rows.where((r) => !r.dup).length
                      ? '全不选'
                      : '全选',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          for (var i = 0; i < rows.length; i++) ...[
            // 章节/卷分隔：连续同章节只出一枚标题。**顺序不动**——勾选用行下标，
            // 重排会让「第 i 行」与用户的点选对不上。
            if (i == 0 || rows[i].clip.chapter != rows[i - 1].clip.chapter)
              if ((rows[i].clip.chapter ?? '').isNotEmpty)
                Padding(
                  key: ValueKey('imp-ch-$i'),
                  padding: const EdgeInsets.only(top: 6, bottom: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 3,
                        height: 11,
                        decoration: BoxDecoration(
                          color: tokens.accent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          rows[i].clip.chapter!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            Container(
              key: ValueKey('imp-row-$i'),
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: .35),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Checkbox(
                        key: ValueKey('imp-check-$i'),
                        value: _picked.contains(i),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        onChanged: rows[i].dup
                            ? null
                            : (v) => setState(() {
                                  if (v == true) {
                                    _picked.add(i);
                                  } else {
                                    _picked.remove(i);
                                  }
                                }),
                      ),
                      const SizedBox(width: 2),
                      Flexible(
                        child: Text(
                          rows[i].clip.book,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          [
                            if ((rows[i].clip.chapter ?? '').isNotEmpty)
                              rows[i].clip.chapter!,
                            if (rows[i].clip.page != null)
                              'P${rows[i].clip.page}',
                          ].join(' · '),
                          style: TextStyle(
                            fontSize: 10,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        rows[i].dup
                            ? '已存在 · 跳过'
                            : rows[i].bookId == null
                            ? '将建档 · 新增'
                            : '新增',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: rows[i].dup
                              ? const Color(0xFFD97706)
                              : const Color(0xFF0D9488),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    rows[i].clip.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, height: 1.5),
                  ),
                  if ((rows[i].clip.thought ?? '').isNotEmpty)
                    Text(
                      '想法：${rows[i].clip.thought}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (rows.isNotEmpty)
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const ValueKey('imp-run'),
                onPressed: _busy || _picked.isEmpty ? null : _run,
                child: Text('导入 ${_picked.length} 条'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _card(ColorScheme cs, ThemeTokens tokens, {required Widget child}) =>
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: .5)),
        ),
        child: child,
      );

  Widget _title(ColorScheme cs, ThemeTokens tokens, String t) => Text(
    t,
    style: TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w800,
      color: cs.onSurface,
    ),
  );

  Widget _chip(
    ColorScheme cs,
    ThemeTokens tokens, {
    required String keyName,
    required String label,
    required bool on,
    required VoidCallback onTap,
  }) => GestureDetector(
    key: ValueKey(keyName),
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: on
            ? tokens.accent
            : cs.surfaceContainerHighest.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: on ? Colors.white : cs.onSurfaceVariant,
        ),
      ),
    ),
  );
}
