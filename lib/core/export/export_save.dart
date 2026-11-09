/// C08b · 导出落盘薄封装（写临时文件 → 既有 SAF「另存为」出口）。
///
/// 只做两件事：把纯序列化层产出的文本写进临时目录（唯一子目录＝文件名不被
/// 时间戳污染，系统另存弹层显示的仍是正经名字），再交给
/// `core/platform/saf.dart` 的 [safSaveAs]。零新增原生通道、零网络。
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../platform/saf.dart';
import 'multi_format.dart';
import 'printable_html.dart';

/// 写文本到临时目录的唯一子目录并调系统另存。返回选定文件名；取消＝null。
Future<String?> _saveTextAs({
  required String fileName,
  required String text,
}) async {
  final tmp = await getTemporaryDirectory();
  final stamp = DateTime.now().millisecondsSinceEpoch;
  final dir = Directory(p.join(tmp.path, 'lh-export-$stamp'));
  await dir.create(recursive: true);
  final file = File(p.join(dir.path, fileName));
  await file.writeAsString(text, encoding: utf8, flush: true);
  return safSaveAs(file.path);
}

/// 可打印 HTML 另存（用户后续在浏览器/打印面板「另存为 PDF」）。
Future<String?> savePrintableHtmlAs({
  required String title,
  required String html,
}) =>
    _saveTextAs(fileName: printableHtmlFileName(title), text: html);

/// 导图 SVG 另存（复用 [serializeMindmapSvg]；中文不缺字、无外链资源）。
///
/// 导图 UI 侧的接线点（`mmRunExport` 的格式分支）不在本轮可改路径内，
/// 本函数是其唯一落盘出口，接上时直接调用即可。
Future<String?> saveMindmapSvgAs({
  required String title,
  required List<SvgNode> nodes,
  int width = 960,
  int height = 640,
}) {
  final name = (title.trim().isEmpty ? '未命名导图' : title.trim())
      .replaceAll(RegExp(r'[/\\:*?"<>|\r\n\t]'), '-')
      .trim();
  return _saveTextAs(
    fileName: '${name.isEmpty ? '未命名导图' : name}.svg',
    text: serializeMindmapSvg(
        title: title, nodes: nodes, width: width, height: height),
  );
}
