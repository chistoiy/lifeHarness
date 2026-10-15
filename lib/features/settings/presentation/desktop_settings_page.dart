import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/desktop_actions.dart';
import '../../../core/platform/desktop_shortcuts.dart';
import '../../../core/providers.dart';
import '../../../core/settings/settings_repository.dart';
import '../../../core/theme/app_theme.dart';

/// 「桌面与快捷方式」二级页（原型 `p-sub-desktop`，家＝壳 index.html；本屏 Flutter 侧）。
///
/// 规格＝docs/handoff/桌面模块-冻结版开发方案-20261013.md §2.1 F1-3~F1-6 / §4.1 / §4.2 / §5。
///
/// 三卡结构与原型同序：① 长按菜单（7 个动作行 checkbox，已选 N/4 计数，上限拦截）
/// ② 铺到桌面（每行「铺到桌面」／已铺态，不支持则禁用＋提示 B2）③ 小组件（两个开关＋隐藏金额）。
///
/// **架构红线（R1）**：本页与各业务 feature **互不直连 import**，跳转只用动作表
/// 里的 path 字符串；本页不引用任何 feature 的业务方法（守 architecture_test）。
class DesktopSettingsPage extends ConsumerStatefulWidget {
  const DesktopSettingsPage({super.key});

  @override
  ConsumerState<DesktopSettingsPage> createState() => _DesktopSettingsPageState();
}

class _DesktopSettingsPageState extends ConsumerState<DesktopSettingsPage> {
  List<String> _menu = const <String>[];
  Set<String> _pinned = <String>{};
  bool _wgSummary = true;
  bool _wgQuick = true;
  bool _hideAmount = false;
  bool _pinSupported = true;

  SettingsRepository get _repo => ref.read(settingsRepositoryProvider);

  @override
  void initState() {
    super.initState();
    final r = _repo;
    _menu = r.loadDesktopMenu();
    _pinned = r.loadDesktopPinned();
    _wgSummary = r.loadDesktopWidgetSummary();
    _wgQuick = r.loadDesktopWidgetQuick();
    _hideAmount = r.loadDesktopHideAmount();
    // 铺桌面支持态由原生侧回包；测试环境无通道时按「不支持」降级（B2）。
    _pinSupported = pinShortcutSupported;
    // 首进入屏即重建一次长按菜单，保证与偏好一致（冷启动偏好变了也能对上）。
    WidgetsBinding.instance.addPostFrameCallback((_) => _rebuildShortcuts());
  }

  Future<void> _rebuildShortcuts() async {
    if (!mounted) return;
    try {
      await syncShortcuts(_menu);
    } catch (_) {
      // catch-ok: 原生桥不可用（测试/异常设备）时静默降级，不打断设置页。
    }
  }

  /// 上限拦截（§4.1）：已满且该项未选 → 拒并提示，**不写偏好**。
  Future<void> _toggleMenu(String id, bool on) async {
    if (!on) {
      setState(() => _menu = _menu.where((e) => e != id).toList());
    } else {
      if (_menu.length >= kMenuMax) {
        _toast('长按菜单最多 $kMenuMax 个，更多入口请「铺到桌面」');
        return;
      }
      setState(() => _menu = <String>[..._menu, id]);
    }
    await _repo.saveDesktopMenu(_menu);
    await _rebuildShortcuts(); // F1-2/F1-4：改动即时重建，无需重启
  }

  Future<void> _pin(String id) async {
    final ok = await requestPinShortcut(id);
    if (ok) {
      setState(() => _pinned = <String>{..._pinned, id});
      await _repo.saveDesktopPinned(_pinned);
      _toast('已铺到桌面');
    } else {
      _toast('这台设备不支持铺到桌面');
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(msg), duration: const Duration(milliseconds: 1600)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final menuCount = _menu.length;

    return Scaffold(
      appBar: AppBar(title: const Text('桌面与快捷方式')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          // ===== ① 长按菜单 =====
          _card(context, child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('长按图标菜单',
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
                  const Spacer(),
                  Text('已选 $menuCount/$kMenuMax',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: scheme.primary)),
                ],
              ),
              const SizedBox(height: 2),
              Text('长按桌面图标弹出的快捷菜单最多 $kMenuMax 个；更多入口请用下方「铺到桌面」',
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
              const SizedBox(height: 6),
              // 两列网格（同「底部导航栏自定义」语言）
              LayoutBuilder(builder: (ctx, c) {
                const gap = 20.0;
                final w = (c.maxWidth - gap) / 2;
                return Wrap(
                  spacing: gap,
                  runSpacing: 0,
                  children: kDesktopActions.map((a) {
                    final on = _menu.contains(a.id);
                    // 上限拦截：已满且该项未选 → 置灰不可点（§4.1）
                    final blocked = !on && menuCount >= kMenuMax;
                    return SizedBox(
                      width: w,
                      height: 42,
                      child: Row(
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: Checkbox(
                              key: ValueKey<String>('menu-${a.id}'),
                              value: on,
                              onChanged: blocked
                                  ? null
                                  : (v) => _toggleMenu(a.id, v ?? false),
                            ),
                          ),
                          const SizedBox(width: 2),
                          Flexible(
                            child: Text(a.label,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: blocked
                                        ? scheme.onSurfaceVariant
                                        : null)),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                );
              }),
              if (menuCount >= kMenuMax)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('已选满 $kMenuMax 个，取消一个才能换其他动作',
                      style: TextStyle(fontSize: 10.5, color: scheme.outline)),
                ),
            ],
          )),

          // ===== ② 铺到桌面 =====
          _card(context, margin: const EdgeInsets.only(top: 12), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('铺到桌面',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text('把常用动作固定到桌面，数量不限、逐条添加',
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
              const SizedBox(height: 4),
              ...kDesktopActions.map((a) {
                final done = _pinned.contains(a.id);
                return Column(
                  children: [
                    Divider(height: 1, color: scheme.outlineVariant),
                    SizedBox(
                      height: 46,
                      child: Row(
                        children: [
                          Icon(_iconOf(a.id), size: 18, color: scheme.onSurfaceVariant),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(a.label,
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w600)),
                          ),
                          if (done)
                            Text('已铺',
                                style: TextStyle(fontSize: 11, color: scheme.outline))
                          else
                            TextButton(
                              key: ValueKey<String>('pin-${a.id}'),
                              onPressed: _pinSupported ? () => _pin(a.id) : null,
                              child: Text(
                                _pinSupported ? '铺到桌面' : '本机不支持',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: _pinSupported ? scheme.primary : scheme.outline),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              }),
            ],
          )),

          // ===== ③ 小组件 =====
          _card(context, margin: const EdgeInsets.only(top: 12), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('小组件',
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
                  const Spacer(),
                  TextButton(
                    onPressed: () => _toast('已调起系统小部件中心（批 2 交付原生选择器）'),
                    child: Text('添加到桌面',
                        style: TextStyle(fontSize: 12, color: scheme.primary)),
                  ),
                ],
              ),
              Text('桌面常驻读数，点击直达应用内',
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
              _switchRow('今日概览读数（2×2）', _wgSummary, (v) async {
                setState(() => _wgSummary = v);
                await _repo.saveDesktopWidgetSummary(v);
              }, keyName: 'wg-summary'),
              _switchRow('快捷记录入口（4×1）', _wgQuick, (v) async {
                setState(() => _wgQuick = v);
                await _repo.saveDesktopWidgetQuick(v);
              }, keyName: 'wg-quick'),
              _switchRow('隐藏金额同步到小组件', _hideAmount, (v) async {
                setState(() => _hideAmount = v);
                await _repo.saveDesktopHideAmount(v);
              }, keyName: 'wg-hide-amount'),
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 4),
                child: Text(
                  '小组件读数来自最近一次同步快照，可能略有延迟；开启「隐藏金额」时小组件金额位显示为 ••••。',
                  style: TextStyle(fontSize: 10.5, height: 1.6, color: scheme.outline),
                ),
              ),
            ],
          )),

          // ===== 链接直达 =====
          _card(context, margin: const EdgeInsets.only(top: 12), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('链接直达',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text.rich(
                TextSpan(style: TextStyle(fontSize: 11, height: 1.7, color: scheme.onSurfaceVariant), children: [
                  const TextSpan(text: '支持 lh:// 链接从浏览器、二维码、NFC 或自动化工具直接打开对应动作，例如 '),
                  TextSpan(text: 'lh://ledger/add', style: TextStyle(color: scheme.primary, fontFamily: 'monospace')),
                  const TextSpan(text: '、'),
                  TextSpan(text: 'lh://inbox/new', style: TextStyle(color: scheme.primary, fontFamily: 'monospace')),
                  const TextSpan(text: '。'),
                ]),
              ),
            ],
          )),
        ],
      ),
    );
  }

  Widget _switchRow(String label, bool value, Future<void> Function(bool) onChanged,
      {String? keyName}) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Divider(height: 1, color: scheme.outlineVariant),
        SizedBox(
          height: 48,
          child: Row(
            children: [
              Expanded(
                child: Text(label,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              Switch(
                key: keyName == null ? null : ValueKey<String>(keyName),
                value: value,
                onChanged: (v) => onChanged(v),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _card(BuildContext context, {required Widget child, EdgeInsets? margin}) {
    final tokens = context.tokens;
    return Container(
      margin: margin,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: tokens.card,
        borderRadius: BorderRadius.circular(tokens.cardRadius),
        border: Border.all(color: tokens.cardBorder),
        boxShadow: tokens.cardShadow,
      ),
      child: child,
    );
  }

  /// 线性图标（禁 emoji · §5.5）。
  IconData _iconOf(String id) {
    switch (id) {
      case 'inbox':
        return Icons.inbox_outlined;
      case 'todo':
        return Icons.checklist_outlined;
      case 'ledger':
        return Icons.account_balance_wallet_outlined;
      case 'habit':
        return Icons.task_alt_outlined;
      case 'journal':
        return Icons.edit_note_outlined;
      case 'items':
        return Icons.inventory_2_outlined;
      case 'today':
        return Icons.today_outlined;
      default:
        return Icons.bolt_outlined;
    }
  }
}