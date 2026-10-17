/// 离屏 PNG 编码尾段（批2 F4-5 从 journal 域 `note_sheets.dart` 的
/// `_noteCardPng` 范式抽离——PictureRecorder→toImage→png bytes 的通用尾三步）。
///
/// R1 合规落点：mindmap 导出 PNG 不能直连 journal 域文件，把**纯编码尾段**
/// 放 shared 供两域共用（笔记卡片 = journal 域自绘内容 + 本尾段；
/// 导图 PNG = mindmap 画布 painter 自绘内容 + 本尾段）。
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

/// 收尾录制并编码 PNG。调用侧画完内容后把 recorder 与尺寸交给本函数。
Future<Uint8List> encodeOffscreenPng(
  ui.PictureRecorder recorder,
  double width,
  double height,
) async {
  final img = await recorder
      .endRecording()
      .toImage(width.ceil(), height.ceil());
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  return data!.buffer.asUint8List();
}
