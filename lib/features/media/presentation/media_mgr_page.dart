import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/load_error_state.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../data/media_repo_dict.dart';
import 'media_providers.dart';
import 'media_sheets.dart' show kMediaTabularRead;

/// 影音资料管理器（原型 `m-mgr` · 路由 `/media/mgr?tab=`）：
/// 来源/分组/创作者/发行/标签 五类实体一张屏管，行上三个动作＝
/// 点行＝跨 kind 反查同值条目（落架面关键词口径）· 改名＝联动条目侧的列 · 删除＝引用守卫。
///
/// 三条口径在页面层也钉死：
/// - 清单＝名册 ∪ 条目实际值（字典没登记过但条目在用的名字必须看得见，否则删不掉也改不了）；
/// - 引用数只数在册条目（软删的不算「仍在用」，也不阻碍改名）；
/// - 有在用条目＝删除被拦并如实报数，不做「强制删除」（避免软删父行藏子记录那条坑）。
class MediaMgrPage extends ConsumerStatefulWidget {
  const MediaMgrPage({super.key, this.initialTab});

  final String? initialTab;

  @override
  ConsumerState<MediaMgrPage> createState() => _MediaMgrPageState();
}

class _MediaMgrPageState extends ConsumerState<MediaMgrPage> {
  static const _tabs = <(String, String)>[
    ('source', '来源'),
    ('grp', '分组'),
    ('creator', '创作者'),
    ('pub', '发行'),
    ('tags', '标签'),
  ];

  @override
  void initState() {
    super.initState();
    final t = widget.initialTab;
    if (t != null && MediaDictRepo.dictKinds.containsKey(t)) {
      Future<void>.microtask(() {
        if (mounted) ref.read(mediaDictTabProvider.notifier).state = t;
      });
    }
  }

  Future<void> _rename(String dictKind, String from) async {
    final to = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(from: from),
    );
    if (to == null || to.trim().isEmpty || to == from || !mounted) return;
    final n = await ref.read(mediaRepositoryProvider).renameDict(dictKind, from, to);
    if (!mounted) return;
    _bump();
    AppToast.show(context, '已改名，$n 条在册条目同步跟上');
  }

  Future<void> _delete(String dictKind, String name, int refCount) async {
    if (refCount > 0) {
      AppToast.show(context, '还有 $refCount 条在册条目在用，改完名或移走再删');
      return;
    }
    final ok = await lhConfirm(context, '从名册删掉「$name」？不影响任何在册条目。');
    if (!ok || !mounted) return;
    final gone = await ref.read(mediaRepositoryProvider).deleteDict(dictKind, name);
    if (!mounted) return;
    _bump();
    AppToast.show(context, gone ? '已从名册删除' : '名册里没有这一项');
  }

  void _bump() {
    final t = ref.read(mediaTickProvider.notifier);
    t.state = t.state + 1;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tab = ref.watch(mediaDictTabProvider);
    final rows = ref.watch(mediaDictRowsProvider(tab));
    return Scaffold(
      appBar: AppBar(title: const Text('影音资料')),
      body: Column(
        children: [
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final (k, label) in _tabs)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: PillChip(
                      key: ValueKey('mds-mgr-tab-$k'),
                      label: label,
                      selected: tab == k,
                      onTap: () => ref.read(mediaDictTabProvider.notifier).state = k,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: rows.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => LoadErrorBanner(
                title: '名册没加载出来',
                error: e,
                onRetry: () => ref.invalidate(mediaDictRowsProvider(tab)),
              ),
              data: (list) {
                if (list.isEmpty) {
                  return EmptyDashRow(text: '这一类还没有名字 · 新增条目时会自动登记');
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 24),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => Divider(
                    height: 1,
                    color: scheme.outlineVariant.withValues(alpha: .5),
                  ),
                  itemBuilder: (_, i) {
                    final r = list[i];
                    return ListTile(
                      key: ValueKey('mds-mgr-row-${r.name}'),
                      dense: true,
                      title: Text(r.name, style: const TextStyle(fontSize: 13)),
                      subtitle: Text(
                        r.refCount == 0 ? '0 条在册 · 点击反查' : '${r.refCount} 条 · 点击反查',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: scheme.onSurfaceVariant,
                          fontFeatures: kMediaTabularRead,
                        ),
                      ),
                      onTap: () => context.push(
                        Uri(
                          path: '/media/shelf',
                          queryParameters: {'q': r.name},
                        ).toString(),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            key: ValueKey('mds-mgr-rename-${r.name}'),
                            tooltip: '改名',
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            onPressed: () => _rename(MediaDictRepo.dictKinds[tab]!, r.name),
                          ),
                          IconButton(
                            key: ValueKey('mds-mgr-del-${r.name}'),
                            tooltip: '删除',
                            icon: Icon(
                              Icons.delete_outline,
                              size: 18,
                              color: r.refCount > 0
                                  ? scheme.onSurface.withValues(alpha: .3)
                                  : scheme.error,
                            ),
                            onPressed: () =>
                                _delete(MediaDictRepo.dictKinds[tab]!, r.name, r.refCount),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 改名对话框（就地输入＋空值就地报错，不借道提示条＝LH-K32 口径）。
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.from});

  final String from;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _c = TextEditingController(text: widget.from);
  String? _err;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('改名 · ${widget.from}'),
      content: SizedBox(
        width: 280,
        child: TextField(
          key: const ValueKey('mds-mgr-rename-input'),
          controller: _c,
          autofocus: true,
          decoration: InputDecoration(
            labelText: '新名字',
            errorText: _err,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
          onChanged: _err == null ? null : (_) => setState(() => _err = null),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const ValueKey('mds-mgr-rename-ok'),
          onPressed: () {
            final v = _c.text.trim();
            if (v.isEmpty) {
              setState(() => _err = '请写新名字');
              return;
            }
            Navigator.of(context).pop(v);
          },
          child: const Text('确定'),
        ),
      ],
    );
  }
}
