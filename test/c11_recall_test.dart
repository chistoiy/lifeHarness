import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/ai/local_recall.dart';

/// C11 本地关键词召回守护。判据＝每条用例正档 true／负档 false 同例都断，
/// 避免「被测分支压根没进也会过」的假绿（变异刀要能打红）。
void main() {
  const docs = <RecallDoc>[
    RecallDoc(id: 'n1', title: '相机保养', body: '每半年给镜头做一次保养，换干燥剂。'),
    RecallDoc(id: 'n2', title: '周报', body: '本周完成了归档与导出。'),
    RecallDoc(id: 'n3', title: '保养清单', body: '保养记录：皮腔、快门、取景器。'),
  ];

  test('① 正档命中／负档不相关文档不返回，且引用可见', () {
    final hits = localRecall(query: '保养', docs: docs);
    expect(hits, isNotEmpty, reason: '正档：应召回');
    // 不钉死首位 id（中文切词会同时产生单字/双字组，首名随词频浮动）；
    // 改断「两篇相关都进、不相关不进、分数降序」＝排序对不对照样有判定力。
    expect(hits.map((h) => h.docId).toSet(), containsAll(<String>['n1', 'n3']),
        reason: '正档：两篇含「保养」的文档都应召回');
    expect(hits.first.title, isNotEmpty, reason: '引用来源标题可见');
    expect(hits.first.score, greaterThan(0));
    expect(hits.any((h) => h.docId == 'n2'), isFalse,
        reason: '负档：不相关文档不许进结果');
    expect(hits.any((h) => h.docId == 'unknown'), isFalse);
    for (var i = 1; i < hits.length; i++) {
      expect(hits[i - 1].score >= hits[i].score, isTrue,
          reason: '负档：结果必须按分数降序');
    }
  });

  test('② 可关闭：enabled=true 非空 / enabled=false 恒空（同一例两档对照）', () {
    expect(localRecall(query: '保养', docs: docs, enabled: true), isNotEmpty);
    expect(localRecall(query: '保养', docs: docs, enabled: false), isEmpty,
        reason: '负档：关闭检索必须零召回');
  });

  test('③ 不上传全库：长文只回短片段，超长 body 不被整段带出', () {
    final long = '保养${List.filled(60, '镜头清灰与防潮记录。').join()}';
    final hits = localRecall(
      query: '保养',
      docs: [RecallDoc(id: 'long', title: '长文', body: long)],
      maxHits: 1,
      snippetChars: 80,
    );
    expect(hits, hasLength(1));
    expect(hits.first.snippet.length, lessThanOrEqualTo(80),
        reason: '正档：片段被截');
    expect(hits.first.snippet, isNot(equals(long)),
        reason: '负档：不许整段全文进 prompt');
    expect(hits.first.snippet.contains('保养'), isTrue,
        reason: '正档：片段含命中词');
    expect(hits.first.snippet.contains('\n'), isFalse,
        reason: '负档：换行压平，不破 prompt 行');
  });

  test('④ 标题命中权重高于正文：同例两档对照', () {
    const two = <RecallDoc>[
      RecallDoc(id: 'a', title: '保养', body: '保养一次'),
      RecallDoc(id: 'b', title: '杂记', body: '保养保养'),
    ];
    final hits = localRecall(query: '保养', docs: two, maxHits: 2);
    expect(hits.first.docId, 'a',
        reason: '正档：标题加权后排前（a 得分高于 b）');
    expect(hits.last.docId, 'b', reason: '负档：另一篇仍在但不占首');
  });

  test('⑤ TopK 限制与稳定排序', () {
    final many = <RecallDoc>[
      for (var i = 0; i < 6; i++)
        RecallDoc(id: 'd$i', title: '保养', body: '保养'),
    ];
    final hits = localRecall(query: '保养', docs: many, maxHits: 2);
    expect(hits, hasLength(2), reason: '正档：不超 maxHits');
    expect(hits.first.docId, 'd0', reason: '负档：同分按 id 稳定，不许乱序');
    expect(localRecall(query: '保养', docs: many, maxHits: 0), isEmpty);
  });

  test('⑥ 空查询／纯停用词零召回（防「查什么都回全库」）', () {
    expect(localRecall(query: '', docs: docs), isEmpty);
    expect(localRecall(query: '的 了 和', docs: docs), isEmpty);
    expect(recallTerms(''), isEmpty);
  });

  test('⑦ 切词：中英混排、停用词过滤、去重', () {
    final terms = recallTerms('相机 Camera 保养');
    expect(terms.contains('camera'), isTrue, reason: '正档：拉丁词小写归一');
    expect(terms.contains('保养'), isTrue, reason: '正档：中文双字组');
    expect(terms.contains('的'), isFalse, reason: '负档：停用词不进');
    expect(terms.toSet().length, terms.length, reason: '负档：不许重复词');
  });
}
