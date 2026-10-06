import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'backup_service.dart' show kAutoBeforeRestoreTag;

/// B-1 备份文件清单（原型 `p-sub-backup` 对译）。
///
/// 规格唯一依据＝`docs/handoff/交棒话术-20261004-备份管理与图片预览批.md` §2 B-1 与 §11
/// 落地记录：这一屏是**导入主通道**——云同步下载的 `.lhbak` 落在应用内部 `exports/`，
/// 系统文件选择器（SAF）逛不到那里，「下载下来的包选不到」＝换机恢复断在最后一环。
/// 三条红线照工单：只扫 `exports/` 浅层不触 SAF；删除＝物理删**不进回收站**
/// （回收站是数据记录面，文件面不混）；不动 `snapshot_service` 的保留份数裁剪策略。

/// 来源三档（原型同名角标；配色在 UI 侧，本层只给口径与文案）。
enum BackupFileSource { local, cloud, auto }

extension BackupFileSourceX on BackupFileSource {
  String get label => switch (this) {
    BackupFileSource.auto => '恢复前自动',
    BackupFileSource.cloud => '云端下载',
    BackupFileSource.local => '本地导出',
  };
}

/// 一个备份包。
class BackupFileEntry {
  const BackupFileEntry({
    required this.path,
    required this.name,
    required this.bytes,
    required this.mtime,
    required this.source,
  });

  final String path;
  final String name;
  final int bytes;
  final DateTime mtime;
  final BackupFileSource source;

  String get sizeText => '${(bytes / 1048576).toStringAsFixed(1)} MB';

  /// 行上的时间读数（原型 `ts` 口径＝MM-dd HH:mm）。
  String get timeText {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(mtime.month)}-${two(mtime.day)} ${two(mtime.hour)}:${two(mtime.minute)}';
  }
}

/// 扫目录出清单＋来源判定＋物理删除。
///
/// 来源口径：`auto_before_restore_*` 前缀＝恢复前自动；名字在**云端下载台账**里＝云端下载；
/// 其余＝本地导出。台账自本批起在下载落盘时记名（[markDownloaded]）——**早于本批**的
/// 历史下载包会被读成「本地导出」，只影响角标文字、不影响任何动作，随新包自然收敛。
class BackupFileScanner {
  BackupFileScanner({required this.dir, required this.prefs});

  final String dir;
  final SharedPreferences prefs;

  static const downloadedKey = 'lh.backup_downloaded';

  /// 台账上限：只用于标角标，不做恢复依据，故留近 60 条足够（超出即最旧的先出账）。
  static const maxLedger = 60;

  static Set<String> downloadedNames(SharedPreferences prefs) =>
      (prefs.getStringList(downloadedKey) ?? const []).toSet();

  /// 同步下载落 `exports/` 成功时记一名（调用方＝`SyncOrchestrator`）。
  static Future<void> markDownloaded(
      SharedPreferences prefs, String name) async {
    final s = downloadedNames(prefs)..add(name);
    final list = s.toList();
    await prefs.setStringList(
        downloadedKey,
        list.length > maxLedger ? list.sublist(list.length - maxLedger) : list);
  }

  Future<List<BackupFileEntry>> scan() async {
    final d = Directory(dir);
    if (!await d.exists()) return const [];
    final known = downloadedNames(prefs);
    final out = <BackupFileEntry>[];
    await for (final e in d.list(recursive: false, followLinks: false)) {
      if (e is! File || !e.path.toLowerCase().endsWith('.lhbak')) continue;
      final st = await e.stat();
      final name = p.basename(e.path);
      out.add(BackupFileEntry(
        path: e.path,
        name: name,
        bytes: st.size,
        mtime: st.modified,
        source: name.startsWith(kAutoBeforeRestoreTag)
            ? BackupFileSource.auto
            : known.contains(name)
                ? BackupFileSource.cloud
                : BackupFileSource.local,
      ));
    }
    out.sort((a, b) => b.mtime.compareTo(a.mtime));
    return out;
  }

  /// 物理删除，返回释放字节数（缺失文件跳过不报错：列表可能已过期）。
  Future<int> purge(List<String> paths) async {
    var freed = 0;
    for (final path in paths) {
      final f = File(path);
      if (!await f.exists()) continue;
      freed += (await f.stat()).size;
      await f.delete();
    }
    return freed;
  }
}
