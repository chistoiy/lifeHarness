import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../logging/app_log.dart';

/// R5b：note_images 存量文件一次性收编为 SHA256 内容寻址命名。
///
/// 口径：
/// - 判据：basename 去扩展名后**不是 64 位小写 hex** 的文件视为旧命名
///   （毫秒时间戳等），参与迁移；已是 hash 名的跳过（幂等，可重跑）；
/// - 目标名已存在（内容相同）→ 删源文件并把引用改指目标（全局去重合并）；
///   否则 rename + 六列文本引用整串替换（旧绝对路径 → 新绝对路径）；
/// - 引用列（图片路径以绝对路径内嵌于文本/列表）：notes.content /
///   note_snapshots.content / journal.content / journal_sections.body /
///   book_quotes.image_paths / books.cover_path；
/// - 任何单文件失败只 warn 跳过，不中断迁移；全部完成后由调用方落
///   prefs 标志（本服务不持 prefs，保持纯函数式可测）。
class MediaHashMigrator {
  MediaHashMigrator({required this.db, required this.noteImagesDir});

  final Database db;
  final String noteImagesDir;

  static final _hashName = RegExp(r'^[0-9a-f]{64}$');

  static const List<(String, String)> _refColumns = [
    ('notes', 'content'),
    ('note_snapshots', 'content'),
    ('journal_entries', 'content'),
    ('journal_sections', 'body'),
    ('book_quotes', 'image_paths'),
    ('books', 'cover_path'),
  ];

  /// 迁移统计（日志/UI 复用）。
  Future<Map<String, int>> migrate() async {
    final stats = {'scanned': 0, 'renamed': 0, 'merged': 0, 'failed': 0};
    final dir = Directory(noteImagesDir);
    if (!dir.existsSync()) return stats;
    for (final f in dir.listSync().whereType<File>()) {
      final base = p.basenameWithoutExtension(f.path);
      if (_hashName.hasMatch(base)) continue; // 新命名，跳过
      stats['scanned'] = stats['scanned']! + 1;
      try {
        final hash =
            crypto.sha256.convert(f.readAsBytesSync()).toString();
        final ext = p.extension(f.path).toLowerCase();
        final dest = File(p.join(noteImagesDir, '$hash$ext'));
        final oldPath = f.path;
        if (dest.existsSync() && p.canonicalize(dest.path) != p.canonicalize(oldPath)) {
          f.deleteSync();
          await _replaceRef(oldPath, dest.path);
          stats['merged'] = stats['merged']! + 1;
        } else {
          f.renameSync(dest.path);
          await _replaceRef(oldPath, dest.path);
          stats['renamed'] = stats['renamed']! + 1;
        }
      } catch (e) {
        stats['failed'] = stats['failed']! + 1;
        AppLog.add('图片哈希迁移失败（跳过不中断）：${p.basename(f.path)} $e',
            level: LhLevel.warn);
      }
    }
    if (stats['scanned']! > 0) {
      AppLog.add('图片内容寻址迁移：改名 ${stats['renamed']} · 去重合并 ${stats['merged']}'
          ' · 失败 ${stats['failed']}');
    }
    return stats;
  }

  Future<void> _replaceRef(String oldPath, String newPath) async {
    for (final (table, col) in _refColumns) {
      try {
        // 表缺失（裁剪构建/测试库）只跳过该列，不炸整条迁移。
        final rows = await db.query(table,
            columns: ['id', col],
            where: '$col LIKE ?',
            whereArgs: ['%$oldPath%'],
            limit: 500);
        for (final r in rows) {
          final text = r[col] as String?;
          if (text == null) continue;
          await db.update(table, {col: text.replaceAll(oldPath, newPath)},
              where: 'id = ?', whereArgs: [r['id']]);
        }
      } catch (e) {
        // 单列失败不影响其余列改名替换（文件侧已原子完成）。
        // 但这意味着**库里还指着旧路径**，不留痕就是静默丢引用。
        AppLog.add('图片哈希迁移引用替换失败（$table.$col）：$e',
            level: LhLevel.warn);
      }
    }
  }
}
