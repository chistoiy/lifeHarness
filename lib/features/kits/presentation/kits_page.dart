import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../domain/kit_calc.dart';
import '../domain/kit_models.dart';
import 'kit_providers.dart';

/// 小工具合集首页 = 控制盘（原型 `#p-tools` · 变更单 §八 B2 合并单网格口径）。
///
/// 批0 先落：hero 四枚数据位（实算）· 分类 chips · 搜索 · 全分类合并单网格
/// （每行 5 枚紧凑工具卡）· 点卡写使用足迹。
/// 批1 再叠：数据位配置草稿弹层 · 模块设置弹层 · 最近使用条 · 空态引导 · 拓展组。
class KitsPage extends ConsumerStatefulWidget {
  const KitsPage({super.key});

  @override
  ConsumerState<KitsPage> createState() => _KitsPageState();
}

class _KitsPageState extends ConsumerState<KitsPage> {
  String _q = '';
  KitCat? _cat;

  Future<void> _open(KitTool t) async {
    await ref.read(kitRepositoryProvider).logUse(t.key);
    if (!mounted) return;
    ref.read(kitTickProvider.notifier).state++;
    context.push('/kits/tool/${t.key}');
  }

  /// 首页可见工具：隐藏项恒不展示；分类与搜索按当前筛选叠加。
  List<KitTool> _visible(KitHomeData d) {
    final q = _q.trim().toLowerCase();
    return [
      for (final t in kKitTools)
        if (!d.hidden.contains(t.key) &&
            (_cat == null || t.cat == _cat) &&
            (q.isEmpty ||
                t.name.toLowerCase().contains(q) ||
                t.cat.label.toLowerCase().contains(q)))
          t,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final home = ref.watch(kitHomeProvider);
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('小工具合集'),
            Text('本地轻工具 · 可插件拓展',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.normal)),
          ],
        ),
      ),
      body: switch (home) {
        AsyncData(:final value) => _body(value),
        AsyncError(:final error) => Center(child: Text('读取失败：$error')),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _body(KitHomeData d) {
    final now = DateTime.now();
    final counts = kitCountByTool(d.log);
    final visible = _visible(d);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _Hero(data: d, now: now),
        const SizedBox(height: 12),
        _SearchBar(
          onQuery: (v) => setState(() => _q = v),
          onManage: () => AppToast.show(context, '工具管理屏随批4 实装'),
        ),
        const SizedBox(height: 8),
        _CatChips(current: _cat, onPick: (c) => setState(() => _cat = c)),
        const SizedBox(height: 10),
        Text('全部工具  ${visible.length}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        if (visible.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 24),
            child: Center(
                child: Text('没有匹配的工具 · 换个关键词或点「全部」',
                    style: TextStyle(fontSize: 12, color: Colors.grey))),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5,
              mainAxisSpacing: 8,
              crossAxisSpacing: 6,
              childAspectRatio: .78,
            ),
            itemCount: visible.length,
            itemBuilder: (_, i) => _Tile(
              tool: visible[i],
              uses: counts[visible[i].key] ?? 0,
              fav: d.fav.contains(visible[i].key),
              onTap: () => _open(visible[i]),
            ),
          ),
      ],
    );
  }
}

/// hero 控制盘卡（原型 `.grad` 卡 + 四枚数据位）。
class _Hero extends StatelessWidget {
  const _Hero({required this.data, required this.now});

  final KitHomeData data;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final plugs = data.plugins;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: tokens.gradient,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('小工具合集',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800)),
              SizedBox(height: 2),
              Text('本地计算 · 离线可用 · 无广告',
                  style: TextStyle(color: Colors.white70, fontSize: 10.5)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final m in data.hero)
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        '${kitMetricValue(m,
                            log: data.log,
                            now: now,
                            fav: data.fav,
                            plugCount: plugs.length,
                            plugOnCount: plugs.where((p) => p.enabled).length,
                            plugSizeKb: plugs.fold<int>(0, (a, p) => a + p.size))}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(m.label,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 10)),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 搜索行（原型 `#kitSearch` + 「管理」钮）。
class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.onQuery, required this.onManage});

  final ValueChanged<String> onQuery;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            key: const ValueKey('kit-search'),
            onChanged: onQuery,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: '搜索工具 · 名称或用途',
              hintStyle: const TextStyle(fontSize: 13, color: Colors.grey),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: context.tokens.cardBorder),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        TextButton(
          key: const ValueKey('kit-manage'),
          onPressed: onManage,
          child: const Text('管理', style: TextStyle(fontSize: 12.5)),
        ),
      ],
    );
  }
}

/// 分类筛选 chips（原型 `#kitCatChips`：全部 + 九类）。
class _CatChips extends StatelessWidget {
  const _CatChips({required this.current, required this.onPick});

  final KitCat? current;
  final ValueChanged<KitCat?> onPick;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        PillChip(
          key: const ValueKey('kit-cat-all'),
          label: '全部',
          selected: current == null,
          onTap: () => onPick(null),
        ),
        for (final c in KitCat.values)
          PillChip(
            key: ValueKey('kit-cat-${c.name}'),
            label: c.label,
            selected: current == c,
            onTap: () => onPick(current == c ? null : c),
          ),
      ],
    );
  }
}

/// 紧凑工具卡（原型 `.kit-tile`：30px 图标块 + 名称 + 使用次数 + ★ 角标）。
class _Tile extends StatelessWidget {
  const _Tile({
    required this.tool,
    required this.uses,
    required this.fav,
    required this.onTap,
  });

  final KitTool tool;
  final int uses;
  final bool fav;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      key: ValueKey('kit-tile-${tool.key}'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: tokens.card,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: tokens.cardBorder),
                ),
                child: Icon(tool.icon, size: 19, color: scheme.onSurface),
              ),
              if (fav)
                const Positioned(
                  right: -7,
                  top: -5,
                  child: Icon(Icons.star, size: 11, color: Color(0xFFF59E0B)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(tool.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700)),
          Text(uses == 0 ? '未用过' : '已用 $uses 次',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 8, color: Colors.grey)),
        ],
      ),
    );
  }
}
