/// 备份格式四件套批2 · notes/ md 投影生成（评估件 §四·方案A「可读的包」）。
///
/// 口径（需求清单 V1.66 / 工单批2 面板钉子2）：
/// - **md ＝ 只读投影，恢复一律以 db.sqlite 为权威**（评估件 §三 钉死，不许反哺恢复）；
/// - 每条 front-matter 存元信息（标题/目录/日期/标签），正文复用 `noteToMarkdown`
///   的 Delta→md 口径（rich 有损＝投影口径明示，无损数据只在库里）；
/// - 图片引用改写为包内相对路径 `../attachments/note_images/<basename>`
///   （note_images 内容寻址命名＝basename 天然唯一，同 note_export 的撞名口径）;
/// - 输出＝成员名 → 文本内容（`notes/notes.md` 等），由 BackupService 作为
///   `extraFiles` 交给 [LhBak.create]（恒明文，与 logs 同档）。
///
/// 落位 shared/linkage：要吃 journal/read/mindmap 的 domain 模型（R1 禁
/// features 互 import，聚合层唯一合法落点）。
library;

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../core/database/schema.dart';
import '../../core/logging/app_log.dart';
import '../../features/journal/domain/journal_entry.dart';
import '../../features/journal/domain/note.dart';
import '../../features/journal/presentation/note_export.dart'
    show noteToMarkdown; // Delta→md 单源复用（私有 _deltaToMd 的公开门面）

/// md 本地图片语法（与 note_export 同式；那边是私有，此处按同 regex 自持）。
final RegExp _mdImgRe = RegExp(r'!\[([^\]]*)\]\(([^)]+)\)');

bool _isLocalAsset(String s) =>
    s.isNotEmpty && !s.startsWith('http://') && !s.startsWith('https://');

/// 正文里的本地图片引用 → 包内相对路径。非本地（http）与认不出的原样保留，
/// 绝不编造指不到文件的链接（note_export 同口径）。
String _relativizeToAttachments(String body) => body.replaceAllMapped(
      _mdImgRe,
      (m) {
        final path = m.group(2) ?? '';
        if (!_isLocalAsset(path)) return m.group(0)!;
        final base = p.basename(path.replaceAll('\\', '/'));
        if (base.isEmpty || base == '/' ) return m.group(0)!;
        return '![${m.group(1)}](../attachments/note_images/$base)';
      },
    );

String _iso(int? ms) => ms == null
    ? ''
    : DateTime.fromMillisecondsSinceEpoch(ms).toIso8601String();

/// front-matter 块（键序稳定，人可读优先）。
String _frontMatter(Map<String, String> fields) {
  final sb = StringBuffer('---\n');
  for (final e in fields.entries) {
    if (e.value.isEmpty) continue;
    sb.write('${e.key}: ${e.value.replaceAll('\n', ' ')}\n');
  }
  sb.write('---\n\n');
  return sb.toString();
}

/// rich/纯文本正文 → md（零资产映射：图片引用交给 [_relativizeToAttachments]）。
String _bodyToMd(String content, String kind) {
  if (kind == 'rich') {
    final n = Note(
      title: '',
      content: content,
      kind: 'rich',
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );
    return _relativizeToAttachments(noteToMarkdown(n, const {}));
  }
  return _relativizeToAttachments(content);
}

/// 日记一条 → md 段（结构化模板条目用 content 渲染快照——投影够读，
/// 分节真结构只在库里）。
String _diaryEntryToMd(JournalEntry e) {
  final fm = _frontMatter({
    'kind': 'diary',
    'date': _dayKey(e.day),
    if (e.mood != null) 'mood': '${e.mood}',
    if (e.tags.isNotEmpty) 'tags': e.tags.join(', '),
    'created': _iso(e.createdAt.millisecondsSinceEpoch),
    'updated': _iso(e.updatedAt.millisecondsSinceEpoch),
  });
  return '$fm${_bodyToMd(e.content, e.kind)}\n\n---\n\n';
}

String _dayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// 笔记一条 → md 段（软删不投影；归档照投，front-matter 带 archived 标）。
String _noteToMd(Map<String, Object?> row, String folderName) {
  final n = Note.fromRow(row);
  final fm = _frontMatter({
    'kind': 'note',
    'title': n.title.trim().isEmpty ? '未命名笔记' : n.title.trim(),
    if (folderName.isNotEmpty) 'folder': folderName,
    if (n.archived) 'archived': 'true',
    'created': _iso(n.createdAt.millisecondsSinceEpoch),
    'updated': _iso(n.updatedAt.millisecondsSinceEpoch),
  });
  return '$fm${_bodyToMd(n.content, n.kind)}\n\n---\n\n';
}

/// 生成包内 notes/ 投影成员（成员名 → 文本）。
///
/// - [moduleIds] 空 = 全部数据（四类成员全生成）；非空按模块裁剪。
/// - 任一腿查询/转换失败降级为跳过该成员并 warn（投影是只读增值件，
///   不许它把整个导出炸了——DB 与附件两条权威腿不受影响）。
Future<Map<String, String>> buildNoteProjectionMembers(
  Database db, {
  required Set<String> moduleIds,
}) async {
  final all = moduleIds.isEmpty;
  final wantJournal = all || moduleIds.contains('journal');
  final wantRead = all || moduleIds.contains('read');
  final wantMindmap = all || moduleIds.contains('mindmap');
  final members = <String, String>{};

  if (wantJournal) {
    try {
      // 笔记（软删不投影；folder 列＝目录名 TEXT，直接用）。
      final noteRows = await db.query(
        DbSchema.tNotes,
        where: 'deleted_at IS NULL',
        orderBy: 'updated_at DESC',
      );
      if (noteRows.isNotEmpty) {
        final sb = StringBuffer('# 笔记投影\n\n'
            '> 只读投影 · 恢复以 db.sqlite 为权威 · 共 ${noteRows.length} 篇\n\n');
        for (final row in noteRows) {
          sb.write(_noteToMd(row, (row['folder'] as String?) ?? ''));
        }
        members['notes/notes.md'] = sb.toString();
      }
    } catch (e) {
      AppLog.add('笔记投影生成失败（跳过 notes.md）：$e', level: LhLevel.warn);
    }
    try {
      // 日记（含分节条目的渲染快照；软删不投影）。
      final rows = await db.query(DbSchema.tJournal,
          where: 'deleted_at IS NULL', orderBy: 'entry_date DESC, id DESC');
      if (rows.isNotEmpty) {
        final sb = StringBuffer('# 日记投影\n\n'
            '> 只读投影 · 恢复以 db.sqlite 为权威 · 共 ${rows.length} 篇\n\n');
        for (final row in rows) {
          try {
            sb.write(_diaryEntryToMd(JournalEntry.fromRow(row)));
          } catch (_) {
            // 单条列形态异常跳过，不炸整份投影。
          }
        }
        members['notes/diary.md'] = sb.toString();
      }
    } catch (e) {
      AppLog.add('日记投影生成失败（跳过 diary.md）：$e', level: LhLevel.warn);
    }
  }

  if (wantRead) {
    try {
      final rows = await db.rawQuery('''
        SELECT q.*, b.title AS _book_title
        FROM ${DbSchema.tBookQuotes} q
        LEFT JOIN ${DbSchema.tBooks} b ON b.id = q.book_id
        WHERE q.deleted_at IS NULL
        ORDER BY b.title ASC, q.created_at ASC
      ''');
      if (rows.isNotEmpty) {
        final sb = StringBuffer('# 书摘投影\n\n'
            '> 只读投影 · 恢复以 db.sqlite 为权威 · 共 ${rows.length} 条\n\n');
        var curBook = '';
        for (final row in rows) {
          final book = (row['_book_title'] as String?) ?? '未归书';
          if (book != curBook) {
            curBook = book;
            sb.write('## $book\n\n');
          }
          final body = (row['body'] as String?) ?? '';
          final thought = row['thought'] as String?;
          final chapter = row['chapter'] as String?;
          final loc = row['loc'];
          sb.write('> ${body.replaceAll('\n', '\n> ')}\n');
          if (thought != null && thought.trim().isNotEmpty) {
            sb.write('\n想法：${thought.trim()}\n');
          }
          final src = [
            if (chapter != null && chapter.trim().isNotEmpty) chapter.trim(),
            if (loc != null) '位置 $loc',
          ].join(' · ');
          if (src.isNotEmpty) sb.write('\n（$src）\n');
          sb.write('\n');
        }
        members['notes/book_quotes.md'] = sb.toString();
      }
    } catch (e) {
      AppLog.add('书摘投影生成失败（跳过 book_quotes.md）：$e', level: LhLevel.warn);
    }
  }

  if (wantMindmap) {
    try {
      final maps = await db.query(DbSchema.tMindmaps,
          where: 'deleted_at IS NULL', orderBy: 'updated_at DESC');
      final nodes = await db.query(DbSchema.tMindmapNodes,
          orderBy: 'map_id ASC, sort ASC, id ASC');
      if (maps.isNotEmpty) {
        final byMap = <int, List<Map<String, Object?>>>{};
        for (final n in nodes) {
          byMap.putIfAbsent(n['map_id'] as int, () => []).add(n);
        }
        final sb = StringBuffer('# 导图投影\n\n'
            '> 只读投影（大纲文本）· 恢复以 db.sqlite 为权威 · 共 ${maps.length} 张\n\n');
        for (final m in maps) {
          final id = m['id'] as int;
          sb.write('## ${m['title']}\n\n');
          final children = byMap[id] ?? const [];
          // parent_id 现单层恒 NULL；按缩进兜多层树口。
          String render(Map<String, Object?> n, int depth) {
            final title = (n['title'] as String?) ?? '';
            final note = (n['note'] as String?) ?? '';
            final task = n['is_task'] == 1
                ? (n['task_done'] == 1 ? '- [x] ' : '- [ ] ')
                : '- ';
            var line = '${'  ' * depth}$task$title\n';
            if (note.trim().isNotEmpty) {
              line += '${'  ' * depth}  - ${note.trim()}\n';
            }
            return line;
          }
          for (final n in children) {
            final parent = n['parent_id'] as int?;
            if (parent == null) {
              sb.write(render(n, 0));
              for (final c in children) {
                if (c['parent_id'] == n['id']) sb.write(render(c, 1));
              }
            }
          }
          sb.write('\n');
        }
        members['notes/mindmaps.md'] = sb.toString();
      }
    } catch (e) {
      AppLog.add('导图投影生成失败（跳过 mindmaps.md）：$e', level: LhLevel.warn);
    }
  }

  return members;
}
