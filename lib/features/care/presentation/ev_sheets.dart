import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../domain/care_events.dart';
import 'care_kit.dart';
import 'care_providers.dart';

/// sheetEvManage 事件管理 + sheetEvForm 自定义事件新建/编辑 + sheetEvPanel 快录宫格。

/// 事件管理（内置不可删·自定义可编辑/删除/新建）。
Future<void> showEvManage(BuildContext context) {
  return showCareSheet<void>(context, builder: (bc) => const _EvManage());
}

class _EvManage extends ConsumerWidget {
  const _EvManage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(careDataProvider).valueOrNull;
    if (d == null) return const SizedBox.shrink();
    final tokens = context.tokens;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('事件管理',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          for (final key in d.evOrder)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                    color: tokens.cardBorder.withValues(alpha: .5),
                    borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    _EvIco(evKey: key, size: 32, font: 16),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(d.evOf(key).name,
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w700)),
                          Text(
                              key.startsWith('cus:')
                                  ? '自定义 · 单位 ${d.evOf(key).unit ?? '—'}'
                                  : '内置事件',
                              style: const TextStyle(fontSize: 9, color: Colors.grey)),
                        ],
                      ),
                    ),
                    if (!key.startsWith('cus:'))
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2.5),
                        decoration: BoxDecoration(
                            color: tokens.cardBorder,
                            borderRadius: BorderRadius.circular(999)),
                        child: const Text('内置',
                            style: TextStyle(
                                fontSize: 9, fontWeight: FontWeight.w700, color: Colors.grey)),
                      )
                    else ...[
                      GestureDetector(
                        key: ValueKey('evm-edit-$key'),
                        onTap: () => showEvForm(context, editKey: key),
                        child: const Text('编辑',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.grey)),
                      ),
                      GestureDetector(
                        key: ValueKey('evm-del-$key'),
                        onTap: () async {
                          final repo = ref.read(careRepositoryProvider);
                          final nm = d.evOf(key).name;
                          await repo.delCustomEvent(key);
                          careTouch(ref);
                          if (context.mounted) {
                            AppToast.show(context, '已删除自定义事件「$nm」');
                          }
                        },
                        child: const Padding(
                          padding: EdgeInsets.only(left: 8),
                          child: Text('×', style: TextStyle(fontSize: 13, color: Colors.grey)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          const SizedBox(height: 4),
          OutlinedButton(
            key: const ValueKey('evm-add'),
            onPressed: () => showEvForm(context),
            style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 13)),
            child: const Text('＋ 新建自定义事件', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

/// 事件图标+底色块（tint 500 级低透明）。
class _EvIco extends ConsumerWidget {
  const _EvIco({required this.evKey, required this.size, required this.font});
  final String evKey;
  final double size;
  final double font;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(careDataProvider).valueOrNull;
    final E = d?.evOf(evKey) ?? resolveEv(evKey, const {});
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: careHex(E.tint).withValues(alpha: .16),
        borderRadius: BorderRadius.circular(size * .28),
      ),
      alignment: Alignment.center,
      child: Text(E.icon, style: TextStyle(fontSize: font)),
    );
  }
}

/// sheetEvForm 新建/编辑自定义事件（名称/图标池/单位；改名走键迁移）。
Future<void> showEvForm(BuildContext context, {String? editKey}) {
  return showCareSheet<void>(
      context, builder: (bc) => _EvForm(editKey: editKey));
}

class _EvForm extends ConsumerStatefulWidget {
  const _EvForm({this.editKey});
  final String? editKey;

  @override
  ConsumerState<_EvForm> createState() => _EvFormState();
}

class _EvFormState extends ConsumerState<_EvForm> {
  final _nameCtl = TextEditingController();
  String _icon = '✨';
  String _unit = 'ml';
  bool _loaded = false;

  static const _units = ['ml', 'min', 'g', '次', '°C'];

  InputDecoration _inpBox(BuildContext ctx, String hint) {
    final tokens = ctx.tokens;
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: tokens.cardBorder)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: tokens.cardBorder)),
    );
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.editKey != null;
    if (!_loaded && editing) {
      _loaded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final c = ref.read(careDataProvider).valueOrNull?.customs[widget.editKey];
        if (c == null || !mounted) return;
        setState(() {
          _nameCtl.text = c.name;
          _icon = c.icon;
          _unit = c.unit;
        });
      });
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(editing ? '编辑自定义事件' : '新建自定义事件',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
              if (editing)
                GestureDetector(
                  key: const ValueKey('evf-del'),
                  onTap: () async {
                    final repo = ref.read(careRepositoryProvider);
                    final nm = _nameCtl.text.trim();
                    await repo.delCustomEvent(widget.editKey!);
                    careTouch(ref);
                    if (!context.mounted) return;
                    Navigator.pop(context);
                    AppToast.show(context, '已删除自定义事件「$nm」');
                  },
                  child: const Text('删除事件',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFF43F5E))),
                ),
            ],
          ),
          const CLabel('名称', top: 12),
          TextField(
            key: const ValueKey('evf-name'),
            controller: _nameCtl,
            style: const TextStyle(fontSize: 12),
            decoration: _inpBox(context, '如：拍嗝 / 抚触'),
          ),
          const CLabel('图标'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final ic in kEvIconPool)
                CChip(
                  key: ValueKey('evf-ico-$ic'),
                  label: ic,
                  dense: true,
                  selected: _icon == ic,
                  onTap: () => setState(() => _icon = ic),
                ),
            ],
          ),
          const CLabel('量单位'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final u in _units)
                CChip(
                  key: ValueKey('evf-unit-$u'),
                  label: u,
                  dense: true,
                  selected: _unit == u,
                  onTap: () => setState(() => _unit = u),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12)),
                  child: const Text('取消'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  key: const ValueKey('evf-save'),
                  onPressed: () async {
                    final nm = _nameCtl.text.trim();
                    final repo = ref.read(careRepositoryProvider);
                    final messenger = ScaffoldMessenger.of(context);
                    if (nm.isEmpty) {
                      AppToast.show(context, '先填事件名称');
                      return;
                    }
                    final ok = editing
                        ? await repo.renameCustomEvent(widget.editKey!, nm, _icon, _unit)
                        : await repo.addCustomEvent(nm, _icon, _unit);
                    if (!ok) {
                      if (context.mounted) {
                        AppToast.show(context,
                            editing ? '「$nm」已存在' : '「$nm」已存在，可直接编辑');
                      }
                      return;
                    }
                    if (!editing) {
                      final cur = await repo.customEvents();
                      final ord = await repo.evOrder(cur);
                      if (!ord.contains('cus:$nm')) {
                        ord.add('cus:$nm');
                        await repo.saveEvOrder(ord);
                      }
                    }
                    careTouch(ref);
                    if (context.mounted) Navigator.pop(context);
                    messenger
                      ..hideCurrentSnackBar()
                      ..showSnackBar(SnackBar(
                          content: Text(editing
                              ? '✔ 事件已更新'
                              : '已新建「$nm」并加入速记区'),
                          duration: const Duration(milliseconds: 1600)));
                  },
                  style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12)),
                  child: const Text('保存'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// sheetEvPanel 快速记录宫格（全天记录页右上钮）。返回所选事件键。
Future<String?> showEvPanel(BuildContext context) {
  return showCareSheet<String>(context, builder: (bc) => const _EvPanel());
}

class _EvPanel extends ConsumerWidget {
  const _EvPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(careDataProvider).valueOrNull;
    if (d == null) return const SizedBox.shrink();
    // 弹层收起动画会按最小拖拽高度重排；不可滚动 Column 会撞 136px 溢出，统一套滚动。
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('快速记录',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.15,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            children: [
              for (final key in d.evOrder)
                GestureDetector(
                  key: ValueKey('evp-$key'),
                  onTap: () => Navigator.pop(context, key),
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _EvIco(evKey: key, size: 40, font: 18),
                      const SizedBox(height: 4),
                      Text(d.evOf(key).name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 10, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 11)),
            child: const Text('回宝宝页 · 管理事件顺序 ›',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
          ),
          ],
        ),
      ),
    );
  }
}
