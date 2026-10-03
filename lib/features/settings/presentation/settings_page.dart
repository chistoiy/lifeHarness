import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ai/ai_providers.dart' show aiConfigProvider;
import '../../../core/database/app_database.dart';
import '../../../core/database/schema.dart';
import '../../../core/nav/nav_module.dart';
import '../../../core/providers.dart';
import '../../../core/settings/user_settings.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/linkage/linkage_events.dart';
import '../../../shared/linkage/stats_providers.dart';
import '../../../shared/weather/weather.dart';
import 'profile_edit_sheet.dart';
import 'weather_city_sheet.dart';

/// 我的/设置（M0 · 对齐原型 p-profile）。
/// 真数据：完成任务数/连续记录天/主题/深色/底栏配置。
/// 仍为占位入口：插件中心(M4)/主题市场/字号调节；数据与同步·提醒通知·AI·小工具均已上线。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final settings = ref.watch(settingsControllerProvider);
    final streak = ref.watch(streakDaysProvider).valueOrNull ?? 0;
    final doneTasks = ref.watch(doneTaskCountProvider).valueOrNull ?? 0;
    // R14-12/13：资料与三宫格同源实算——昵称/签名走设置项，书籍数走聚合层。
    final nick = settings.nickOrFallback;
    final books = ref.watch(shelfBookCountProvider).valueOrNull ?? 0;

    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 资料卡（原型 p-profile：渐变字母头像 + 昵称 + 本地模式副行 + 编辑）
          Row(
            children: [
              Container(
                width: 62,
                height: 62,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    shape: BoxShape.circle, gradient: tokens.gradient),
                child: Text(nick.substring(0, 1).toUpperCase(),
                    style: const TextStyle(
                        color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(nick,
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    // 真机反馈轮4③：副标题「已记录 N 天」点按直达日记（记录页）。
                    GestureDetector(
                      key: const ValueKey('profile-sub'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => context.go(NavModule.journal.path),
                      child: Text(
                          // 原型 p-profile 副行 + 顶栏副标题（App 顶栏无副标题位，签名并到这一行）。
                          '本地模式 · 无账号 · 已记录 $streak 天'
                          '${settings.profileBio.isEmpty ? '' : ' · ${settings.profileBio}'}',
                          style: const TextStyle(fontSize: 11.5, color: Colors.grey)),
                    ),
                  ],
                ),
              ),
              TextButton(
                key: const ValueKey('profile-edit'),
                onPressed: () => showProfileEditSheet(context, ref),
                child: Text('编辑',
                    style: TextStyle(
                        color: tokens.accent, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // 统计三宫格（真机反馈轮4③：数字与模块同源，点卡直达对应列表页）
          Row(
            children: [
              _StatCell(
                  key: const ValueKey('stat-done'),
                  value: '$doneTasks',
                  label: '完成任务',
                  color: tokens.accent,
                  onTap: () => context.go(NavModule.todo.path)),
              const SizedBox(width: 10),
              _StatCell(
                  key: const ValueKey('stat-streak'),
                  value: '$streak',
                  label: '连续记录天',
                  color: const Color(0xFF2DD4BF),
                  onTap: () => context.go(NavModule.journal.path)),
              const SizedBox(width: 10),
              _StatCell(
                  key: const ValueKey('stat-books'),
                  value: '$books',
                  label: '在册书籍',
                  color: const Color(0xFFF59E0B),
                  onTap: () => context.push('/read/shelf')),
            ],
          ),
          const SizedBox(height: 14),
          // 二级入口列表（原型 p-profile 顺序：数据与同步/提醒通知/AI/分类/工具/插件）
          Container(
            decoration: context.cardDecoration,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _EntryRow(
                    key: const ValueKey('entry-sync'),
                    iconWidget: Icon(Icons.cloud_outlined,
                    size: 18, color: const Color(0xFF10B981)),
                                        bg: const Color(0xFF10B981).withValues(alpha: .12),
                    title: '数据与同步',
                    sub: 'WebDAV · 备份 · 加密 · 同步历史',
                    trailing: '● 未配置',
                    trailingColor: Colors.grey,
                    // V1.41 Task 10：占位 toast 改真实 /sync 路由（空壳页）。
                    // R2 项④：go→push——push 压栈保留设置页，系统返回回设置页；
                    // go 会替换整栈致返回直接退出 app。
                    onTap: () => context.push('/sync')),
                // 批8收口：母婴敏感数据同步排除联动行（开关实体在呵护提醒页）。
                const _CareSyncLink(),
                // V1.41批1 Task 6：日志查看页入口（原型 index-sync p-log）。
                _EntryRow(
                    key: const ValueKey('entry-log'),
                    iconWidget: const Icon(Icons.receipt_long_outlined,
                        size: 18, color: Color(0xFF0891B2)),
                    bg: const Color(0xFF06B6D4).withValues(alpha: .12),
                    title: '运行日志',
                    sub: '环形缓冲 300 · 级别过滤 · 复制全量 · 保留天数',
                    trailing: '',
                    // R2 项④：go→push，从设置页进日志后返回回设置页而非退出 app。
                    onTap: () => context.push('/log')),
                // R5c：图片存储清理入口（本地孤儿图片勾选清理）。
                _EntryRow(
                    key: const ValueKey('entry-media-clean'),
                    iconWidget: const Icon(Icons.image_outlined,
                        size: 18, color: Color(0xFF059669)),
                    bg: const Color(0xFF10B981).withValues(alpha: .12),
                    title: '图片存储清理',
                    sub: '未引用图片扫描 · 勾选清理',
                    trailing: '',
                    onTap: () => context.push('/settings/media-clean')),
                _EntryRow(
                    iconWidget: Icon(Icons.notifications_none,
                    size: 18, color: const Color(0xFF6366F1)),
                                        bg: const Color(0xFF6366F1).withValues(alpha: .12),
                    title: '提醒通知',
                    sub: '日程 · 日记复盘 · 收集箱清理 · 习惯',
                    trailing: ref
                            .watch(settingsControllerProvider.select(
                                (s) => s.notify.todoEvent || s.notify.inboxClean || s.notify.diaryReview))
                        ? '已开启'
                        : '未开启',
                    trailingColor: Colors.grey,
                    onTap: () => context.push('/settings/notify')),
                _EntryRow(
                    key: const ValueKey('entry-ai'),
                    iconWidget: Icon(Icons.memory,
                    size: 18, color: const Color(0xFF8B5CF6)),
                                        bg: const Color(0xFF8B5CF6).withValues(alpha: .12),
                    title: 'AI 增强',
                    sub: '服务商 · Key · 能力矩阵 · API 验证',
                    trailing: ref
                            .watch(aiConfigProvider.select((c) => c.master))
                        ? '已开启'
                        : '默认关闭',
                    trailingColor: ref
                            .watch(aiConfigProvider.select((c) => c.master))
                        ? const Color(0xFF10B981)
                        : Colors.grey,
                    // AI批：占位 toast → 真实二级页（原型 p-sub-ai）。
                    onTap: () => context.push('/settings/ai')),
                _EntryRow(
                    iconWidget: Icon(Icons.label_outline,
                    size: 18, color: const Color(0xFFF97316)),
                                        bg: const Color(0xFFF97316).withValues(alpha: .12),
                    title: '分类管理',
                    sub: '时间块/日程两级分类 · 颜色 · 标签 · 拖拽换组',
                    trailing: '',
                    onTap: () => context.push('/categories')),
                // V1.58 反馈轮5：「小工具合集」入口行摘除——与「今天」页
                // 全部功能宫格的「小工具」重复，入口只留一处。
                _EntryRow(
                    iconWidget: Icon(Icons.extension_outlined,
                    size: 18, color: const Color(0xFF6B7280)),
                                        bg: Colors.grey.withValues(alpha: .12),
                    title: '插件中心',
                    sub: '大模块按需安装 · 更新 · 回滚',
                    trailing: '',
                    last: true,
                    onTap: () => _toast(context, '插件中心 · 敬请期待')),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // V1.27 P2：主题风格/深色/主题色/字号 收进「外观」二级页，主页只留一行入口
          _Card(
            child: _EntryRow(
                    key: const ValueKey('entry-appearance'),
                    iconWidget: Icon(Icons.palette_outlined,
                    size: 18, color: const Color(0xFF0EA5E9)),
                                        bg: const Color(0xFF0EA5E9).withValues(alpha: .12),
                    title: '外观',
                    sub: '主题风格 · 深色模式 · 主题色 · 字体大小',
                    trailing: '',
                    last: true,
                    onTap: () => context.push('/settings/appearance')),
          ),
          const SizedBox(height: 14),
          // 批2e：日记天气城市（一次选定 · 写日记当天自动抓快照 · 不申请定位权限）
          _Card(
            child: _EntryRow(
                    key: const ValueKey('entry-weather'),
                    iconWidget: const Icon(Icons.wb_sunny_outlined,
                        size: 18, color: Color(0xFF0284C7)),
                    bg: const Color(0xFF0EA5E9).withValues(alpha: .12),
                    title: '日记天气',
                    sub: '城市 · ${WeatherCity.decode(ref.watch(settingsControllerProvider).weatherCity)?.name ?? '未设置'}',
                    trailing: '',
                    last: true,
                    onTap: () => showWeatherCitySheet(context, ref)),
          ),
          const SizedBox(height: 14),
          // V1.29批A4：记录管理二级页（原型 p-sub-recmg：四段设置归位 + 通用）
          _Card(
            child: _EntryRow(
                    key: const ValueKey('entry-recmg'),
                    iconWidget: Icon(Icons.menu_book_outlined,
                    size: 18, color: const Color(0xFF8B5CF6)),
                                        bg: const Color(0xFF8B5CF6).withValues(alpha: .12),
                    title: '记录管理',
                    sub: '版本恢复 · 快照 · 回收站清理',
                    trailing: '',
                    last: true,
                    onTap: () => context.push('/settings/recmg')),
          ),
          const SizedBox(height: 14),
          // 底部导航自定义卡
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                        child: Text('底部导航栏自定义',
                            style:
                                TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
                    Text(
                      '已启用 ${settings.navIds.length}/5',
                      style: TextStyle(
                          fontSize: 11,
                          color: tokens.accent,
                          fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const Text('开启的栏目实时出现在底部导航；「今天」「我的」固定',
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 6),
                _NavToggleGrid(settings: settings),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    // V1.27 P3：编排直达 = 回今天页并进入长按编排模式（与 H1 同一实现）
                    onPressed: () {
                      context.go(NavModule.today.path);
                      Future.delayed(const Duration(milliseconds: 350),
                          () => ref
                              .read(eventBusProvider)
                              .publish(const EnterDashEditEvent()));
                    },
                    style: OutlinedButton.styleFrom(
                      backgroundColor: tokens.accent.withValues(alpha: .06),
                      foregroundColor: tokens.accent,
                      side: BorderSide(color: tokens.accent.withValues(alpha: .3)),
                    ),
                    child: const Text('主页编排直达（或长按卡片）›',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // 关于卡
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: context.cardDecoration,
            child: const Text(
              '关于\n\nLifeHarness · 全模块本地优先的生活记录台\n'
              '仅中文 ｜ 纯本地无账号 ｜ Android 8.0+ ｜ 离线优先 ｜ AI 能力可选增强\n'
              '7 套内置主题 · 设计令牌热加载 · 未开放模块入口灰显 + 版本角标',
              style: TextStyle(fontSize: 11.5, height: 1.7, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  static bool _isDarkNow(BuildContext context, UserSettings s) {
    if (s.mode == ThemeModeOption.dark) return true;
    if (s.mode == ThemeModeOption.light) return false;
    return MediaQuery.platformBrightnessOf(context) == Brightness.dark;
  }
}

void _toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(milliseconds: 1500)));
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: context.cardDecoration,
      child: child,
    );
  }
}

/// 设置行图标块（原型 .set-ic：36px 圆角浅底）。
class _SetIc extends StatelessWidget {
  const _SetIc({this.emoji = '', this.icon, this.text = false});

  final String emoji;

  /// R14-7：外观页小方格图标位（禁 emoji，传线性图标）。
  final IconData? icon;
  final bool text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: icon != null
          ? Icon(icon, size: 18, color: scheme.onSurfaceVariant)
          : Text(emoji,
              style: TextStyle(
                  fontSize: text ? 13 : 16,
                  fontWeight: text ? FontWeight.w800 : FontWeight.normal)),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({
    super.key,
    required this.value,
    required this.label,
    required this.color,
    this.onTap,
  });

  final String value;
  final String label;
  final Color color;
  // 真机反馈轮4③：统计卡可点直达对应列表页（LH-K15 虚线下划线语义）。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: context.cardDecoration,
          child: Column(
            children: [
              Text(value,
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: color,
                      decoration: onTap == null
                          ? null
                          : TextDecoration.underline,
                      decorationStyle: TextDecorationStyle.dashed,
                      decorationColor: Colors.grey.withValues(alpha: .6))),
              const SizedBox(height: 2),
              Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    super.key,
    required this.iconWidget,
    required this.bg,
    required this.title,
    required this.sub,
    required this.trailing,
    this.last = false,
    this.trailingColor,
    required this.onTap,
  });

  /// R14-7：入口位只接受线性图标（UI 禁 emoji 硬规矩；emoji 文本位已整体摘除）。
  final Widget iconWidget;
  final Color bg;
  final String title;
  final String sub;
  final String trailing;
  final bool last;
  final Color? trailingColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          border: last ? null : const Border(bottom: BorderSide(color: Color(0x14000000))),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
              child: iconWidget,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                  Text(sub, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ),
            Text(trailing,
                style: TextStyle(
                    fontSize: 10.5, color: trailingColor ?? Colors.grey)),
            const Text(' ›', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

/// 主题预览缩略卡 3 列（原型 themeStyleRow）。
class _ThemeGrid extends ConsumerWidget {
  const _ThemeGrid({required this.registry, required this.selectedId});

  final ThemeRegistry registry;
  final String selectedId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, c) {
        const cols = 3;
        const gap = 8.0;
        final w = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final b in registry.all)
              SizedBox(
                width: w,
                child: _ThemeTile(
                  bundle: b,
                  selected: b.id == selectedId,
                  onTap: () {
                    ref.read(settingsControllerProvider.notifier).setTheme(b.id);
                    ref.read(eventBusProvider).publish(ThemeChangedEvent(b.id));
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ThemeTile extends StatelessWidget {
  const _ThemeTile({required this.bundle, required this.selected, required this.onTap});

  final ThemeBundle bundle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = bundle.pick(Theme.of(context).brightness == Brightness.dark);
    final darkBg =
        ThemeData.estimateBrightnessForColor(t.card) == Brightness.dark;
    final labelColor = darkBg ? Colors.white70 : Colors.black87;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: t.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected ? t.accent : t.cardBorder, width: selected ? 2 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 14,
              decoration: BoxDecoration(
                  gradient: t.gradient, borderRadius: BorderRadius.circular(5)),
            ),
            const SizedBox(height: 5),
            Row(
              children: [
                Expanded(
                    child: Container(
                        height: 8,
                        decoration: BoxDecoration(
                            color: t.accent.withValues(alpha: .35),
                            borderRadius: BorderRadius.circular(3)))),
                const SizedBox(width: 3),
                Expanded(
                    child: Container(
                        height: 8,
                        decoration: BoxDecoration(
                            color: t.page,
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(color: t.cardBorder)))),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(bundle.meta.name,
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                          color: selected ? t.accent : labelColor),
                      overflow: TextOverflow.ellipsis),
                ),
                if (selected) Icon(Icons.check_circle, size: 13, color: t.accent),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 底栏栏目两列开关网格。
class _NavToggleGrid extends ConsumerWidget {
  const _NavToggleGrid({required this.settings});

  final UserSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pinned = {NavModule.today.id, NavModule.settings.id};
    return LayoutBuilder(
      builder: (context, c) {
        final w = (c.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 2,
          children: [
            for (final m in NavModule.values)
              SizedBox(
                width: w,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        pinned.contains(m.id) ? '${m.label}（固定）' : m.label,
                        style: const TextStyle(fontSize: 12.5),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Switch(
                      value: settings.navIds.contains(m.id),
                      onChanged: pinned.contains(m.id)
                          ? null
                          : (_) async {
                              final messenger = ScaffoldMessenger.of(context);
                              final ok = await ref
                                  .read(settingsControllerProvider.notifier)
                                  .toggleNav(m);
                              if (!ok) {
                                messenger.showSnackBar(
                                    const SnackBar(content: Text('底部导航最多 5 个栏目')));
                              }
                            },
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// V1.27 P2 外观二级页（原型 p-sub-appearance）：主题风格/深色模式/主题色/字体大小 收拢。
class AppearanceSettingsPage extends ConsumerWidget {
  const AppearanceSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final settings = ref.watch(settingsControllerProvider);
    final registry = ref.watch(themeRegistryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('外观')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                        child: Text('主题风格',
                            style:
                                TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
                    TextButton(
                      onPressed: () => _toast(context, '主题市场（GitHub 热加载）V1.x 上线'),
                      child: Text('更多主题 ›',
                          style: TextStyle(
                              fontSize: 11,
                              color: tokens.accent,
                              fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                Text('${registry.ids.length} 套内置 · 配置文件热加载 · 与深色模式正交 · 赛博朋克强制深色',
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 10),
                _ThemeGrid(registry: registry, selectedId: settings.themeId),
                // 深色模式（原型：单 toggle · 与主题正交）
                Row(
                  children: [
                    _SetIc(icon: Icons.dark_mode_outlined),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('深色模式',
                              style: TextStyle(
                                  fontSize: 13.5, fontWeight: FontWeight.w700)),
                          GestureDetector(
                            onTap: () => ref
                                .read(settingsControllerProvider.notifier)
                                .setMode(ThemeModeOption.system),
                            child: Text(
                              settings.mode == ThemeModeOption.system
                                  ? '与任意主题风格叠加生效 · 当前跟随系统（点此锁定/解锁）'
                                  : '与任意主题风格叠加生效 · ${settings.mode == ThemeModeOption.dark ? '已锁定深色' : '已锁定浅色'}（点此跟随系统）',
                              style: const TextStyle(
                                  fontSize: 10.5, color: Colors.grey),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: SettingsPage._isDarkNow(context, settings),
                      onChanged: (v) => ref
                          .read(settingsControllerProvider.notifier)
                          .setMode(v ? ThemeModeOption.dark : ThemeModeOption.light),
                    ),
                  ],
                ),
                // 主题色（原型 themeDots：一排色点，点击=切对应主题）
                Row(
                  children: [
                    _SetIc(icon: Icons.palette_outlined),
                    const SizedBox(width: 12),
                    const Expanded(
                        child: Text('主题色',
                            style:
                                TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700))),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final b in registry.all)
                          Builder(builder: (context) {
                            final t = b.pick(
                                Theme.of(context).brightness == Brightness.dark);
                            final on = b.id == settings.themeId;
                            return GestureDetector(
                              key: ValueKey('theme-dot-${b.id}'),
                              onTap: () {
                                ref
                                    .read(settingsControllerProvider.notifier)
                                    .setTheme(b.id);
                                ref
                                    .read(eventBusProvider)
                                    .publish(ThemeChangedEvent(b.id));
                              },
                              child: Container(
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: t.gradient,
                                  border: Border.all(
                                      color: on
                                          ? t.accent
                                          : Colors.black.withValues(alpha: .12),
                                      width: on ? 2.5 : 1),
                                ),
                              ),
                            );
                          }),
                      ],
                    ),
                  ],
                ),
                // 字体大小（原型默认第 2 档）
                Row(
                  children: [
                    _SetIc(emoji: 'Aa', text: true),
                    const SizedBox(width: 12),
                    const Expanded(
                        child: Text('字体大小',
                            style:
                                TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700))),
                    SizedBox(
                      width: 120,
                      child: Slider(
                        value: 2,
                        max: 3,
                        onChanged: (_) =>
                            _toast(context, '字号调节 · 敬请期待（无障碍）'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 呵护敏感数据同步排除·联动行（红线 7）。
/// 开关实体在「呵护提醒」页；此行只读展示状态并作为跳转入口，
/// 与原型 p-sub-data 的灰字提示行对应（同步引擎落地前先可见可查）。
final careSyncExcludedProvider = FutureProvider.autoDispose<bool>((ref) async {
  final rows = await AppDatabase.instance.db.query(DbSchema.tSettings,
      where: 'key = ?', whereArgs: ['care.syncExcluded'], limit: 1);
  final v = rows.isEmpty ? null : rows.first['value'] as String?;
  return v == null || v == 'true'; // 默认开
});

class _CareSyncLink extends ConsumerWidget {
  const _CareSyncLink();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(careSyncExcludedProvider).valueOrNull ?? true;
    return GestureDetector(
      key: const ValueKey('settings-care-sync'),
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push('/care/remind'),
      child: Container(
        padding: const EdgeInsets.fromLTRB(52, 0, 16, 12),
        child: Row(
          children: [
            const Expanded(
              child: Text('母婴等敏感数据排除同步（模块级）',
                  style: TextStyle(fontSize: 11, color: Colors.grey)),
            ),
            Text(on ? '已开启 · 呵护内管理 ›' : '已关闭 · 呵护内管理 ›',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: on ? const Color(0xFF10B981) : Colors.grey)),
          ],
        ),
      ),
    );
  }
}
