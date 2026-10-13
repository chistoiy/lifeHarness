/// `BackupService`（Task 10）：`.lhbak` 导出/导入恢复的应用服务层。
///
/// 口径（设计稿 §3 / brief）：
/// - 导出走 [LhBak.create]（活库 VACUUM INTO 一致性快照，不拷活文件）；
///   目录与库全部构造注入——生产侧在 main 组根接 path_provider 与
///   [AppDatabase]，测试侧接临时目录 + ffi 库（模式照记账 L15 dirOverride）。
/// - 导入顺序钉死：**verify → 恢复前自动备份（auto_before_restore_*，
///   只落应用导出目录、永不进同步目录）→ close → unpack → reopen → 报告**。
///   前置校验失败时现库一字节不动；unpack 中途失败时现库已被 close，
///   失败路径重开原库恢复现场（事务回滚 + 自动备份先行，原库文件未受污染）
///   后冒泡异常。
/// - 「另存到…」（SAF，2026-10-04 轮6 起走自研 `lh/saf` 通道）：先落应用目录
///   再由用户经系统「创建文档」选任意位置；取消=null；上次成功目标仅记
///   prefs `backup_last_save_hint` 供展示，不做常驻目录授权。
///   （旧实现 flutter_file_dialog 在进程被杀后冷启动投递结果时 NPE 崩溃、
///   目标停 0 字节——根因与证据见 lib/core/platform/saf.dart 文件头。）
/// - 对话框钩子 [saveAsDialog]/[pickFileHook] 为可替换静态字段
///   （模式照 `LhBak.snapshotFactory`），widget/单测注入 fake。
library;

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../database/schema.dart';
import '../logging/app_log.dart';
import '../logging/file_log_sink.dart';
import '../platform/saf.dart';
import '../settings/settings_repository.dart';
import '../../../shared/linkage/export_units.dart';
import 'lh_bak.dart';

/// 「保存为」系统弹层钩子签名：入参 = 已生成的备份文件路径；
/// 返回用户选定位置的显示文件名（轮6 起，旧插件返回的是 content URI 路径），
/// 取消 = null；失败抛异常（由 UI 兜底可见）。
typedef SaveAsHandler = Future<String?> Function(String srcPath);

/// 备份文件选择器钩子签名：返回选中路径，取消 = null。
typedef PickBackupHandler = Future<String?> Function();

/// unpack 实现钩子（测试注入中途失败场景；null = 走 [LhBak.unpack]）。
typedef UnpackImpl = Future<LhBakManifest> Function({
  required String filePath,
  required Database targetDb,
  String? passphrase,
});

/// 上次成功「另存到…」目标的展示提示串（仅 UI 提示，不回写权限）。
const String kBackupLastSaveHintKey = 'backup_last_save_hint';

/// 恢复前自动备份的 nameTag（命名 `auto_before_restore_*.lhbak`）。
const String kAutoBeforeRestoreTag = 'auto_before_restore';

/// [BackupService.attachRootDirs] 浅扫白名单扩展名（documents 根目录
/// 直落文件才入包：记账导出 `lifeharness_ledger.csv/.json` 及未来同层
/// 导出件；logs/backup 等子目录内容不在此通道，防误收）。
const Set<String> kRootAttachExts = {'.csv', '.json', '.md'};

/// 备份/同步快照**恒排除**的可再生派生表（轮7 拍板 2026-10-04：X-Ray
/// 全书解析产物按书可在阅读器重新解析生成——真机实测占全库 97.3%，
/// 入包纯膨胀）。用户养成的词库 `xray_userdict` 不在其列，照常入包。
/// 恢复后 unpack 按当前 schema 建空表（报告 missingTables），解析随用随补。
const List<String> kRegenerableExcluded = [
  DbSchema.tXrayMention,
  DbSchema.tXrayEntity,
  DbSchema.tXrayTask,
];

/// [BackupService.importBackup] 成功后的恢复报告（UI 据此渲染，
/// 含 skippedLarge——导入报告必须列出「N 个超大附件未入包」）。
class RestoreReport {
  const RestoreReport({
    required this.tableCount,
    required this.totalRows,
    required this.missingTables,
    required this.skippedLarge,
    required this.autoBackupPath,
    this.restoredAttachmentFiles = 0,
    this.configRestored = false,
  });

  /// 包内恢复的表数。
  final int tableCount;

  /// 包内恢复的总行数。
  final int totalRows;

  /// 当前 schema 有而包内没有的表（unpack 按当前 schema 建空表）。
  final List<String> missingTables;

  /// manifest.skippedLarge：加密包因超单文件上限未入包的附件成员名。
  final List<String> skippedLarge;

  /// 本次恢复前生成的自动备份路径（app 导出目录内）。
  final String? autoBackupPath;

  /// V1.66 P0-1：附件落盘还原的实际文件数（组在包内才动作；0＝包内无附件组）。
  final int restoredAttachmentFiles;

  /// V1.66 批2：包内 `config/settings.json` 是否已应用（旧 v1 包恒 false）。
  final bool configRestored;
}

/// 备份导出/导入恢复服务（目录/库/对话框全注入，可测）。
class BackupService {
  BackupService({
    required this.exportDir,
    required this.db,
    this.attachDirs = const [],
    this.attachRootDirs = const [],
    this.closeDb,
    this.prefs,
    this.healthExcluded,
  });

  /// 应用导出目录（生产 = `<docs>/backup`，测试 = 临时目录）。
  final String Function() exportDir;

  /// 当前库提供者（生产 = `AppDatabase.instance.open`；配合 [closeDb]
  /// 关闭清缓存后再调即拿到新可用连接）。
  final Future<Database> Function() db;

  /// 库关闭器（生产 = `AppDatabase.instance.close`，close 后置空 _db）。
  /// 评审修复（Critical）：裸 [Database.close] 不清 AppDatabase 缓存句柄，
  /// 之后 db() 仍拿到死句柄。null = 测试注入路径（每次 db() 新开连接，
  /// 直接关当次连接即可）。
  final Future<void> Function()? closeDb;

  /// 附件子目录清单（整目录递归，成员名 `attachments/<目录名>/<相对路径>`）。
  /// 取证 V1.41 Task 10：应用文档目录下实际落盘子目录 =
  /// note_images / book_covers / exports / share（见 task-10-report）。
  final List<String> attachDirs;

  /// 附件「根目录浅扫」清单（评审修复：记账导出
  /// `lifeharness_ledger.csv/.json` 直接落 documents 根，不在子目录）。
  /// 收集口径：仅浅一层、仅白名单扩展名 [kRootAttachExts]，
  /// 成员名 `attachments/<文件名>`。
  final List<String> attachRootDirs;

  /// 仅用于记录「另存到…」上次成功目标提示串（可空 = 测试不关心）。
  final SharedPreferences? prefs;

  /// 健康模块「随本地备份」的反向读取器（批6b · 需求 176 行，形状照组合根给
  /// `SnapshotService.careExcluded` 的那枚）：返回 true＝健康十四表不进本地包。
  /// core 不得 import features，所以这里只吃函数，由 `main.dart` 接
  /// `HealthSettings.includeInBackup()`；null＝不启用（测试与旧调用侧行为不变）。
  ///
  /// 只管**本地备份**：同步快照那条腿显式关掉这枚（`applyHealthExclusion: false`），
  /// 因为「本地不进包」与「上不上云」是两件事——云端另有 `care.syncExcluded` 的形，
  /// 健康侧目前没有对应的同步开关。
  final bool Function()? healthExcluded;

  // ---- 可替换对话框钩子（模式照 LhBak.snapshotFactory）----

  /// 「保存为」系统弹层实现（生产 = 自研 `lh/saf` 通道，SAF「创建文档」）。
  static SaveAsHandler saveAsDialog = defaultSaveAsDialog;
  static final SaveAsHandler defaultSaveAsDialog = safSaveAs;

  /// 备份文件选择器实现（生产 file_picker，SAF 自动缓存副本按路径处理）。
  /// 2026-10-04 真机缺陷根治：`lhbak` 是自造扩展名、不在 Android MIME 表，
  /// FileType.custom 会被插件判 Unsupported filter 抛 PlatformException
  /// （选择器根本不弹、异常被 async 通道吞＝「点了没反应」）。
  /// 现先试过滤版，失败降级 [FileType.any]——选中后仍由 inspect() 校验包合法性。
  static PickBackupHandler pickFileHook = defaultPickFile;
  static final PickBackupHandler defaultPickFile = _pickViaFilePicker;

  /// file_picker 薄注入点（单测验降级路径；生产 = 平台通道直调）。
  static Future<FilePickerResult?> Function(FileType type, List<String>? exts)
      pickFilesImpl = (type, exts) => FilePicker.platform.pickFiles(
          type: type, allowedExtensions: exts, withData: false);

  /// 非 null 时替代 [LhBak.unpack]（仅供测试注入「中途失败」路径）。
  static UnpackImpl? unpackOverride;

  /// md 投影钩子（V1.66 批2·组合根装配）：库连接 + 所选模块集 → 成员名→文本。
  /// R2：core 不碰 features——投影器在 `shared/linkage/backup_projection.dart`，
  /// 由 main.dart 注入；null＝不生成 notes 成员（单测默认，行为确定）。
  static Future<Map<String, String>> Function(Database db,
      {required Set<String> moduleIds})? projectionHook;

  /// 上次「另存到…」成功目标（仅展示用）。
  String? get lastSaveHint => prefs?.getString(kBackupLastSaveHintKey);

  /// 健康排除读取兜底（与 `SnapshotService._careExcludedSafe` **反向**钉死）：
  /// 读取失败按 **false**（＝照常含进包）＋ warn。
  /// 理由：本地包少一张表＝用户以为备份了却没备到（不可逆的数据面缺口）；
  /// 含进去只是本机多存一份，随时能再关掉。同步那条腿的兜底之所以取反，
  /// 是因为它多传＝隐私外流，两害不同级。
  bool _healthExcludedSafe() {
    final f = healthExcluded;
    if (f == null) return false;
    try {
      return f();
    } catch (e) {
      AppLog.add('健康备份开关读取失败，照常含进包：$e', level: LhLevel.warn);
      return false;
    }
  }

  /// 导出备份：默认全量（含呵护表——红线 7 排除的是同步不是备份）。
  ///
  /// - [withLogs]：随包 [FileLogSink.dayFiles] 全部落盘日志（含分卷）。
  /// - [withAttachments]：随包 [attachDirs] 清单目录。
  /// - [passphrase]：非空 = AES-GCM 口令加密档（V1.66 起 UI 出包恒明文，
  ///   本参数仅为旧链路与测试保留）。
  /// - [excludeTables]/[outDirOverride]：批4 SnapshotService 复用于产同步快照。
  /// - [applyHealthExclusion]：false＝无视健康本地备份开关（同步快照那条腿用，
  ///   见 `SnapshotService.build` 的注释）。
  /// - [nameTag]：非空时改名 `<nameTag>_YYYYMMDD_HHmmss.lhbak`
  ///   （恢复前自动备份 = `auto_before_restore_*`）。
  /// - [modules]（V1.66 批2）：所选模块 id 清单（[kExportUnits] 的 id）；
  ///   **空 = 全部数据**（口径与改造前完全一致）。非空 = 子集出口——排除表
  ///   用活库表名差集法（实表 − 所选单元表并集，面板钉子1），附件只收所选
  ///   模块映射目录，根目录散件（历史导出物）不收。
  /// - [withProjection]（V1.66 批2）：true = 包内带可读成员
  ///   `config/settings.json`（口径设置·零凭据）与 `notes/` md 投影
  ///   （[withMd] 关＝只无 notes/）。默认 **false**＝恢复前自动备份等
  ///   回退件不背投影；ExportSheet / 另存到 / 同步快照传 true。
  /// - [withMd]：仅 [withProjection] 为 true 时有意义（见上）。
  Future<LhBakCreateResult> exportBackup({
    bool withLogs = false,
    bool withAttachments = true,
    String? passphrase,
    List<String> excludeTables = const [],
    String? outDirOverride,
    String? nameTag,
    bool applyHealthExclusion = true,
    List<String> modules = const [],
    bool withProjection = false,
    bool withMd = true,
  }) async {
    // L1 日志批：备份导出全程可查（成功=key 带终名与表数；失败=error 带成因）。
    try {
      final out = outDirOverride ?? exportDir();
      final database = await db();
      List<String> logFiles = const [];
      if (withLogs) {
        final dir = FileLogSink.dirPath;
        if (dir != null) {
          logFiles = (await FileLogSink.dayFiles())
              .map((name) => p.join(dir, name))
              .toList();
        }
      }
      // 轮7 拍板：调用方排除表 ∪ 健康本地备份排除（批6b）∪ 可再生派生表
      // （X-Ray 全书索引等），恒不进包；manifest.excludedTables 据实登记，恢复报告可见。
      final healthEx = applyHealthExclusion && _healthExcludedSafe()
          ? DbSchema.healthTables
          : const <String>[];
      // V1.66 批2 面板钉子1：子集范围＝活库实表差集（注册表漏列只会「多备
      // 不少备」，绝不误删数据）。
      final scopeEx = modules.isEmpty
          ? const <String>[]
          : await _liveTablesMinus(database, exportTablesForModules(modules));
      final effExcludes = {
        ...excludeTables,
        ...scopeEx,
        ...healthEx,
        ...kRegenerableExcluded
      }.toList()
        ..sort();
      // 附件腿：子集只收所选模块映射目录；根目录散件（历史导出物）仅全量收。
      final keepDirs =
          modules.isEmpty ? null : exportAttachDirsForModules(modules);
      final List<String> dirs = withAttachments
          ? (keepDirs == null
              ? attachDirs
              : [
                  for (final d in attachDirs)
                    if (keepDirs.contains(p.basename(d))) d
                ])
          : const [];
      final rootAttach = withAttachments && modules.isEmpty
          ? collectRootAttachFiles()
          : const <String>[];
      // 可读成员：config 恒入（投影开关开时）；notes/ md 走组合根注入钩子
      // （R2：core 不碰 features，投影器在 shared/linkage，main 装配）。
      final extraFiles = <String, String>{};
      if (withProjection) {
        if (prefs != null) {
          try {
            final settingsJson = const JsonEncoder.withIndent('  ')
                .convert(SettingsRepository(prefs!).exportAll());
            extraFiles['config/settings.json'] = settingsJson;
          } catch (e) {
            AppLog.add('口径设置序列化失败（包内无 config 成员）：$e',
                level: LhLevel.warn);
          }
        }
        if (withMd) {
          final hook = projectionHook;
          if (hook != null) {
            try {
              extraFiles
                  .addAll(await hook(database, moduleIds: modules.toSet()));
            } catch (e) {
              AppLog.add('md 投影生成失败（包内无 notes 成员）：$e',
                  level: LhLevel.warn);
            }
          }
        }
      }
      var res = await LhBak.create(
        db: database,
        outDirPath: out,
        attachDirs: dirs,
        attachFiles: rootAttach,
        logFiles: logFiles,
        excludeTables: effExcludes,
        passphrase: passphrase,
        extraFiles: extraFiles,
      );
      if (nameTag != null && nameTag.isNotEmpty) {
        final base = p.basename(res.file.path);
        final stem = base.startsWith('lifeharness')
            ? base.substring('lifeharness'.length)
            : '_$base';
        // 同目录同名（同秒二次自动备份）不覆盖——去重命名后再搬移。
        final dir = p.dirname(res.file.path);
        final target =
            File(p.join(dir, uniqueFileNameInDir(dir, '$nameTag$stem')));
        res = LhBakCreateResult(
          await res.file.rename(target.path),
          res.manifest,
        );
      }
      AppLog.addKey(
        '备份导出成功：${p.basename(res.file.path)} · 表 ${res.manifest.tables.length} 张'
        '${effExcludes.isNotEmpty ? ' · 排除 ${effExcludes.length} 张' : ''}'
        '${modules.isNotEmpty ? ' · 范围 ${modules.join("+")}' : ''}'
        '${extraFiles.isNotEmpty ? ' · 可读成员 ${extraFiles.length}' : ''}'
        '${passphrase != null ? ' · 口令加密' : ''}',
      );
      return res;
    } catch (e, st) {
      AppLog.add('备份导出失败：$e', level: LhLevel.error, src: '备份');
      AppLog.addStack(st.toString(), src: '备份');
      rethrow;
    }
  }

  /// 活库实表 − [keep] ＝ 子集导出的排除清单（`sqlite_%` 内部表不在扫描面）。
  Future<List<String>> _liveTablesMinus(Database database, Set<String> keep) async {
    final rows = await database.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' "
        "AND name NOT LIKE 'sqlite_%'");
    return [
      for (final r in rows)
        if (!keep.contains(r['name'])) r['name'] as String,
    ]..sort();
  }

  /// 预估口径的恒排除表（与 [measureIncludedDbBytes] 的 DROP 集一致；
  /// ExportSheet 子集比例的分母也用它，口径同源）。
  List<String> estimateExcludedTables() => [
        ...kRegenerableExcluded,
        if (_healthExcludedSafe()) ...DbSchema.healthTables,
      ];

  // ---- 导出位置（V1.66 装机回知批：持久 SAF 目录树，null＝默认应用目录）----

  static const _kExportTreeUri = 'lh.export_tree_uri';
  static const _kExportTreeName = 'lh.export_tree_name';

  /// 已设导出位置（SAF tree URI）；null＝未设，导出落应用目录。
  String? get exportTreeUri => prefs?.getString(_kExportTreeUri);

  /// 人话目录名（tree URI documentId 去卷前缀，如 `Download/lifeHarness`）。
  String? get exportTreeName => prefs?.getString(_kExportTreeName);

  /// 设/清导出位置（null＝清，回默认应用目录）。
  Future<void> setExportTree(String? uri) async {
    if (uri == null || uri.isEmpty) {
      await prefs?.remove(_kExportTreeUri);
      await prefs?.remove(_kExportTreeName);
      return;
    }
    await prefs?.setString(_kExportTreeUri, uri);
    await prefs?.setString(_kExportTreeName, treeDisplayName(uri));
  }

  /// tree URI → 人话目录名：`content://…/tree/primary%3ADownload%2Flh` 里取
  /// documentId（`primary:Download/lh`）去卷前缀。纯字符串解析，不动 IO。
  static String treeDisplayName(String uri) {
    final i = uri.indexOf('tree/');
    if (i < 0) return '所选目录';
    final id = Uri.decodeComponent(uri.substring(i + 5));
    final c = id.indexOf(':');
    return (c >= 0 && c + 1 < id.length) ? id.substring(c + 1) : id;
  }

  /// V1.66 预估修正（6120 装机回知）：活库文件大头是可再生索引（X-Ray 全书
  /// 解析产物真机实测占全库 97.3%，打包时快照里恒 DROP），包体再经 zip 压缩
  /// ——按原文件大小预估会把 2.5MB 实包说成 37MB。这里与实包同口径实测：
  /// `VACUUM INTO` → DROP 恒排除表 → gzip 压缩实测（gzip≈zip deflate 档）。
  /// TTL 10 分钟缓存（「约」字口径，同会话内复用）；失败抛错由调用方兜底。
  static ({int bytes, DateTime at})? _includedDbMeasure;
  Future<int> measureIncludedDbBytes(Database database) async {
    final cached = _includedDbMeasure;
    if (cached != null &&
        DateTime.now().difference(cached.at) < const Duration(minutes: 10)) {
      return cached.bytes;
    }
    final temp = Directory.systemTemp.createTempSync('lhbak_est_');
    try {
      final snapPath = p.join(temp.path, 'db.sqlite');
      await database
          .execute("VACUUM INTO '${snapPath.replaceAll("'", "''")}'");
      final liveRows = await database.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' "
          "AND name NOT LIKE 'sqlite_%'");
      final dropSet = estimateExcludedTables().toSet();
      final snap = await LhBak.snapshotFactory.openDatabase(snapPath);
      try {
        var dropped = 0;
        for (final r in liveRows) {
          final t = r['name'] as String;
          if (dropSet.contains(t)) {
            await snap.execute('DROP TABLE IF EXISTS "$t"');
            dropped++;
          }
        }
        // 与 LhBak.create 同口径：DROP 后补 VACUUM 收净 freelist 陈旧页，
        // 预估才反映真实在包内容（DROP 只挂链不缩文件，见 lh_bak 同注）。
        if (dropped > 0) {
          await snap.execute('VACUUM');
        }
      } finally {
        await snap.close();
      }
      final bytes = gzip.encode(await File(snapPath).readAsBytes()).length;
      _includedDbMeasure = (bytes: bytes, at: DateTime.now());
      return bytes;
    } finally {
      try {
        temp.deleteSync(recursive: true);
      } catch (_) {}
    }
  }

  /// [attachRootDirs] 浅扫：仅一层文件、仅白名单扩展名 [kRootAttachExts]。
  /// 记账导出 `lifeharness_ledger.csv/.json` 直落 documents 根，不在
  /// attachDirs 子目录通道内（评审 Important 修复：附件取证遗漏）；
  /// 浅扫+白名单防误收（backup/logs 子目录与 .db 等不入包）。
  /// 目录不存在/读取异常 → 跳过，不阻塞导出。
  List<String> collectRootAttachFiles() {
    final found = <String>[];
    for (final root in attachRootDirs) {
      try {
        for (final e in Directory(root).listSync(followLinks: false)) {
          if (e is! File) continue;
          if (kRootAttachExts.contains(p.extension(e.path).toLowerCase())) {
            found.add(e.path);
          }
        }
      } catch (_) {
        // 根目录不可读：按无根附件处理。
      }
    }
    found.sort((a, b) => a.compareTo(b));
    return found;
  }

  /// 只读校验包（导入 UI 的「校验报告态」数据源）：坏包冒泡 [LhBakException]。
  Future<LhBakManifest> inspect(String filePath, {String? passphrase}) async {
    try {
      final m = await LhBak.verify(filePath, passphrase: passphrase);
      AppLog.addKey('备份校验通过：${p.basename(filePath)} · 表 ${m.tables.length} 张');
      return m;
    } catch (e) {
      AppLog.add('备份校验失败：$e', level: LhLevel.error);
      rethrow;
    }
  }

  /// 把已生成的备份文件经系统「保存为」弹层另存到用户自选位置。
  /// 用户取消 = null（不做任何后续动作）；成功记 prefs 提示串。
  Future<String?> saveCopyToUserLocation(String srcPath) async {
    final saved = await saveAsDialog(srcPath);
    if (saved != null) {
      try {
        await prefs?.setString(kBackupLastSaveHintKey, saved);
      } catch (_) {
        // 提示串写失败不影响另存结果（仅展示用）。
      }
    }
    return saved;
  }

  /// 选择备份文件（SAF 选择自动缓存副本，后续按路径处理不整读内存）。
  /// 取消 = null；未知扩展名被平台拒时降级全文件选择（见 [_pickViaFilePicker]），
  /// 仍抛出的异常由 UI 层兜底可见提示（2026-10-04 起，不再承诺「导出记录 tab」）。
  Future<String?> pickBackupFile() => pickFileHook();

  /// 导入恢复（整库替换，不做记录级合并）。顺序钉死，见文件头注释。
  Future<RestoreReport> importBackup(String filePath,
      {String? passphrase}) async {
    // L1 日志批：恢复前置备份/校验/解包失败全部落日志（现场重开也记）。
    AppLog.addKey('备份导入开始：${p.basename(filePath)}');
    // 1) 前置校验：坏包在这里拒绝，现库一字节不动。
    try {
      await LhBak.verify(filePath, passphrase: passphrase);
    } catch (e) {
      AppLog.add('备份校验失败（现库未动）：$e', level: LhLevel.error);
      rethrow;
    }
    // 2) 恢复前自动备份：close 之前完成 → 原库文件此后不再被触碰。
    final auto = await exportBackup(nameTag: kAutoBeforeRestoreTag);
    // 3) close → unpack → reopen。
    //    close 必须走 [closeDb]（生产 = AppDatabase.instance.close：关连接
    //    且置空 _db 缓存）——评审 Critical：裸 Database.close 后 AppDatabase
    //    .open() 短路返回缓存死句柄，unpack 会在已关库上执行。
    //    closeDb=null（测试注入路径）：db() 每次新开连接，关当次即可。
    final closer = closeDb;
    if (closer != null) {
      await closer();
    } else {
      final current = await db();
      await current.close();
    }
    Database? working;
    LhBakManifest manifest;
    try {
      working = await db();
      final unpack = unpackOverride ?? LhBak.unpack;
      manifest = await unpack(
          filePath: filePath, targetDb: working, passphrase: passphrase);
    } catch (e, st) {
      // L1：解包失败先记成因，再做现场清理（清理自身失败也记）。
      AppLog.add('备份解包失败（即将重开原库恢复现场）：$e',
          level: LhLevel.error);
      AppLog.addStack(st.toString());
      // 恢复失败路径：清理必须与成功路径同一注入通道——closeDb 非空
      // （生产）时调 closer（= AppDatabase.instance.close：关连接且置空
      // _db 缓存），裸 working.close() 会留下缓存死句柄让 db() 短路返回、
      // 「重开原库恢复现场」失效；closer=null（测试注入路径）关当次连接。
      // 之后 db() 重开原库（unpack 全在事务内，失败即回滚，原库文件未受
      // 污染）后冒泡异常。
      try {
        if (closer != null) {
          await closer();
        } else {
          await working?.close();
        }
      } catch (_) {}
      try {
        await db(); // 重开并保持实例可用（生产 = _db 已置空 → 新开连接）
      } catch (e2) {
        // 重开失败不掩盖原始异常（L1：但必须留痕，否则现场无从取证）。
        AppLog.add('备份导入后原库重开失败：$e2', level: LhLevel.error);
      }
      rethrow;
    }
    AppLog.addKey(
      '备份导入成功：表 ${manifest.tables.length} 张 · 共 '
      '${manifest.tables.values.fold<int>(0, (a, t) => a + t.rows)} 行'
      '${manifest.missingTables.isNotEmpty ? ' · 缺表 ${manifest.missingTables.join(",")}' : ""}',
    );
    // V1.66 P0-1：附件腿——DB 恢复成功后按包内 attachments/ 落盘还原。
    // 目录组＝attachDirs 基名→原目录（组在包内才清旧目录）；散件＝
    // attachRootDirs 根目录（只覆盖不清理，根目录混有非附件文件）。
    // 失败 fail loud：自动备份已先行，用户可回退后重试（评估件 P0 口径）。
    var restoredFiles = 0;
    try {
      restoredFiles = await LhBak.restoreAttachments(
        filePath: filePath,
        dirTargets: {
          for (final d in attachDirs) p.basename(d): d,
        },
        rootFilesTarget:
            attachRootDirs.isEmpty ? null : attachRootDirs.first,
        passphrase: passphrase,
      );
      if (restoredFiles > 0) {
        AppLog.addKey('备份附件落盘还原：$restoredFiles 个文件');
      }
    } catch (e, st) {
      AppLog.add('附件落盘恢复失败（DB 已替换，可用恢复前自动备份回退）：$e',
          level: LhLevel.error, src: '备份');
      AppLog.addStack(st.toString(), src: '备份');
      rethrow;
    }
    // V1.66 批2：口径设置腿——包内 config/settings.json（若在）经
    // SettingsRepository.importAll 应用。**失败 warn 不炸恢复**（面板钉子4）：
    // config＝投影非权威，DB 与附件已落定，fail loud 会把好数据堵在门外；
    // 旧 v1 包无该成员＝静默跳过（null）。prefs 未注入（单测）＝跳过。
    var configRestored = false;
    if (prefs != null) {
      try {
        final text = await readMemberText(
            filePath, 'config/settings.json',
            passphrase: passphrase);
        if (text != null) {
          await SettingsRepository(prefs!)
              .importAll(jsonDecode(text) as Map<String, Object?>);
          configRestored = true;
          AppLog.addKey('备份口径设置恢复：config/settings.json 已应用');
        }
      } catch (e) {
        AppLog.add('口径设置恢复失败（DB 已替换，继续返回报告）：$e',
            level: LhLevel.warn);
      }
    }
    return RestoreReport(
      tableCount: manifest.tables.length,
      totalRows:
          manifest.tables.values.fold<int>(0, (a, t) => a + t.rows),
      missingTables: manifest.missingTables,
      skippedLarge: manifest.skippedLarge ?? const [],
      autoBackupPath: auto.file.path,
      restoredAttachmentFiles: restoredFiles,
      configRestored: configRestored,
    );
  }

  // ---- 生产侧默认实现（测试被钩子替换，不触平台通道）----

  static Future<String?> _pickViaFilePicker() async {
    FilePickerResult? result;
    try {
      result = await pickFilesImpl(FileType.custom, const ['lhbak']);
    } on PlatformException catch (e) {
      // 未知扩展名被拒 → 降级全文件选择（不再静默）。降级本身留痕可查。
      AppLog.add('备份选择器扩展名被平台拒（降级全文件）：$e',
          level: LhLevel.warn);
      result = await pickFilesImpl(FileType.any, null);
    }
    if (result == null || result.files.isEmpty) return null;
    return result.files.single.path;
  }
}
