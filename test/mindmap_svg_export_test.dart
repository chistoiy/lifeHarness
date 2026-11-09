import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 导图 SVG 导出入口守护（源码级）：选项在册、执行分支接既有落盘出口、
/// 节点树保留父子关系、且**不许冒充 PDF**（零依赖下 PDF 只走可打印 HTML）。
const _f =
    'lib/features/mindmap/presentation/mindmap_export_actions.dart';

String _src() => File(_f).readAsStringSync();

void main() {
  test('① SVG 选项与执行分支在册，且不含冒充 PDF 的选项', () {
    final s = _src();
    expect(s.contains("('svg', 'SVG 矢量图'"), isTrue,
        reason: '正档：格式项在册');
    expect(s.contains("case 'svg':"), isTrue, reason: '正档：执行分支在册');
    expect(s.contains('saveMindmapSvgAs('), isTrue,
        reason: '正档：接既有落盘出口（零新增原生通道）');
    expect(s.contains("case 'pdf':"), isFalse, reason: '负档：不冒充 PDF 格式');
    expect(s.contains('已导出 PDF'), isFalse, reason: '负档：不许假承诺');
  });

  test('② SVG 只带结构：正文开关对它置灰', () {
    final s = _src();
    expect(s.contains("bool get _isSvg => _fmt == 'svg';"), isTrue,
        reason: '正档：新增判定');
    expect(s.contains('_isPng || _isXmind || _isSvg'), isTrue,
        reason: '正档：并入「无正文语义」');
    expect(s.contains('_isPng || _isXmind;'), isFalse,
        reason: '负档：旧的两项口径不许残留');
  });

  test('③ 节点树扁平化保留父子关系', () {
    final s = _src();
    expect(s.contains(r"parentId: n.parentId == null ? null : '${n.parentId}'"),
        isTrue,
        reason: '正档：父子关系带出');
    expect(s.contains(r"id: '${n.id ?? 0}'"), isTrue, reason: '正档：节点 id 转串');
    expect(s.contains('nodes: svgNodes'), isTrue, reason: '正档：交给序列化层');
    expect(s.contains('width: choice.landscape ? 1280 : 960'), isTrue,
        reason: '正档：横向预设生效');
  });
}
