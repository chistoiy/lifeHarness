/// MD 快捷栏纯变换（原型 pwMd 映射表 · 批1b）：
/// kind + 全文 + 选区 → 新文本、光标位与 toast 文案。
({String text, int caret, String label}) applyMdShortcut(
    String kind, String text, int start, int end) {
  if (start > end) (start, end) = (end, start);
  if (kind == 'h') {
    final ls = text.lastIndexOf('\n', start - 1) + 1;
    var ne = text.indexOf('\n', ls);
    if (ne == -1) ne = text.length;
    final line = text.substring(ls, ne);
    final m = RegExp(r'^(#{1,6})\s').firstMatch(line);
    final lv = m == null ? 1 : (m.group(1)!.length >= 6 ? 0 : m.group(1)!.length + 1);
    final rest = line.replaceFirst(RegExp(r'^#{1,6}\s?'), '');
    final nl = lv == 0 ? rest : '${'#' * lv} $rest';
    return (
      text: text.substring(0, ls) + nl + text.substring(ne),
      caret: ls + nl.length,
      label: '标题级别：${lv == 0 ? '正文' : 'h$lv'}（再点循环升级至 h6）',
    );
  }
  const wraps = {
    'bold': ('**', '**'),
    'ital': ('*', '*'),
    'strike': ('~~', '~~'),
    'code': ('`', '`'),
    'math': ('\$', '\$'),
    'link': ('[', '](https://)'),
    'img': ('![图片说明](', 'https://)'),
    'quote': ('> ', ''),
    'ul': ('- ', ''),
    'task': ('- [ ] ', ''),
    'hr': ('\n---\n', ''),
    'table': ('\n| 列 | 列 |\n| --- | --- |\n| 内容 | 内容 |\n', ''),
    'mathb': ('\n\$', '\$\n'),
  };
  final (pre, suf) = wraps[kind] ?? ('', '');
  final sel = text.substring(start, end);
  return (
    text: text.substring(0, start) + pre + sel + suf + text.substring(end),
    caret: start + pre.length + sel.length,
    label: '已插入 $kind 语法（选中文本被包裹）',
  );
}
