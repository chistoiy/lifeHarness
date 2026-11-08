// 跨模块待办出口：日子模块等只 import 本文件，不直接 import todo feature。
// 形态照 stats_providers.dart（纯 export show 白名单·耦合面可枚举）。
export '../../features/todo/domain/todo.dart' show Todo, Quadrant;
export '../../features/todo/presentation/todo_providers.dart'
    show todoRepositoryProvider;
