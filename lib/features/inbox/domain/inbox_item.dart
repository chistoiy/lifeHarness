/// 模块5 收集箱条目（routedTo: null=未整理；todo/journal/note 已分流）。
class InboxItem {
  const InboxItem({
    this.id,
    required this.rawText,
    this.kind,
    this.routedTo,
    this.routedRef,
    required this.createdAt,
  });

  final int? id;
  final String rawText;

  /// 捕捉来源（手动/通知栏/桌面快捷方式；M0 恒为 null=手动）。
  final String? kind;
  final String? routedTo;
  final int? routedRef;
  final DateTime createdAt;

  static InboxItem fromRow(Map<String, Object?> row) => InboxItem(
        id: row['id'] as int?,
        rawText: (row['raw_text'] as String?) ?? '',
        kind: row['kind'] as String?,
        routedTo: row['routed_to'] as String?,
        routedRef: row['routed_ref'] as int?,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      );

  Map<String, Object?> toRow() => {
        'raw_text': rawText,
        'kind': kind,
        'routed_to': routedTo,
        'routed_ref': routedRef,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  /// 原型 age 展示：刚刚 / N 分钟前 / 今天 HH:MM / N 天前。
  String ageLabel([DateTime? now]) {
    final n = now ?? DateTime.now();
    final diff = n.difference(createdAt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (createdAt.year == n.year &&
        createdAt.month == n.month &&
        createdAt.day == n.day) {
      final hh = createdAt.hour.toString().padLeft(2, '0');
      final mm = createdAt.minute.toString().padLeft(2, '0');
      return '今天 $hh:$mm';
    }
    return '${diff.inDays} 天前';
  }
}
