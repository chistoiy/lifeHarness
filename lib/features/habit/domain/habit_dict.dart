/// 习惯字典条目（habit_dict · kind ∈ cat|unit · 计划 §2.1）。
/// 改名=事务内回写引用行；删除前 COUNT 引用>0 → 拒绝并提供「迁移到…」（批2）。
class HabitDict {
  const HabitDict({
    this.id = 0,
    required this.kind,
    required this.name,
    this.sort = 0,
  });

  static const kCat = 'cat';
  static const kUnit = 'unit';

  final int id;
  final String kind;
  final String name;
  final int sort;

  Map<String, Object?> toRow() => {
    'id': id == 0 ? null : id,
    'kind': kind,
    'name': name,
    'sort': sort,
  };

  factory HabitDict.fromRow(Map<String, Object?> r) => HabitDict(
    id: r['id'] as int,
    kind: r['kind'] as String,
    name: r['name'] as String,
    sort: (r['sort'] as int?) ?? 0,
  );
}
