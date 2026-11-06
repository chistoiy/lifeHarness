import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

// 二期批5 · F5-4：快照落盘的可发送载荷与 isolate 侧写入器。
// 单列一文件＝epub_cache 已顶到 1200 面（单文件体量闸），且这半边是「纯数据＋纯 IO」，
// 与 DocStore 的解析/私有序列化逻辑无关（载荷由 DocStore 拍平，本件只管编码与写盘）。
//
// 字节口径与旧主线程写法**完全一致**：同一份 jsonEncode + 同一套字段顺序。

/// 快照落盘的可发送载荷（F5-4）：全部为纯数据，可跨 isolate 传递。
typedef DocSnapPayload = ({
  String dir,
  String fp,
  String format,
  String title,
  String? author,
  String? pub,
  String? date,
  String? lang,
  String? desc,
  String? covN,
  int imgC,
  int chars,
  int fontC,
  int bmC,
  List<List<Object?>> uns,
  List<List<Object?>> toc,
  List<String> hrefs,
  List<String> titles,
  List<int> paraN,
  List<int> charN,
  List<List<Object?>> chapters,
  List<int>? cover,
  SendPort mainPort,
  int version,
});

/// isolate 侧：编码＋写盘＋索引组装（原 DocStore.save 的写盘段 1:1 搬移，
/// 字节口径不变）。返回「是否真在别的 isolate 跑」与落盘总字节，供用例取证。
({bool offMain, int bytes}) writeDocSnapshot(DocSnapPayload s) {
  // 「真在别的 isolate 跑」的自证读数：调用方把自己的 controlPort 一起传进来，
  // 只有换了个 isolate 才会不相等（否则这条改动只能靠人肉推断，用例守不住）。
  final offMain = Isolate.current.controlPort != s.mainPort;
  final dir = Directory(s.dir)..createSync(recursive: true);
  final spine = <Map<String, Object>>[];
  final raf = File(p.join(dir.path, 'data.bin')).openSync(mode: FileMode.write);
  var off = 0;
  try {
    for (var i = 0; i < s.chapters.length; i++) {
      final b = utf8.encode(jsonEncode(s.chapters[i]));
      spine.add({
        'href': s.hrefs[i],
        'title': s.titles[i],
        'n': s.paraN[i],
        'chars': s.charN[i],
        'off': off,
        'len': b.length,
      });
      raf.writeFromSync(b);
      off += b.length;
    }
  } finally {
    raf.closeSync();
  }
  final idx = <String, Object?>{
    'v': s.version,
    'fp': s.fp,
    'format': s.format,
    'title': s.title,
    'author': s.author,
    'pub': s.pub,
    'date': s.date,
    'lang': s.lang,
    'desc': s.desc,
    'covN': s.covN,
    'imgC': s.imgC,
    'chars': s.chars,
    'fontC': s.fontC,
    'bmC': s.bmC,
    // 批三刀2：包内声明了我们表达不了的排版项（竖排/多栏/浮动/表格/行内留白…），
    // 随快照落盘，重开也还在——刀3 用它落日志＋该书外观页提示行（不许静默降级）。
    'uns': s.uns,
    'toc': s.toc,
    'spine': spine,
  };
  final idxStr = jsonEncode(idx);
  File(p.join(dir.path, 'index.json')).writeAsStringSync(idxStr);
  var bytes = off + utf8.encode(idxStr).length;
  final cov = s.cover;
  if (cov != null) {
    File(p.join(dir.path, 'cover.bin')).writeAsBytesSync(cov);
    bytes += cov.length;
  }
  return (offMain: offMain, bytes: bytes);
}
