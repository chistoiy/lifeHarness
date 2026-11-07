import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/features/read/data/read_import.dart';

/// 微信读书「整本导出」解析（2026-10-29 产品报障：解析为空 / 按清单建书
/// 33 条笔记被建成 60+ 本）。
const _sample = '''《资治通鉴·横排版（胡三省注）294卷全》
司馬光 胡三省 鄒寰宇
23个笔记
資治通鑑卷第一
◆ 2026/10/28发表想法
韩魏害怕了，灭赵氏之后，韩魏必定继续被清算，因此心照不宣，要做新打算
原文：桓子肘康子，康子履桓子之跗
◆ 2026/10/28发表想法
此时唇亡齿寒，后面卷二就开始围魏救赵了
原文：臣聞脣亡則齒寒
◆ 卑不謀尊，疏不謀戚
◆ 居視其所親，富視其所與
-- 来自微信读书
''';

void main() {
  final ch = ImportChannel(
    id: 'clip_weread',
    cat: 'clip',
    name: '微信读书',
    fmt: '自动识别',
    parser: 'weread',
    config: {
      'pattern': r'(?<body>[^\n]+(?:\n(?!——)[^\n]+)*)\n+——《(?<book>[^》\n]+)》[^\n]*',
    },
  );

  test('整本导出：书名/作者/章节/想法＋原文/纯划线', () {
    final clips = parseClips(ch, _sample);
    expect(clips, hasLength(4), reason: '两条想法＋两条纯划线');
    expect(clips.every((c) => c.book == '资治通鉴·横排版（胡三省注）294卷全'), isTrue,
        reason: '书名只在首行出现一次，不该被当成多条');
    expect(clips.first.author, '司馬光 胡三省 鄒寰宇');
    expect(clips.first.chapter, '資治通鑑卷第一');
    expect(clips.first.thought, contains('韩魏害怕了'));
    expect(clips.first.body, '桓子肘康子，康子履桓子之跗');
    expect(clips.first.at, DateTime(2026, 10, 28));
    expect(clips[2].thought, isNull, reason: '纯划线没有想法');
    expect(clips[2].body, '卑不謀尊，疏不謀戚');
  });

  test('按清单建书：整本导出只建 1 本（原实现逐行当书名 → 60+ 本）', () {
    final rows = parseBookList(_sample);
    expect(rows, hasLength(1));
    expect(rows.single.title, '资治通鉴·横排版（胡三省注）294卷全');
    expect(rows.single.author, '司馬光 胡三省 鄒寰宇');
  });

  test('旧单条划线格式仍走原正则（复制单条时的格式不能坏）', () {
    final clips = parseClips(
        ch, '所谓门槛，能力够了就是门，能力不够就是槛。\n——《人生算法》 第三章 边界 P42');
    expect(clips, hasLength(1));
    expect(clips.single.book, '人生算法');
  });
}
