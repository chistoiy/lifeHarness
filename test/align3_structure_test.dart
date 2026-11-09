import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 三段专版细节对齐 · 零视觉判定项源码级守护（规格＝tmp/align3/spec.md §2/§5）。
/// 判据＝每个动刀项在同一条用例里「新形态存在」＋「旧错误形态不存在」成对断言，
/// 防止「被测分支压根没进也会过」的假绿。
const _journal = 'prototype/index-journal.html';
const _bookshelf = 'prototype/index-bookshelf.html';

List<int> _bytes(String p) => File(p).readAsBytesSync();
String _text(String p) => File(p).readAsStringSync();

void main() {
  test('① 两份专版行尾保真＝纯 LF，CR 零命中，字节数精确对齐规格', () {
    expect(_bytes(_journal).length, 458841,
        reason: 'journal 改后实测 458788+53');
    expect(_bytes(_bookshelf).length, 655031,
        reason: 'bookshelf 改后实测 654932+99');
    for (final p in [_journal, _bookshelf]) {
      final b = _bytes(p);
      expect(b.contains(13), isFalse, reason: '$p 出现 CR＝行尾被污染');
      expect(b.where((x) => x == 10).length, p == _journal ? 4797 : 6649,
          reason: '$p LF 数漂移');
    }
  });

  test('② J1/B1 前景叠加图补 alt：正档存在＋负档旧裸 img 不存在', () {
    const oldImg =
        '<img src="assets/lh_img_4a6cf0a2.jpg" style="inset:16%';
    const newImg =
        '<img src="assets/lh_img_4a6cf0a2.jpg" alt="" style="inset:16%';
    for (final p in [_journal, _bookshelf]) {
      final s = _text(p);
      expect(s.contains(newImg), isTrue, reason: '$p 正档：alt 已补');
      expect(s.contains(oldImg), isFalse, reason: '$p 负档：旧裸 img 仍在');
    }
  });

  test('③ J2a/J2b 笔记编辑两枚纯图标按钮补 aria-label：正负两档', () {
    final j = _text(_journal);
    expect(j.contains('class="pw-ic-btn text-xl" aria-label="返回"'), isTrue,
        reason: '正档：返回钮有可访问名');
    expect(j.contains('class="pw-ic-btn" aria-label="更多选项"'), isTrue,
        reason: '正档：更多钮有可访问名');
    expect(j.contains('class="pw-ic-btn text-xl">‹'), isFalse,
        reason: '负档：旧裸返回钮');
    expect(j.contains('class="pw-ic-btn">⋯'), isFalse,
        reason: '负档：旧裸更多钮');
  });

  test('④ B2 状态值与渲染比较值同型：中文初值在、英文旧值不在', () {
    final b = _text(_bookshelf);
    expect(b.contains("newPos:'开头',yearSort:'升序'"), isTrue,
        reason: '正档：与 chips 选项同值域');
    expect(b.contains("newPos:'head',yearSort:'asc'"), isFalse,
        reason: '负档：旧英文初值会让默认态 chip 无一高亮');
  });

  test('⑤ B3a/B3b X-Ray 容器与开关补 role/aria：正负两档', () {
    final b = _text(_bookshelf);
    expect(b.contains('id="xrcTabs" role="tablist" aria-label="X-Ray 视图"'),
        isTrue,
        reason: '正档：tab 容器有 role');
    expect(
        b.contains('id="xrwToggle" role="switch" aria-label="启用养成词库"'),
        isTrue,
        reason: '正档：开关有 role 与可访问名');
    expect(b.contains('<div class="mt-2.5 flex gap-1.5" id="xrcTabs">'),
        isFalse,
        reason: '负档：旧裸容器');
    expect(b.contains('<span class="toggle on" id="xrwToggle" onclick='),
        isFalse,
        reason: '负档：旧裸开关');
  });

  test('⑥ 零新增原型屏 id：两份专版 p- 屏集合数量不变', () {
    final j = _text(_journal);
    final b = _text(_bookshelf);
    expect(RegExp(r'id="p-').allMatches(j).length, 3,
        reason: 'journal 开工前 3 屏');
    expect(RegExp(r'id="p-').allMatches(b).length, 21,
        reason: 'bookshelf 开工前 21 屏');
  });
}
