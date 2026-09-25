import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../logging/app_log.dart';
import '../media/media_usage_scanner.dart';
import 'remote_store.dart';
import 'service_config.dart';

/// R5d：云端孤儿附件清理（归档移动为主，删除仅显式确认）。
///
/// 口径：
/// - 云端孤儿 = 云端 `attachments/` 前缀文件中，basename 未被本地六列引用
///   文本命中者；`media_archive/` 前缀自身永不参与孤儿判定（归档区豁免）；
/// - **归档**：move 到 `media_archive/<原相对路径>`（只移不删，双云各自留档）；
/// - **删除**：仅用户在清理半屏逐项确认后可用（同步链路永不触发删除——
///   「删除不传播」红线不变）；
/// - 自动归档开关（`sync.autoArchive`，默认关）：每轮同步成功后把云端孤儿
///   **归档**（不删除）；30 天清理开关（`sync.archivePurge30`，默认关）：
///   自动归档后顺带删除归档区内修改时间早于 30 天的条目。
class CloudCleanService {
  CloudCleanService({required this.prefs, required this.scanner});

  final SharedPreferences prefs;
  final MediaUsageScanner scanner;

  static const String attachmentsPrefix = 'attachments/';
  static const String archivePrefix = 'media_archive/';
  static const String kAutoArchive = 'sync.autoArchive';
  static const String kArchivePurge30 = 'sync.archivePurge30';
  static const Duration archiveTtl = Duration(days: 30);

  /// 云端孤儿附件清单（force 穿透清单缓存，清理决策必须看最新云端）。
  Future<List<FileEntry>> cloudOrphans(
      RemoteStore store, ServiceConfig c) async {
    final listing = await store.list(c, c.cloudDirName, force: true);
    final text = await scanner.referenceText();
    return listing.files
        .where((e) =>
            e.relativePath.startsWith(attachmentsPrefix) &&
            !text.contains(p.basename(e.relativePath)))
        .toList(growable: false);
  }

  /// 归档：逐条 move 到归档区；单条失败 warn 不中断。返回成功数。
  Future<int> archive(RemoteStore store, ServiceConfig c,
      List<FileEntry> sel) async {
    var n = 0;
    for (final e in sel) {
      try {
        await store.move(
            c, e.relativePath, '$archivePrefix${e.relativePath}');
        n++;
      } catch (err) {
        AppLog.add('⚠️ 云端归档失败（跳过不中断）：${e.relativePath} $err',
            level: LhLevel.warn);
      }
    }
    if (n > 0) AppLog.add('云端归档 $n 个未引用附件（media_archive/，未删除）');
    return n;
  }

  /// 彻底删除：仅限用户在清理半屏显式确认的条目。单条失败不中断。
  Future<int> purge(RemoteStore store, ServiceConfig c,
      List<FileEntry> sel) async {
    var n = 0;
    for (final e in sel) {
      try {
        await store.delete(c, e.relativePath);
        n++;
      } catch (err) {
        AppLog.add('⚠️ 云端删除失败（跳过不中断）：${e.relativePath} $err',
            level: LhLevel.warn);
      }
    }
    if (n > 0) AppLog.add('云端彻底删除 $n 个条目（用户逐项确认）');
    return n;
  }

  /// 同步成功后的自动钩子：归档开关开启才动，且**永远只归档不删除**；
  /// 30 天清理开关叠加时，仅清归档区内超期条目。
  Future<void> autoCleanAfterSync(RemoteStore store, ServiceConfig c,
      {DateTime? now}) async {
    if (prefs.getBool(kAutoArchive) != true) return;
    try {
      await archive(store, c, await cloudOrphans(store, c));
      if (prefs.getBool(kArchivePurge30) == true) {
        final t = now ?? DateTime.now();
        final listing = await store.list(c, c.cloudDirName, force: true);
        final expired = listing.files
            .where((e) =>
                e.relativePath.startsWith(archivePrefix) &&
                e.modified != null &&
                t.difference(e.modified!) > archiveTtl)
            .toList(growable: false);
        if (expired.isNotEmpty) await purge(store, c, expired);
      }
    } catch (e) {
      AppLog.add('⚠️ 云端自动归档失败（不影响同步结果）：$e',
          level: LhLevel.warn);
    }
  }
}
