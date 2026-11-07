import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/ui_kit.dart' show AppToast;
import '../domain/tag.dart';
import 'journal_providers.dart';
import 'widgets/tag_chip.dart';

/// 编辑标签弹层（原型 `sheetTagEdit`）＋合并目标弹层（`sheetTagMerge`）。
///
/// 三件事都从这一处出：改名、改适用模块、合并/删除。**写操作全部经 TagDao**，
/// 弹层自己不碰表——口径①「池全局唯一」的落地方式就是「只有一个写口」。
Future<void> showTagEditSheet(BuildContext context, WidgetRef ref, Tag tag) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _TagEditSheet(tag: tag),
  );
}

class _TagEditSheet extends ConsumerStatefulWidget {
  const _TagEditSheet({required this.tag});

  final Tag tag;

  @override
  ConsumerState<_TagEditSheet> createState() => _TagEditSheetState();
}

class _TagEditSheetState extends ConsumerState<_TagEditSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.tag.name);
  late final Set<String> _scopes = {...widget.tag.scopes};
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    final dao = ref.read(tagDaoProvider);
    final r1 = await dao.rename(widget.tag.id, _name.text);
    if (!r1.ok) {
      if (mounted) {
        setState(() => _busy = false);
        AppToast.show(context, r1.msg, ms: 1600);
      }
      return;
    }
    final r2 = await dao.setScopes(widget.tag.id, _scopes);
    if (!mounted) return;
    if (!r2.ok) {
      setState(() => _busy = false);
      AppToast.show(context, r2.msg, ms: 1600);
      return;
    }
    ref.invalidate(tagPoolProvider);
    Navigator.of(context).pop();
    AppToast.show(context,
        _name.text.trim() == widget.tag.name ? '已保存' : '已改名为「${_name.text.trim()}」',
        ms: 1400);
  }

  Future<void> _delete() async {
    final ok = await lhConfirm(
      context,
      '删除标签「${widget.tag.name}」？三个模块里所有引用都会解除，内容本身不删。',
    );
    if (!ok || !mounted) return;
    await ref.read(tagDaoProvider).deleteTag(widget.tag.id);
    if (!mounted) return;
    ref.invalidate(tagPoolProvider);
    Navigator.of(context).pop();
    AppToast.show(context, '已删除「${widget.tag.name}」· 引用已解除', ms: 1600);
  }

  Future<void> _merge() async {
    final target = await showTagMergeSheet(context, ref, widget.tag);
    if (target == null || !mounted) return;
    final r = await ref.read(tagDaoProvider).merge(widget.tag.id, target.id);
    if (!mounted) return;
    if (!r.ok) {
      AppToast.show(context, r.msg, ms: 1600);
      return;
    }
    ref.invalidate(tagPoolProvider);
    Navigator.of(context).pop();
    AppToast.show(context, '「${widget.tag.name}」已并入「${target.name}」', ms: 1600);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: tokens.text2.withValues(alpha: .25),
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 14),
              Row(children: [
                const Expanded(
                  child: Text('编辑标签',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                ),
                IconButton(
                  key: const ValueKey('tg-edit-close'),
                  tooltip: '关闭',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, size: 18),
                ),
              ]),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: tokens.cardBorder),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
                    child: Row(children: [
                      const Text('名称',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          key: const ValueKey('tg-edit-name'),
                          controller: _name,
                          maxLength: kTagNameMax,
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontSize: 13),
                          decoration: const InputDecoration(
                            isDense: true,
                            counterText: '',
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                    ]),
                  ),
                  Divider(height: 1, color: tokens.cardBorder),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const Text('适用模块',
                              style: TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w700)),
                          const Spacer(),
                          Text(
                              _scopes.length == kTagScopes.length
                                  ? '三处通用'
                                  : '已选 ${_scopes.length} 个模块',
                              style: TextStyle(fontSize: 11, color: tokens.text2)),
                        ]),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final k in kTagScopes)
                              _ScopePill(
                                key: ValueKey('tg-edit-scope-$k'),
                                label: tagSceneName(k),
                                on: _scopes.contains(k),
                                onTap: () {
                                  setState(() {
                                    if (_scopes.contains(k)) {
                                      if (_scopes.length == 1) {
                                        AppToast.show(context, '至少保留一个适用模块',
                                            ms: 1400);
                                        return;
                                      }
                                      _scopes.remove(k);
                                    } else {
                                      _scopes.add(k);
                                    }
                                  });
                                },
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: tokens.cardBorder),
                  InkWell(
                    key: const ValueKey('tg-edit-merge'),
                    onTap: _merge,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      child: Row(children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('合并到其他标签',
                                  style: TextStyle(
                                      fontSize: 13, fontWeight: FontWeight.w700)),
                              const SizedBox(height: 2),
                              Text('把这个标签的引用全部并入目标，源标签删除',
                                  style:
                                      TextStyle(fontSize: 11, color: tokens.text2)),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right, size: 18, color: tokens.text2),
                      ]),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 8),
              Text(
                '改名 = 所有模块里的这个名字一起改；删除 = 三个模块一律解除绑定，内容本身不删。',
                style: TextStyle(fontSize: 11, height: 1.5, color: tokens.text2),
              ),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('tg-edit-delete'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                      side: BorderSide(
                          color: Theme.of(context)
                              .colorScheme
                              .error
                              .withValues(alpha: .45)),
                      foregroundColor: Theme.of(context).colorScheme.error,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _busy ? null : _delete,
                    child: const Text('删除',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('tg-edit-save'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                      backgroundColor: tokens.accent,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _busy ? null : _save,
                    child: const Text('保存',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

/// 合并目标弹层：排除自己，列出其余标签（名字 + 适用模块 + 引用数）。
Future<Tag?> showTagMergeSheet(BuildContext context, WidgetRef ref, Tag from) {
  return showModalBottomSheet<Tag>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _TagMergeSheet(from: from),
  );
}

class _TagMergeSheet extends ConsumerWidget {
  const _TagMergeSheet({required this.from});

  final Tag from;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final pool = (ref.watch(tagPoolProvider).valueOrNull ?? const <Tag>[])
        .where((t) => t.id != from.id)
        .toList();
    return Container(
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * .7),
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: tokens.text2.withValues(alpha: .25),
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 14),
              const Text('合并到…',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('「${from.name}」的引用会全部并入所选标签，然后源标签消失',
                  style: TextStyle(fontSize: 11, color: tokens.text2)),
              const SizedBox(height: 10),
              Flexible(
                child: pool.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text('池里没有别的标签可合并',
                              style:
                                  TextStyle(fontSize: 11, color: tokens.text2)),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: pool.length,
                        separatorBuilder: (_, _) =>
                            Divider(height: 1, color: tokens.cardBorder),
                        itemBuilder: (_, i) {
                          final t = pool[i];
                          return InkWell(
                            key: ValueKey('tg-merge-${t.name}'),
                            onTap: () => Navigator.of(context).pop(t),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Row(children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                      color: tagToneColor(tagToneAt(t.id), tokens),
                                      shape: BoxShape.circle),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(t.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600)),
                                ),
                                Text(
                                  t.isPublic
                                      ? '三处通用'
                                      : [
                                          for (final k in kTagScopes)
                                            if (t.appliesTo(k)) tagSceneName(k)
                                        ].join('·'),
                                  style:
                                      TextStyle(fontSize: 11, color: tokens.text2),
                                ),
                                const SizedBox(width: 8),
                                Text('${t.useCount} 条',
                                    style: TextStyle(
                                        fontSize: 11, color: tokens.text2)),
                              ]),
                            ),
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

/// 适用模块胶囊（原型 `.tg-pill`：选中走主色淡底 + 勾）。
class _ScopePill extends StatelessWidget {
  const _ScopePill({
    super.key,
    required this.label,
    required this.on,
    required this.onTap,
  });

  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: on ? tokens.accent.withValues(alpha: .12) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: on
                  ? tokens.accent.withValues(alpha: .55)
                  : tokens.text2.withValues(alpha: .35)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                  color: on ? tokens.accent : tokens.text1)),
          if (on) ...[
            const SizedBox(width: 4),
            Icon(Icons.check, size: 11, color: tokens.accent),
          ],
        ]),
      ),
    );
  }
}
