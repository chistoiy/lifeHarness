/// Android SAF「另存为」自研通道（2026-10-04 真机轮6 起替换 flutter_file_dialog）。
///
/// 换通道根因（logcat 实锤）：flutter_file_dialog 的 Kotlin 端在
/// `onActivityResult` 里对 [sourceFile] 用 `!!`——进程在选择器打开期间被杀
/// （导出卡 UI 触发 bg ANR）后冷启动投递结果时必 NPE 崩溃，SAF 已建好的目标
/// 文件停在 0 字节；其拷贝还强转 `FileOutputStream`，对非文件型 provider 同样
/// 脆弱。本通道实现放 MainActivity.kt：无状态时静默忽略过期结果（不崩）、
/// 拷贝走通用 OutputStream（不挑 provider）。
///
/// 返回语义：成功 = 用户选定位置的显示文件名（另存提示用）；取消 = null；
/// 失败抛 [PlatformException]（UI 层兜底可见提示）。
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../logging/app_log.dart';

/// 保存通道（与 MainActivity.kt 的 `lh/saf` 对齐）。
const MethodChannel safChannel = MethodChannel('lh/saf');

/// 把 [srcPath] 经系统「创建文档」弹层另存到用户自选位置。
/// 返回选定文件显示名；取消 = null；失败抛 PlatformException。
Future<String?> safSaveAs(String srcPath) {
  return safChannel.invokeMethod<String?>('saveAs', {
    'srcPath': srcPath,
    'fileName': p.basename(srcPath),
  });
}

/// file_picker 选择器＋自造扩展名降级（2026-10-04 缺陷口径，同
/// `BackupService._pickViaFilePicker`：lhbak/xrwords/xraybak 等自造扩展名
/// 不在 Android MIME 表，FileType.custom 会被插件判 Unsupported filter 抛
/// PlatformException＝「点了没反应」；先试过滤版、失败降级全文件）。
/// [logTag] 为人话来源前缀（词库/索引包…）。备份侧因有注入缝单列实现，
/// 本函数服务 X-Ray 两通道。
Future<String?> safPickWithFallback(List<String> exts,
    {String logTag = '备份'}) async {
  FilePickerResult? result;
  try {
    result = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: exts, withData: false);
  } on PlatformException catch (e) {
    AppLog.add('$logTag选择器扩展名被平台拒（降级全文件）：$e',
        level: LhLevel.warn);
    result = await FilePicker.platform.pickFiles(
        type: FileType.any, withData: false);
  }
  if (result == null || result.files.isEmpty) return null;
  return result.files.single.path;
}
