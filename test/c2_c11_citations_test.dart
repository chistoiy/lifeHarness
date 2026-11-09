import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/ai/local_recall.dart';
import 'package:lifeharness/core/ai/recall_citations.dart';

/// C11 审阅页「本地引用」守护。判据＝每条正档 true／负档 false 同例都断，
/// 防「被测分支压根没进也会过」的假绿。纯函数级，不 pumpAndSettle。
void main() {
  const hits = <RecallHit>[
    RecallHit(docId: 'n1', title: '相机保养', snippet: '每半年清灰换干燥剂', score: 5),
    RecallHit(docId: 'n2', title: '周报', snippet: '本周完成归档', score: 3),
    RecallHit(docId: 'n3', title: '保养清单', snippet: '皮腔快门取景器', score: 2),
    RecallHit(docId: 'n4', title: '杂记', snippet: '随手记', score: 1),
  ];

  test('① 可关闭：enabled=true 有引用 / false 恒空（同例两档对照）', () {
    final on = recallCitations(hits, enabled: true);
    expect(on, isNotEmpty, reason: '正档：开关开应投影出引用');
    expect(on.length, 3, reason: '正档：默认至多 3 条');
    expect(recallCitations(hits, enabled: false), isEmpty,
        reason: '负档：settings 关＝零引用');
  });

  test('② 只短片段与来源：不含正文全库，来源可见', () {
    final cs = recallCitations(hits);
    final section = formatCitationSection(cs);
    expect(section, contains('相机保养'), reason: '正档：来源标题可见');
    expect(section, contains('n1'), reason: '正档：来源 id 可见');
    expect(section, contains('每半年清灰换干燥剂'), reason: '正档：短片段可见');
    expect(cs.first.runtimeType, RecallCitation);
    expect(section, isNot(contains('全文')), reason: '负档：引用段不宣称带全文');
    expect(formatCitationSection(const <RecallCitation>[]), isEmpty,
        reason: '负档：空引用不产生段');
  });

  test('③ 截断与顺序：TopK 生效且沿用分数降序', () {
    final top2 = recallCitations(hits, maxCitations: 2);
    expect(top2, hasLength(2), reason: '正档：不超 maxCitations');
    expect(top2.first.docId, 'n1', reason: '正档：沿用输入（分数降序）首位');
    expect(recallCitations(hits, maxCitations: 0), isEmpty,
        reason: '负档：0 条恒空');
  });

  test('④ attachRecallToUser：关＝原样 / 开＝注入短片段且不含全库', () {
    const user = '请总结本月保养要点';
    expect(attachRecallToUser(user, hits, enabled: false), equals(user),
        reason: '负档：关闭时零行为变化');
    final injected = attachRecallToUser(user, hits, enabled: true);
    expect(injected, startsWith(user), reason: '正档：保留原 user');
    expect(injected, contains('相机保养'), reason: '正档：引用来源进段');
    expect(injected, contains('本地参考片段'), reason: '正档：标注是参考片段');
    expect(injected, isNot(contains('每半年给镜头做一次保养换干燥剂并逐条记录全部细节')),
        reason: '负档：绝不拼入全库正文');
  });

  test('⑤ 与 localRecall 联动：命中→引用段含命中词', () {
    const docs = <RecallDoc>[
      RecallDoc(id: 'a', title: '保养', body: '保养保养，镜头与干燥剂。'),
      RecallDoc(id: 'b', title: '无关', body: '本周归档。'),
    ];
    final recalled = localRecall(query: '保养', docs: docs, enabled: true);
    expect(recalled, isNotEmpty, reason: '正档：内核召回命中');
    final section = formatCitationSection(recallCitations(recalled));
    expect(section, contains('保养'), reason: '正档：引用段带命中词');
    expect(section, isNot(contains('id:b')), reason: '负档：不相关文档不进');
    expect(
        formatCitationSection(
            recallCitations(localRecall(query: '保养', docs: docs, enabled: false))),
        isEmpty,
        reason: '负档：内核关＝引用段空');
  });
}
