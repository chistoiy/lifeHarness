part of 'settings_page.dart';

/// 「外观与交互」组入口卡：外观 ＋ 桌面与快捷方式两行（桌面模块批1 · F1-3）。
/// 行卡样式与「外观」完全同款（`_EntryCard` + `_EntryRow`），禁新造控件（§5.5）。
Widget buildDesktopEntryGroup(BuildContext context, {required bool flat}) =>
    _EntryCard(
      flat: flat,
      child: Column(
        children: [
          _EntryRow(
              key: const ValueKey('entry-appearance'),
              iconWidget: const Icon(Icons.palette_outlined,
                  size: 18, color: _kIcAppearance),
              bg: _kIcAppearance.withValues(alpha: .12),
              title: '外观',
              sub: '主题风格 · 深色模式 · 主题色 · 字体大小',
              trailing: '',
              onTap: () => context.push('/settings/appearance')),
          _EntryRow(
              key: const ValueKey('entry-desktop'),
              iconWidget: const Icon(Icons.widgets_outlined,
                  size: 18, color: _kIcDesktop),
              bg: _kIcDesktop.withValues(alpha: .12),
              title: '桌面与快捷方式',
              sub: '长按图标菜单 · 铺到桌面 · 小组件',
              trailing: '',
              last: true,
              onTap: () => context.push('/settings/desktop')),
        ],
      ),
    );