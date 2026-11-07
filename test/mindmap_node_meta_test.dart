import 'dart:convert' show jsonDecode, utf8;

import 'package:archive/archive.dart' show ZipDecoder;
import 'package:flutter/material.dart' show ColorScheme;
import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/features/mindmap/domain/mindmap_export.dart';
import 'package:lifeharness/features/mindmap/domain/mindmap_measure.dart';
import 'package:lifeharness/features/mindmap/domain/mindmap_models.dart';
import 'package:lifeharness/features/mindmap/domain/mindmap_node_meta.dart';
import 'package:lifeharness/features/mindmap/domain/mindmap_style.dart';
import 'package:lifeharness/shared/linkage/linkage_events.dart';

/// 批5 F4-9 · 节点增强域层（工单 §4f.1 主体件·**纯 Dart 零 widget**）。
///
/// 覆盖五条：
/// ① 标签编解码（含**损坏回落**＝变异刀2 钉点）；
/// ② 任务事件载荷与 `TaskCompletedEvent` 向后兼容；
/// ③ 度量加宽（`extraWidth` 进盒宽，默认态逐值不变）；
/// ④ `.xmind` 序列化（三文件齐 ＋ 标签/任务字段在＝变异刀3 钉点）；
/// ⑤ 角标色进 `MmPaintStyle`（== / hashCode 自洽＝重画判据）。
void main() {
  group('① 标签：输入切分 → JSON 落库 → 读回', () {
    test('半角/全角逗号都切、逐项 trim、去重保序', () {
      expect(mmTagsParse(' 方法论 , 复盘 '), ['方法论', '复盘']);
      expect(mmTagsParse('a，b，c'), ['a', 'b', 'c']);
      expect(mmTagsParse('a, a, b'), ['a', 'b'],
          reason: '重名标签画布叠 chip，无信息量');
      expect(mmTagsParse('  ,  ,'), isEmpty);
      expect(mmTagsParse(''), isEmpty);
    });

    test('落库为 JSON 数组文本；读回逐值相等（round-trip）', () {
      final tags = ['方法论', '带,逗号的标签', 'x'];
      final raw = mmTagsEncode(tags);
      expect(raw, isNotNull);
      expect(raw, contains('带,逗号的标签'));
      expect(mmTagsDecode(raw), tags,
          reason: '标签含逗号时必须靠 JSON 而非分隔串保真');
    });

    test('空列表落 null（不写 "[]" 污染存量行）', () {
      expect(mmTagsEncode(const []), isNull);
      expect(mmTagsDecode(null), isEmpty);
      expect(mmTagsDecode(''), isEmpty);
      expect(mmTagsDecode('   '), isEmpty);
    });

    test('**损坏文本回落空列表不抛**（变异刀2 钉点：真机可能被改库）', () {
      expect(mmTagsDecode('{不是 json'), isEmpty);
      expect(mmTagsDecode('[1, 2]'), isEmpty, reason: '非字符串元素一律丢弃');
      expect(mmTagsDecode('"字符串"'), isEmpty, reason: '不是数组即视为无标签');
      expect(mmTagsDecode('[null, " ok "]'), ['ok']);
    });

    test('读回格式与写回解析互逆', () {
      expect(mmTagsParse(mmTagsFormat(['a', 'b'])), ['a', 'b']);
      expect(mmTagsFormat(const []), '');
    });

    test('模型 fromRow 走同一份解析（只有一处口径）', () {
      final n = MindmapNode.fromRow({
        'id': 1,
        'map_id': 1,
        'title': 'x',
        'tags': '["a","b"]',
        'is_task': 1,
        'task_done': 0,
        'image_path': '/tmp/a.jpg',
        'created_at': 1,
        'updated_at': 1,
      });
      expect(n.tags, ['a', 'b']);
      expect(n.isTask, isTrue);
      expect(n.taskDone, isFalse);
      expect(n.hasImage, isTrue);
      // 老行（四列全缺）零值
      final old = MindmapNode.fromRow(
          {'id': 2, 'map_id': 1, 'title': 'y', 'created_at': 1, 'updated_at': 1});
      expect(old.tags, isEmpty);
      expect(old.isTask, isFalse);
      expect(old.hasImage, isFalse);
    });
  });

  group('② 任务：事件载荷与向后兼容', () {
    test('载荷带 source=mindmap 与节点标题（订阅方按 source 分流）', () {
      final e = MmNodeTaskEvent(
          mapId: 3, nodeId: 9, nodeTitle: '写周报', atMs: 123);
      expect(e.source, 'mindmap');
      expect(mmTaskEventSource, 'mindmap');
      expect(e.nodeTitle, '写周报');
      expect(e.mapId, 3);
      expect(e.nodeId, 9);
    });

    test('TaskCompletedEvent 新增 source 默认 todo ⇒ 既有构造逐值不变', () {
      const e = TaskCompletedEvent(42, 1000);
      expect(e.todoId, 42);
      expect(e.atMs, 1000);
      expect(e.source, 'todo', reason: 'todo_repository 唯一发射处行为零变化');
      const e2 = TaskCompletedEvent(42, 1000, source: 'x');
      expect(e2.source, 'x');
    });
  });

  group('③ 度量：extraWidth 进盒宽，默认态逐值不变', () {
    test('extra=0 与不给 extraWidth 同值（默认态零视觉变化的机制面）', () {
      expect(mmNodeMeasure('标题', extraWidth: 0), mmNodeMeasure('标题'));
    });

    test('三段各占一份加宽，合计等于 mmNodeExtraWidth', () {
      expect(
          mmNodeExtraWidth(
              tags: const [], isTask: false, hasImage: false, tagWidth: 0),
          0);
      expect(
          mmNodeExtraWidth(
              tags: const [], isTask: true, hasImage: false, tagWidth: 0),
          18);
      expect(
          mmNodeExtraWidth(
              tags: const [], isTask: false, hasImage: true, tagWidth: 0),
          25);
      expect(
          mmNodeExtraWidth(
              tags: const ['a'], isTask: true, hasImage: true, tagWidth: 18),
          18 + 25 + 21);
    });

    test('标签越多盒越宽（度量与 painter 同一份占宽源）', () {
      final one = mmNodeMeasure('标题',
          extraWidth: mmNodeExtraWidth(
              tags: const ['a'], isTask: false, hasImage: false, tagWidth: 18));
      final two = mmNodeMeasure('标题',
          extraWidth: mmNodeExtraWidth(
              tags: const ['a', 'b'],
              isTask: false,
              hasImage: false,
              tagWidth: 18));
      expect(two.width, greaterThan(one.width));
    });

    test('extraWidth 不改行高（只加宽，不打乱纵向间距口径）', () {
      final a = mmNodeMeasure('标题');
      final b = mmNodeMeasure('标题', extraWidth: 60);
      expect(b.height, a.height);
    });

    test('盒宽仍受 maxWidth 封顶（标签再多也不撑破布局）', () {
      final w = mmNodeMeasure('标题',
              maxWidth: 200,
              extraWidth: 9999)
          .width;
      expect(w, lessThanOrEqualTo(200));
    });
  });

  group('④ .xmind 只出不进（批5 F4-9）', () {
    List<MindmapNode> rows() {
      var t = 1000;
      MindmapNode mk(int id, int? pid, String title,
              {int sort = 0,
              List<String> tags = const <String>[],
              bool task = false}) =>
          MindmapNode(
            id: id,
            mapId: 1,
            parentId: pid,
            title: title,
            note: id == 1 ? '根备注' : '',
            sort: sort,
            tags: tags,
            isTask: task,
            createdAt: t++,
            updatedAt: t,
          );
      return [
        mk(1, null, '根A', tags: ['方法论', '复盘'], task: true),
        mk(2, 1, '子A1', sort: 0),
        mk(3, 1, '子A2', sort: 1),
      ];
    }

    Map<String, dynamic> unzip(List<int> bytes) {
      final arc = ZipDecoder().decodeBytes(bytes);
      final out = <String, dynamic>{};
      for (final f in arc.files) {
        if (!f.isFile) continue;
        out[f.name] = jsonDecode(utf8.decode(f.content as List<int>));
      }
      return out;
    }

    test('zip 内三文件齐全（content/metadata/manifest）', () {
      final files = unzip(mmExportXmindBytes(mapTitle: '图名', rows: rows()));
      expect(files.keys,
          containsAll(['content.json', 'metadata.json', 'manifest.json']));
    });

    test('content.json 是 sheet 数组、标题与 rootTopic 在', () {
      final files = unzip(mmExportXmindBytes(mapTitle: '图名', rows: rows()));
      final content = files['content.json'] as List;
      expect(content, hasLength(1));
      final sheet = content.first as Map<String, dynamic>;
      expect(sheet['class'], 'sheet');
      expect(sheet['title'], '图名');
      final root = sheet['rootTopic'] as Map<String, dynamic>;
      expect(root['title'], '根A');
      expect(root['notes'], isNotNull, reason: '备注写进 notes.plain');
    });

    test('**标签与任务字段在**（变异刀3 钉点：摘掉即红）', () {
      final files = unzip(mmExportXmindBytes(mapTitle: '图名', rows: rows()));
      final content = files['content.json'] as List;
      final root = (content.first as Map)['rootTopic'] as Map;
      expect(root['labels'], ['方法论', '复盘']);
      expect(root['progress'], -1, reason: '任务未完成用 -1（XMind 无进度语义）');
      final kids = (root['children'] as Map)['attached'] as List;
      expect(kids, hasLength(2));
      expect((kids.first as Map).containsKey('labels'), isFalse,
          reason: '无标签的节点不该写空数组');
      expect((kids.first as Map).containsKey('progress'), isFalse,
          reason: '非任务节点不该写 progress');
    });

    test('完成态 progress=100；取消任务属性后不写', () {
      final done = rows().first.copyWith(taskDone: true);
      final files = unzip(mmExportXmindBytes(
          mapTitle: '图名', rows: [done, ...rows().skip(1)]));
      final content = files['content.json'] as List;
      final root = (content.first as Map)['rootTopic'] as Map;
      expect(root['progress'], 100);
      final off = done.copyWith(isTask: false);
      final f2 = unzip(mmExportXmindBytes(
          mapTitle: '图名', rows: [off, ...rows().skip(1)]));
      final c2 = f2['content.json'] as List;
      expect(((c2.first as Map)['rootTopic'] as Map).containsKey('progress'),
          isFalse);
    });

    test('多根：rootTopic 取图名、各根作 attached 子级（XMind 单根折中）', () {
      final files = unzip(mmExportXmindBytes(mapTitle: '多根图', rows: [
        MindmapNode(id: 1, mapId: 1, title: '根A', createdAt: 1, updatedAt: 1),
        MindmapNode(id: 2, mapId: 1, title: '根B', createdAt: 1, updatedAt: 1),
      ]));
      final content = files['content.json'] as List;
      final root = (content.first as Map)['rootTopic'] as Map;
      expect(root['title'], '多根图');
      final kids = (root['children'] as Map)['attached'] as List;
      expect(kids.map((e) => (e as Map)['title']), ['根A', '根B']);
    });

    test('manifest 声明 xmind-workbook ＋ 两份 json 条目', () {
      final files = unzip(mmExportXmindBytes(mapTitle: '图名', rows: rows()));
      final m = files['manifest.json'] as Map;
      expect(m['file-type'], 'xmind-workbook');
      final entries = (m['entries'] as List).cast<Map>();
      expect(entries.map((e) => e['fileName']),
          containsAll(['content.json', 'metadata.json']));
    });

    test('空图不炸（导出按钮对空图也点得到）', () {
      final files =
          unzip(mmExportXmindBytes(mapTitle: '空图', rows: const []));
      expect(files.keys, contains('content.json'));
    });
  });

  group('⑤ 样式面：批5 角标色进 MmPaintStyle（== / hashCode 自洽）', () {
    test('baseline 带齐五个角标色且两份逐值相等', () {
      final a = MmPaintStyle.baseline(const ColorScheme.light());
      final b = MmPaintStyle.baseline(const ColorScheme.light());
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.okColor, isNot(a.nodeBg));
      expect(a.tagText, a.accent, reason: '标签字色与强调色同源（零新增色值）');
    });

    test('改任一角标色即视为不等（shouldRepaint 的判据面）', () {
      final a = MmPaintStyle.baseline(const ColorScheme.light());
      final b = MmPaintStyle(
        bg: a.bg,
        grid: a.grid,
        nodeBg: a.nodeBg,
        nodeBorder: a.nodeBorder,
        nodeText: a.nodeText,
        edge: a.edge,
        accent: a.accent,
        accentSoft: a.accentSoft,
        lineW: a.lineW,
        fontSize: a.fontSize,
        dots: a.dots,
        okColor: a.nodeBorder, // 只改这一个
        onOkColor: a.onOkColor,
        thumbBg: a.thumbBg,
        tagBg: a.tagBg,
        tagText: a.tagText,
      );
      expect(b == a, isFalse);
    });
  });
}
