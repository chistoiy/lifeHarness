/// C 案批6d · N2/N3/M3/M4 回写原型常驻守护（2026-11-07）。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('① N2 批量删除二次确认已回写壳', () {
    final s = File('prototype/index.html').readAsStringSync();
    expect(s, contains("if(!confirm('确定把选中的 '+noteSel.size+' 篇移入回收站？'))return;"),
        reason: '批量删除确认被摘除（产品裁定保留加固）');
  });

  test('② N3 树底条第 5 枚导出＋NT_IC.export', () {
    final s = File('prototype/index.html').readAsStringSync();
    expect(s, contains('id="ntBtExport"'), reason: '导出钮被摘除');
    expect(s, contains("function ntExport(){toast('已导出为本地目录（模拟）');}"),
        reason: '导出入口函数被摘除');
    expect(s, contains("export:'<svg"), reason: 'NT_IC export 键被摘除');
    expect(s, contains("\$('#ntBtExport')&&(\$('#ntBtExport').innerHTML=NT_IC.export);"),
        reason: '图标注入被摘除');
  });

  test('③ M3 影音架 FAB 直开新条目弹层', () {
    final s = File('prototype/index-media.html').readAsStringSync();
    expect(s, contains("'m-shelf':{ico:'＋',act:()=>openSheet('m-sheet-add')}"),
        reason: '架面 FAB 配置被摘除');
  });

  test('④ M4 批量条贴底通栏平底', () {
    final s = File('prototype/index-media.html').readAsStringSync();
    expect(s, contains('bottom-0 left-0 right-0 z-30 px-5 py-3'),
        reason: '批量条回退悬浮胶囊');
    expect(s, isNot(contains(r'bottom-20 left-4 right-4 z-30 p-3 rounded-2xl')),
        reason: '悬浮胶囊形态复活');
  });
}
