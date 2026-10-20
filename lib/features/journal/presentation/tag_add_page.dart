import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart' show AppToast;
import '../domain/tag.dart';
import 'journal_providers.dart';
import 'widgets/tag_chip.dart';

/// 添加标签（原型 `p-sub-tagAdd`）。
///
/// 口径②：适用模块**默认三个全勾**，可手动取消；「放进公共」＝一键全选的快捷表达
/// （不是第四个 scope，见 `domain/tag.dart` 文件头）。
class TagAddPage extends ConsumerStatefulWidget {
  const TagAddPage({super.key});

  @override
  ConsumerState<TagAddPage> createState() => _TagAddPageState();
}

class _TagAddPageState extends ConsumerState<TagAddPage> {
  final _name = TextEditingController();
  Set<String> _scopes = kTagScopes.toSet();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    final r = await ref.read(tagDaoProvider).create(_name.text, scopes: _scopes);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) {
      AppToast.show(context, r.msg, ms: 1600);
      return;
    }
    ref.invalidate(tagPoolProvider);
    context.pop();
    AppToast.show(context, '已添加标签「${r.tag?.name ?? ''}」', ms: 1400);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final name = _name.text.trim().replaceFirst(RegExp(r'^#+'), '');
    final allOn = kTagScopes.every(_scopes.contains);

    return Scaffold(
      appBar: AppBar(title: const Text('添加标签')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
        children: [
          Container(
            decoration: BoxDecoration(
              color: tokens.card,
              borderRadius: BorderRadius.circular(tokens.cardRadius),
              border: Border.all(color: tokens.cardBorder),
            ),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
                child: Row(children: [
                  const Text('标签名称',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('tg-add-name'),
                      controller: _name,
                      maxLength: kTagNameMax,
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 13),
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        isDense: true,
                        counterText: '',
                        border: InputBorder.none,
                        hintText: '如：复盘',
                        hintStyle: TextStyle(fontSize: 13),
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
                          _scopes.isEmpty
                              ? '至少选一个模块'
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
                            key: ValueKey('tg-add-scope-$k'),
                            label: tagSceneName(k),
                            on: _scopes.contains(k),
                            onTap: () => setState(() {
                              if (_scopes.contains(k)) {
                                _scopes.remove(k);
                              } else {
                                _scopes.add(k);
                              }
                            }),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: tokens.cardBorder),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
                child: Row(children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('放进「公共」',
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text('勾上 = 三个模块全选（同一件事的快捷表达）',
                            style: TextStyle(fontSize: 11, color: tokens.text2)),
                      ],
                    ),
                  ),
                  Switch(
                    key: const ValueKey('tg-add-public'),
                    value: allOn,
                    onChanged: (v) => setState(() {
                      _scopes = v ? kTagScopes.toSet() : {kTagScopes.first};
                    }),
                  ),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: tokens.card,
              borderRadius: BorderRadius.circular(tokens.cardRadius),
              border: Border.all(color: tokens.cardBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('预览',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: tokens.text2)),
                const SizedBox(height: 8),
                Row(children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                        color: tagToneColor(
                            tagToneAt(ref.watch(tagPoolProvider).valueOrNull?.length ?? 0),
                            tokens),
                        shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('#${name.isEmpty ? '标签名' : name}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700)),
                  ),
                  Text(
                      _scopes.isEmpty
                          ? '未选模块'
                          : [for (final k in kTagScopes) if (_scopes.contains(k)) tagSceneName(k)]
                              .join(' / '),
                      style: TextStyle(fontSize: 11, color: tokens.text2)),
                ]),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const ValueKey('tg-add-save'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
              backgroundColor: tokens.accent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _busy || _scopes.isEmpty ? null : _save,
            child: const Text('添加标签',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

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
