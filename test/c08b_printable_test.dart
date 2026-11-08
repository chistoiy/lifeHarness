import 'package:flutter_test/flutter_test.dart';
import 'package:lifeharness/core/export/printable_html.dart';

/// C08b 守护：零依赖下 PDF 出口改「可打印 HTML」。
/// 每个用例正档（该有的在）与负档（不该有的不许有）同断。
void main() {
  test('① A4 / 打印规则 / 中文字体栈：正档齐备，负档无脚本无外链', () {
    final html = noteToPrintableHtml(
      title: '周记',
      body: '今天读完了《长夜》。',
    );
    expect(html, startsWith('<!DOCTYPE html>'), reason: '正档：完整文档');
    expect(html, contains('charset="utf-8"'), reason: '正档：UTF-8 直写中文');
    expect(html, contains('lang="zh-CN"'), reason: '正档：中文语言标记');
    expect(html, contains('@page'), reason: '正档：分页规则存在');
    expect(html, contains('size: A4'), reason: '正档：A4 纸张');
    expect(html, contains('@media print'), reason: '正档：打印样式');
    expect(html, contains('"PingFang SC"'), reason: '正档：macOS 中文栈');
    expect(html, contains('"Microsoft YaHei"'), reason: '正档：Windows 中文栈');
    expect(html, contains('"Noto Sans CJK SC"'), reason: '正档：Linux/Android 中文栈');
    expect(html, contains('周记'), reason: '正档：标题中文不缺字');
    expect(html, contains('今天读完了《长夜》。'), reason: '正档：正文中文不缺字');
    expect(html.trim(), endsWith('</html>'), reason: '正档：闭合完整');
    expect(html, isNot(contains('<script')), reason: '负档：产物不引脚本');
    expect(html, isNot(contains('<link')), reason: '负档：无外部样式表');
    expect(html, isNot(contains('@import')), reason: '负档：无外链资源');
    expect(html, isNot(contains('application/pdf')), reason: '负档：不冒充 PDF 产物');
  });

  test('② HTML 转义：正档可见字符，负档用户文本不变标签', () {
    final html = noteToPrintableHtml(
      title: '<script>alert(1)</script>',
      body: '正文 <img src=x onerror=alert(2)> & 结束',
    );
    expect(html, contains('&lt;script&gt;alert(1)&lt;/script&gt;'),
        reason: '正档：标题尖括号转义后仍可读');
    expect(html, contains('&lt;img src=x onerror=alert(2)&gt;'),
        reason: '正档：正文标签转义');
    expect(html, contains('&amp; 结束'), reason: '正档：& 转义');
    expect(html, isNot(contains('<script>alert(1)</script>')),
        reason: '负档：用户脚本不许成为标签');
    expect(html, isNot(contains('<img src=x')), reason: '负档：不产 img 标签');
    expect(printableHtmlEscape('"q" \'s\''), equals('&quot;q&quot; &#39;s&#39;'),
        reason: '正档：引号成对转义');
    expect(printableHtmlEscape('相机保养'), equals('相机保养'),
        reason: '负档：中文不被转义破坏');
  });

  test('③ 代码块 / 引用样式：正档在，负档围栏标记不泄漏', () {
    final html = noteToPrintableHtml(
      title: '摘录',
      body: '> 引用一句\n\n```\nvoid main() {}\n```\n\n- 一\n- 二',
    );
    expect(html, contains('<blockquote><p>引用一句</p></blockquote>'),
        reason: '正档：引用成块');
    expect(html, contains('<pre><code>void main() {}'), reason: '正档：代码块成块');
    expect(html, contains('blockquote {'), reason: '正档：引用样式规则');
    expect(html, contains('.doc-body pre {'), reason: '正档：代码块样式规则');
    expect(html, contains('<li>一</li>'), reason: '正档：列表成项');
    expect(html, isNot(contains('```')), reason: '负档：围栏标记不泄漏到成品');
    expect(html, isNot(contains('<blockquote>引用一句')),
        reason: '负档：引用文本必须包在 p 里');
  });

  test('④ 页眉页脚可关：正档有，关后负档不输出', () {
    final on = noteToPrintableHtml(
        title: '带页眉', body: 'x', printedAt: '2026-11-09');
    expect(on, contains('class="doc-head"'), reason: '正档：页眉在');
    expect(on, contains('class="doc-foot"'), reason: '正档：页脚在');
    expect(on, contains('2026-11-09'), reason: '正档：时间行如实写入');

    final off = noteToPrintableHtml(
        title: '无页眉', body: 'x', showHeader: false, showFooter: false);
    expect(off, isNot(contains('class="doc-head"')), reason: '负档：关页眉即不输出');
    expect(off, isNot(contains('class="doc-foot"')), reason: '负档：关页脚即不输出');
    expect(off, contains('<title>无页眉</title>'), reason: '正档：标题仍在 title');
    expect(off, isNot(contains('class="doc-title"')),
        reason: '负档：正文区不重复标题');
  });

  test('⑤ 文案不假承诺 + 文件名：正档说可打印 HTML，负档无「已导出 PDF」', () {
    expect(kPrintableHtmlExportHint, contains('可打印 HTML'),
        reason: '正档：说清产物是 HTML');
    expect(kPrintableHtmlExportHint, contains('另存为 PDF'),
        reason: '正档：说清 PDF 怎么来');
    expect(kPrintableHtmlExportHint, isNot(contains('已导出 PDF')),
        reason: '负档：不许假承诺');

    final html = noteToPrintableHtml(title: 't', body: 'b');
    expect(html, contains(kPrintableHtmlExportHint), reason: '正档：页脚带出口文案');
    expect(html, isNot(contains('已导出 PDF')), reason: '负档：成品里无假承诺串');
    expect(html, contains('no-print'), reason: '正档：屏上提示可打印隐藏');

    expect(printableHtmlFileName('周记/第一篇'), equals('周记-第一篇.html'),
        reason: '正档：路径非法字符换 -');
    expect(printableHtmlFileName('  '), equals('未命名笔记.html'),
        reason: '负档：空标题不产空文件名');
  });
}
