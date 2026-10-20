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

/// F-13（2026-10-07）：段生效划线的一条——同段可以有多条，渲染层按 createdAt
/// 升序逐条铺色（列表靠后＝最新＝重叠区取它）。暂存行无时间戳，按加入顺序编号。
typedef BrHl = ({
  String tg,
  Color c,
  bool hasThought,
  QuoteCf cf,
  int createdAt,
});

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
    // 轮4①：字符级偏移随暂存行落 kv（老行无键＝null＝整段旧行为）。
    if (cf.o0 != null) 'o0': cf.o0,
    if (cf.o1 != null) 'o1': cf.o1,
    'tg': tg,
  };

  static _LocalHl? fromMap(Map<Object?, Object?> m) {
    final c = m['c'], p0 = m['p0'], p1 = m['p1'];
    if (c is! num || p0 is! num || p1 is! num) return null;
    return _LocalHl(
      id: '${m['id']}',
      bookId: '${m['b']}',
      cf: QuoteCf(
        c: c.toInt(),
        p0: p0.toInt(),
        p1: p1.toInt(),
        o0: (m['o0'] as num?)?.toInt(),
        o1: (m['o1'] as num?)?.toInt(),
      ),
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

  /// V1.53.2 性能批 3（方案 D）：判断位置 [j] 处的标点是否是**真正的句末**。
  /// 排除常见英文缩写（Mr. Dr. Mrs. Prof. St. No. vs. etc.）、小数点、
  /// 连续标点（!? / ?!）、引号内成句的收尾判定。
  bool _isRealTermAt(String t, int j) {
    final c = t[j];
    if (!_kTerm.contains(c)) return false;
    // 连续标点（!?/?!）：只认最后一个
    if (j + 1 < t.length && _kTerm.contains(t[j + 1])) return false;
    // 英文缩写里的点：前一个字母 + 后一个空格/大写 视为缩写
    if (c == '.') {
      if (j > 0 && _isAsciiLetter(t[j - 1])) {
        // 常见缩写表（前 4 字母 + 结尾 .）
        final head = t.substring(
          (j - 4).clamp(0, t.length),
          j,
        );
        const abbrs = ['mr', 'mrs', 'dr', 'prof', 'st', 'no', 'vs', 'etc', 'jr', 'sr'];
        for (final a in abbrs) {
          if (head.toLowerCase().endsWith(a) &&
              (head.length == a.length ||
                  !_isAsciiLetter(head[head.length - a.length - 1]))) {
            return false;
          }
        }
      }
      // 小数：3.14 中的点
      if (j > 0 && j + 1 < t.length &&
          _isDigit(t[j - 1]) && _isDigit(t[j + 1])) {
        return false;
      }
    }
    return true;
  }

  bool _isAsciiLetter(String c) {
    if (c.isEmpty) return false;
    final u = c.codeUnitAt(0);
    return (u >= 65 && u <= 90) || (u >= 97 && u <= 122);
  }

  bool _isDigit(String c) {
    if (c.isEmpty) return false;
    final u = c.codeUnitAt(0);
    return u >= 48 && u <= 57;
  }

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
      // V1.53.2 方案 D：用 _isRealTermAt 排除缩写/小数点/连续标点
      if (_isRealTermAt(t, j - 1)) {
        a = j;
        break;
      }
      // 保留原逻辑：非真句末但仍是标点（例如 , 等），不切
      if (c == '\n') {
        a = j;
        break;
      }
    }
    var b = t.length;
    for (var j = i; j < t.length; j++) {
      // V1.53.2 方案 D：真句末才切
      if (_isRealTermAt(t, j)) {
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
