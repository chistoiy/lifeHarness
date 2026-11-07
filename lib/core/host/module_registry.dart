import 'mount_point.dart';

/// 一个可挂载的模块描述符（内置模块与插件模块共用同一契约）。
///
/// 骨架阶段以纯数据描述（不含 Widget），保证宿主能力 API 与 UI 解耦、可单测；
/// 后续路由层据 [id]/[routePath] 渲染。
class HostModule {
  const HostModule({
    required this.id,
    required this.title,
    required this.routePath,
    this.mount = const {},
    this.weight = 0,
    this.isPlugin = false,
  });

  final String id;
  final String title;
  final String routePath;

  /// 该模块在各挂载点期望的顺序（值越小越靠前）。
  final Map<MountPoint, int> mount;

  /// 同挂载点权重（冲突仲裁第二优先级）。
  final int weight;

  /// 是否为插件模块（试点：物品/影音游）。
  final bool isPlugin;
}

/// 模块注册表（宿主能力 API 基线 v0）。
///
/// 冲突仲裁链（需求 V1.15）：用户显式序 > 权重 > 注册时序。
class ModuleRegistry {
  final List<HostModule> _modules = [];
  final Map<String, int> _userOrder = {};

  List<HostModule> get all => List.unmodifiable(_modules);

  HostModule? byId(String id) {
    for (final m in _modules) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// 注册（同 id 覆盖）。内置模块应在启动阶段先注册。
  void register(HostModule module) {
    final idx = _modules.indexWhere((m) => m.id == module.id);
    if (idx >= 0) {
      _modules[idx] = module;
    } else {
      _modules.add(module);
    }
  }

  void unregister(String id) => _modules.removeWhere((m) => m.id == id);

  /// 设置用户对某挂载点的显式排序（最优先）。
  void setUserOrder(MountPoint point, List<String> orderedIds) {
    for (var i = 0; i < orderedIds.length; i++) {
      _userOrder['${point.name}:${orderedIds[i]}'] = i;
    }
  }

  /// 取某挂载点下已声明该点的模块，按仲裁链排序。
  List<HostModule> resolve(MountPoint point) {
    final candidates = _modules.where((m) => m.mount.containsKey(point)).toList();
    // 注册时序索引（仲裁链第三优先级）。
    final seq = <String, int>{
      for (var i = 0; i < _modules.length; i++) _modules[i].id: i,
    };
    candidates.sort((a, b) {
      final ua = _userOrder['${point.name}:${a.id}'];
      final ub = _userOrder['${point.name}:${b.id}'];
      if (ua != null || ub != null) {
        final xa = ua ?? 1 << 30;
        final xb = ub ?? 1 << 30;
        if (xa != xb) return xa.compareTo(xb);
      }
      // 用户序缺省者按模块 mount 内声明的序，再按权重（大者前），再按注册时序。
      final ma = a.mount[point]!;
      final mb = b.mount[point]!;
      if (ma != mb) return ma.compareTo(mb);
      if (a.weight != b.weight) return b.weight.compareTo(a.weight);
      return seq[a.id]!.compareTo(seq[b.id]!);
    });
    return candidates;
  }
}
