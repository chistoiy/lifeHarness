/// 思维导图模块·跨模块 API 门面（架构守护 R1 的唯一合法入口）。
///
/// 为什么要有这一件：两个模块都要用导图的能力，但 `features/**` 之间直连会被
/// R1 判红（改动互相牵连、改 A 崩 B、测试漏测）——
/// - 笔记的「导图视图」复用**横向树引擎与画布 painter**（节点度量、列宽、父居中、
///   连线画法、层级描边必须与导图页同一份实现，各写一套必然漂移）；
/// - 收集箱把一段文字转导图要**建 dao + 解析大纲**。
///
/// 形态＝`stats_providers.dart` 同款「纯 export + show 白名单」：**只放行跨模块
/// 真正用到的七个符号**，不是把导图整个 domain 转出去。新增跨模块符号＝在这里
/// 加一行 `show`，让耦合面永远可枚举（读本文件即知外部用了导图的哪些能力）。
///
/// 分工：本件是「别的模块 → 导图能力」的出口；导图 ← 笔记/收集箱的数据读写走
/// [`mindmap_mounts.dart`]（反向），两者别混。
library;

export '../../features/mindmap/data/mindmap_dao.dart' show MindmapDao;
export '../../features/mindmap/domain/md_parse.dart' show mmOutlineFlat;
export '../../features/mindmap/domain/mindmap_layout.dart'
    show HorizontalTreeEngine, MmLayoutResult;
export '../../features/mindmap/domain/mindmap_measure.dart' show mmNodeMeasure;
export '../../features/mindmap/domain/mindmap_models.dart' show MindmapNode;
export '../../features/mindmap/domain/mindmap_style.dart' show MmPaintStyle;
export '../../features/mindmap/presentation/mindmap_painter.dart'
    show MmCanvasPainter;
