import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart' as crypto;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/logging/app_log.dart';

// ==================== 影音游批6 · 条目封面写入端 ====================
//
// 计划 §四 L216 欠到今天的「封面上传 canvas 压缩」在 Flutter 侧的对应面：
// 原型用 canvas 把选中的图降采样（长边钉 480）再 `toDataURL('image/jpeg', .82)`；
// dart:ui 的 `ImageByteFormat` 没有 JPEG 编码器（引擎注释写明不再扩格式），
// 所以**降采样与 JPEG 重编码由取图口执行**（`image_picker` 的 maxWidth/maxHeight/imageQuality
// 在平台侧等比缩放并按质量重编码）——同一口径，零新依赖，见 [mdsCoverPickArgs]。
//
// 三条硬口径（工单 §5 铁口径）：
// · 读不出＝返回 null，调用侧**不许往条目落半个值**（0 字节/半截文件都算读不出）；
// · 存文件不存 dataURL，落既有媒体根 `note_images/` 并按内容寻址命名（R5b 同法）——
//   另造目录会被备份/同步/清理三闸漏掉，而工单 §5 的意图正是「备份/换机语义跟笔记附件同路」；
// · 删除条目不删磁盘文件（软删保留记录口径），孤儿回收只走既有清理扫描（引用列已登记本列）。

/// 封面长边上限（原型 `mCoverDownscale(src, 480)` 同数）。
const int kMdsCoverMaxSide = 480;

/// JPEG 重编码质量（原型 `.82`）。
const int kMdsCoverQuality = 82;

/// 取图参数单独成函数＝用例能把「摘掉缩放」这一刀钉红（变异刀①靶点）。
({int maxWidth, int maxHeight, int imageQuality}) mdsCoverPickArgs() => (
      maxWidth: kMdsCoverMaxSide,
      maxHeight: kMdsCoverMaxSide,
      imageQuality: kMdsCoverQuality,
    );

/// 内容寻址文件名：同图全局只存一份（与日记/笔记插图同一命名法，孤儿判定零读二进制）。
String mdsCoverStoreName(List<int> bytes, {String ext = 'jpg'}) =>
    '${crypto.sha256.convert(bytes).toString()}.$ext';

/// 取图三种收场，UI 侧要分开说：取消＝静默，读不出＝一句实话。
enum MdsCoverOutcome { ok, canceled, failed }

/// 取图口返回体（路径只在 [MdsCoverOutcome.ok] 时非空）。
typedef MdsCoverPickResult = ({MdsCoverOutcome outcome, String? path});

/// 取图口签名（生产＝[mdsPickAndStoreCover]；测试注入固定返回值，
/// 因为 widget 测试里真插件通道与异步文件 I/O 都不能碰）。
typedef MdsCoverPick = Future<MdsCoverPickResult> Function(ImageSource src);

/// 字节能否真当图解开（过小/解码失败＝读不出，UI 只提示、不落值）。
Future<bool> mdsCoverBytesReadable(Uint8List bytes) async {
  if (bytes.lengthInBytes < 24) return false;
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    frame.image.dispose();
    return true;
  } catch (e) {
    AppLog.add('封面解码失败：$e', level: LhLevel.warn, src: '影音游');
    return false;
  }
}

/// 把封面字节落进 [dir]（媒体根下的 `note_images/`），返回绝对路径；写不进＝null。
/// 同步写＝FakeAsync 的 widget 测试里异步 writeAsBytes 永不完成（既有坑），
/// 且 MB 级同步落盘是毫秒量级，生产无感。
String? mdsWriteCoverSync(Uint8List bytes, {required String dir}) {
  try {
    final d = Directory(dir);
    if (!d.existsSync()) d.createSync(recursive: true);
    final dest = File(p.join(d.path, mdsCoverStoreName(bytes)));
    if (!dest.existsSync()) dest.writeAsBytesSync(bytes);
    return dest.path;
  } catch (e) {
    AppLog.add('封面落盘失败：$e', level: LhLevel.warn, src: '影音游');
    return null;
  }
}

/// 生产入口：选图（取图口按 [mdsCoverPickArgs] 降采样出 JPEG）→ 解码自证 → 落盘 → 返回路径。
/// 取消＝canceled；读不出/写不进＝failed 且**条目 cover_path 不落半个值**。
Future<MdsCoverPickResult> mdsPickAndStoreCover({
  required ImageSource source,
}) async {
  final docs = (await getApplicationDocumentsDirectory()).path;
  XFile? picked;
  try {
    final args = mdsCoverPickArgs();
    picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: args.maxWidth.toDouble(),
      maxHeight: args.maxHeight.toDouble(),
      imageQuality: args.imageQuality,
    );
  } catch (e) {
    AppLog.add('封面取图失败：$e', level: LhLevel.warn, src: '影音游');
    return (outcome: MdsCoverOutcome.failed, path: null);
  }
  if (picked == null) return (outcome: MdsCoverOutcome.canceled, path: null);
  final f = File(picked.path);
  if (!f.existsSync()) return (outcome: MdsCoverOutcome.failed, path: null);
  Uint8List bytes;
  try {
    bytes = await f.readAsBytes();
  } catch (e) {
    AppLog.add('封面读取失败：$e', level: LhLevel.warn, src: '影音游');
    return (outcome: MdsCoverOutcome.failed, path: null);
  }
  if (!await mdsCoverBytesReadable(bytes)) {
    return (outcome: MdsCoverOutcome.failed, path: null);
  }
  final path = mdsWriteCoverSync(bytes, dir: p.join(docs, 'note_images'));
  return (
    outcome: path == null ? MdsCoverOutcome.failed : MdsCoverOutcome.ok,
    path: path,
  );
}
