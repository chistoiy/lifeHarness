part of 'reader_page.dart';

// 治理G7a：零状态件自 reader_page.dart 纯搬移（同库私有名不变·行为零改动）。


/// 阅读位置（brPos[bid]：{ci,pg} + 书签 bm=[ci,pg,ts]）。
class _Pos {
  _Pos({this.ci = 0, this.pg = 0, this.bm});
  int ci, pg;
  List<int>? bm;

  factory _Pos.decode(String? raw) {
    try {
      final v = raw == null ? null : jsonDecode(raw) as Map<String, dynamic>?;
      if (v == null) return _Pos();
      return _Pos(
        ci: (v['ci'] as num?)?.toInt() ?? 0,
        pg: (v['pg'] as num?)?.toInt() ?? 0,
        bm: (v['bm'] as List?)?.map((e) => (e as num).toInt()).toList(),
      );
    } catch (_) {
      return _Pos();
    }
  }

  String encode() => jsonEncode({'ci': ci, 'pg': pg, if (bm != null) 'bm': bm});
}

/// brSync 关时的划线暂存行（原型 BR_LOCAL_HL · 全量存 kv `reader.hl`）。
/// 与 book_quotes 同构语义：cf 章段区间 + 颜色分类 tg + 稳定 rid。
class _LocalHl {
  const _LocalHl({
    required this.id,
    required this.bookId,
    required this.cf,
    required this.tg,
  });

  final String id;
  final String bookId;
  final QuoteCf cf;
  final String tg;

  Map<String, Object?> toMap() => {
    'id': id,
    'b': bookId,
    'c': cf.c,
    'p0': cf.p0,
    'p1': cf.p1,
    'tg': tg,
  };

  static _LocalHl? fromMap(Map<Object?, Object?> m) {
    final c = m['c'], p0 = m['p0'], p1 = m['p1'];
    if (c is! num || p0 is! num || p1 is! num) return null;
    return _LocalHl(
      id: '${m['id']}',
      bookId: '${m['b']}',
      cf: QuoteCf(c: c.toInt(), p0: p0.toInt(), p1: p1.toInt()),
      tg: '${m['tg']}',
    );
  }

  static List<_LocalHl> decodeAll(String? raw) {
    try {
      final v = raw == null ? null : jsonDecode(raw) as List?;
      if (v == null) return const [];
      return [
        for (final e in v.whereType<Map<Object?, Object?>>())
          ?_LocalHl.fromMap(e),
      ];
    } catch (_) {
      return const [];
    }
  }

  static String encodeAll(List<_LocalHl> l) =>
      jsonEncode([for (final x in l) x.toMap()]);
}

const _kTerm = '。！？!?；;…\n';

const _kSoft = '，,、：:；';

const _kTail = '”’」』）)】》';

const _kBrDict = {
    '锚定': ('ān dìng', '动', '在判断中过度依赖最先获得的数值。'),
    '折扣': ('zhé kòu', '名', '未来奖励在当下估值中的缩水。'),
    '联想': ('lián xiǎng', '名', '一个概念激活后向评价、情绪、动作扩散的链条。'),
  };

  /// 从 [pos] 命中段内整句：左右扫到句读边界；超长则按软标点再切一档。
({int a, int b}) _sentenceAt(String t, int pos) {
    if (t.isEmpty) return (a: 0, b: 0);
    var i = pos.clamp(0, t.length - 1);
    // 落在标点上 → 先回退到最近实词。
    while (i > 0 && (_kTerm.contains(t[i]) || _kSoft.contains(t[i]))) {
      i--;
    }
    var a = 0;
    for (var j = i; j > 0; j--) {
      final c = t[j - 1];
      if (_kTerm.contains(c)) {
        a = j;
        break;
      }
    }
    var b = t.length;
    for (var j = i; j < t.length; j++) {
      if (_kTerm.contains(t[j])) {
        b = j + 1;
        while (b < t.length && _kTail.contains(t[b])) {
          b++;
        }
        break;
      }
    }
    if (b - a > 60) {
      for (var j = a; j < b; j++) {
        if (_kSoft.contains(t[j])) {
          if (j - a >= 12 && (b - (j + 1)) >= 12) {
            b = j + 1;
            while (b < t.length && _kTail.contains(t[b])) {
              b++;
            }
            break;
          }
        }
      }
      if (b - a > 60) {
        for (var j = i; j >= a; j--) {
          if (_kSoft.contains(t[j]) && (i - j) <= 40) {
            a = j + 1;
            break;
          }
        }
      }
      // 拉丁文本没有句读可用：退到词边界（空格），仍保证只选一句的范围。
      if (b - a > 60) {
        var sa = a;
        for (var j = i; j >= a; j--) {
          if (t[j] == ' ' && (i - j) <= 40) {
            sa = j + 1;
            break;
          }
        }
        var sb = b;
        for (var j = i; j < b; j++) {
          if (t[j] == ' ') {
            sb = j;
            break;
          }
        }
        if (sb > sa) {
          a = sa;
          b = sb;
        }
      }
    }
    return (a: a, b: b);
  }

RenderParagraph? _firstRenderParagraph(RenderObject root) {
    RenderParagraph? out;
    void walk(RenderObject ro) {
      if (out != null) return;
      if (ro is RenderParagraph) {
        out = ro;
        return;
      }
      ro.visitChildren(walk);
    }
    walk(root);
    return out;
  }
