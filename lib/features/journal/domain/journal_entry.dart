import 'dart:convert';

import 'note.dart';

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
    this.kind = '',
    this.weatherCode,
    this.tempMax,
    this.tempMin,
    this.weatherManual = false,
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

  /// M1批2a：自由书写富文本类型（''=纯文本 · rich=Quill Delta JSON·同笔记 kind）。
  final String kind;

  /// M1批2e：天气快照（写日记当天抓一次落库·WMO 码+当日低/高温；
  /// manual=用户在本篇手动覆盖过，不再自动更新）。
  final int? weatherCode;
  final double? tempMax;
  final double? tempMin;
  final bool weatherManual;

  /// 面向展示/计数/解析的正文（rich 去 Delta JSON 痕迹；纯文本去图片本地语法
  /// →「图片」，与笔记 displayBody 同口径·imagePaths 仍解析原 content）。
  String get plainBody => kind == 'rich'
      ? Note.richToPlain(content)
      : Note.stripMdImages(content);

  /// 正文图片路径（列表 4 缩略 / INS 2×2 网格数据源）：
  /// 纯文本=![..](path) 语法行；rich=Delta image embed。
  List<String> get imagePaths {
    if (kind == 'rich') {
      try {
        final ops = jsonDecode(content);
        if (ops is List) {
          return [
            for (final op in ops)
              if (op is Map &&
                  op['insert'] is Map &&
                  (op['insert'] as Map)['image'] is String)
                (op['insert'] as Map)['image'] as String,
          ];
        }
      } catch (_) {/* 非 JSON 回退语法扫描 */}
    }
    return RegExp(r'!\[[^\]]*\]\(([^)]*)\)')
        .allMatches(content)
        .map((m) => m.group(1)!)
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// 分节 → 文本快照（列表预览/☐ 待办行/#标签解析仍走 content）。
  static String renderSections(List<DiarySection> secs) => secs
      .map((s) => '## ${s.title}\n${s.body.trim()}')
      .join('\n\n');

  bool get structured => sections.isNotEmpty;

  /// 列表预览：结构化快照（`## 标题` 分节）渲染为「标题：首行」串联，
  /// 自由书写原样返回——避免条目卡/那年今日露出 markdown 痕迹。
  String get previewText {
    final body = plainBody;
    if (!body.contains('## ')) return body;
    final parts = body
        .split(RegExp(r'^## ', multiLine: true))
        .where((p) => p.trim().isNotEmpty)
        .toList();
    if (parts.isEmpty) return body;
    return parts.map((p) {
      final lines = p.trim().split('\n');
      final title = lines.first.trim();
      final body2 = lines.skip(1).join(' ').trim();
      if (body2.isEmpty) return title;
      return '$title：${body2.length <= 20 ? body2 : '${body2.substring(0, 20)}…'}';
    }).join(' · ');
  }

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
        kind: (row['kind'] as String?) ?? '',
        weatherCode: row['weather_code'] as int?,
        tempMax: (row['temp_max'] as num?)?.toDouble(),
        tempMin: (row['temp_min'] as num?)?.toDouble(),
        weatherManual: (row['weather_manual'] as int? ?? 0) == 1,
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
        'kind': kind,
        'weather_code': weatherCode,
        'temp_max': tempMax,
        'temp_min': tempMin,
        'weather_manual': weatherManual ? 1 : 0,
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

  /// 整行图片语法（M1批2a 日记插图协议：正文与 ![图片](path) 行同列存储）。
  static final RegExp _imgLineRe = RegExp(r'^!\[[^\]]*\]\([^)]*\)$');

  /// 编辑载入用：剥离整行图片语法（图片改由网格卡呈现，保存时再追加回来）。
  static String bodyWithoutImages(String content) => content
      .split('\n')
      .where((l) => !_imgLineRe.hasMatch(l.trim()))
      .join('\n')
      .trimRight();

  /// 保存落库用：正文尾部以空行分隔追加 ![图片](path) 行（与笔记纯文本同协议）。
  static String appendImageLines(String body, List<String> paths) {
    if (paths.isEmpty) return body;
    final joined = paths.map((p) => '![图片]($p)').join('\n');
    final head = body.trimRight();
    return head.isEmpty ? joined : '$head\n\n$joined';
  }

  static bool sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// 正文中「☐ 待办」行（原型 L3 联动：保存后同步至任务列表·rich 走 plainBody）。
  List<String> todoLines() => plainBody
      .split('\n')
      .map((l) => RegExp(r'^\s*(?:[-*]\s*)?☐\s*(.+)$').firstMatch(l))
      .whereType<Match>()
      .map((m) => m.group(1)!.trim())
      .where((t) => t.isNotEmpty)
      .toList();

  /// 正文中提取 #标签（保存时并入 tags·rich 走 plainBody）。
  List<String> hashTags() => RegExp(r'#(\S+)')
      .allMatches(plainBody)
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
    String? kind,
    int? weatherCode,
    double? tempMax,
    double? tempMin,
    bool? weatherManual,
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
        kind: kind ?? this.kind,
        weatherCode: weatherCode ?? this.weatherCode,
        tempMax: tempMax ?? this.tempMax,
        tempMin: tempMin ?? this.tempMin,
        weatherManual: weatherManual ?? this.weatherManual,
        sections: sections ?? this.sections,
      );
}
