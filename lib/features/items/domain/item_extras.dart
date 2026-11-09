/// 物品「实物属性」批（2026-11-09 · I01/I05/I08/I10/I11/I12/I13/I14）。
///
/// 纯 Dart：只依赖 `dart:convert`，零 Flutter、零网络、零新依赖，故测试可脱离
/// widget/DB 直接断言。所有结构化字段以 JSON 文本存进 `item_profiles` 的 8 个
/// 可空列（v53 迁移 `DbSchema.itemsV53AddColumns`）；列缺失 / NULL / 损坏 JSON
/// 一律回落空值 ⇒ 已装用户升级零数据风险（列全可空、无 DEFAULT、无搬数据）。
library;

import 'dart:convert';

// —— v53 列名：与 schema.dart `itemsV53AddColumns` 的 ALTER 一一对应 ——
const kColPhotos = 'photos';
const kColLocationPath = 'location_path';
const kColAttachments = 'attachments';
const kColBarcode = 'barcode';
const kColLoanTo = 'loan_to';
const kColLoanAt = 'loan_at';
const kColLoanDue = 'loan_due';
const kColCustomFields = 'custom_fields';

/// 凭证类别（I08）；与档案附件下拉同源。
const kAttachKinds = ['发票', '说明书', '保修卡', '其他'];

// ==================== 值对象 ====================

/// 凭证附件（I08）：path＝本机应用目录落盘路径（与 I01 照片共用本地文件基建）。
class ItemAttachment {
  const ItemAttachment({required this.kind, required this.path, this.name});

  final String kind;
  final String path;
  final String? name;

  Map<String, Object?> toJson() => {'kind': kind, 'path': path, 'name': name};

  static ItemAttachment? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final kind = raw['kind'];
    final path = raw['path'];
    if (kind is! String || path is! String) return null;
    return ItemAttachment(kind: kind, path: path, name: raw['name'] as String?);
  }
}

/// 一条两层位置路径（I05）：l1＝房间／一级，l2＝收纳位／二级。
class ItemLocationPath {
  const ItemLocationPath(this.l1, this.l2);
  final String l1;
  final String l2;
}

/// 两层位置树节点（I05）：一级房间 → 其下去重后的二级收纳位列表。
class ItemLocationNode {
  const ItemLocationNode(this.l1, this.children);
  final String l1;
  final List<String> children;
}

// ==================== 档案实物属性聚合 ====================

/// 全字段 final、默认空值 ⇒ 可 `const ItemExtras()`（`ItemProfile` 默认值用它）。
class ItemExtras {
  const ItemExtras({
    this.photos = const [],
    this.locationPath,
    this.attachments = const [],
    this.barcode,
    this.loanTo,
    this.loanAt,
    this.loanDue,
    this.customFields = const {},
  });

  /// I14 多图：本机落盘路径列表（首张作封面）。
  final List<String> photos;
  /// I05 位置：'一级/二级'，null＝未设。
  final String? locationPath;
  /// I08 凭证附件。
  final List<ItemAttachment> attachments;
  /// I10 条码（EAN/UPC 数字串）。
  final String? barcode;
  /// I11 借给谁；null/空＝在册未借出。
  final String? loanTo;
  /// I11 借出日 YYYY-MM-DD。
  final String? loanAt;
  /// I11 应还日 YYYY-MM-DD。
  final String? loanDue;
  /// I13 自定义字段（键 → 值）。
  final Map<String, String> customFields;

  bool get isLent => (loanTo ?? '').trim().isNotEmpty;

  ItemExtras copyWith({
    List<String>? photos,
    String? locationPath,
    List<ItemAttachment>? attachments,
    String? barcode,
    String? loanTo,
    String? loanAt,
    String? loanDue,
    Map<String, String>? customFields,
    bool clearLocation = false,
    bool clearBarcode = false,
    bool clearLoan = false,
  }) =>
      ItemExtras(
        photos: photos ?? this.photos,
        locationPath:
            clearLocation ? null : (locationPath ?? this.locationPath),
        attachments: attachments ?? this.attachments,
        barcode: clearBarcode ? null : (barcode ?? this.barcode),
        loanTo: clearLoan ? null : (loanTo ?? this.loanTo),
        loanAt: clearLoan ? null : (loanAt ?? this.loanAt),
        loanDue: clearLoan ? null : (loanDue ?? this.loanDue),
        customFields: customFields ?? this.customFields,
      );

  /// 摊平成 v53 的 8 个列值（供 repository insert/update 展开）；空值写 NULL。
  Map<String, Object?> toColumns() => {
        kColPhotos: photos.isEmpty ? null : jsonEncode(photos),
        kColLocationPath: _nonEmpty(locationPath),
        kColAttachments: attachments.isEmpty
            ? null
            : jsonEncode([for (final a in attachments) a.toJson()]),
        kColBarcode: _nonEmpty(barcode),
        kColLoanTo: _nonEmpty(loanTo),
        kColLoanAt: _nonEmpty(loanAt),
        kColLoanDue: _nonEmpty(loanDue),
        kColCustomFields:
            customFields.isEmpty ? null : jsonEncode(customFields),
      };

  /// 从一行读回：列缺失 / NULL / 损坏 JSON 一律回落空值（升级零风险）。
  factory ItemExtras.fromColumns(Map<String, Object?> r) => ItemExtras(
        photos: decodePhotos(r[kColPhotos] as String?),
        locationPath: _nonEmpty(r[kColLocationPath]),
        attachments: decodeAttachments(r[kColAttachments] as String?),
        barcode: _nonEmpty(r[kColBarcode]),
        loanTo: _nonEmpty(r[kColLoanTo]),
        loanAt: _nonEmpty(r[kColLoanAt]),
        loanDue: _nonEmpty(r[kColLoanDue]),
        customFields: decodeCustomFields(r[kColCustomFields] as String?),
      );
}

/// 去空格后非空才返回，否则 null（避免 `?.` 链歧义）。
String? _nonEmpty(Object? v) {
  if (v is! String) return null;
  final s = v.trim();
  return s.isEmpty ? null : s;
}

// ==================== I01 单图 / I14 多图 ====================

const _kImageExts = ['jpg', 'jpeg', 'png', 'webp', 'heic', 'gif', 'bmp'];

/// 单张照片路径合法性（I01）：非空且带图片扩展名。
bool isValidPhotoPath(String? path) {
  if (path == null) return false;
  final s = path.trim();
  if (s.isEmpty) return false;
  final dot = s.lastIndexOf('.');
  if (dot < 0 || dot == s.length - 1) return false;
  return _kImageExts.contains(s.substring(dot + 1).toLowerCase());
}

/// I14 多图：至少一张、且张张合法才算有效图集。
bool isValidPhotoGallery(List<String> paths) =>
    paths.isNotEmpty && paths.every((p) => isValidPhotoPath(p));

List<String> decodePhotos(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  try {
    final d = jsonDecode(raw);
    if (d is! List) return const [];
    return [for (final e in d) if (e is String && isValidPhotoPath(e)) e];
  } catch (_) {
    return const [];
  }
}

String encodePhotos(List<String> paths) => jsonEncode([
      for (final p in paths)
        if (isValidPhotoPath(p)) p
    ]);

// ==================== I05 位置两层树 ====================

/// 合法两层位置路径＝恰好一个 '/'、两段去空格都非空。
bool isValidLocationPath(String? path) {
  if (path == null) return false;
  final parts = path.split('/');
  if (parts.length != 2) return false;
  return parts[0].trim().isNotEmpty && parts[1].trim().isNotEmpty;
}

String encodeLocation(String l1, String l2) => '${l1.trim()}/${l2.trim()}';

ItemLocationPath? decodeLocation(String? path) {
  if (!isValidLocationPath(path)) return null;
  final parts = path!.split('/');
  return ItemLocationPath(parts[0].trim(), parts[1].trim());
}

/// 若干档案的位置路径聚成「房间 → 收纳位」两层树：脏值跳过、二级去重、
/// 一级与二级各自按字典序排定（纯函数，列表页位置筛选可直接吃）。
List<ItemLocationNode> buildLocationTree(Iterable<String?> paths) {
  final map = <String, List<String>>{};
  for (final raw in paths) {
    final p = decodeLocation(raw);
    if (p == null) continue;
    final kids = map.putIfAbsent(p.l1, () => <String>[]);
    if (!kids.contains(p.l2)) kids.add(p.l2);
  }
  final nodes = <ItemLocationNode>[
    for (final e in map.entries) ItemLocationNode(e.key, e.value..sort())
  ];
  nodes.sort((a, b) => a.l1.compareTo(b.l1));
  return nodes;
}

// ==================== I08 凭证附件 ====================

bool isValidAttachment(ItemAttachment a) =>
    kAttachKinds.contains(a.kind) && a.path.trim().isNotEmpty;

List<ItemAttachment> decodeAttachments(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  try {
    final d = jsonDecode(raw);
    if (d is! List) return const [];
    final out = <ItemAttachment>[];
    for (final e in d) {
      final a = ItemAttachment.fromJson(e);
      if (a != null && isValidAttachment(a)) out.add(a);
    }
    return out;
  } catch (_) {
    return const [];
  }
}

String encodeAttachments(List<ItemAttachment> list) => jsonEncode([
      for (final a in list)
        if (isValidAttachment(a)) a.toJson()
    ]);

// ==================== I10 条码扫码 ====================

/// EAN-8 / UPC-A / EAN-13 / ITF-14：纯数字、长度 8/12/13/14。
bool isValidBarcode(String? code) {
  if (code == null) return false;
  final s = code.trim();
  if (!RegExp(r'^\d+$').hasMatch(s)) return false;
  return const {8, 12, 13, 14}.contains(s.length);
}

/// 扫码→快速搜索：档案条码与查询码去空格后完全相等才命中。
bool barcodeMatches(String? stored, String? query) {
  final q = query?.trim();
  final s = stored?.trim();
  if (q == null || q.isEmpty || s == null || s.isEmpty) return false;
  return s == q;
}

// ==================== I11 借出归还 ====================

/// 应还日格式 YYYY-MM-DD（宽松校验：定长、分隔符对位、可解析）。
bool isValidLoanDue(String? ymd) {
  if (ymd == null) return false;
  final s = ymd.trim();
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) return false;
  return DateTime.tryParse(s) != null;
}

/// 借出且已过应还日才判逾期；未借出 / 无应还日 / 日期非法 / 未到期一律 false。
/// [today] 由调用方注入 ⇒ 纯函数（测试可固定钟）。
bool isLoanOverdue({
  required String? loanTo,
  required String? loanDue,
  required DateTime today,
}) {
  if ((loanTo ?? '').trim().isEmpty) return false;
  if (!isValidLoanDue(loanDue)) return false;
  final due = DateTime.tryParse(loanDue!.trim());
  if (due == null) return false;
  final t = DateTime(today.year, today.month, today.day);
  return due.isBefore(t);
}

// ==================== I13 自定义字段 ====================

/// 键合法：去空格非空、无首尾空格、≤32 字、无控制字符、非保留键（防覆盖档案列）。
bool isValidCustomFieldKey(String? key) {
  if (key == null) return false;
  final s = key.trim();
  if (s.isEmpty || s != key || s.length > 32) return false;
  if (key.codeUnits.any((c) => c < 32 || c == 127)) return false;
  return !const {'id', 'name', 'price', 'brand', 'serial', 'note'}
      .contains(s.toLowerCase());
}

Map<String, String> decodeCustomFields(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const {};
  try {
    final d = jsonDecode(raw);
    if (d is! Map) return const {};
    final out = <String, String>{};
    d.forEach((k, v) {
      if (k is String && v is String && isValidCustomFieldKey(k)) out[k] = v;
    });
    return out;
  } catch (_) {
    return const {};
  }
}

String encodeCustomFields(Map<String, String> fields) => jsonEncode({
      for (final e in fields.entries)
        if (isValidCustomFieldKey(e.key)) e.key: e.value
    });

// ==================== 详情/编辑卡汇总文案（纯函数） ====================

String extrasSummary(ItemExtras e) {
  final bits = <String>[];
  if (e.photos.isNotEmpty) bits.add('多图 ${e.photos.length}');
  final loc = decodeLocation(e.locationPath);
  if (loc != null) bits.add('位置 ${loc.l1}/${loc.l2}');
  if (e.attachments.isNotEmpty) bits.add('凭证 ${e.attachments.length}');
  if ((e.barcode ?? '').isNotEmpty) bits.add('条码 ${e.barcode}');
  if (e.isLent) {
    bits.add('借出 ${e.loanTo}${e.loanDue == null ? '' : ' · 应还 ${e.loanDue}'}');
  }
  if (e.customFields.isNotEmpty) bits.add('自定义 ${e.customFields.length}');
  return bits.isEmpty ? '未登记实物属性 · 点击补齐' : bits.join(' · ');
}
