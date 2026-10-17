import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/share_card.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../data/media_repo_list.dart';
import '../domain/media_item.dart';
import '../domain/media_list.dart';
import 'media_providers.dart';
import 'widgets/media_card.dart';

/// 影音单弹层组（批8b · 原型 `m-sheet-mlist` / `m-sheet-mlist-new` / `m-sheet-share`）。
///
/// 分享＝习惯模块定式：半屏预览＋复制文字版（TXT/MD 两档），存图吃公共
/// `captureShareCard` 真渲染通道（回执带真实路径，失败落 warn 日志不谎报）。

/// 一段达成时刻的分享行尾注（底稿行带日期＝原型 TXT 逐行 `· YYYY-MM-DD` 同构）。
String _mdsDateTail(MediaItem x) {
  final e = x.endedAt;
  if (e == null) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(e);
  return ' · ${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// 合计读数（分钟→小时一位小数；与屏内统计行同一算子＝刀3 钉的对账点）。
String mdsShareSum(List<MediaItem> items) {
  final m = items.fold<int>(0, (a, x) => a + x.durationMin);
  return '共 ${items.length} 条 · 合计 ${(m / 60).toStringAsFixed(1)} h';
}

/// TXT 文字版（原型 mlShareText 逐行同构：单名／类型行／编号条目行／合计行）。
String mdsShareTxt({
  required String name,
  required String typeLine,
  required List<MediaItem> items,
}) =>
    [
      name,
      typeLine,
      for (var i = 0; i < items.length; i++)
        '${i + 1}. ${items[i].title} · ${items[i].kind} · ${items[i].state}${_mdsDateTail(items[i])}',
      mdsShareSum(items),
    ].join('\n');

/// MD 文字版（原型 mlShareMd 同构：标题＋引用合计＋三列表格）。
String mdsShareMd({
  required String name,
  required List<MediaItem> items,
}) =>
    [
      '# $name',
      '> ${items.length} 条 · 合计 ${(items.fold<int>(0, (a, x) => a + x.durationMin) / 60).toStringAsFixed(1)} h',
      '',
      '| 条目 | 类型 | 状态 |',
      '| --- | --- | --- |',
      for (final x in items) '| ${x.title} | ${x.kind} | ${x.state} |',
    ].join('\n');

/// 底稿的类型行（＝原型 `年度底稿 · 完结档动态求得`）。
String mdsYearTypeLine(int year) => '$year 年度底稿 · 完结档动态求得';

/// 就地改名（原型＝标题换输入框；Flutter 形态＝半屏一个输入框＋保存，回车即存）。
Future<String?> showMediaListRenameSheet(
  BuildContext context,
  MediaList row,
) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _RenameSheet(initial: row.name),
  );
}

class _RenameSheet extends StatefulWidget {
  const _RenameSheet({required this.initial});

  final String initial;

  @override
  State<_RenameSheet> createState() => _RenameSheetState();
}

class _RenameSheetState extends State<_RenameSheet> {
  late final TextEditingController _c = TextEditingController(text: widget.initial);
  String? _err;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _save() {
    final v = _c.text.trim();
    if (v.isEmpty) {
      setState(() => _err = '单名不能为空');
      return;
    }
    if (v == widget.initial) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('改单名',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('ml-rename-input'),
              controller: _c,
              autofocus: true,
              onSubmitted: (_) => _save(),
              decoration: InputDecoration(
                errorText: _err,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const ValueKey('ml-rename-save'),
              onPressed: _save,
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 新建影音单（原型 `m-sheet-mlist-new`）：五档类型 chips＋就地输名。
/// 返回＝(单名, 类型键)，取消＝null；写库在调用方（弹层 pop 后不碰其 ref）。
Future<(String, String)?> showMediaListNewSheet(BuildContext context) {
  return showModalBottomSheet<(String, String)>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _NewSheet(),
  );
}

class _NewSheet extends StatefulWidget {
  const _NewSheet();

  @override
  State<_NewSheet> createState() => _NewSheetState();
}

class _NewSheetState extends State<_NewSheet> {
  final _c = TextEditingController();
  String _type = MediaItem.kMovie;
  String? _err;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _go() {
    final v = _c.text.trim();
    if (v.isEmpty) {
      setState(() => _err = '给这张单起个名');
      return;
    }
    Navigator.of(context).pop((v, _type));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('新建影音单',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final k in MediaList.typeOrder)
                  PillChip(
                    key: ValueKey('mln-type-$k'),
                    label: MediaList.typeLabels[k]!,
                    selected: _type == k,
                    onTap: () => setState(() => _type = k),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('mln-name'),
              controller: _c,
              onSubmitted: (_) => _go(),
              decoration: InputDecoration(
                labelText: '单名',
                errorText: _err,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const ValueKey('mln-go'),
              onPressed: _go,
              child: const Text('建好并进入'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 添加条目（详情面「＋ 添加条目」＝原型 `m-sheet-mlist` 选择半屏）：
/// 在册条目全列，已在本单的打勾；点行即加／即取消（当场落库，往返可逆）。
Future<void> showMediaListAddItemSheet(
  BuildContext context,
  ProviderContainer container,
  MediaList row,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AddItemSheet(row: row),
  );
}

class _AddItemSheet extends ConsumerWidget {
  const _AddItemSheet({required this.row});

  final MediaList row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bundle = ref.watch(mediaListsBundleProvider).valueOrNull;
    final items = ref.watch(mediaAllLiveItemsProvider).valueOrNull ?? const [];
    final inList = {for (final x in bundle?.of(row) ?? const <MediaItem>[]) x.id};
    return Container(
      height: MediaQuery.sizeOf(context).height * .7,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Column(
        children: [
          Text('添加条目 · ${row.name}',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Expanded(
            child: items.isEmpty
                ? const Center(child: Text('架上还没有条目'))
                : ListView(
                    children: [
                      for (final x in items)
                        ListTile(
                          key: ValueKey('ml-add-pick-${x.id}'),
                          dense: true,
                          title: Text(x.title,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('${x.kind} · ${x.state}',
                              style: const TextStyle(fontSize: 10)),
                          trailing: Icon(
                            inList.contains(x.id)
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                            size: 20,
                            color: inList.contains(x.id)
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.outline,
                          ),
                          onTap: () async {
                            final repo = ref.read(mediaRepositoryProvider);
                            final cur = [
                              for (final m in ref
                                      .read(mediaListsBundleProvider)
                                      .valueOrNull
                                      ?.of(row) ??
                                  const <MediaItem>[])
                                m.id,
                            ];
                            final next = inList.contains(x.id)
                                ? cur.where((i) => i != x.id).toList()
                                : [...cur, x.id];
                            await repo.setMembers(row.id, next);
                            final t = ref.read(mediaTickProvider.notifier);
                            t.state = t.state + 1;
                          },
                        ),
                    ],
                  ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const ValueKey('ml-add-close'),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('收起'),
            ),
          ),
        ],
      ),
    );
  }
}

/// 移入影音单（条目操作弹层动作＝原型动作面改真接线）：候选只列手动单，
/// 底稿不进候选（它由达成日求得，人工移入移出不成立）。
Future<void> showMediaListMoveSheet(
  BuildContext context,
  ProviderContainer container,
  MediaItem item,
) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => _MoveSheet(item: item),
  );
}

class _MoveSheet extends ConsumerWidget {
  const _MoveSheet({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bundle = ref.watch(mediaListsBundleProvider).valueOrNull;
    final lists = bundle?.lists ?? const [];
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('移入影音单 · ${item.title}',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          if (lists.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Text('还没有手动单 · 先去「影音单」建一张',
                  style: TextStyle(fontSize: 12)),
            )
          else
            for (final l in lists)
              ListTile(
                key: ValueKey('ml-move-${l.id}'),
                dense: true,
                title: Text(l.name),
                subtitle: Text(l.typeLabel,
                    style: const TextStyle(fontSize: 10)),
                trailing: Icon(
                  (bundle?.of(l) ?? const []).any((m) => m.id == item.id)
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  size: 20,
                ),
                onTap: () async {
                  final repo = ref.read(mediaRepositoryProvider);
                  final cur = [
                    for (final m in ref
                            .read(mediaListsBundleProvider)
                            .valueOrNull
                            ?.of(l) ??
                        const <MediaItem>[])
                      m.id,
                  ];
                  final next = cur.contains(item.id)
                      ? cur.where((i) => i != item.id).toList()
                      : [...cur, item.id];
                  await repo.setMembers(l.id, next);
                  final t = ref.read(mediaTickProvider.notifier);
                  t.state = t.state + 1;
                },
              ),
        ],
      ),
    );
  }
}

/// 分享长图（原型 `m-sheet-share`）：封面轨道预览（真渲染源）＋TXT/MD 切换
/// ＋复制文字版／保存图片。
Future<void> showMediaListShareSheet(
  BuildContext context, {
  required String name,
  required String typeLine,
  required List<MediaItem> items,
  required bool year,
  bool md = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ShareSheet(
        name: name, typeLine: typeLine, items: items, year: year, md: md),
  );
}

class _ShareSheet extends ConsumerStatefulWidget {
  const _ShareSheet({
    required this.name,
    required this.typeLine,
    required this.items,
    required this.year,
    this.md = false,
  });

  final String name;
  final String typeLine;
  final List<MediaItem> items;
  final bool year;

  /// 初始档（导出 MD＝直接落 MD 档；分享长图＝TXT）。
  final bool md;

  @override
  ConsumerState<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends ConsumerState<_ShareSheet> {
  final GlobalKey _boundary = GlobalKey(debugLabel: 'ml-share');
  late bool _md = widget.md;

  String get _text => _md
      ? mdsShareMd(name: widget.name, items: widget.items)
      : mdsShareTxt(
          name: widget.name, typeLine: widget.typeLine, items: widget.items);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .82,
      ),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('分享这张影音单',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            // 预览层＝保存图片的捕获源（习惯模块同法：所见即所得，不另画一张）。
            RepaintBoundary(
              key: _boundary,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    Text(widget.name,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text(widget.typeLine,
                        style: TextStyle(
                            fontSize: 9.5, color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 8),
                    if (widget.items.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Text('这张单还是空的'),
                      )
                    else
                      Row(
                        children: [
                          for (final x in widget.items.take(6))
                            Expanded(
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 2),
                                child: AspectRatio(
                                  aspectRatio: 3 / 4,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(5),
                                    child: MdsCoverArt(
                                        item: x, monoSize: 18),
                                  ),
                                ),
                              ),
                            ),
                          if (widget.items.length > 6)
                            Text('+${widget.items.length - 6}',
                                style: const TextStyle(fontSize: 10)),
                        ],
                      ),
                    const SizedBox(height: 6),
                    Text(mdsShareSum(widget.items),
                        style: TextStyle(
                            fontSize: 9.5,
                            color: scheme.onSurfaceVariant,
                            fontFeatures: kMdsShareTabular)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                PillChip(
                  key: const ValueKey('mlsh-fmt-txt'),
                  label: 'TXT',
                  selected: !_md,
                  onTap: () => setState(() => _md = false),
                ),
                const SizedBox(width: 8),
                PillChip(
                  key: const ValueKey('mlsh-fmt-md'),
                  label: 'MD',
                  selected: _md,
                  onTap: () => setState(() => _md = true),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('mlsh-text'),
              controller: TextEditingController(text: _text),
              maxLines: 7,
              readOnly: true,
              style: const TextStyle(fontSize: 11, height: 1.5),
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('mlsh-copy'),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: _text));
                      if (!mounted) return;
                      AppToast.show(context, '文字版已可粘贴');
                    },
                    child: const Text('复制文字版'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('mlsh-save'),
                    onPressed: () async {
                      final nav = Navigator.of(context);
                      final m = ScaffoldMessenger.of(context);
                      final path = await captureShareCard(
                        _boundary,
                        name: widget.name,
                        src: '影音单',
                      );
                      nav.pop();
                      m.showSnackBar(SnackBar(
                        content: Text(path == null
                            ? '分享长图生成失败 · 详见日志'
                            : '分享长图已保存：$path'),
                      ));
                    },
                    child: const Text('保存图片'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 等宽读数特征（分享合计行；与模块内读数行同档）。
const List<FontFeature> kMdsShareTabular = [FontFeature.tabularFigures()];
