import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/features/read/data/offline_meta.dart';

/// C09 离线元数据补全守护：纯本地解析，正负两档同例都断；零网络目的地。
void main() {
  const sample = '《相机保养笔记》\n'
      '作者：张三\n'
      'ISBN 9787111000000\n'
      '第三章 镜头\n'
      'P42\n'
      '位置 1234\n'
      '来自微信读书';

  test('① 剪贴板本地解析：正档抽全字段 / 负档坏数据全空', () {
    final m = parseClipboardMeta(sample);
    expect(m.book, '相机保养笔记', reason: '正档：书名');
    expect(m.author, '张三', reason: '正档：作者');
    expect(m.isbn, '9787111000000', reason: '正档：ISBN');
    expect(m.chapter, isNotNull, reason: '正档：章节');
    expect(m.page, 42, reason: '正档：页码');
    expect(m.loc, 1234.0, reason: '正档：位置');
    expect(m.source, 'weread', reason: '正档：渠道来源（本地识别）');
    expect(m.isEmpty, isFalse, reason: '正档：命中不算空');

    expect(parseClipboardMeta('').isEmpty, isTrue,
        reason: '负档：空文本不臆造');
    expect(parseClipboardMeta('-- 来自微信读书').isEmpty, isTrue,
        reason: '负档：纯脚注行不当书名');
  });

  test('② 批量粘贴：正档分块解析 / 负档过滤空块', () {
    final batch = parseClipboardBatch('《A》\n作者：甲\n\n《B》\n作者：乙\n\n\n');
    expect(batch, hasLength(2), reason: '正档：两块各解析一条');
    expect(batch.first.book, 'A');
    expect(batch.last.book, 'B');
    expect(parseClipboardBatch('\n\n\n'), isEmpty,
        reason: '负档：全空块零输出');
  });

  test('③ external_id 批量映射：正档多形态 / 负档未知来源与去重', () {
    final es = parseExternalIdBatch(
      'tmdb:123\n'
      '标题, douban:456\n'
      'imdb tt0111161\n'
      'https://movie.douban.com/subject/26264956/\n'
      'https://www.themoviedb.org/movie/999 备注\n'
      '# 注释行\n'
      'unknown:777\n'
      'tmdb:123\n', // 重复，应去重
    );
    expect(es, hasLength(5), reason: '正档：5 条有效映射（含 URL 与 kv）');
    expect(es.any((e) => e.source == 'tmdb' && e.id == '123'), isTrue);
    expect(es.any((e) => e.source == 'douban' && e.id == '456'), isTrue);
    expect(es.any((e) => e.source == 'imdb' && e.id == 'tt0111161'), isTrue);
    expect(es.any((e) => e.source == 'douban' && e.id == '26264956'), isTrue);
    expect(es.any((e) => e.source == 'tmdb' && e.id == '999'), isTrue);
    expect(es.where((e) => e.source == 'tmdb' && e.id == '123').length, 1,
        reason: '负档：同 (source,id) 去重');
    expect(es.any((e) => e.source == 'unknown'), isFalse,
        reason: '负档：未知来源跳过');
    expect(es.any((e) => e.id == '777'), isFalse,
        reason: '负档：注释/非法行不进');
  });

  test('④ 纯离线字典：来源集合固定，不新增网络目的地', () {
    expect(kExternalIdSources.contains('tmdb'), isTrue, reason: '正档：含 tmdb');
    expect(kExternalIdSources.contains('igdb'), isTrue, reason: '正档：含 igdb');
    expect(kExternalIdSources.contains('netflix'), isFalse,
        reason: '负档：不臆造未登记来源');
    expect(kExternalIdSources.length, 8);
  });
}
