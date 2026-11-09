/// 纯 UI/UX 余项守护（2026-11-09 · 本轮核实＋收尾）。
/// 规格依据：
///  - 交棒话术-20261107 §9/§12/§10：`openSheet('sheetAddMedia')` 与 `'p-records'`
///    四段 FAB 死调用＝批4 已清；本轮补清漏网的 `closeSheet` 侧，计时器可达链
///    `renderMedia` 保留（属 §13 剩余债「另一批大手术」，不越界清）。
///  - 评估结论-20261019 §5/§17：批P5 贴点气泡（两枚·四档落位·`MmBubbleProbe.tier`
///    ·`debugBubbleDelegate`）已实现，核实后不重写。
///  - 交互整改开发计划-20261003 批八＋表单浮动标签整改规格 §11：
///    「维持现状／不扩面」「永久豁免」项一律不动。
///  - 阅读专版段级 align/margin 面全是语义对齐属性与间距档，无零视觉等价写法
///    可归一，本轮跳过。
/// 纯源码级：只读 `prototype/` 与 `lib/features/mindmap/`，不起整机、不建库、不执行实现。
/// 每条用例＝正档（盘上真实源码通过守卫）＋负档（内存注入缺陷、守卫必须拒绝）双断，
/// 避免「断言值恰好等于分支没进的结果」这类恒等假绿。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _proto(String name) => File('prototype/$name').readAsStringSync();

String _bubblePart() => File(
        'lib/features/mindmap/presentation/mindmap_canvas_bubble.dart')
    .readAsStringSync();

/// 守卫①a：零指向已删弹层的任何调用（open/close/RED/markup 一网打尽）。
bool _noDead(String s) => !s.contains('sheetAddMedia');

/// 守卫①b：计时器可达链保留——防「整块删光」造成零命中假绿。
bool _chainIntact(String s) => s.contains('renderMedia();');

/// 守卫②：FAB_CFG 定义块零 `'p-records'` 键，且首页键仍在（块未被截空）。
bool _fabCfgGuard(String s) {
  final a = s.indexOf('const FAB_CFG={');
  if (a < 0) return false;
  final e = s.indexOf('};', a);
  if (e < 0) return false;
  final blk = s.substring(a, e);
  return !blk.contains("'p-records':") && blk.contains("'p-dashboard':");
}

/// 守卫③：批P5 气泡实现在册（贴节点上沿两枚·四档落位·探针·调试入口）。
bool _bubbleGuard(String s) =>
    s.contains('class _MmBubbleDelegate') &&
    s.contains("String tier = 'top'") &&
    s.contains("'right'") &&
    s.contains("'left'") &&
    s.contains("'below'") &&
    s.contains('class MmBubbleProbe') &&
    s.contains('debugBubbleDelegate');

/// 守卫④：按盘上真实行尾纯正（media/mindmap CRLF、bookshelf LF）。
bool _eolGuard(String s, {required bool crlf}) {
  final stripped = s.replaceAll('\r\n', '');
  if (crlf) {
    return s.contains('\r\n') &&
        !stripped.contains('\r') &&
        !stripped.contains('\n');
  }
  return !s.contains('\r');
}

/// 守卫⑤：产品裁定维持项与 §13 孪生链仍在册（未被本轮越界清）。
bool _keptGuard(String s) =>
    s.contains('text-[9px]') &&
    s.contains('btnRecSwitch') &&
    s.contains("'p-records':['");

void main() {
  const media = 'index-media.html';
  const shelf = 'index-bookshelf.html';
  const mind = 'index-mindmap.html';

  test('① 三份专版零 sheetAddMedia 死调用（含 close 侧）· 计时器可达链仍在', () {
    for (final name in <String>[media, shelf]) {
      final s = _proto(name);
      expect(_noDead(s), isTrue, reason: '正档：$name 修复态零死调用');
      expect(_chainIntact(s), isTrue, reason: '正档：$name 可达链保留');
      expect(
          _noDead(s.replaceFirst(
              'renderMedia();', "closeSheet('sheetAddMedia');renderMedia();")),
          isFalse,
          reason: '负档：$name 注回 close 死调用，守卫须拒绝');
      expect(_chainIntact(s.replaceAll('renderMedia();', '')), isFalse,
          reason: '负档：$name 可达链被越界清掉，守卫须拒绝');
    }
    final m = _proto(mind);
    expect(_noDead(m), isTrue, reason: '正档：导图专版零该死调用');
    expect(_noDead(m.replaceFirst('mmSyncBubble',
            "closeSheet('sheetAddMedia');mmSyncBubble")),
        isFalse,
        reason: '负档：导图专版注回死调用，守卫须拒绝');
  });

  test('② FAB_CFG 零 p-records 键 · 首页键与其余配置仍在', () {
    for (final name in <String>[media, shelf]) {
      final s = _proto(name);
      expect(_fabCfgGuard(s), isTrue, reason: '正档：$name FAB_CFG 应无死键');
      // 注入必须落在 FAB_CFG 块内：`'p-dashboard':` 在文件里首次出现可能在
      // 其它常量表（不在块内），replaceFirst 会打偏＝负档假通过。
      expect(
          _fabCfgGuard(s.replaceFirst(
              'const FAB_CFG={', "const FAB_CFG={'p-records':{},")),
          isFalse,
          reason: '负档：$name 复活 p-records 键，守卫须拒绝');
      expect(
          _fabCfgGuard(
              s.replaceFirst('const FAB_CFG={', 'const FAB_CFG_OFF={')),
          isFalse,
          reason: '负档：$name 配置块被改名，守卫须拒绝');
    }
  });

  test('③ 批P5 贴点气泡实现与原型样张在册 · 未被重写或清空', () {
    final s = _bubblePart();
    expect(_bubbleGuard(s), isTrue, reason: '正档：气泡四档落位与探针齐备');
    expect(
        _bubbleGuard(s.replaceAll("String tier = 'top'", 'String tier = 0')),
        isFalse,
        reason: '负档：抹掉 tier 档位，守卫须拒绝');
    // 不能改成 xxxOff：原串是前缀 ⇒ contains 仍为 true＝负档假通过。
    expect(
        _bubbleGuard(s.replaceAll('debugBubbleDelegate', '')),
        isFalse,
        reason: '负档：调试入口被抹掉，守卫须拒绝');
    final p = _proto(mind);
    expect(p.contains('mmSyncBubble'), isTrue, reason: '正档：原型气泡同步在册');
    expect(p.contains('MAXW=280'), isTrue, reason: '正档：§18 上限统一在册');
    expect(p.replaceAll('mmSyncBubble', 'mmSyncOff').contains('mmSyncBubble'),
        isFalse,
        reason: '负档：原型气泡被撤，守卫须拒绝');
    expect(p.replaceAll('MAXW=280', 'MAXW=300').contains('MAXW=280'), isFalse,
        reason: '负档：上限被回退，守卫须拒绝');
  });

  test('④ 三份原型行尾纯正 · 未因改动 smudge', () {
    for (final name in <String>[media, mind]) {
      final s = _proto(name);
      expect(_eolGuard(s, crlf: true), isTrue, reason: '正档：$name 应为纯 CRLF');
      expect(_eolGuard(s.replaceFirst('\r\n', '\n'), crlf: true), isFalse,
          reason: '负档：$name 混入孤立 LF，守卫须拒绝');
    }
    final b = _proto(shelf);
    expect(_eolGuard(b, crlf: false), isTrue, reason: '正档：$shelf 应为纯 LF');
    expect(_eolGuard(b.replaceFirst('\n', '\r\n'), crlf: false), isFalse,
        reason: '负档：$shelf 混入 CRLF，守卫须拒绝');
  });

  test('⑤ 产品裁定「维持现状／不扩面」项与 §13 孪生链仍在册', () {
    final b = _proto(shelf);
    // T15 装饰小字（批七已推全，批八裁定不再对剩余装饰小字提对比）；
    // R-G3 历史靛紫阴影属「只记清单、另批治理」，本轮不动。
    expect(b.contains('text-[9px]'), isTrue, reason: '正档：装饰小字档位维持');
    expect(b.contains('shadow-indigo-500'), isTrue,
        reason: '正档：靛紫阴影维持未动');
    expect(_keptGuard(b), isTrue, reason: '正档：孪生元数据表与 JS 维持');
    expect(_keptGuard(b.replaceAll('btnRecSwitch', 'btnRecX')), isFalse,
        reason: '负档：孪生 JS 被越界清，守卫须拒绝');
    expect(_keptGuard(b.replaceAll("'p-records':['", "'p-recordsX':['")),
        isFalse,
        reason: '负档：孪生元数据表被越界清，守卫须拒绝');
  });
}
