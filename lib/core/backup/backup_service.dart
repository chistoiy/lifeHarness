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
/// - 「另存到…」（SAF，2026-09-25 增补）：先落应用目录再经
///   `flutter_file_dialog.saveFile` 由用户选任意位置；取消=null；上次成功
///   目标仅记 prefs `backup_last_save_hint` 供展示，不做常驻目录授权。
/// - 对话框钩子 [saveAsDialog]/[pickFileHook] 为可替换静态字段
///   （模式照 `LhBak.snapshotFactory`），widget/单测注入 fake。
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../logging/file_log_sink.dart';
import 'lh_bak.dart';

/// 「保存为」系统弹层钩子签名：入参 = 已生成的备份文件路径；
/// 返回用户选定路径，取消 = null。
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

/// [BackupService.importBackup] 成功后的恢复报告（UI 据此渲染，
/// 含 skippedLarge——导入报告必须列出「N 个超大附件未入包」）。
class RestoreReport {
  const RestoreReport({
    required this.tableCount,
    required this.totalRows,
    required this.missingTables,
    required this.skippedLarge,
    required this.autoBackupPath,
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
}

/// 备份导出/导入恢复服务（目录/库/对话框全注入，可测）。
class BackupService {
  BackupService({
    required this.exportDir,
    required this.db,
    this.attachDirs = const [],
    this.prefs,
  });

  /// 应用导出目录（生产 = `<docs>/backup`，测试 = 临时目录）。
  final String Function() exportDir;

  /// 当前库提供者（生产 = `AppDatabase.instance.open`：close 后再调即重开）。
  final Future<Database> Function() db;

  /// 附件根目录清单（成员名 `attachments/<目录名>/<相对路径>`）。
  /// 取证 V1.41 Task 10：应用文档目录下实际落盘子目录 =
  /// note_images / book_covers / exports / share（见 task-10-report）。
  final List<String> attachDirs;

  /// 仅用于记录「另存到…」上次成功目标提示串（可空 = 测试不关心）。
  final SharedPreferences? prefs;

  // ---- 可替换对话框钩子（模式照 LhBak.snapshotFactory）----

  /// 「保存为」系统弹层实现（生产经 flutter_file_dialog SAF 创建文档）。
  static SaveAsHandler saveAsDialog = defaultSaveAsDialog;
  static final SaveAsHandler defaultSaveAsDialog = _saveViaFileDialog;

  /// 备份文件选择器实现（生产 file_picker，SAF 自动缓存副本按路径处理）。
  static PickBackupHandler pickFileHook = defaultPickFile;
  static final PickBackupHandler defaultPickFile = _pickViaFilePicker;

  /// 非 null 时替代 [LhBak.unpack]（仅供测试注入「中途失败」路径）。
  static UnpackImpl? unpackOverride;

  /// 上次「另存到…」成功目标（仅展示用）。
  String? get lastSaveHint => prefs?.getString(kBackupLastSaveHintKey);

  /// 导出备份：默认全量（含呵护表——红线 7 排除的是同步不是备份）。
  ///
  /// - [withLogs]：随包 [FileLogSink.dayFiles] 全部落盘日志（含分卷）。
  /// - [withAttachments]：随包 [attachDirs] 清单目录。
  /// - [passphrase]：非空 = AES-GCM 口令加密档。
  /// - [excludeTables]/[outDirOverride]：批4 SnapshotService 复用于产同步快照。
  /// - [nameTag]：非空时改名 `<nameTag>_YYYYMMDD_HHmmss.lhbak`
  ///   （恢复前自动备份 = `auto_before_restore_*`）。
  Future<LhBakCreateResult> exportBackup({
    bool withLogs = false,
    bool withAttachments = true,
    String? passphrase,
    List<String> excludeTables = const [],
    String? outDirOverride,
    String? nameTag,
  }) async {
    final out = outDirOverride ?? exportDir();
    List<String> logFiles = const [];
    if (withLogs) {
      final dir = FileLogSink.dirPath;
      if (dir != null) {
        logFiles = (await FileLogSink.dayFiles())
            .map((name) => p.join(dir, name))
            .toList();
      }
    }
    var res = await LhBak.create(
      db: await db(),
      outDirPath: out,
      attachDirs: withAttachments ? attachDirs : const [],
      logFiles: logFiles,
      excludeTables: excludeTables,
      passphrase: passphrase,
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
      res = LhBakCreateResult(await res.file.rename(target.path), res.manifest);
    }
    return res;
  }

  /// 只读校验包（导入 UI 的「校验报告态」数据源）：坏包冒泡 [LhBakException]。
  Future<LhBakManifest> inspect(String filePath, {String? passphrase}) =>
      LhBak.verify(filePath, passphrase: passphrase);

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
  /// 取消 = null；file_picker 平台异常时 UI 降级「本机导出记录」tab。
  Future<String?> pickBackupFile() => pickFileHook();

  /// 导入恢复（整库替换，不做记录级合并）。顺序钉死，见文件头注释。
  Future<RestoreReport> importBackup(String filePath,
      {String? passphrase}) async {
    // 1) 前置校验：坏包在这里拒绝，现库一字节不动。
    await LhBak.verify(filePath, passphrase: passphrase);
    // 2) 恢复前自动备份：close 之前完成 → 原库文件此后不再被触碰。
    final auto = await exportBackup(nameTag: kAutoBeforeRestoreTag);
    // 3) close → unpack → reopen。
    final current = await db();
    await current.close();
    Database? working;
    LhBakManifest manifest;
    try {
      working = await db();
      final unpack = unpackOverride ?? LhBak.unpack;
      manifest = await unpack(
          filePath: filePath, targetDb: working, passphrase: passphrase);
    } catch (_) {
      // 恢复失败路径：现库已被本次流程 close——重开原库恢复现场后冒泡
      // （unpack 全在事务内，失败即回滚，原库文件未受污染）。
      try {
        await working?.close();
      } catch (_) {}
      try {
        await db(); // 生产 = AppDatabase.instance.open() 重开并保持实例可用
      } catch (_) {
        // 重开失败不掩盖原始异常。
      }
      rethrow;
    }
    return RestoreReport(
      tableCount: manifest.tables.length,
      totalRows:
          manifest.tables.values.fold<int>(0, (a, t) => a + t.rows),
      missingTables: manifest.missingTables,
      skippedLarge: manifest.skippedLarge ?? const [],
      autoBackupPath: auto.file.path,
    );
  }

  // ---- 生产侧默认实现（测试被钩子替换，不触平台通道）----

  static Future<String?> _saveViaFileDialog(String srcPath) {
    return FlutterFileDialog.saveFile(
      params: SaveFileDialogParams(
        fileName: p.basename(srcPath),
        sourceFilePath: srcPath,
        mimeTypesFilter: const ['application/octet-stream'],
      ),
    );
  }

  static Future<String?> _pickViaFilePicker() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['lhbak'],
      withData: false,
    );
    if (result == null || result.files.isEmpty) return null;
    return result.files.single.path;
  }
}
