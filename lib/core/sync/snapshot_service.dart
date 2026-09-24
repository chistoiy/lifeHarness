import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../backup/backup_service.dart';
import '../backup/lh_bak.dart';
import '../database/schema.dart';
import '../logging/app_log.dart';
import 'remote_store.dart';

/// 「保留 N 份历史快照」prefs 键（S6 控流设置页读写，默认 5）。
const String kSyncKeepSnapshotsKey = 'sync_keep_snapshots';

/// [kSyncKeepSnapshotsKey] 缺省/非法值兜底（设计稿 §4：默认 N=5）。
const int kSyncKeepSnapshotsDefault = 5;

/// `care.syncExcluded` 读取器签名。组合根接线为
/// `() => CareRepository(db).syncExcluded()`——core/sync 不得 import features
/// （架构守护 R2），故本服务只收函数；测试注入常量/抛异常体。
typedef CareExcludedReader = Future<bool> Function();

/// [SnapshotService.build] 结果：快照文件 + manifest + 本轮被裁掉的文件名。
class SyncSnapshotResult {
  const SyncSnapshotResult({
    required this.file,
    required this.manifest,
    required this.pruned,
  });

  /// 刚生成的快照（`<docs>/sync/` 内，nameTag=sync）。
  final File file;

  /// 打包时的 manifest（excludedTables 即 care 排表证据，S3 差异/恢复报告用）。
  final LhBakManifest manifest;

  /// 本轮裁剪删除的文件名（basename，含被裁的历史快照）。
  final List<String> pruned;
}

/// 同步快照生成器（Task 16；设计稿 §3+§4：同步对象 = `<docs>/sync/` 目录）。
///
/// 口径（钉死）：
/// - **快照 = 备份文件**：一次 [build] 即调 [BackupService.exportBackup]
///   （`withLogs:true` + `outDirOverride:<docs>/sync/` + `nameTag:'sync'` +
///   `excludeTables`: careExcluded 置位时整组 [DbSchema.careTables]、否则空），
///   不为同步另造容器格式；
/// - careExcluded 读取抛异常（DB 未开等）→ **视为 true 保守排除** + AppLog
///   warn（红线 7 宁缺勿泄）；
/// - 生成成功后按 mtime 新→旧裁剪目录内快照命名的 `.lhbak`，保最新 keepN 份
///   （刚生成者 protect 永不裁）；`auto_before_restore_` 前缀本不该进
///   sync/（T10 落 exports/），防御性跳过；非快照命名文件（logs/ 子目录等）
///   一律不碰；
/// - [localInventory] 为台账/差异引擎的**本地侧清单来源**（digest=null，
///   size/mtime 仅展示用——一致性判定绝不引用 mtime，R8）。
class SnapshotService {
  SnapshotService({
    required this.backup,
    required this.prefs,
    required this.docsDir,
    required this.careExcluded,
  });

  final BackupService backup;
  final SharedPreferences prefs;

  /// 应用文档目录提供者（生产 = path_provider getApplicationDocumentsDirectory）。
  final String Function() docsDir;

  /// `care.syncExcluded` 读取函数（红线 7，组合根接 CareRepository）。
  final CareExcludedReader careExcluded;

  /// 同步快照目录 = `<docs>/sync/`（设计稿 §4 同步对象根）。
  String get syncDir => p.join(docsDir(), 'sync');

  /// 裁剪候选判据：`.lhbak` 且「快照命名」——nameTag=sync 的 T10 实装名
  /// `sync_YYYYMMDD_HHMMSS[-n].lhbak`，或 brief 字面档
  /// `lifeharness_*sync*.lhbak`；`auto_before_restore_*` 一律排除（防御：
  /// 该前缀永不参与云同步，见 T10 口径）。
  static bool isSyncSnapshotName(String name) {
    if (!name.endsWith('.lhbak')) return false;
    if (name.startsWith(kAutoBeforeRestoreTag)) return false;
    return name.startsWith('sync_') ||
        (name.startsWith('lifeharness_') && name.contains('sync'));
  }

  /// keepN 生效值：形参 > prefs `sync_keep_snapshots` > 默认 5；
  /// 非正数/非法一律落回默认（S6 只写正整档，脏值不炸裁剪）。
  int effectiveKeepN([int? keepN]) {
    final raw = keepN ?? prefs.getInt(kSyncKeepSnapshotsKey);
    if (raw == null || raw < 1) return kSyncKeepSnapshotsDefault;
    return raw;
  }

  /// 生成一份同步快照并裁剪目录至最新 keepN 份。
  /// [keepN] 显式传入优先于 prefs 配置（UI 预览/测试用）。
  Future<SyncSnapshotResult> build({int? keepN}) async {
    final n = effectiveKeepN(keepN);
    final dir = syncDir;
    Directory(dir).createSync(recursive: true);
    final excluded = await _careExcludedSafe() ? DbSchema.careTables : const <String>[];
    final res = await backup.exportBackup(
      withLogs: true,
      outDirOverride: dir,
      excludeTables: excluded,
      nameTag: 'sync',
    );
    final pruned = await pruneSnapshots(keepN: n, protect: res.file.path);
    return SyncSnapshotResult(file: res.file, manifest: res.manifest, pruned: pruned);
  }

  /// 本地侧清单：递归扫 sync/（快照 + logs/ 子目录等全部文件），产出可直接
  /// 喂 `computeDiff` / `SyncLedger.record` 的 [FileEntry] 列表。
  /// digest=null（严格 MD5 档由远端 32-hex ETag 门槛自动关闭）；
  /// relativePath 以 sync/ 为根、posix 分隔、非空保证（basename 兜底）。
  Future<List<FileEntry>> localInventory() async {
    final dir = Directory(syncDir);
    if (!dir.existsSync()) return [];
    final out = <FileEntry>[];
    try {
      for (final e in dir.listSync(recursive: true).whereType<File>()) {
        final rel = p.posix.joinAll(p.split(p.relative(e.path, from: dir.path)));
        if (rel.isEmpty) continue;
        DateTime? mtime;
        try {
          mtime = e.lastModifiedSync();
        } catch (_) {
          // 句柄占用/瞬时错误：mtime 仅展示用，缺了不影响差异判定（R8）。
        }
        out.add(FileEntry(
          relativePath: rel,
          size: e.lengthSync(),
          modified: mtime,
        ));
      }
    } catch (_) {
      // 目录中途不可读：按已收集部分返回，绝不炸同步链路。
    }
    out.sort((a, b) => a.relativePath.compareTo(b.relativePath));
    return out;
  }

  /// 裁剪 sync/ 内快照命名文件至最新 [keepN] 份（mtime 新→旧，同秒按名序
  /// 倒序兜底）；[protect]（刚生成者/正在下载者）豁免占一份、绝不吃刀。
  /// 返回被删文件的 basename（旧→新序）。非快照命名与 `auto_before_restore_`
  /// 不在候选内（[isSyncSnapshotName]）。
  Future<List<String>> pruneSnapshots({
    required int keepN,
    String? protect,
  }) async {
    final dir = Directory(syncDir);
    if (!dir.existsSync() || keepN < 1) return [];
    final protectPath = protect == null
        ? null
        : p.canonicalize(protect);
    final candidates = <File>[];
    for (final f in dir.listSync().whereType<File>()) {
      if (!isSyncSnapshotName(p.basename(f.path))) continue;
      if (protectPath != null && p.canonicalize(f.path) == protectPath) continue;
      candidates.add(f);
    }
    // 新→旧：mtime 倒序，同时间戳按名倒序（唯一化兜底，不依赖 rename 时序）。
    candidates.sort((a, b) {
      final ma = _mtimeOf(a), mb = _mtimeOf(b);
      if (ma != mb) return mb.compareTo(ma);
      return p.basename(b.path).compareTo(p.basename(a.path));
    });
    // protect 已占一份名额 → 历史档最多再留 keepN-1 份。
    final keepHistory = keepN - (protectPath != null ? 1 : 0);
    final doomed = candidates.skip(keepHistory < 0 ? 0 : keepHistory);
    final removed = <String>[];
    for (final f in doomed.toList().reversed) {
      // 反序删除 = 报告里按「旧→新」列出，UI 摘要可读。
      try {
        f.deleteSync();
        removed.add(p.basename(f.path));
      } catch (e) {
        AppLog.add('快照裁剪失败（${p.basename(f.path)}）：$e',
            level: LhLevel.warn);
      }
    }
    return removed;
  }

  /// careExcluded 读取兜底（钉死）：失败视为 true（保守排除呵护表）+ warn。
  Future<bool> _careExcludedSafe() async {
    try {
      return await careExcluded();
    } catch (e) {
      AppLog.add('care.syncExcluded 读取失败，按 true 保守排除呵护表：$e',
          level: LhLevel.warn);
      return true;
    }
  }

  static int _mtimeOf(File f) {
    try {
      return f.lastModifiedSync().millisecondsSinceEpoch;
    } catch (_) {
      return 0;
    }
  }
}
