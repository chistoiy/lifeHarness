import 'package:flutter/material.dart';

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
  static const kinds = [kSource, kGroup, kAuthor, kPublisher, kTag];

  /// 中文组名（管理器标题 / 阅读设置行）。
  static String label(String kind) => switch (kind) {
    kSource => '来源',
    kGroup => '分组',
    kTag => '标签',
    kAuthor => '作者',
    kPublisher => '出版社',
    _ => kind,
  };

  /// 单类管理页标题（原型 BM_META 首项）。
  static String title(String kind) => switch (kind) {
    kSource => '书籍来源',
    kGroup => '书籍分组',
    kAuthor => '作者管理',
    kPublisher => '出版社管理',
    kTag => '标签管理',
    _ => kind,
  };

  /// 单类管理页概述（原型 BM_META 次项）。
  static String note(String kind) => switch (kind) {
    kSource => '记录书从哪里来（购买/下载/借阅），可在录入时选择或新建',
    kGroup => '自定义组名，与「在读/已读」状态互相独立',
    kAuthor => '录入新书时自动登记作者，也可从列表挑选；点作者反查其全部藏书',
    kPublisher => '与作者同构，由书目自动汇聚',
    kTag => '一本书可多标签，支持改名与删除（被引用时需先解绑）',
    _ => kind,
  };

  /// 单类管理页头部图标（原型 BM_IC_KEY，线性 Material 图标）。
  static IconData icon(String kind) => switch (kind) {
    kSource => Icons.place,
    kGroup => Icons.grid_view,
    kAuthor => Icons.person,
    kPublisher => Icons.menu_book,
    kTag => Icons.sell,
    _ => Icons.label_outline,
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
