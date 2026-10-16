part of 'settings_page.dart';

/// NFC 入口行图标块配色：**直接复用宿主的 `_kIcAppearance`**（同属外观与交互组、
/// 与「外观」同色即可，与桌面那枚品牌靛拉开一点色相差，不新造色阶）。
/// ⚠ 不另立常量：色值棘轮按文件记账，part 件基线 0，另立一枚即撞红灯
/// （doclint 守护十）；part 共享宿主作用域，复用零成本。
///

/// NFC 入口行的卡片张数（F1-6 · 与 `/nfc` 屏列表**同源**读数）。
///
/// 走 linkage 出口而非直连 nfc feature（R1：settings feature 跨 feature
/// 只经 `shared/linkage`）。catch-ok：widget 全 app 用例无真盘库时会抛
/// `MissingPluginException`，降级为 0 张、**不打断整页渲染**。
/// ⚠ 本函数落 part 件而非宿主：宿主已贴体量预算上限（`size_budget_test`
/// 登记 1609 行，只许减不许增）。
Future<int> _nfcCardCountForEntry() async {
  try {
    return await nfcCardCount();
  } catch (_) {
    // catch-ok: widget 全 app 用例无真盘库时 sqflite 抛 MissingPluginException，
    // 入口计数降级为「0 张」；真机上该异常不存在，降级只影响测试环境显示。
    return 0;
  }
}

/// 外观与交互组的入口卡（含 NFC 行）——自带计数读取，宿主只管摆位。
Widget buildDesktopEntryGroup(BuildContext context, {required bool flat}) =>
    FutureBuilder<int>(
      future: _nfcCardCountForEntry(),
      builder: (_, snap) => _desktopEntryGroup(context, flat: flat, nfcCardCount: snap.data ?? 0),
    );

/// 「外观与交互」组入口卡：外观 ＋ 桌面与快捷方式 ＋ NFC 卡片三行
/// （桌面批1 F1-3 ／ NFC 批1 F1-6）。
/// 行卡样式与「外观」完全同款（`_EntryCard` + `_EntryRow`），禁新造控件（§5.5）。
Widget _desktopEntryGroup(BuildContext context,
        {required bool flat, required int nfcCardCount}) =>
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
              onTap: () => context.push('/settings/desktop')),
          // NFC 卡片批1（F1-6）：紧邻「桌面与快捷方式」**下一行**，右侧显示卡片张数。
          // 计数与 `/nfc` 屏列表同源（同表 COUNT，见 `nfcCardCount`）——两处各算一套迟早漂。
          _EntryRow(
              key: const ValueKey('entry-nfc'),
              iconWidget: const Icon(Icons.contactless_outlined,
                  size: 18, color: _kIcAppearance),
              bg: _kIcAppearance.withValues(alpha: .12),
              title: 'NFC 卡片',
              sub: '摸一下就开始 · 再摸一下就结束',
              trailing: '$nfcCardCount 张',
              trailingColor: Colors.grey,
              last: true,
              onTap: () => context.push('/nfc')),
        ],
      ),
    );