import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// R5c：本地孤儿图片扫描/清理（存储卫生）。
///
/// 口径：
/// - 引用判定 = 六列文本（笔记/快照/日记/日记小节/书摘图/封面）里是否
///   含文件 **basename**（路径前缀可能因迁移/恢复变化，名字是唯一稳定键；
///   hash 命名下 basename 即内容指纹，误判概率≈0）；
/// - 只扫媒体根目录（note_images / book_covers），别的目录一概不碰；
/// - [deleteOrphans] 带路径护栏：目标必须位于注册根内，否则拒绝。
class MediaScanEntry {
  const MediaScanEntry({
    required this.path,
    required this.size,
    required this.modified,
  });

  final String path;
  final int size;
  final DateTime? modified;

  String get name => p.basename(path);
}

class MediaScanResult {
  const MediaScanResult({required this.orphans, required this.totalFiles});

  /// 未被任何引用命中的文件。
  final List<MediaScanEntry> orphans;

  /// 扫描到的媒体文件总数（展示「N / M」用）。
  final int totalFiles;

  int get orphanBytes => orphans.fold<int>(0, (a, e) => a + e.size);
}

class MediaUsageScanner {
  MediaUsageScanner({required this.db, required this.mediaDirs});

  final Database db;

  /// 参与扫描的本地媒体根目录（绝对路径）。
  final List<String> mediaDirs;

  static const List<(String, String)> _refColumns = [
    ('notes', 'content'),
    ('note_snapshots', 'content'),
    ('journal_entries', 'content'),
    ('journal_sections', 'body'),
    ('book_quotes', 'image_paths'),
    ('books', 'cover_path'),
  ];

  /// 六列引用全文（一次性拉入内存；R5c 孤儿判定与 R5d 云端清理共用）。
  Future<String> referenceText() async {
    final buf = StringBuffer();
    for (final (table, col) in _refColumns) {
      try {
        final rows = await db.query(table, columns: [col]);
        for (final r in rows) {
          final v = r[col];
          if (v is String) buf.write(v);
          buf.write('\n');
        }
      } catch (_) {
        // 表缺失（裁剪构建）跳过该列。
      }
    }
    return buf.toString();
  }

  Future<MediaScanResult> scan() async {
    final text = await referenceText();
    final orphans = <MediaScanEntry>[];
    var total = 0;
    for (final dir in mediaDirs) {
      final d = Directory(dir);
      if (!d.existsSync()) continue;
      for (final f in d.listSync(recursive: true).whereType<File>()) {
        total++;
        if (!text.contains(p.basename(f.path))) {
          DateTime? m;
          try {
            m = f.lastModifiedSync();
          } catch (_) {}
          orphans.add(MediaScanEntry(
              path: f.path, size: f.lengthSync(), modified: m));
        }
      }
    }
    orphans.sort((a, b) => a.path.compareTo(b.path));
    return MediaScanResult(orphans: orphans, totalFiles: total);
  }

  /// 删除给定孤儿（用户勾选后调用）。护栏：路径必须落在注册根内。
  int deleteOrphans(List<String> paths) {
    var n = 0;
    for (final path in paths) {
      final canonical = p.canonicalize(path);
      final insideRoot = mediaDirs.any((root) =>
          canonical.startsWith(p.canonicalize(root) + p.separator));
      if (!insideRoot) continue; // 绝不越界删
      try {
        File(canonical).deleteSync();
        n++;
      } catch (_) {
        // 句柄占用等：跳过，不中断批量。
      }
    }
    return n;
  }
}
