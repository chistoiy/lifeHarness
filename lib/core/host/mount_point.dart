/// 宿主暴露的可挂载点（需求 V1.15 挂载冲突仲裁的坐标）。
///
/// 内置模块与未来插件都通过这些锚点声明式挂载 UI，宿主统一渲染与排序。
enum MountPoint {
  homeCard('主页卡片'),
  navSlot('底部导航栏位'),
  settingsSecondary('设置二级入口'),
  detailSection('详情页扩展区'),
  fab('悬浮球动作');

  const MountPoint(this.label);
  final String label;
}
