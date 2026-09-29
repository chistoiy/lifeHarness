import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../logging/app_log.dart';

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
      } catch (e) {
        // 表缺失（裁剪构建）跳过该列。
        // 但「读不到引用」＝该列全部文件会被判成孤儿，必须留痕提醒别据此清理。
        AppLog.add('媒体引用列读取失败（$table.$col）：$e · 孤儿判定会偏多',
            level: LhLevel.warn);
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
    final result = MediaScanResult(orphans: orphans, totalFiles: total);
    AppLog.addKey('媒体扫描：根 ${mediaDirs.length} 个 · 文件 $total 个 · 孤儿 '
        '${orphans.length} 个 ${(result.orphanBytes / 1048576).toStringAsFixed(1)}MB');
    return result;
  }

  /// 删除给定孤儿（用户勾选后调用）。护栏：路径必须落在注册根内。
  int deleteOrphans(List<String> paths) {
    var n = 0, refused = 0;
    for (final path in paths) {
      final canonical = p.canonicalize(path);
      final insideRoot = mediaDirs.any((root) =>
          canonical.startsWith(p.canonicalize(root) + p.separator));
      if (!insideRoot) {
        // 绝不越界删
        refused++;
        AppLog.add('媒体清理越界拒绝（不在注册根内）：$canonical',
            level: LhLevel.warn);
        continue;
      }
      try {
        File(canonical).deleteSync();
        n++;
      } catch (e) {
        // 句柄占用等：跳过，不中断批量。
        AppLog.add('媒体清理删除失败（跳过不中断）：$canonical $e',
            level: LhLevel.error);
      }
    }
    AppLog.addKey('媒体清理完成：删除 $n/${paths.length} 个'
        '${refused > 0 ? ' · 越界拒绝 $refused 个' : ''}');
    return n;
  }
}
