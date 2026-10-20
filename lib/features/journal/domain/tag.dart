import '../../../core/database/schema/tag.dart';

// 三个适用模块的常量与建表语句同源（`scopes` 列的字面值就来自这里），
// 故从 schema 层再导出一次——UI/DAO 只 import 本文件即可，不用各自记两条路径。
export '../../../core/database/schema/tag.dart' show kTagScopes;

/// 标签名上限（原型输入框 `maxlength="12"`）。
///
/// 放在 domain 而不是 DAO：添加页的输入框、编辑弹层、DAO 校验三处都要用，
/// 各写一个 12 迟早会漂（改一处忘另一处）。
const int kTagNameMax = 12;

/// 标签池里的一枚标签（批2b · 全局唯一池）。
///
/// `scopes` 是**多值**属性：一个标签可以同时属于日记/笔记/时间三个模块
/// （口径②「新建默认全部勾选，可手动取消」）。`public` 不落库——
/// 它是「三个模块全含」的派生视图，见 [isPublic]。
class Tag {
  const Tag({
    required this.id,
    required this.name,
    this.scopes = const {},
    this.sort = 0,
    this.builtin = false,
    this.useCount = 0,
  });

  final int id;
  final String name;
  final Set<String> scopes;
  final int sort;
  final bool builtin;

  /// 全仓引用条数（日记＋笔记＋时间之和，口径拍板④）。
  ///
  /// 不按模块各造一份计数：口径①「池全局唯一」的直接推论是
  /// 「同一标签在日记页看到的数字＝它在全仓被用了几次」。
  final int useCount;

  /// 三模块全含＝「公共」分区（**派生视图，不是第四个 scope**）。
  bool get isPublic => kTagScopes.every(scopes.contains);

  bool appliesTo(String module) => scopes.contains(module);

  Tag copyWith({
    int? id,
    String? name,
    Set<String>? scopes,
    int? sort,
    bool? builtin,
    int? useCount,
  }) =>
      Tag(
        id: id ?? this.id,
        name: name ?? this.name,
        scopes: scopes ?? this.scopes,
        sort: sort ?? this.sort,
        builtin: builtin ?? this.builtin,
        useCount: useCount ?? this.useCount,
      );

  static Tag fromRow(Map<String, Object?> row) => Tag(
        id: row['id'] as int,
        name: (row['name'] as String?) ?? '',
        scopes: tagScopesOf((row['scopes'] as String?) ?? ''),
        sort: row['sort'] as int? ?? 0,
        builtin: (row['builtin'] as int? ?? 0) == 1,
        useCount: row['use_count'] as int? ?? 0,
      );
}

/// `scopes` 列（逗号分隔）→ 集合。
///
/// 脏值一律丢弃（不认识的模块名留着只会让「公共」判定莫名变真）；
/// 空串＝一个模块都不适用——这种标签在三个模块里都选不到，但管理页仍要能看到它
/// （用户可再勾回来），所以不在这里过滤。
Set<String> tagScopesOf(String raw) {
  if (raw.isEmpty) return const {};
  return {
    for (final s in raw.split(','))
      if (kTagScopes.contains(s.trim())) s.trim(),
  };
}

/// 集合 → `scopes` 列（**按 [kTagScopes] 序**，不是插入序）。
///
/// 稳定序列化的理由：同一组模块无论用户按什么顺序勾，落库都是同一串——
/// 否则「并集比较」「是否变化」这类判据会被顺序差异骗出假改动。
String tagScopesEncode(Set<String> scopes) =>
    [for (final k in kTagScopes) if (scopes.contains(k)) k].join(',');

/// 模块键 → 中文名（原型 `TG_SCENES[].n` 同口径）。
String tagSceneName(String key) => switch (key) {
      'diary' => '日记',
      'note' => '笔记',
      'time' => '时间',
      'public' => '公共',
      _ => key,
    };

/// 标签胶囊的语义色名（原型 `DI_TAG_COLORS` 六色轮转）。
///
/// 颜色**不是产品属性**（池里不存色）：按标签在池内的次序轮转，
/// 保证「同一标签在筛选段与编辑页拿到同一个色」。UI 侧把色名映射到主题令牌，
/// 4 主题 × 明暗自动跟随（禁写死色值）。
const List<String> kTagToneNames = [
  'indigo',
  'emerald',
  'amber',
  'rose',
  'sky',
  'violet',
];

/// 池内第 [index] 枚标签的语义色名。
String tagToneAt(int index) =>
    kTagToneNames[index < 0 ? 0 : index % kTagToneNames.length];

/// 跨模块搜索命中的一条内容（口径④：忽略作用域，能搜到全部模块带该标签的内容）。
///
/// [module] 只用 `diary` / `note` / `time` 三值（`public` 不是内容模块）；
/// [sub] 是正文摘要（日记/笔记）或时间（时间块），[tags] 是该条挂的标签串。
class TagSearchHit {
  const TagSearchHit({
    required this.module,
    required this.title,
    this.sub = '',
    this.tags = '',
  });

  final String module;
  final String title;
  final String sub;
  final String tags;
}
