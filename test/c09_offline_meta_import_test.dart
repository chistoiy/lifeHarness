import 'package:flutter_test/flutter_test.dart';

import 'package:lifeharness/features/read/data/offline_meta.dart';

/// C09 接线守护：批量粘贴解析 → 建书行 → 既有 importBookRows 去重链路。
///
/// 正档＝书目块解析出书名/作者/ISBN；负档＝空块、纯 external_id 文本不产书行
/// （不把「tmdb:123」臆造成书名）。
void main() {
  test('① 书目块 → 建书行：正档三列齐全 / 负档空书名跳过', () {
    final batch = parseClipboardBatch(
      '《相机保养笔记》\n'
      '作者：张三\n'
      'ISBN 9787111000000\n'
      '第三章 镜头\n'
      'P42\n'
      '\n'
      '《夜航》\n'
      '作者：李四\n',
    );
    final rows = clipboardBookRows(batch);

    expect(rows, hasLength(2), reason: '正档：两块各出一本书');
    expect(rows.first.title, '相机保养笔记', reason: '正档：书名');
    expect(rows.first.author, '张三', reason: '正档：作者');
    expect(rows.first.isbn, '9787111000000', reason: '正档：ISBN 透传');
    expect(rows.last.isbn, isNull, reason: '负档：没有 ISBN 就保持 null，不编');

    expect(clipboardBookRows(const <ClipboardMeta>[]), isEmpty,
        reason: '负档：空输入零输出');
    expect(
      clipboardBookRows(const <ClipboardMeta>[ClipboardMeta(author: '无名氏')]),
      isEmpty,
      reason: '负档：无书名不建书（作者不足以成书）',
    );
  });

  test('② 纯 external_id 文本：正档映射 / 负档不产书行', () {
    const raw = 'tmdb:123\n'
        '标题, douban:456\n'
        'https://movie.douban.com/subject/26264956/\n'
        'unknown:777\n';

    final ext = parseExternalIdBatch(raw);
    expect(ext, hasLength(3), reason: '正档：三条有效映射（未知来源跳过）');
    expect(ext.any((e) => e.source == 'tmdb' && e.id == '123'), isTrue);

    final rows = clipboardBookRows(parseClipboardBatch(raw));
    expect(rows, isEmpty, reason: '负档：external_id 不是书名，不得臆造书行');
  });

  test('③ 混合粘贴：书目与 external_id 各归各的预览档', () {
    const raw = '《置身事内》\n作者：兰小欢\nISBN 9787208171336\n\n'
        'tmdb:603\n';

    final metas = parseClipboardBatch(raw);
    final rows = clipboardBookRows(metas);
    final ext = parseExternalIdBatch(raw);

    expect(rows, hasLength(1), reason: '正档：书目只取有书名的一块');
    expect(rows.single.title, '置身事内');
    expect(rows.single.isbn, '9787208171336');
    expect(ext, hasLength(1), reason: '正档：external_id 独立成条');
    expect(ext.single.source, 'tmdb');
  });

  test('④ 渠道来源落库名：正档识别 / 负档未知不臆造', () {
    expect(clipboardSourceLabel('weread'), '微信读书', reason: '正档：微信读书');
    expect(clipboardSourceLabel('douban'), '豆瓣', reason: '正档：豆瓣');
    expect(clipboardSourceLabel(''), '离线粘贴',
        reason: '负档：无来源回落通用名');
    expect(clipboardSourceLabel('netflix'), '离线粘贴',
        reason: '负档：未登记渠道不冒充');
  });
}
