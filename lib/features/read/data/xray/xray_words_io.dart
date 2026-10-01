/// X-Ray 养成词库导入导出（需求 V1.54.1 批3 · `.xrwords` 两段式 JSON）。
///
/// 口径（docs/X-Ray词条质量治理计划-20261002.md §5）：
/// - 包 = `{"v":1,"kind":"xrwords","preset":{...},"entries":[...]}`——
///   `preset` 段＝**预置词库只读基准标识**（八表文件名+非加密指纹，随包走供对端
///   比对，不可导入覆盖资产）；`entries` 段＝用户养起来的数据（GLOBAL 全量可合并）；
/// - 导入逐条 upsert 进 GLOBAL 层（不碰按书覆盖层），完成报「新增/覆盖/跳过」；
/// - 与 `.xraybak`（单书四表迁移）各走各路互不影响；
/// - SAF 钩子复用 [XrSaveAs]/[XrPick] 注入模式（widget 测试不触平台通道）；
/// - 指纹用 FNV-1a 64（纯 Dart 零依赖，仅作基准比对标识，非加密摘要）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../../core/logging/app_log.dart';
import 'xray_backup.dart' show XrPick, XrSaveAs;
import 'xray_dao.dart';
import 'xray_lexicon.dart' show XrayWordBank;

/// 导入预检/结果报告。
class XrWordsReport {
  const XrWordsReport({
    required this.total,
    required this.added,
    required this.updated,
    required this.skipped,
  });

  /// 包内 entries 原始条数（含解析层跳过的）。
  final int total;
  final int added;
  final int updated;
  final int skipped;

  /// 解析层跳过＝包内非法行（DAO 层还会再兜一道同口径）。
  int get parseSkipped => total - added - updated;
}

class XrayWordsIoService {
  XrayWordsIoService(
    this.dao, {
    this.saveAs,
    this.pickFile,
    this.docsOverride,
    Future<String> Function(String path)? readAsset,
  }) : readAsset = readAsset ?? _rootAsset;

  final XrayDao dao;

  /// 测试注入钩子（同 XrayBackupService 惯例；null＝生产实现）。
  final XrSaveAs? saveAs;
  final XrPick? pickFile;
  final Directory? docsOverride;

  /// 预置词表读取器（生产=rootBundle；测试=File，供指纹计算）。
  final Future<String> Function(String path) readAsset;

  static const String kind = 'xrwords';

  static Future<String> _rootAsset(String path) => rootBundle.loadString(path);

  /// FNV-1a 非加密指纹（hex；仅用于预置词库基准比对）。取 63 位：
  /// Dart int 有符号，最高位弃用以免 toRadixString 出负号。
  static String fingerprint(String s) {
    var h = 0xcbf29ce484222325;
    for (final c in s.codeUnits) {
      h ^= c;
      h = (h * 0x100000001b3) & 0x7FFFFFFFFFFFFFFF;
    }
    return h.toRadixString(16).padLeft(16, '0');
  }

  /// 组包：预置基准标识 + GLOBAL 全量 entries（按书覆盖层不进包）。
  Future<Map<String, Object?>> buildBundle() async {
    final files = <String, String>{};
    for (final n in XrayWordBank.assetNames) {
      files[n] = fingerprint(await readAsset('assets/xray/dicts/$n'));
    }
    final dict = await dao.listGlobalDict();
    return {
      'v': 1,
      'kind': kind,
      'preset': {
        'id': fingerprint(files.values.join('\n')),
        'files': files,
      },
      'entries': [
        for (final r in dict)
          {
            'word': r.word,
            'type': r.type,
            'action': r.action,
            'target': r.target,
            'pattern_hint': r.patternHint,
            'ts': r.createTime,
          },
      ],
    };
  }

  /// 导出全部养成词 → 返回另存后的最终路径（用户取消＝null）。
  Future<String?> exportWords() async {
    final json = const JsonEncoder.withIndent('  ').convert(await buildBundle());
    final dir = Directory(p.join(
        (docsOverride ?? await getApplicationDocumentsDirectory()).path,
        'xray_words'));
    await dir.create(recursive: true);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final tmp = File(p.join(dir.path, 'xraywords-$stamp.xrwords'));
    await tmp.writeAsString(json, flush: true);
    final saved = await (saveAs ?? defaultSaveAs)(tmp.path);
    if (saved == null) {
      try {
        await tmp.delete();
      } catch (e) {
        // 清理失败不影响取消语义（临时文件留在应用私有目录），但要留痕。
        AppLog.add('xrwords 临时文件清理失败: $e', level: LhLevel.warn);
      }
    }
    return saved;
  }

  /// 选择并解析 `.xrwords`（取消＝null；不是合法包/kind 不对 → FormatException）。
  Future<Map<String, Object?>?> readPick() async {
    final path = await (pickFile ?? defaultPick)();
    if (path == null) return null;
    final v = jsonDecode(await File(path).readAsString());
    if (v is! Map || v['kind'] != kind) {
      throw const FormatException('不是合法的 .xrwords 包');
    }
    return (v).cast<String, Object?>();
  }

  /// 解析 entries（只取 add/forbid，type 未收录词类归 null）；返回载荷 + 跳过数。
  (List<XrayDictEntry>, int) parseEntries(Map<String, Object?> bundle) {
    final raw = (bundle['entries'] as List?) ?? const [];
    final out = <XrayDictEntry>[];
    var skipped = 0;
    for (final row in raw) {
      if (row is! Map) {
        skipped++;
        continue;
      }
      final word = (row['word'] as String?)?.trim() ?? '';
      final action = row['action'] as String?;
      if (word.isEmpty ||
          action == null ||
          (action != 'add' && action != 'forbid')) {
        skipped++;
        continue;
      }
      final type = row['type'] as String?;
      out.add(XrayDictEntry(
        word: word,
        action: action,
        type: _validType(type) ? type : null,
        target: row['target'] as String?,
        patternHint: row['pattern_hint'] as String?,
        createTime: (row['ts'] as num?)?.toInt() ?? 0,
      ));
    }
    return (out, skipped);
  }

  static bool _validType(String? t) => t != null && _types.contains(t);
  static const Set<String> _types = {'per', 'loc', 'org', 'term', 'abbr', 'book'};

  /// 一键导入：读包 → 解析 → DAO upsert → 报告。
  Future<XrWordsReport> importWords(Map<String, Object?> bundle) async {
    final (entries, parseSkipped) = parseEntries(bundle);
    final r = await dao.importGlobalDict(entries);
    return XrWordsReport(
      total: (bundle['entries'] as List?)?.length ?? 0,
      added: r.added,
      updated: r.updated,
      skipped: r.skipped + parseSkipped,
    );
  }

  static final XrSaveAs defaultSaveAs = _saveViaFileDialog;
  static final XrPick defaultPick = _pickViaFilePicker;
}

Future<String?> _saveViaFileDialog(String srcPath) {
  // 与 BackupService/XrayBackupService 同通道（SAF「创建文档」），独立实例不复用状态。
  return FlutterFileDialog.saveFile(
    params: SaveFileDialogParams(
      fileName: p.basename(srcPath),
      sourceFilePath: srcPath,
      mimeTypesFilter: const ['application/octet-stream'],
    ),
  );
}

Future<String?> _pickViaFilePicker() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['xrwords'],
    withData: false,
  );
  return result?.files.firstOrNull?.path;
}
