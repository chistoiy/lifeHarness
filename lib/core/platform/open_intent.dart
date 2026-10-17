/// V1.64 批1（工单 交棒话术-20261004 §2 N-3/N-4）：系统「打开方式」多类型通道。
///
/// 由 V1.53.4⑥ 的 EPUB 单类型通道泛化：原生侧 `lh/intents` 的 `takeEpubUri`
/// 改为 `takeOpenFile`（返回 Map：kind=epub|note|''，path=已拷入
/// cacheDir/lh_open/ 的绝对路径，name=原文件名，uri=原始 content URI 字符串）。
/// 三态沿用旧语义：null=无待处理；kind ''=命中不支持的类型（Dart 侧 toast）；
/// 其余=可处理文件。分派在组合根（app.dart）——R1：read/journal 不得互 import。
///
/// 回写（拍板 G）：`lh/saf` 新增 `writeBack`（按原 content URI 覆写流）；
/// 授权失效/原文件不在由原生按 'no_perm'/'missing' 返回，UI 侧降级提示
/// （＝仅存应用内，工单 §2）。真 IO 全走可替换缝（widget 测试 FakeAsync
/// 禁真磁盘——既有踩坑）。
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

const MethodChannel _intentsChannel = MethodChannel('lh/intents');

/// kind '' 时的统一人话提示（分派侧与守护共读这一句）。
const kOpenUnsupportedToast = '目前只支持 EPUB 与 Markdown 文件';

class OpenIntentFile {
  const OpenIntentFile(
      {required this.kind, required this.path, required this.name, required this.uri});

  final String kind; // 'epub' | 'note' | ''
  final String path; // cacheDir/lh_open/ 下的绝对路径
  final String name; // 原文件名（含扩展名）
  final String uri; // 原始 content URI（回写锚点）
}

/// 单次消费入队意图（取一次即清原生挂起态）。通道缺失（测试/桌面）＝null。
Future<OpenIntentFile?> takeOpenFile() async {
  try {
    final Object? raw =
        await _intentsChannel.invokeMethod<Map<dynamic, dynamic>>('takeOpenFile');
    if (raw is! Map) return null;
    return OpenIntentFile(
      kind: (raw['kind'] as String?) ?? '',
      path: (raw['path'] as String?) ?? '',
      name: (raw['name'] as String?) ?? '',
      uri: (raw['uri'] as String?) ?? '',
    );
  } catch (_) {
    // catch-ok: 原生侧未挂到 intents（非打开方式进入）＝无待接文件，正常分支。
    return null;
  }
}

/// 意图分派（纯函数：组合根与守护测试共用同一决策表）。
/// 返回 null＝无事发生；''＝不支持类型（调用方按 [kOpenUnsupportedToast] 提示）。
String? classifyOpenIntent(OpenIntentFile? f) => f?.kind;

/// 回写缝：uri+正文 → 'ok'|'no_perm'|'missing'|'error'。测试替换用
/// （默认实现落临时文件再走原生流拷贝，FakeAsync 下不可真跑）。
Future<String> Function(String uri, String content) noteWriteBack =
    defaultNoteWriteBack;

Future<String> defaultNoteWriteBack(String uri, String content) async {
  try {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}${Platform.pathSeparator}lh_writeback.tmp');
    await f.writeAsString(content);
    final r = await const MethodChannel('lh/saf')
        .invokeMethod<String>('writeBack', {'uri': uri, 'srcPath': f.path});
    return r ?? 'missing';
  } catch (_) {
    // catch-ok: 通道缺失/原生异常一律按授权失效降级（UI 提示可见，不静默）。
    return 'no_perm';
  }
}

/// 保存后的回写决策（工单 §2 N-3）：仅 open_with 来源且带原始 URI 才回写。
/// 返回 null＝该条不参与回写；调用方对非 'ok' 出降级提示。
/// 分派点被 `test/note_open_with_test.dart` 源码守护钉死（note_edit_save 必须调用本函数）。
Future<String?> noteWriteBackGuard(
    {required String source, required String originUri, required String content}) async {
  if (source != 'open_with' || originUri.isEmpty) return null;
  return noteWriteBack(originUri, content);
}
