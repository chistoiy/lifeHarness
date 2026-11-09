/// 导出域·跨模块取数出口（架构守护 R1）。
///
/// 为什么要有这一件：备份/导出弹层（`features/settings/presentation/export_sheet.dart`）
/// 导出 `.ics` 时要读三路的原料——时间块 dao（calendar）、重要日子（days）、
/// 待办（todo）。`features/settings/**` 直连这三个模块会被 R1 判红：模块间直连
/// 会互相牵连（改 A 崩 B、测试漏测）。
///
/// 形态＝`stats_providers.dart` 同款「纯 export + show 白名单」门面：**只放行
/// 三个 provider**，聚合与映射仍是各自模块的事，本件不写业务逻辑。
///
/// 与相邻两件分工：`ics_collect.dart`＝原料 → `IcsItem` 的**纯函数映射**；
/// `export_units.dart`＝模块 → 表清单的**静态注册表**；本件只管**取数口**。
library;

export '../../features/calendar/presentation/calendar_providers.dart'
    show timeBlockDaoProvider;
export '../../features/days/presentation/days_providers.dart'
    show daysRepositoryProvider;
export '../../features/todo/presentation/todo_providers.dart'
    show todoRepositoryProvider;
