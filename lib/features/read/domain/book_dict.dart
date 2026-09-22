/// 书架资料字典项（book_dict 表 · 计划 §2.2 / §3.4 资料管理器）。
/// kind ∈ source|group|tag|author|publisher。
class DictEntry {
  const DictEntry({
    this.id,
    required this.kind,
    required this.name,
    this.sort = 0,
    this.extra,
  });

  static const kSource = 'source';
  static const kGroup = 'group';
  static const kTag = 'tag';
  static const kAuthor = 'author';
  static const kPublisher = 'publisher';
  static const kinds = [kSource, kGroup, kTag, kAuthor, kPublisher];

  /// 中文组名（管理器标题 / 阅读设置行）。
  static String label(String kind) => switch (kind) {
    kSource => '来源',
    kGroup => '分组',
    kTag => '标签',
    kAuthor => '作者',
    kPublisher => '出版社',
    _ => kind,
  };

  final int? id;
  final String kind;
  final String name;
  final int sort;
  final String? extra;

  static DictEntry fromRow(Map<String, Object?> r) => DictEntry(
    id: r['id'] as int?,
    kind: r['kind'] as String,
    name: r['name'] as String,
    sort: (r['sort'] as int?) ?? 0,
    extra: r['extra'] as String?,
  );

  Map<String, Object?> toRow() => {
    if (id != null) 'id': id,
    'kind': kind,
    'name': name,
    'sort': sort,
    'extra': extra,
  };
}
