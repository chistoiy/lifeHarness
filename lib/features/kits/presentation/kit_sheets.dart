// 小工具弹层族（原型 `sheetKitCfg` / `sheetKitSet` / `sheetKitFav` / `sheetKitRecent` 同源）。
//
// 四条既有红线在本文件统一遵守：
// - 弹层内不挂 SnackBar（模态路由里看不见）→ 一律用行内提示文案；
// - 草稿保存制：数据位与收藏点选只改草稿，「保存」才落库；
// - 破坏性动作两段式：清空足迹需在同一处再点一次确认；
// - 弹层零 BackdropFilter（用户拍板：不透明面板）。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/settings/user_settings.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/kit_calc.dart';
import '../domain/kit_models.dart';
import 'kit_providers.dart';

/// 收藏上限（原型「收藏即加入首页快捷行 · 最多 6 个」）。
const int kKitFavMax = 6;

/// 弹层统一外壳（原型 `.sheet-panel`：grabber + 标题 + 正文 + 底部按钮行）。
class KitSheetScaffold extends StatelessWidget {
  const KitSheetScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.trailing,
  });

  final String title;
  final Widget body;
  final List<Widget>? actions;

  /// 标题行右侧动作（原型「最近使用」弹层右上角「清空」）。
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: tokens.cardBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 10),
            Flexible(child: SingleChildScrollView(child: body)),
            if (actions != null) ...[
              const SizedBox(height: 14),
              Row(children: actions!),
            ],
          ],
        ),
      ),
    );
  }
}

/// 弹层底部主按钮（原型 `.grad` 实心胶囊）。
Widget kitSheetPrimary(String label, VoidCallback? onTap) => Expanded(
  child: FilledButton(
    key: ValueKey('kit-sheet-primary-$label'),
    onPressed: onTap,
    style: FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(vertical: 13),
      shape: const StadiumBorder(),
    ),
    child: Text(label, style: const TextStyle(fontSize: 13.5)),
  ),
);

/// 弹层底部次按钮（浅灰底胶囊）。
Widget kitSheetSecondary(
  BuildContext context,
  String label,
  VoidCallback onTap,
) => Expanded(
  child: OutlinedButton(
    key: ValueKey('kit-sheet-secondary-$label'),
    onPressed: onTap,
    style: OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(vertical: 13),
      side: BorderSide(color: context.tokens.cardBorder),
      shape: const StadiumBorder(),
    ),
    child: Text(label, style: const TextStyle(fontSize: 13.5)),
  ),
);

/// 行式设置项（左标题+副文案，右控件；原型 `.row` 口径）。
class KitSheetRow extends StatelessWidget {
  const KitSheetRow({
    super.key,
    required this.title,
    this.sub = '',
    required this.trailing,
  });

  final String title;
  final String sub;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 13)),
                if (sub.isNotEmpty)
                  Text(
                    sub,
                    style: const TextStyle(fontSize: 10.5, color: Colors.grey),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          trailing,
        ],
      ),
    );
  }
}

/// 破坏性动作两段式按钮（首次点击变「再次点击确认」，4 秒后自动回退）。
class KitTwoStageButton extends StatefulWidget {
  const KitTwoStageButton({
    super.key,
    required this.label,
    required this.confirmLabel,
    required this.onConfirm,
    this.compact = false,
  });

  final String label;
  final String confirmLabel;
  final VoidCallback onConfirm;
  final bool compact;

  @override
  State<KitTwoStageButton> createState() => _KitTwoStageButtonState();
}

class _KitTwoStageButtonState extends State<KitTwoStageButton> {
  bool _armed = false;

  /// 武装态回退定时器：必须在 dispose 里取消，否则 widget 测试收尾报
  /// 「A Timer is still pending」（既有踩坑）。
  Timer? _revert;

  @override
  void dispose() {
    _revert?.cancel();
    super.dispose();
  }

  void _arm() {
    _revert?.cancel();
    setState(() => _armed = true);
    _revert = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _armed = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return TextButton(
      key: ValueKey('kit-2stage-${widget.label}'),
      onPressed: () {
        if (!_armed) {
          _arm();
          return;
        }
        _revert?.cancel();
        setState(() => _armed = false);
        widget.onConfirm();
      },
      style: TextButton.styleFrom(
        padding: widget.compact
            ? const EdgeInsets.symmetric(horizontal: 10, vertical: 4)
            : const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        foregroundColor: const Color(0xE6F43F5E),
      ),
      child: Text(
        _armed ? widget.confirmLabel : widget.label,
        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// 数据位配置弹层（原型 `sheetKitCfg`：实时预览 + 指标库 + 草稿保存制）。
Future<void> kitShowHeroCfg(BuildContext context, KitHomeData data) =>
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _HeroCfgSheet(data: data),
    );

class _HeroCfgSheet extends ConsumerStatefulWidget {
  const _HeroCfgSheet({required this.data});

  final KitHomeData data;

  @override
  ConsumerState<_HeroCfgSheet> createState() => _HeroCfgSheetState();
}

class _HeroCfgSheetState extends ConsumerState<_HeroCfgSheet> {
  late List<KitMetric> _draft = List.of(widget.data.hero);
  String _hint = '';

  void _pick(KitMetric m) {
    setState(() {
      if (_draft.contains(m)) {
        if (_draft.length == 1) {
          _hint = '至少保留 1 枚数据位';
          return;
        }
        _draft = _draft.where((e) => e != m).toList();
      } else if (_draft.length == 4) {
        _hint = '最多 4 枚 · 先取消一项再选';
        return;
      } else {
        _draft = [..._draft, m];
      }
      _hint = '';
    });
  }

  Future<void> _save() async {
    if (_draft.length != 4) {
      setState(() => _hint = '请选满 4 个数据位（当前 ${_draft.length}）');
      return;
    }
    await ref.read(kitRepositoryProvider).setHeroSlots(_draft);
    ref.read(kitTickProvider.notifier).state++;
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final now = DateTime.now();
    return KitSheetScaffold(
      title: '⇄ 主卡数据位',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '从指标库选 4 项 · 点选只写草稿 · 保存才生效',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          Container(
            key: const ValueKey('kit-cfg-preview'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: tokens.gradient,
            ),
            child: Row(
              children: [
                for (final m in _draft)
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          '${kitMetricValue(m, log: widget.data.log, now: now, fav: widget.data.fav, plugCount: widget.data.plugins.length)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          m.label,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 9.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                for (var i = _draft.length; i < 4; i++)
                  const Expanded(
                    child: Text(
                      '—',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38, fontSize: 17),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          for (final m in KitMetric.values)
            InkWell(
              key: ValueKey('kit-cfg-${m.name}'),
              onTap: () => _pick(m),
              child: KitSheetRow(
                title: m.label,
                trailing: Icon(
                  _draft.contains(m)
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  size: 19,
                  color: _draft.contains(m) ? tokens.accent : Colors.grey,
                ),
              ),
            ),
          if (_hint.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _hint,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: Color(0xE6F43F5E),
                ),
              ),
            ),
        ],
      ),
      actions: [
        kitSheetSecondary(context, '取消', () => Navigator.of(context).pop()),
        const SizedBox(width: 8),
        kitSheetPrimary('保存', _save),
      ],
    );
  }
}

/// 模块设置弹层（原型 `sheetKitSet`：四项开关 + 插件中心入口 + 清空足迹）。
Future<void> kitShowSettings(
  BuildContext context, {
  required VoidCallback onGoPlugins,
}) => showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  builder: (_) => _KitSetSheet(onGoPlugins: onGoPlugins),
);

class _KitSetSheet extends ConsumerStatefulWidget {
  const _KitSetSheet({required this.onGoPlugins});

  final VoidCallback onGoPlugins;

  @override
  ConsumerState<_KitSetSheet> createState() => _KitSetSheetState();
}

class _KitSetSheetState extends ConsumerState<_KitSetSheet> {
  Future<void> _set(KitSettings Function(KitSettings) f) async {
    final cur = ref.read(settingsControllerProvider).kit;
    await ref.read(settingsControllerProvider.notifier).setKit(f(cur));
  }

  @override
  Widget build(BuildContext context) {
    final k = ref.watch(settingsControllerProvider).kit;
    final plugCount = ref.watch(kitHomeProvider).value?.plugins.length ?? 0;
    return KitSheetScaffold(
      title: '小工具设置',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '本机生效 · 随应用备份导出',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(height: 6),
          KitSheetRow(
            title: '自动扫描私有 plugins/ 目录',
            sub: '启动时热加载符合规范的工具包',
            trailing: Switch(
              key: const ValueKey('kit-set-scan'),
              value: k.scan,
              onChanged: (v) => _set((s) => s.copyWith(scan: v)),
            ),
          ),
          KitSheetRow(
            title: 'Wi-Fi 下自动检查更新',
            sub: '每周一次 · 仅请求索引清单',
            trailing: Switch(
              key: const ValueKey('kit-set-wifi'),
              value: k.wifiCheck,
              onChanged: (v) => _set((s) => s.copyWith(wifiCheck: v)),
            ),
          ),
          KitSheetRow(
            title: '插件列表随备份导出',
            sub: '换机恢复时按清单重装 · 数据各随其主',
            trailing: Switch(
              key: const ValueKey('kit-set-backupPlugins'),
              value: k.backupPlugins,
              onChanged: (v) => _set((s) => s.copyWith(backupPlugins: v)),
            ),
          ),
          KitSheetRow(
            title: '使用足迹随备份导出',
            sub: '关闭后 .lhbak 不含足迹流水 · 收藏与编排仍导出',
            trailing: Switch(
              key: const ValueKey('kit-set-backupFootprint'),
              value: k.backupFootprint,
              onChanged: (v) => _set((s) => s.copyWith(backupFootprint: v)),
            ),
          ),
          const Divider(height: 18),
          KitSheetRow(
            title: '插件中心',
            sub: '安装 · 更新 · 回滚 · 权限与审计',
            trailing: TextButton(
              key: const ValueKey('kit-set-plugins'),
              onPressed: () {
                Navigator.of(context).pop();
                widget.onGoPlugins();
              },
              child: const Text('前往 ›', style: TextStyle(fontSize: 12.5)),
            ),
          ),
          KitSheetRow(
            title: '已装拓展',
            sub: '沙箱运行 · 默认无网络与用户数据',
            trailing: Text(
              '$plugCount 个',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 8),
          KitTwoStageButton(
            label: '清空使用足迹',
            confirmLabel: '再次点击确认清空',
            onConfirm: () async {
              await ref.read(kitRepositoryProvider).clearUsage();
              await ref.read(kitRepositoryProvider).setRecent(const []);
              ref.read(kitTickProvider.notifier).state++;
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
        ],
      ),
      actions: [kitSheetPrimary('完成', () => Navigator.of(context).pop())],
    );
  }
}

/// 收藏管理弹层（原型 `sheetKitFav`：勾选 + 行内 ↑↓ + 草稿保存制 · 最多 6 个）。
Future<void> kitShowFav(BuildContext context, List<String> fav) =>
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FavSheet(initial: fav),
    );

class _FavSheet extends ConsumerStatefulWidget {
  const _FavSheet({required this.initial});

  final List<String> initial;

  @override
  ConsumerState<_FavSheet> createState() => _FavSheetState();
}

class _FavSheetState extends ConsumerState<_FavSheet> {
  late final List<String> _draft = List.of(widget.initial);
  String _hint = '';

  void _toggle(String key) {
    setState(() {
      if (_draft.contains(key)) {
        _draft.remove(key);
      } else if (_draft.length >= kKitFavMax) {
        _hint = '最多收藏 $kKitFavMax 个 · 先取消一个再选';
        return;
      } else {
        _draft.add(key);
      }
      _hint = '';
    });
  }

  void _move(int i, int delta) {
    final j = i + delta;
    if (i < 0 || j < 0 || i >= _draft.length || j >= _draft.length) return;
    setState(() {
      final t = _draft[i];
      _draft[i] = _draft[j];
      _draft[j] = t;
    });
  }

  Future<void> _save() async {
    await ref.read(kitRepositoryProvider).setFavorites(_draft);
    ref.read(kitTickProvider.notifier).state++;
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return KitSheetScaffold(
      title: '收藏管理',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '收藏即加入首页快捷行 · 最多 $kKitFavMax 个 · 行内 ↑↓ 调序',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(height: 6),
          for (final t in kKitTools)
            InkWell(
              key: ValueKey('kit-fav-${t.key}'),
              onTap: () => _toggle(t.key),
              child: KitSheetRow(
                title: t.name,
                sub: t.cat.label,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_draft.contains(t.key)) ...[
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _move(_draft.indexOf(t.key), -1),
                        icon: const Icon(Icons.arrow_upward, size: 16),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _move(_draft.indexOf(t.key), 1),
                        icon: const Icon(Icons.arrow_downward, size: 16),
                      ),
                    ],
                    Icon(
                      _draft.contains(t.key) ? Icons.star : Icons.star_border,
                      size: 19,
                      color: _draft.contains(t.key)
                          ? const Color(0xFFF59E0B)
                          : Colors.grey,
                    ),
                  ],
                ),
              ),
            ),
          if (_hint.isNotEmpty)
            Text(
              _hint,
              style: const TextStyle(fontSize: 11.5, color: Color(0xE6F43F5E)),
            ),
          const SizedBox(height: 4),
          Text(
            '当前 ${_draft.length} / $kKitFavMax',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
      actions: [
        kitSheetSecondary(context, '取消', () => Navigator.of(context).pop()),
        const SizedBox(width: 8),
        kitSheetPrimary('保存', _save),
      ],
    );
  }
}

/// 最近使用弹层（原型 `sheetKitRecent`：按最近倒序 + 清空）。
/// 返回被点开的工具键（页面侧负责跳转，弹层路由 pop 后自身 context 已失效）。
Future<String?> kitShowRecent(BuildContext context, List<String> recent) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RecentSheet(recent: recent),
    );

class _RecentSheet extends ConsumerWidget {
  const _RecentSheet({required this.recent});

  final List<String> recent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final log = ref.watch(kitHomeProvider).value?.log ?? const <KitUsage>[];
    return KitSheetScaffold(
      title: '最近使用',
      trailing: KitTwoStageButton(
        compact: true,
        label: '清空',
        confirmLabel: '确认清空',
        onConfirm: () async {
          await ref.read(kitRepositoryProvider).setRecent(const []);
          ref.read(kitTickProvider.notifier).state++;
        },
      ),
      body: Column(
        children: [
          if (recent.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Text(
                '还没有打开过工具 · 从首页点一枚开始',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          for (final key in recent)
            Builder(
              builder: (_) {
                final t = kitToolOf(key);
                if (t == null) return const SizedBox.shrink();
                return InkWell(
                  key: ValueKey('kit-recent-$key'),
                  onTap: () => Navigator.of(context).pop(key),
                  child: KitSheetRow(
                    title: t.name,
                    sub: '已用 ${kitCountByTool(log)[key] ?? 0} 次',
                    trailing: Text(
                      kitRelText(kitLastUse(log, key), now),
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
