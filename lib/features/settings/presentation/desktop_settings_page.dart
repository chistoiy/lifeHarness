import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/platform/desktop_actions.dart';
import '../../../core/platform/desktop_shortcuts.dart';
import '../../../core/platform/desktop_widget.dart'
    show DesktopWidgetSnapshot, kWidgetTodoRows;
import '../../../core/providers.dart';
import '../../../core/settings/settings_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/linkage/desktop_widget_mounts.dart'
    show buildSnapshot, desktopWidgetKickProvider;
import '../../../shared/linkage/widget_bind_mounts.dart'
    show addHabitWidgetFromSettings, WidgetAddOutcome;

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
  const DesktopSettingsPage({super.key, this.addWidgetFlow});

  /// 测试注入缝：「添加小组件」的先选后落流程（生产不传＝走 `shared/linkage` 真流程）。
  ///
  /// 与 `showWidgetTargetPicker(db:)` 同款手法——真流程要读库，而本页测试不该为
  /// 了按一下按钮去初始化整库；注入一个假流程即可钉住**接线与提示**这一层。
  final Future<WidgetAddOutcome?> Function(
      BuildContext context, SharedPreferences prefs)? addWidgetFlow;

  @override
  ConsumerState<DesktopSettingsPage> createState() => _DesktopSettingsPageState();
}

class _DesktopSettingsPageState extends ConsumerState<DesktopSettingsPage> {
  List<String> _menu = const <String>[];
  Set<String> _pinned = <String>{};
  bool _wgSummary = true;
  bool _wgQuick = true;
  bool _wgTodoList = true;
  bool _wgLedger = true;
  bool _hideAmount = false;
  bool _pinSupported = true;

  /// 今日三项读数的当前值：预览与桌面小组件共用同一聚合真源（见 [buildSnapshot]），
  /// 禁在UI 层另算一套（预览写着别的数＝骗人）。
  DesktopWidgetSnapshot _snap = const DesktopWidgetSnapshot(
    todoCount: 0,
    habitDone: 0,
    habitTotal: 0,
    amountCell: '',
    hasSnapshot: false,
  );

  SettingsRepository get _repo => ref.read(settingsRepositoryProvider);

  @override
  void initState() {
    super.initState();
    final r = _repo;
    _menu = r.loadDesktopMenu();
    _pinned = r.loadDesktopPinned();
    _wgSummary = r.loadDesktopWidgetSummary();
    _wgQuick = r.loadDesktopWidgetQuick();
    _wgTodoList = r.loadDesktopWidgetTodoList();
    _wgLedger = r.loadDesktopWidgetLedger();
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

  /// 「添加小组件」＝先选后落（批A · 工单 §2 配置页层 / 原型 `dt-widget` 步①~④）。
  ///
  /// ① 开共享五段选择器（打卡段预开）→ ② 选中即落**预选绑定** → ③ 请系统 pin。
  /// 第④步「配置页读预选绑定无感回写」在原生侧，Dart 不参与；用户在选择器里
  /// 取消则**什么都不落**（不写预选、不调 pin），与原型步③「取消则不落桌面」同口径。
  ///
  /// ⚠ 2026-10-18 真机**二次**报障「点击打卡依旧显示在系统弹窗里确认，但依旧没有系统弹窗」：
  /// 上一版按 `requestPinAppWidget` 的返回值分流，可 **MIUI 返回 true 却什么都不弹**
  /// （系统把请求吞了）⇒ 「true 就说等确认」这条路在真机上依然是谎话。
  ///
  /// 现改为**一律给同一份引导**，措辞不再承诺任何弹窗：标题「已选好 X」，正文先说
  /// 「如果系统没弹确认框（部分桌面会静默忽略）」，再给三步手动添加，并明确
  /// 「拖出来的就是它，不用再选一次」。两种桌面都成立，且不会让用户干等。
  ///
  /// R1：跨模块能力一律经 `shared/linkage`（本页不 import `features/widget`），
  /// 这里只拿到所选目标的人话标签，不接触目标模型与绑定键。
  Future<void> _addHabitWidget() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final flow = widget.addWidgetFlow ?? addHabitWidgetFromSettings;
    final out = await flow(context, prefs);
    if (!mounted || out == null) return;
    await _showAddGuide(out.label);
  }

  /// 「已选好 X，怎么把它放到桌面」的引导（底部弹层·三步）。
  ///
  /// 为什么必须给：`requestPinAppWidget` 是系统能力，桌面可以拒、也可以**静默吞掉**
  /// （MIUI 实测返回 true 但不出弹窗），而 App 没有任何 API 能把实例直接塞到桌面
  /// （`bindAppWidgetId` 要系统权限）。但**手动拖出来照样能用**——选好的目标已经落成
  /// 默认绑定，拖出的新实例直接显示它。所以这里只讲清「去哪儿拖」＋「已经记住了」。
  Future<void> _showAddGuide(String label) async {
    final scheme = Theme.of(context).colorScheme;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '已选好「$label」',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                '如果系统没有弹出「添加到主屏幕」的确认框（部分桌面会静默忽略），'
                '按下面三步手动添加——拖出来的就是「$label」，不用再选一次。',
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.6,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              for (final (i, step) in const [
                (1, '长按桌面空白处，点「添加小工具」'),
                (2, '在列表里找到「LifeHarness」'),
                (3, '把「打卡-单习惯」拖到桌面'),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 20,
                        height: 20,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: scheme.primary.withValues(alpha: .14),
                        ),
                        child: Text(
                          '$i',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: scheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          step,
                          style: const TextStyle(fontSize: 13, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('知道了'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 小组件偏好改动 ⇒ 让快照重算重绘（批2 · F2-3/§4.4）。
  ///
  /// 走 [desktopWidgetKickProvider] 计数源，不直连各 feature（守 R1）。
  void _kickWidgetSync() {
    ref.read(desktopWidgetKickProvider.notifier).state++;
    // ⚠ 2026-10-15 8148 装机实锤修「死开关」：光重发快照**不够**。前两个开关的语义是
    // 「是否添加这枚」的总开关（产品定案）⇒ 关掉必须**真从桌面消失**；且原生侧两枚
    // Provider 原先压根没读这两个偏好。通知原生执行「删除已关的实例 + 重绘已开的」。
    unawaited(applyDesktopWidgetFlags());
  }

  /// 预览卡外框：勾选框 + 名称 + 「添加到桌面」按钮 + 等比样式预览（整卡可点，等价勾选）。
  ///
  /// 2026-10-15 产品改口：「先看样式、再勾选」——省掉用户自己去系统小部件库翻。
  ///
  /// 勾选框语义＝**这枚要不要启用**（关掉真从桌面消失）；「添加到桌面」＝**放一枚新的到桌面**。
  /// 两个动作都落在**同一张卡**上，不再有右上角那个全局按钮、也不再弹 App 自己的选择框
  /// （用户原话：那个框「太丑」且「勾选与否不是添加到桌面的意思…不还是不直观吗」）。
  Widget _widgetPreviewCard(
    BuildContext context, {
    required String keyName,
    required bool enabled,
    required String name,
    required Widget child,
    required Future<void> Function(bool) onToggle,
    required String pinId,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: '$name（已${enabled ? "启用" : "停用"}）',
      child: InkWell(
        key: ValueKey<String>(keyName),
        borderRadius: BorderRadius.circular(12),
        onTap: () => onToggle(!enabled),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    enabled
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    size: 17,
                    color: enabled ? scheme.primary : scheme.outline,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(name,
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurface)),
                  ),
                  // 每张卡自己的「添加到桌面」——点哪枚就是哪枚（不再有中间选择框）。
                  // 按钮自带点击区，会吃掉事件，不会连带触发整卡的启用/停用。
                  TextButton(
                    key: ValueKey<String>('widget-pin-$pinId'),
                    onPressed: () => pinDesktopWidget(pinId),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 30),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text('添加到桌面',
                        style: TextStyle(fontSize: 11.5, color: scheme.primary)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Opacity(
                // 未启用＝不放桌面，预览随之淡出（一眼看出「关掉就没有」）。
                opacity: enabled ? 1.0 : 0.42,
                child: child,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 2×2 今日概览预览（结构与 `res/layout/lh_widget_overview.xml` 1:1）。
  Widget _previewOverview(BuildContext context, ColorScheme scheme) {
    return Container(
      height: 96,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .35)),
      ),
      padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('LifeHarness · 今日概览',
              style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant)),
          const Spacer(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('待办',
                      style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                  Text('${_snap.todoCount}',
                      style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                          color: scheme.onSurface)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('打卡',
                      style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                  Text('${_snap.habitDone}/${_snap.habitTotal}',
                      style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                          color: scheme.onSurface)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: _snap.habitTotal <= 0
                  ? 0
                  : (_snap.habitDone / _snap.habitTotal).clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: scheme.outlineVariant.withValues(alpha: .4),
              valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
            ),
          ),
        ],
      ),
    );
  }

  /// 4×1 快捷记录预览（结构与 `res/layout/lh_widget_quick.xml` 1:1：左半按钮＋右半读数）。
  Widget _previewQuick(BuildContext context, ColorScheme scheme) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .35)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Container(
            width: 48,
            color: scheme.primary,
            alignment: Alignment.center,
            // 竖排：4×1 预览左半只有 ~48px 宽，横排必然溢出（真机宽高比约 4:1）。
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add, size: 13, color: scheme.onPrimary),
                const SizedBox(height: 1),
                Text('记一笔',
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        color: scheme.onPrimary)),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('LifeHarness · 快捷记录',
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('今日支出',
                          style:
                              TextStyle(fontSize: 9, color: scheme.onSurfaceVariant)),
                      Text(
                        _snap.amountCell.isEmpty ? '—' : _snap.amountCell,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            height: 1.1,
                            color: scheme.onSurface),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 2×2 待办清单预览（结构与 `res/layout/lh_widget_todo.xml` 1:1：三行＋「还有 N 条」）。
  Widget _previewTodoList(BuildContext context, ColorScheme scheme) {
    final rows = _snap.todoItems;
    return Container(
      height: 96,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .35)),
      ),
      padding: const EdgeInsets.fromLTRB(11, 9, 11, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('LifeHarness · 今日待办',
              style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant)),
          const SizedBox(height: 5),
          if (rows.isEmpty)
            Text(_snap.hasSnapshot ? '今天没有待办' : '打开 App 后同步',
                style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant))
          else
            for (final r in rows.take(kWidgetTodoRows))
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  children: [
                    Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: r.done ? scheme.primary : Colors.transparent,
                        border: Border.all(
                            color: r.done ? scheme.primary : scheme.outline, width: 1.4),
                      ),
                      child: r.done
                          ? Icon(Icons.check, size: 8, color: scheme.onPrimary)
                          : null,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(r.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 10.5,
                              decoration:
                                  r.done ? TextDecoration.lineThrough : null,
                              color: scheme.onSurface)),
                    ),
                  ],
                ),
              ),
          const Spacer(),
          Text(_snap.todoOverflow > 0 ? '还有 ${_snap.todoOverflow} 条' : '',
              style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  /// 2×2 记账概览预览（三行读数：今日支出／本月支出／本月结余）。
  Widget _previewLedger(BuildContext context, ColorScheme scheme) {
    Widget row(String label, String? value, {bool acc = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
              Text(
                (value == null || value.isEmpty) ? '—' : value,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                    color: acc ? scheme.primary : scheme.onSurface),
              ),
            ],
          ),
        );

    return Container(
      height: 96,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .35)),
      ),
      padding: const EdgeInsets.fromLTRB(11, 9, 11, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('LifeHarness · 记账概览',
              style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          row('今日支出', _snap.amountCell.isEmpty ? null : '¥${_snap.amountCell}'),
          row('本月支出',
              _snap.monthAmountCell.isEmpty ? null : '¥${_snap.monthAmountCell}'),
          row('本月结余',
              _snap.balanceCell.isEmpty ? null : _moneySigned(_snap.balanceCell),
              acc: true),
        ],
      ),
    );
  }

  /// 结余位的符号口径与 [widgetBalanceCell] 一致：负数 `-¥1,286`（不是 `¥-1,286`）。
  String _moneySigned(String cell) =>
      cell.startsWith('-') ? '-¥${cell.substring(1)}' : '¥$cell';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final menuCount = _menu.length;
    // 预览读数走共享聚合真源（与桌面上的小组件同一函数）。
    _snap = buildSnapshot(ref.read) ?? _snap;

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
              Text(
                  _pinSupported
                      ? '长按桌面图标弹出的快捷菜单最多 $kMenuMax 个；更多入口请用下方「铺到桌面」'
                      : '长按桌面图标弹出的快捷菜单最多 $kMenuMax 个',
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

          // ===== ② 铺到桌面（仅在桌面支持「钉快捷方式」时才画）=====
          // 2026-10-16 产品令：本机（MIUI）`isRequestPinShortcutSupported` 为 false，
          // 这一整块 7 项全显示「本机不支持」＝废的还占屏。既然设备不支持就不画；
          // 支持的桌面（原生 Pixel 等）照旧显示，能力不丢 —— 不是删功能，是按能力显示。
          if (_pinSupported)
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
              // 2026-10-15 产品改口：右上角那个全局「添加到桌面」按钮删了 —— 它要再弹一个
              // App 自己的选择框（原生 AlertDialog，跟卡片体系完全不搭），而「列表勾选」
              // 与「添加」两个语义又挤在一起。现改为**每张卡自带**按钮，点哪枚就是哪枚。
              //
              // 批A（2026-10-18）：读数四枚仍走「点哪枚加哪枚」；**绑定型**（打卡-单习惯）
              // 多一步「先选后落」——故这里另给一个入口，点了先开五段选择器。
              Row(
                children: [
                  const Text('小组件',
                      style:
                          TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
                  const Spacer(),
                  TextButton(
                    key: const ValueKey<String>('wg-add-widget'),
                    onPressed: _addHabitWidget,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 30),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text('添加小组件',
                        style: TextStyle(fontSize: 11.5, color: scheme.primary)),
                  ),
                ],
              ),
              Text(
                  '桌面常驻读数，点击直达应用内；读数四枚点「添加到桌面」即放一枚，'
                  '打卡枚先选习惯再落桌面',
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
              const SizedBox(height: 10),
              // 2026-10-15 产品改口：先看**样式预览**再勾选要哪几枚，不必去系统小部件库翻。
              // 预览用真实读数与真实比例（按原生 RemoteViews 的结构 1:1 映射），不另造比例。
              _widgetPreviewCard(
                context,
                keyName: 'wg-summary',
                pinId: 'overview',
                enabled: _wgSummary,
                name: '今日概览（2×2）',
                child: _previewOverview(context, scheme),
                onToggle: (v) async {
                  setState(() => _wgSummary = v);
                  await _repo.saveDesktopWidgetSummary(v);
                  _kickWidgetSync();
                },
              ),
              const SizedBox(height: 10),
              _widgetPreviewCard(
                context,
                keyName: 'wg-quick',
                pinId: 'quick',
                enabled: _wgQuick,
                name: '快捷记录（4×1）',
                child: _previewQuick(context, scheme),
                onToggle: (v) async {
                  setState(() => _wgQuick = v);
                  await _repo.saveDesktopWidgetQuick(v);
                  _kickWidgetSync();
                },
              ),
              const SizedBox(height: 10),
              _widgetPreviewCard(
                context,
                keyName: 'wg-todo-list',
                pinId: 'todo',
                enabled: _wgTodoList,
                name: '今日待办（2×2）',
                child: _previewTodoList(context, scheme),
                onToggle: (v) async {
                  setState(() => _wgTodoList = v);
                  await _repo.saveDesktopWidgetTodoList(v);
                  _kickWidgetSync();
                },
              ),
              const SizedBox(height: 10),
              _widgetPreviewCard(
                context,
                keyName: 'wg-ledger',
                pinId: 'ledger',
                enabled: _wgLedger,
                name: '记账概览（2×2）',
                child: _previewLedger(context, scheme),
                onToggle: (v) async {
                  setState(() => _wgLedger = v);
                  await _repo.saveDesktopWidgetLedger(v);
                  _kickWidgetSync();
                },
              ),
              const SizedBox(height: 10),
              _switchRow('隐藏金额同步到小组件', _hideAmount, (v) async {
                setState(() => _hideAmount = v);
                await _repo.saveDesktopHideAmount(v);
                _kickWidgetSync();
              }, keyName: 'wg-hide-amount'),
              // 批A 试点行：绑定型小组件（每枚绑一个习惯·点即打卡）。
              // 与读数四枚的区别＝**有目标**，故添加前必须先选（先选后落）。
              Divider(height: 1, color: scheme.outlineVariant),
              SizedBox(
                height: 48,
                child: Row(
                  children: [
                    Icon(Icons.task_alt_outlined,
                        size: 18, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('打卡-单习惯（2×2）',
                              style: TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                          Text('每枚绑一个习惯，点一下就打卡',
                              style: TextStyle(
                                  fontSize: 10.5, color: scheme.outline)),
                        ],
                      ),
                    ),
                    TextButton(
                      key: const ValueKey<String>('wg-pin-habit'),
                      onPressed: _addHabitWidget,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 30),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text('添加',
                          style:
                              TextStyle(fontSize: 11.5, color: scheme.primary)),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 4),
                child: Text(
                  '小组件读数来自最近一次同步快照，可能略有延迟；开启「隐藏金额」时小组件金额位显示为 ••••。'
                  '「打卡-单习惯」每枚绑一个习惯：点小组件即打卡，不用打开 App。',
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