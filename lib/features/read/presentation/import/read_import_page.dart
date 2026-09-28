import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/read_import.dart';
import '../read_providers.dart';
import '../read_sheets.dart';

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
  List<int>? _lastBatch; // 撤销本批的摘录 id
  bool _busy = false;

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
        .commitImport(ch, _text.text);
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    final pack = _pack;
    final ch = _ch;
    return Scaffold(
      appBar: AppBar(centerTitle: true, title: const Text('导入其他平台读书笔记')),
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
              ],
            ),
    );
  }

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
    final fresh = rows.where((r) => r.bookId == null && !r.dup).length;
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
          for (var i = 0; i < rows.length; i++)
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
          if (rows.isNotEmpty)
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const ValueKey('imp-run'),
                onPressed: _busy
                    ? null
                    : (rows.length - dup > 0 || fresh > 0)
                    ? _run
                    : null,
                child: Text('导入 ${rows.length - dup} 条'),
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
