import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/features/journal/domain/wiki_links.dart';

void main() {
  group('C02 双向链接解析', () {
    test('提取全部引用，不误伤普通链接与图片', () {
      const src = '见 [[周报]] 和 [[读书笔记]]，外链 [官网](https://x.com)，'
          '图片 ![封面](a.png)，空标题 [[]] 不算。';
      final refs = parseWikiLinks(src);
      expect(refs.map((r) => r.title), ['周报', '读书笔记']);
      expect(refs.first.start, src.indexOf('[[周报]]'));
      expect(refs.first.end, src.indexOf('[[周报]]') + '[[周报]]'.length);
    });

    test('可解析的渲染成链接，已删除的只留占位文本', () {
      const src = '参考 [[周报]] 与 [[已删的笔记]]';
      final out = renderWikiLinks(src,
          resolve: (t) => t == '周报' ? '42' : null);
      expect(out, '参考 [周报](lh://note/42) 与 （已删除的笔记）');
      expect(out, isNot(contains(']]')));
      expect(out, isNot(contains('lh://note/null')));
    });

    test('无引用时原文原样返回', () {
      const src = '普通正文 [链接](url)';
      expect(renderWikiLinks(src, resolve: (_) => '1'), src);
    });

    test('改名只跟随链接标题，不动正文同名词', () {
      const src = '周报写在 [[周报]] 里；周报也要归档';
      expect(renameWikiLinks(src, '周报', '周总结'),
          '周报写在 [[周总结]] 里；周报也要归档');
      expect(renameWikiLinks(src, '周报', '周报'), src);
    });
  });
}
