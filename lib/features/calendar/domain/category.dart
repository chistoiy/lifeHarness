import 'package:flutter/material.dart';

/// 两级分类（需求 V1.19.1 · DB v4 categories 表）。
/// 全局唯一分类源：块视图速记列、标记面板、统一添加弹层、时间账本统计共用。
class Category {
  const Category({
    this.id,
    this.parentId,
    required this.name,
    this.colorHex,
    this.tag,
    this.sort = 0,
  });

  final int? id;

  /// null = 一级分类；非 null = 次级（继承父级颜色）。
  final int? parentId;
  final String name;

  /// 十六进制颜色 '#RRGGBB'；次级留空表示继承父级。
  final String? colorHex;

  /// 默认标签，如 '#开会'。
  final String? tag;
  final int sort;

  bool get isPrimary => parentId == null;

  Color color(Color fallback) {
    final hex = colorHex;
    if (hex == null || !hex.startsWith('#') || hex.length < 7) return fallback;
    final v = int.tryParse(hex.substring(1, 7), radix: 16);
    if (v == null) return fallback;
    return Color(0xFF000000 | v);
  }

  Category copyWith({int? parentId, String? name, String? colorHex, String? tag, int? sort}) =>
      Category(
        id: id,
        parentId: parentId ?? this.parentId,
        name: name ?? this.name,
        colorHex: colorHex ?? this.colorHex,
        tag: tag ?? this.tag,
        sort: sort ?? this.sort,
      );

  Map<String, Object?> toRow() => {
        if (id != null) 'id': id,
        'parent_id': parentId,
        'name': name,
        'color': colorHex,
        'tag': tag,
        'sort': sort,
      };

  factory Category.fromRow(Map<String, Object?> r) => Category(
        id: r['id'] as int,
        parentId: r['parent_id'] as int?,
        name: r['name'] as String,
        colorHex: r['color'] as String?,
        tag: r['tag'] as String?,
        sort: (r['sort'] as int?) ?? 0,
      );
}
