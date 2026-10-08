import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:lifeharness/features/media/data/media_cover.dart';

/// 影音游批6 · 条目封面写入端（工单 §⚙ 面板第 3 项：降采样口径＋内容寻址＋读不出不落值）。
///
/// 纯逻辑文件（不起 widget、不碰插件通道）：取图那一步在真机才发生，
/// 本文件钉的是**口径本身**——摘掉缩放参数（变异刀①）这里必红，
/// UI 侧的「取消/读不出」两态在 `media_add_sheet_test.dart` 用注入缝验。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 1×1 透明 PNG（现算字节，仓库里不铺素材）。
  final tinyPng = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  );

  late Directory root;

  /// 取图口假件：记下**真实现传下来的参数**（摘掉 maxWidth/imageQuality 这里就是 null＝刀1 现形），
  /// 并回一张真图路径。定式抄 `journal_test.dart` 的 `_FakeImagePicker`。
  _SpyImagePicker? spy;

  setUp(() {
    root = Directory.systemTemp.createTempSync('lh_cover6');
    spy = null;
    ImagePickerPlatform.instance = _RealPickerStub();
    PathProviderPlatform.instance = _FakePathProvider(root.path);
  });
  tearDown(() {
    ImagePickerPlatform.instance = _RealPickerStub();
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('真链路＝取图口收到 480/480·质量 82，成图落 docs/note_images 且按内容寻址命名',
      () async {
    final srcDir = Directory(p.join(root.path, 'src'))..createSync();
    final src = File(p.join(srcDir.path, 'in.png'))
      ..writeAsBytesSync(tinyPng);
    final docs = Directory(p.join(root.path, 'docs'))..createSync();
    spy = _SpyImagePicker(src.path);
    ImagePickerPlatform.instance = spy!;
    PathProviderPlatform.instance = _FakePathProvider(docs.path);

    final r = await mdsPickAndStoreCover(source: ImageSource.gallery);
    expect(r.outcome, MdsCoverOutcome.ok);
    final a = spy!.last!;
    // 这一组断言才是「降采样」的硬闸：只测 mdsCoverPickArgs() 的返回值，
    // 摘掉真调用里的参数不会红（施工图断言须落在注入路径上）。
    expect(a.maxWidth, 480, reason: '原型 mCoverDownscale(src, 480) 同数');
    expect(a.maxHeight, 480, reason: '两轴同钉＝等比缩放，长边落在 480');
    expect(a.imageQuality, 82, reason: '原型 toDataURL("image/jpeg", .82)');
    expect(spy!.lastSource, ImageSource.gallery);
    final out = r.path!;
    expect(out.startsWith(p.join(docs.path, 'note_images')), isTrue,
        reason: '落既有媒体根＝备份/同步/清理三闸天然覆盖');
    expect(p.basename(out), mdsCoverStoreName(tinyPng));
    expect(File(out).readAsBytesSync(), tinyPng, reason: '字节原样落盘');
  });

  test('真链路＝选中的不是图：failed 且媒体根里不落半个文件', () async {
    final junk = File(p.join(root.path, 'junk.txt'))
      ..writeAsStringSync('这不是图片文件，只是恰好被选中了');
    final docs = Directory(p.join(root.path, 'docs2'))..createSync();
    spy = _SpyImagePicker(junk.path);
    ImagePickerPlatform.instance = spy!;
    PathProviderPlatform.instance = _FakePathProvider(docs.path);

    final r = await mdsPickAndStoreCover(source: ImageSource.camera);
    expect(r.outcome, MdsCoverOutcome.failed);
    expect(r.path, isNull);
    expect(
      Directory(p.join(docs.path, 'note_images')).existsSync(),
      isFalse,
      reason: '读不出＝一个字节都不许落进媒体根',
    );
  });

  test('真链路＝用户取消：canceled（与 failed 分开，UI 才知道该不该说话）', () async {
    final docs = Directory(p.join(root.path, 'docs3'))..createSync();
    spy = _SpyImagePicker(null);
    ImagePickerPlatform.instance = spy!;
    PathProviderPlatform.instance = _FakePathProvider(docs.path);
    final r = await mdsPickAndStoreCover(source: ImageSource.camera);
    expect(r.outcome, MdsCoverOutcome.canceled);
    expect(r.path, isNull);
  });

  test('降采样口径常量＝长边 480·JPEG 质量 82', () {
    final a = mdsCoverPickArgs();
    expect(a.maxWidth, kMdsCoverMaxSide);
    expect(a.maxHeight, kMdsCoverMaxSide);
    expect(a.imageQuality, kMdsCoverQuality);
    expect(kMdsCoverMaxSide, 480);
    expect(kMdsCoverQuality, 82);
  });

  test('内容寻址命名＝同图全局一份、异图不同名、扩展名恒 jpg', () {
    final a = mdsCoverStoreName(tinyPng);
    final b = mdsCoverStoreName(Uint8List.fromList(tinyPng));
    final c = mdsCoverStoreName(Uint8List.fromList([...tinyPng, 9]));
    expect(a, b, reason: '同图同名＝去重（与日记/笔记 R5b 同一命名法）');
    expect(a.endsWith('.jpg'), isTrue);
    expect(a, isNot(c), reason: '差一个字节就该是另一个名字（哈希没写死）');
    expect(a.split('.').first, hasLength(64), reason: 'SHA256 十六进制 64 位');
  });

  test('落盘＝同步写进给定媒体根，重复写不产生第二份', () {
    final dir = p.join(root.path, 'note_images');
    final first = mdsWriteCoverSync(Uint8List.fromList(tinyPng), dir: dir);
    expect(first, isNotNull);
    expect(File(first!).existsSync(), isTrue);
    expect(File(first).lengthSync(), tinyPng.length, reason: '字节原样落盘，没被截断');
    final second = mdsWriteCoverSync(Uint8List.fromList(tinyPng), dir: dir);
    expect(second, first, reason: '同图第二次写＝同一路径（幂等）');
    expect(Directory(dir).listSync(), hasLength(1));
  });

  test('读不出＝false：空字节/半截文件都不算一张图（UI 据此不落半个值）', () async {
    expect(await mdsCoverBytesReadable(Uint8List(0)), isFalse);
    expect(
      await mdsCoverBytesReadable(Uint8List.fromList(utf8.encode('不是图'))),
      isFalse,
    );
    expect(
      await mdsCoverBytesReadable(
        Uint8List.fromList(tinyPng.sublist(0, tinyPng.length ~/ 2)),
      ),
      isFalse,
      reason: '截断的 PNG 也判读不出（0 字节/半截文件同一条坑）',
    );
    expect(await mdsCoverBytesReadable(Uint8List.fromList(tinyPng)), isTrue);
  });
}

/// 取图口假件：记下**真实现传下来的参数**（＝刀1 靶：摘掉 maxWidth/maxHeight/imageQuality
/// 这里就是 null，只测常量函数是抓不到的），并按脚本回一张真图 / 回 null（取消）。
class _SpyImagePicker extends ImagePickerPlatform {
  _SpyImagePicker(this.path);

  final String? path;
  ImagePickerOptions? last;
  ImageSource? lastSource;

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    last = options;
    lastSource = source;
    return path == null ? null : XFile(path!);
  }
}

/// 兜底假件：本文件永不碰真平台通道。
class _RealPickerStub extends ImagePickerPlatform {
  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async =>
      null;
}

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.dir);

  final String dir;

  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}
