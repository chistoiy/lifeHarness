/// 书单（book_lists / book_list_items · 计划 §2.3 批4）。
///
/// autoYear 非空＝年度自动书单：成员由 `state=已读 AND ended_at ∈ 该年` 动态求得，
/// items 不写库（原型 blIds 口径：自动单勾选停用，读完自动进来）。
class BookList {
  const BookList({
    this.id,
    required this.name,
    this.note,
    this.autoYear,
    this.sort = 0,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final int? id;
  final String name;
  final String? note;
  final int? autoYear;
  final int sort;
  final int createdAt;
  final int updatedAt;
  final int? deletedAt;

  bool get isAuto => autoYear != null;

  /// 列表卡角标（原型「{年} 年度 · 自动」/「手动」）。
  String get badge => isAuto ? '$autoYear 年度 · 自动' : '手动';

  static BookList fromRow(Map<String, Object?> r) => BookList(
    id: r['id'] as int?,
    name: r['name'] as String,
    note: r['note'] as String?,
    autoYear: r['auto_year'] as int?,
    sort: (r['sort'] as int?) ?? 0,
    createdAt: r['created_at'] as int,
    updatedAt: r['updated_at'] as int,
    deletedAt: r['deleted_at'] as int?,
  );

  Map<String, Object?> toRow() => {
    if (id != null) 'id': id,
    'name': name,
    'note': note,
    'auto_year': autoYear,
    'sort': sort,
    'created_at': createdAt,
    'updated_at': updatedAt,
    'deleted_at': deletedAt,
  };

  BookList copyWith({String? name, String? note, int? sort}) => BookList(
    id: id,
    name: name ?? this.name,
    note: note ?? this.note,
    autoYear: autoYear,
    sort: sort ?? this.sort,
    createdAt: createdAt,
    updatedAt: updatedAt,
    deletedAt: deletedAt,
  );
}
