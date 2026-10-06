import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
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
    this.reused = false,
  });

  /// 本次使用/生成的快照（`<docs>/sync/` 内，nameTag=sync）。
  final File file;

  /// 打包时的 manifest（excludedTables 即 care 排表证据，S3 差异/恢复报告用）。
  /// [SyncSnapshotResult.reused] 为 true（复用旧快照、未重新打包）时为 null。
  final LhBakManifest? manifest;

  /// 本轮裁剪删除的文件名（basename，含被裁的历史快照）。
  final List<String> pruned;

  /// R3②：true = 数据库自最新快照后无变化，直接复用、未生成新文件。
  final bool reused;
}

/// R5a：附件同步根——本地目录 [localDir] 的文件以 `attachments/<cloudName>/…`
/// 相对路径进入差异引擎（文件级增量：新图上传、两端已有 inSync 跳过、
/// 历史图片永不重传）。
class AttachRoot {
  const AttachRoot({required this.cloudName, required this.localDir});

  /// 云内目录段（attachments/{cloudName}/…）。
  final String cloudName;

  /// 本地绝对目录（如 `<docs>/note_images`）。
  final String localDir;
}

/// 同步快照生成器（Task 16；设计稿 §3+§4：同步对象 = `<docs>/sync/` 目录，
/// R5a 起附件目录以文件级增量并入同一差异集）。
///
/// 口径（R5a 修订）：
/// - **快照 = 纯 DB 备份文件**：一次 [build] 即调 [BackupService.exportBackup]
///   （`withLogs:false` + `withAttachments:false` + `outDirOverride:<docs>/sync/`
///   + `nameTag:'sync'` + `excludeTables`: careExcluded 置位时整组
///   [DbSchema.careTables]、否则空）；图片经 [attachRoots] 以独立文件
///   走文件级增量，不再随包重传；
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
    this.dbFile,
    this.attachRoots = const [],
  });

  final BackupService backup;
  final SharedPreferences prefs;

  /// 应用文档目录提供者（生产 = path_provider getApplicationDocumentsDirectory）。
  final String Function() docsDir;

  /// `care.syncExcluded` 读取函数（红线 7，组合根接 CareRepository）。
  final CareExcludedReader careExcluded;

  /// 活库文件提供者（R3② 快照复用判定用；生产 = AppDatabase.openedPath）。
  /// 返回 null（未开库/测试未注入）时**永不复用**，行为与旧版一致。
  final File? Function()? dbFile;

  /// R5a：附件同步根（note_images / book_covers）。空 = 不并入附件。
  final List<AttachRoot> attachRoots;

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
  /// [force]=true 跳过快照复用判定，必出新包（手动「立即备份」类入口预留）。
  Future<SyncSnapshotResult> build({int? keepN, bool force = false}) async {
    final n = effectiveKeepN(keepN);
    final dir = syncDir;
    Directory(dir).createSync(recursive: true);
    // R3②：活库自最新快照后没有任何写入 → 复用，不再「每点一次同步多一个
    // lhbak」。判定只用 mtime 大小关系（快照晚于/等于库即视为新鲜），
    // -wal 存在时一并取 max（防未来开 WAL 后漏判）。
    if (!force) {
      final reuse = _freshSnapshotOrNull();
      if (reuse != null) {
        AppLog.add('数据库无新写入 · 复用最新快照'
            '（${p.basename(reuse.path)}）');
        return SyncSnapshotResult(
            file: reuse, manifest: null, pruned: const [], reused: true);
      }
    }
    final excluded = await _careExcludedSafe() ? DbSchema.careTables : const <String>[];
    // R5a：同步快照 = 纯 DB（不含日志、不含附件——图片经 attachRoots 以
    // 独立文件走文件级增量，历史图片不再随包重传）。手动备份 S5 不受影响，
    // 仍是全量整包（含附件/可选日志）。
    final res = await backup.exportBackup(
      withLogs: false,
      withAttachments: false,
      outDirOverride: dir,
      excludeTables: excluded,
      nameTag: 'sync',
    );
    final pruned = await pruneSnapshots(keepN: n, protect: res.file.path);
    return SyncSnapshotResult(file: res.file, manifest: res.manifest, pruned: pruned);
  }

  /// 可复用的最新快照：sync/ 内 mtime 最新的快照命名文件，且其 mtime
  /// ≥ 活库（含 -wal）mtime；任一前提缺失（无 dbFile/无快照/读 stat 失败）
  /// 一律返回 null 走真实生成——宁多出一个快照，绝不同步陈旧数据。
  File? _freshSnapshotOrNull() {
    File? db;
    try {
      db = dbFile?.call();
    } catch (_) {
      return null;
    }
    if (db == null || !db.existsSync()) return null;
    final dir = Directory(syncDir);
    if (!dir.existsSync()) return null;
    File? latest;
    int latestM = -1;
    for (final f in dir.listSync().whereType<File>()) {
      if (!isSyncSnapshotName(p.basename(f.path))) continue;
      final m = _mtimeOf(f);
      if (m > latestM) {
        latest = f;
        latestM = m;
      }
    }
    if (latest == null) return null;
    var dbM = _mtimeOf(db);
    final wal = File('${db.path}-wal');
    if (wal.existsSync()) dbM = dbM > _mtimeOf(wal) ? dbM : _mtimeOf(wal);
    return latestM >= dbM ? latest : null;
  }

  /// 本地侧清单：sync/ 全量 + R5a 附件根（`attachments/<cloudName>/…` 前缀），
  /// 产出可直接喂 `computeDiff` / `SyncLedger.record` 的 [FileEntry] 列表。
  /// [withDigest]＝服务配置「允许严格校验（MD5）」开（缺口盘点批 #7）：逐本地文件
  /// 计算 MD5 摘要随行，diff 引擎在远端 etag 为 32-hex 时走严格档；关＝digest=null
  /// （严格档自动关闭，同 R8 降级口径）；附件根单文件 >64MB 跳过摘要（超大件成本闸门）。
  /// relativePath 以 sync/ 为根、posix 分隔、非空保证（basename 兜底）。
  /// 相对路径 → 本机绝对路径（批②b B-2 预览用·纯字符串映射，不触文件系统）。
  /// 口径与 [localInventory] 完全一致：`attachments/<cloudName>/…` 反查附件根，
  /// 其余落 [syncDir]；前缀不认识（如仅云端条目的假想路径）返回 null，
  /// 调用侧据此**不给热区**——本机没有的文件绝不画成可点。
  String? localPathOf(String relativePath) {
    const pre = 'attachments/';
    if (relativePath.startsWith(pre)) {
      final rest = relativePath.substring(pre.length);
      for (final root in attachRoots) {
        final tag = '${root.cloudName}/';
        if (rest.startsWith(tag)) {
          return p.join(root.localDir, rest.substring(tag.length));
        }
      }
      return null;
    }
    return p.join(syncDir, relativePath);
  }

  Future<List<FileEntry>> localInventory({bool withDigest = false}) async {    final out = <FileEntry>[];
    _collectInto(out, Directory(syncDir), '', withDigest);
    for (final root in attachRoots) {
      _collectInto(out, Directory(root.localDir),
          'attachments/${root.cloudName}', withDigest);
    }
    out.sort((a, b) => a.relativePath.compareTo(b.relativePath));
    return out;
  }

  void _collectInto(List<FileEntry> out, Directory dir, String relPrefix,
      bool withDigest) {
    if (!dir.existsSync()) return;
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
        String? digest;
        if (withDigest) {
          digest = _md5Of(e);
        }
        out.add(FileEntry(
          relativePath: relPrefix.isEmpty ? rel : '$relPrefix/$rel',
          size: e.lengthSync(),
          modified: mtime,
          digest: digest,
        ));
      }
    } catch (_) {
      // 目录中途不可读：按已收集部分返回，绝不炸同步链路。
    }
  }

  static const int _digestMaxBytes = 64 * 1024 * 1024;

  /// 单文件 MD5；超大件/读失败返回 null（该文件回落保守档，不判不等）。
  static String? _md5Of(File f) {
    try {
      if (f.lengthSync() > _digestMaxBytes) return null;
      return crypto.md5.convert(f.readAsBytesSync()).toString();
    } catch (_) {
      // catch-ok: 单文件读失败/超大只回「无摘要」，差异对比自动降级到字节数·强 ETag 档；
      // 逐文件记日志会在大库上刷屏，整体失败已由 _collectInto 上层留痕。
      return null;
    }
  }

  /// R5a：差异条目相对路径 → 本地绝对路径（上传取源）。
  /// `attachments/…` 命中附件根映射；其余落 sync/ 下。
  String resolveLocal(String relativePath) {
    if (relativePath.startsWith('attachments/')) {
      final rest = relativePath.substring('attachments/'.length);
      for (final root in attachRoots) {
        if (rest.startsWith('${root.cloudName}/')) {
          return p.joinAll([
            root.localDir,
            ...p.posix.split(rest.substring(root.cloudName.length + 1)),
          ]);
        }
      }
    }
    return p.joinAll([syncDir, ...p.posix.split(relativePath)]);
  }

  /// R5a：下载目的地解析。附件条目**直落媒体目录**（内容寻址命名 +
  /// 「同名同大小即跳过」保证幂等，图片到位即可被 App 引用）；
  /// 同名但大小不同（历史时间戳名撞车，理论极小概率）→ 回落 exports
  /// 隔离区并 warn，绝不覆盖既有文件；非附件条目返回 null（调用方走 exports）。
  String? resolveDownload(String relativePath, int size) {
    if (!relativePath.startsWith('attachments/')) return null;
    final rest = relativePath.substring('attachments/'.length);
    for (final root in attachRoots) {
      if (rest.startsWith('${root.cloudName}/')) {
        final dest = p.joinAll([
          root.localDir,
          ...p.posix.split(rest.substring(root.cloudName.length + 1)),
        ]);
        final f = File(dest);
        if (f.existsSync()) {
          if (f.lengthSync() == size) return dest; // 幂等跳过标记：同路径
          AppLog.add('附件同名不同大小，落导出区隔离：$relativePath',
              level: LhLevel.warn);
          return null;
        }
        return dest;
      }
    }
    return null;
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
