/// X-Ray 索引备份服务（需求 V1.54 · 设计书 §2 F10 · 交棒话术批C）
///
/// 口径：
/// - `.xraybak` ＝ JSON 包（v1：按 md5 分册的四表 + 用户词典含 GLOBAL），**不含正文**；
/// - 导出走「另存为」（复用 BackupService 的 SAF saveAs 先例与静态钩子），
///   导入走系统选择器；对话框钩子可整体替换，widget 测试不触平台通道；
/// - 导入做逐册 MD5 一致性校验（DAO.importBundle 拒收拼改册）+ UI 侧覆盖确认；
/// - 换机主路径仍是 `.lhbak` 整包（四表建在主库内自动随行，§13 路径 B）——
///   `.xraybak` 只服务单书迁移/分享（路径 C）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../../core/logging/app_log.dart';
import '../../../../core/platform/saf.dart';

import 'xray_dao.dart';

typedef XrSaveAs = Future<String?> Function(String srcPath);
typedef XrPick = Future<String?> Function();

class XrImportReport {
  const XrImportReport({required this.books, required this.bad});
  final int books;
  final int bad;
}

class XrayBackupService {
  XrayBackupService(this.dao, {this.saveAs, this.pickFile, this.docsOverride});

  final XrayDao dao;

  /// 测试注入钩子（同 BackupService.saveAsDialog 惯例；null＝生产实现）。
  final XrSaveAs? saveAs;
  final XrPick? pickFile;
  final Directory? docsOverride;

  static final XrSaveAs defaultSaveAs = safSaveAs;
  static final XrPick defaultPick = _pickViaFilePicker;

  /// 导出全部索引 → 返回另存后的最终路径（用户取消＝null）。
  Future<String?> exportAll() async {
    final bundle = await dao.exportBundle();
    final json = const JsonEncoder.withIndent('  ').convert(bundle);
    final dir = Directory(p.join(
        (docsOverride ?? await getApplicationDocumentsDirectory()).path,
        'xray_backup'));
    await dir.create(recursive: true);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final tmp = File(p.join(dir.path, 'xray-$stamp.xraybak'));
    await tmp.writeAsString(json, flush: true);
    final saved = await (saveAs ?? defaultSaveAs)(tmp.path);
    if (saved == null) {
      try {
        await tmp.delete();
      } catch (e) {
        // 清理失败不影响取消语义（临时文件留在应用私有目录），但要留痕。
        AppLog.add('xraybak 临时文件清理失败: $e', level: LhLevel.warn);
      }
    }
    return saved;
  }

  /// 选择并解析 .xraybak（校验失败抛 FormatException；取消＝null）。
  Future<Map<String, Object?>?> readPick() async {
    final path = await (pickFile ?? defaultPick)();
    if (path == null) return null;
    final v = jsonDecode(await File(path).readAsString());
    if (v is! Map) throw const FormatException('不是合法的 .xraybak');
    return v.cast<String, Object?>();
  }

  Future<XrImportReport> importBundle(Map<String, Object?> bundle) async {
    final r = await dao.importBundle(bundle);
    return XrImportReport(books: r.books, bad: r.bad);
  }
}

Future<String?> _pickViaFilePicker() =>
    // 轮6 同缺陷口径：xraybak 自造扩展名会被 FileType.custom 拒→降级全文件。
    safPickWithFallback(const ['xraybak'], logTag: '索引包');
