import 'dart:convert';

/// 心情常量（原型 moodRow 7 表情；mood 值 1~7，null=未记录）。
const kJournalMoods = <(String, String)>[
  ('😄', '开心'), ('😌', '平静'), ('😐', '一般'), ('😪', '疲惫'),
  ('😰', '焦虑'), ('😢', '低落'), ('😡', '愤怒'),
];

String? moodEmoji(int? mood) =>
    mood == null || mood < 1 || mood > kJournalMoods.length ? null : kJournalMoods[mood - 1].$1;

String? moodLabel(int? mood) =>
    mood == null || mood < 1 || mood > kJournalMoods.length ? null : kJournalMoods[mood - 1].$2;

/// 结构化日记的正文分节（V1.28 真结构存储：journal_sections 表一行一节）。
class DiarySection {
  const DiarySection({required this.title, this.body = ''});
  final String title;
  final String body;
}

/// 模块3 日记条目（V1.28 起一天可多篇，每篇各带心情；entry_date 为当日 0 点毫秒；
/// 自由书写=纯文本 content，结构化模板=sections 真结构 + content 渲染快照）。
class JournalEntry {
  const JournalEntry({
    this.id,
    required this.day,
    this.mood,
    this.content = '',
    this.tags = const [],
    required this.createdAt,
    required this.updatedAt,
    this.starred = false,
    this.liked = false,
    this.viewCount = 0,
    this.templateId,
    this.sections = const [],
  });

  final int? id;
  final DateTime day;
  final int? mood;
  final String content;
  final List<String> tags;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// INS 卡片流回望态（本地收藏/点亮 + 打开阅读次数）。
  final bool starred;
  final bool liked;
  final int viewCount;

  /// 使用的模板（null/空 sections=自由书写）。
  final int? templateId;
  final List<DiarySection> sections;

  /// 分节 → 文本快照（列表预览/☐ 待办行/#标签解析仍走 content）。
  static String renderSections(List<DiarySection> secs) => secs
      .map((s) => '## ${s.title}\n${s.body.trim()}')
      .join('\n\n');

  bool get structured => sections.isNotEmpty;

  static JournalEntry fromRow(Map<String, Object?> row) => JournalEntry(
        id: row['id'] as int?,
        day: DateTime.fromMillisecondsSinceEpoch(row['entry_date'] as int),
        mood: row['mood'] as int?,
        content: (row['content'] as String?) ?? '',
        tags: _decodeTags(row['tags'] as String?),
        createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
        starred: (row['starred'] as int? ?? 0) == 1,
        liked: (row['liked'] as int? ?? 0) == 1,
        viewCount: row['view_count'] as int? ?? 0,
        templateId: row['template_id'] as int?,
      );

  Map<String, Object?> toRow() => {
        if (id != null) 'id': id,
        'entry_date': dayStart(day).millisecondsSinceEpoch,
        'mood': mood,
        'content': content,
        'tags': tags.isEmpty ? null : jsonEncode(tags),
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
        'starred': starred ? 1 : 0,
        'liked': liked ? 1 : 0,
        'view_count': viewCount,
        'template_id': templateId,
      };

  static List<String> _decodeTags(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final l = jsonDecode(raw);
      return l is List ? l.map((e) => '$e').toList() : const [];
    } catch (_) {
      return raw.split(',').where((e) => e.isNotEmpty).toList();
    }
  }

  static DateTime dayStart(DateTime d) => DateTime(d.year, d.month, d.day);

  static bool sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// 正文中「☐ 待办」行（原型 L3 联动：保存后同步至任务列表）。
  List<String> todoLines() => content
      .split('\n')
      .map((l) => RegExp(r'^\s*(?:[-*]\s*)?☐\s*(.+)$').firstMatch(l))
      .whereType<Match>()
      .map((m) => m.group(1)!.trim())
      .where((t) => t.isNotEmpty)
      .toList();

  /// 正文中提取 #标签（保存时并入 tags）。
  List<String> hashTags() => RegExp(r'#(\S+)')
      .allMatches(content)
      .map((m) => m.group(1)!)
      .where((t) => !t.startsWith('#'))
      .toList();

  JournalEntry copyWith({
    int? id,
    DateTime? day,
    int? mood,
    String? content,
    List<String>? tags,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? starred,
    bool? liked,
    int? viewCount,
    int? templateId,
    List<DiarySection>? sections,
  }) =>
      JournalEntry(
        id: id ?? this.id,
        day: day ?? this.day,
        mood: mood ?? this.mood,
        content: content ?? this.content,
        tags: tags ?? this.tags,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        starred: starred ?? this.starred,
        liked: liked ?? this.liked,
        viewCount: viewCount ?? this.viewCount,
        templateId: templateId ?? this.templateId,
        sections: sections ?? this.sections,
      );
}
