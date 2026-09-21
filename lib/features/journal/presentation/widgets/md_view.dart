import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;

/// 预览内 ☑ 勾选回调：第 index 个任务行 → 新勾选态。
typedef MdTaskToggle = void Function(int index, bool nowChecked);

/// 公式/代码整体摘除用的私有区占位符（正文渲染时回插）。
const _mark = '\uE000';

class _Tok {
  const _Tok(this.kind, this.text);
  final String kind; // code | pre | math | mathb
  final String text;
}

/// MD 渲染视图（批1c · 原型 pwViewBox/md-view）：
/// markdown 7.3.1 gitHubFlavored（标题/粗斜删/行内码/代码块/引用/列表/
/// ☑ 任务列表/表格/链接/图片占位/分割线）+ flutter_math_fork 公式
/// （$..$、$$..$$、\(..\)、\[..\] 归一化；解析失败回退原文）。
class MdView extends StatelessWidget {
  const MdView({
    super.key,
    required this.source,
    required this.fg,
    this.fontSize = 14,
    this.onToggleTask,
    this.enableLatex = false,
  });

  final String source;
  final Color fg;
  final double fontSize;
  final MdTaskToggle? onToggleTask;

  /// V1.29轮9k：LaTeX 公式渲染开关（记录管理·默认关=按原文显示 $..$/$$..$$）。
  final bool enableLatex;

  static const _brand = Color(0xFF6366F1);

  /// 摘除代码与公式 → 占位符（避免 markdown 语法吃掉 `\`、`_`、`**`）。
  static (String, List<_Tok>) _extract(String src, bool latex) {
    final toks = <_Tok>[];
    String hold(String kind, String text) {
      toks.add(_Tok(kind, text));
      return '$_mark${toks.length - 1}$_mark';
    }

    var s = src;
    if (latex) {
      s = s
          .replaceAllMapped(RegExp(r'\\\((.+?)\\\)'), (m) => '\$${m[1]}\$')
          .replaceAllMapped(
              RegExp(r'\\\[([\s\S]+?)\\\]'), (m) => '\n\$\$${m[1]}\$\$\n');
    }
    s = s.replaceAllMapped(RegExp(r'```\w*\n([\s\S]*?)```'),
        (m) => '\n${hold('pre', m[1]!.replaceAll(RegExp(r'\n$'), ''))}\n');
    s = s.replaceAllMapped(
        RegExp(r'`([^`\n]+)`'), (m) => hold('code', m[1]!));
    if (latex) {
      s = s.replaceAllMapped(RegExp(r'\$\$([\s\S]+?)\$\$'),
          (m) => '\n${hold('mathb', m[1]!.trim())}\n');
      s = s.replaceAllMapped(
          RegExp(r'\$([^$\n]+?)\$'), (m) => hold('math', m[1]!));
    }
    return (s, toks);
  }

  @override
  Widget build(BuildContext context) {
    final (src, toks) = _extract(source, enableLatex);
    final nodes = md
        .Document(extensionSet: md.ExtensionSet.gitHubFlavored)
        .parseLines(const LineSplitter().convert(src));
    final c = _Ctx(fg, fontSize, toks, onToggleTask);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [for (final n in nodes) ...c.block(n)],
    );
  }
}

class _Ctx {
  _Ctx(this.fg, this.fs, this.toks, this.onToggleTask);
  final Color fg;
  final double fs;
  final List<_Tok> toks;
  final MdTaskToggle? onToggleTask;
  int taskCount = 0;

  TextStyle get base => TextStyle(color: fg, fontSize: fs, height: 1.85);
  Color get dim => fg.withValues(alpha: .55);

  static final _soloTok = RegExp('^$_mark(\\d+)$_mark\$');
  static final _anyTok = RegExp('$_mark(\\d+)$_mark');

  // ---------- 块级 ----------

  List<Widget> block(md.Node n) {
    if (n is md.Text) return _para([n]);
    if (n is! md.Element) return const [];
    switch (n.tag) {
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        final lv = int.parse(n.tag.substring(1));
        return [
          Padding(
            key: ValueKey('md-h$lv-${_plain(n.children ?? [])}'),
            padding: EdgeInsets.only(top: lv <= 2 ? 14 : 8, bottom: 4),
            child: Text.rich(TextSpan(
                style: base.copyWith(
                    fontSize: const <double>[22, 18.5, 16.5, 15, 14, 13.5][lv - 1],
                    fontWeight: FontWeight.w900,
                    height: 1.45),
                children: inline(n.children ?? const []))),
          ),
        ];
      case 'p':
        return _para(n.children ?? const []);
      case 'blockquote':
        return [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.only(left: 12),
            decoration: BoxDecoration(
              border:
                  Border(left: BorderSide(color: MdView._brand, width: 3)),
            ),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final k in n.children ?? const []) ...block(k),
                ]),
          ),
        ];
      case 'ul':
        return [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final li in n.children ?? const [])
                    if (li is md.Element && li.tag == 'li') _li(li, null),
                ]),
          ),
        ];
      case 'ol':
        var i = 0;
        return [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final li in n.children ?? const [])
                    if (li is md.Element && li.tag == 'li')
                      _li(li, '${++i}.'),
                ]),
          ),
        ];
      case 'table':
        return [_table(n)];
      case 'hr':
        return [
          Divider(color: fg.withValues(alpha: .25), height: 28),
        ];
      default:
        return _para(n.children ?? const []);
    }
  }

  List<Widget> _para(List<md.Node> nodes) {
    // 整段只有一个代码/公式占位符 → 独占块渲染。
    if (nodes.length == 1 && nodes.single is md.Text) {
      final m = _soloTok.firstMatch((nodes.single as md.Text).text.trim());
      if (m != null) {
        final t = toks[int.parse(m.group(1)!)];
        if (t.kind == 'pre') return [_pre(t.text)];
        if (t.kind == 'mathb') {
          return [
            Center(
              key: ValueKey('md-mathb-${t.text}'),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: _math(t.text, true),
              ),
            ),
          ];
        }
      }
    }
    if (nodes.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Text.rich(TextSpan(style: base, children: inline(nodes))),
      ),
    ];
  }

  Widget _li(md.Element li, String? marker) {
    final kids = [...?li.children];
    var checked = false;
    final isTask = kids.isNotEmpty &&
        kids.first is md.Element &&
        (kids.first as md.Element).tag == 'input';
    if (isTask) {
      checked = (kids.first as md.Element).attributes['checked'] != null;
      kids.removeAt(0);
    }
    final spans = inline(kids);
    final strike = checked
        ? base.copyWith(
            decoration: TextDecoration.lineThrough,
            color: fg.withValues(alpha: .5))
        : base;
    if (isTask) {
      final idx = taskCount++;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              key: ValueKey('md-task-$idx'),
              behavior: HitTestBehavior.opaque,
              onTap: () => onToggleTask?.call(idx, !checked),
              child: Padding(
                padding: const EdgeInsets.only(right: 8, top: 1),
                child: Text(checked ? '☑' : '☐',
                    style: TextStyle(
                        fontSize: fs + 2,
                        color: checked ? MdView._brand : dim)),
              ),
            ),
            Expanded(child: Text.rich(TextSpan(style: strike, children: spans))),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: marker == null ? 16 : 24,
            child: Text(marker ?? '•',
                style: TextStyle(fontSize: fs, color: dim),
                textAlign: marker == null ? TextAlign.center : TextAlign.right),
          ),
          const SizedBox(width: 6),
          Expanded(child: Text.rich(TextSpan(style: base, children: spans))),
        ],
      ),
    );
  }

  Widget _table(md.Element table) {
    List<md.Element> cells(md.Element tr) =>
        [for (final c in [...?tr.children]) if (c is md.Element) c];
    final rows = <TableRow>[];
    for (final sec in [...?table.children]) {
      if (sec is! md.Element || (sec.tag != 'thead' && sec.tag != 'tbody')) {
        continue;
      }
      for (final tr in [...?sec.children]) {
        if (tr is! md.Element || tr.tag != 'tr') continue;
        final head = sec.tag == 'thead';
        rows.add(TableRow(
          decoration: head
              ? BoxDecoration(
                  color: fg.withValues(alpha: .07),
                  border: Border(
                      bottom: BorderSide(color: fg.withValues(alpha: .2))))
              : null,
          children: [
            for (final td in cells(tr))
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                child: Text(
                  _plain(td.children ?? const []),
                  style: base.copyWith(
                      fontSize: fs - 1, fontWeight: head ? FontWeight.w800 : null),
                ),
              ),
          ],
        ));
      }
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    return Container(
      key: const ValueKey('md-table'),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Table(
        border: TableBorder.all(color: fg.withValues(alpha: .15), width: .6),
        defaultColumnWidth: const FlexColumnWidth(),
        children: rows,
      ),
    );
  }

  Widget _pre(String code) => Container(
        key: ValueKey('md-pre-$code'),
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: fg.withValues(alpha: .06),
            borderRadius: BorderRadius.circular(10)),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Text(code,
              style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: fs - 1.5,
                  height: 1.7,
                  color: fg)),
        ),
      );

  Widget _math(String tex, bool displayMode) => Math.tex(
        tex,
        key: ValueKey('md-math-$tex'),
        mathStyle: displayMode ? MathStyle.display : MathStyle.text,
        textStyle: TextStyle(fontSize: fs * (displayMode ? 1.05 : 1), color: fg),
        onErrorFallback: (_) => Text(displayMode ? '\$\$$tex\$\$' : '\$$tex\$',
            style: TextStyle(
                fontFamily: 'monospace', fontSize: fs - 1, color: dim)),
      );

  // ---------- 行内 ----------

  List<InlineSpan> inline(List<md.Node> nodes) => [
        for (final n in nodes)
          if (n is md.Text)
            ...spansOfText(n.text, base)
          else if (n is md.Element)
            ...switch (n.tag) {
              'strong' => inlineWith(n, base.copyWith(fontWeight: FontWeight.w800)),
              'em' => inlineWith(n, base.copyWith(fontStyle: FontStyle.italic)),
              'del' => inlineWith(
                  n, base.copyWith(decoration: TextDecoration.lineThrough)),
              'code' => [TextSpan(text: _plain(n.children ?? []))],
              'br' => const [TextSpan(text: '\n')],
              'a' => [
                TextSpan(
                    style: base.copyWith(
                        color: MdView._brand,
                        decoration: TextDecoration.underline),
                    children: inline(n.children ?? const [])),
              ],
              'img' => [
                TextSpan(
                    text: '🖼 ${n.attributes['alt'] ?? '图片'}',
                    style: base.copyWith(fontStyle: FontStyle.italic, color: dim)),
              ],
              'input' => const <InlineSpan>[],
              _ => inlineWith(n, base),
            },
      ];

  List<InlineSpan> inlineWith(md.Element e, TextStyle style) => [
        for (final n in [...?e.children])
          if (n is md.Text)
            ...spansOfText(n.text, style)
          else if (n is md.Element)
            ...switch (n.tag) {
              'strong' => inlineWith(n, style.copyWith(fontWeight: FontWeight.w800)),
              'em' => inlineWith(n, style.copyWith(fontStyle: FontStyle.italic)),
              'del' =>
                inlineWith(n, style.copyWith(decoration: TextDecoration.lineThrough)),
              'code' => [
                TextSpan(
                    text: ' ${_plain(n.children ?? [])} ',
                    style: style.copyWith(
                        fontFamily: 'monospace',
                        fontSize: style.fontSize! - 1,
                        backgroundColor: fg.withValues(alpha: .08))),
              ],
              'a' => [
                TextSpan(
                    style: style.copyWith(
                        color: MdView._brand,
                        decoration: TextDecoration.underline),
                    children: inline(n.children ?? const [])),
              ],
              'br' => const [TextSpan(text: '\n')],
              _ => inlineWith(n, style),
            },
      ];

  /// 文本按公式/行内码占位符切开回插（数学式、代码样式、独占块降级为行内）。
  List<InlineSpan> spansOfText(String text, TextStyle style) {
    final out = <InlineSpan>[];
    var last = 0;
    for (final m in _anyTok.allMatches(text)) {
      if (m.start > last) {
        out.add(TextSpan(text: text.substring(last, m.start), style: style));
      }
      final t = toks[int.parse(m.group(1)!)];
      out.add(switch (t.kind) {
        'code' => TextSpan(
            text: ' ${t.text} ',
            style: style.copyWith(
                fontFamily: 'monospace',
                fontSize: style.fontSize! - 1,
                backgroundColor: fg.withValues(alpha: .08))),
        'math' || 'mathb' => WidgetSpan(child: _math(t.text, false)),
        _ => TextSpan(text: t.text, style: style),
      });
      last = m.end;
    }
    if (last < text.length) {
      out.add(TextSpan(text: text.substring(last), style: style));
    }
    return out.isEmpty ? [TextSpan(text: text, style: style)] : out;
  }

  String _plain(List<md.Node> nodes) {
    final sb = StringBuffer();
    for (final n in nodes) {
      if (n is md.Text) {
        var last = 0;
        for (final m in _anyTok.allMatches(n.text)) {
          sb.write(n.text.substring(last, m.start));
          final t = toks[int.parse(m.group(1)!)];
          sb.write(switch (t.kind) {
            'code' => '`${t.text}`',
            'mathb' => '\$\$${t.text}\$\$',
            _ => '\$${t.text}\$',
          });
          last = m.end;
        }
        sb.write(n.text.substring(last));
      } else if (n is md.Element && n.tag != 'input') {
        sb.write(_plain([...?n.children]));
      }
    }
    return sb.toString();
  }
}
