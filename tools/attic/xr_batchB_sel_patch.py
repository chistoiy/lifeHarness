# tools/attic/xr_batchB_sel_patch.py — 批B 第三段：选区工具条 X-Ray 动作接线（锚点跟随目标文件行尾）
import io

CRLF_MARK = chr(13) + chr(10)


def patch(p, pairs):
    s = io.open(p, encoding='utf-8', newline='').read()
    crlf = CRLF_MARK in s

    def n(x):
        return x.replace(chr(10), CRLF_MARK) if crlf else x

    for a, b in pairs:
        a, b = n(a), n(b)
        assert s.count(a) == 1, (p, a[:40].encode('unicode_escape'), s.count(a))
        s = s.replace(a, b)
    io.open(p, 'w', encoding='utf-8', newline='').write(s)

patch('lib/features/read/presentation/reader/reader_sel_layer.dart', [
    ("""  '查询',
  '听当前',""",
     """  '查询',
  // V1.54 批B F6：默认在列（read.brSelBar 名单可关；存量已存名单不自动获得）。
  'X-Ray',
  '听当前',"""),
    ("""  required VoidCallback onShare,
  required void Function(String) onColor,
  required VoidCallback onDelete,""",
     """  required VoidCallback onShare,
  required void Function(String) onColor,
  required VoidCallback onDelete,
  VoidCallback? onXray,"""),
    ("""      '查询' => chip('brSelDict', '查询', Icons.search_rounded, onDict),""",
     """      '查询' => chip('brSelDict', '查询', Icons.search_rounded, onDict),
      'X-Ray' => chip(
          'brSelXray', 'X-Ray', Icons.travel_explore_rounded, onXray),"""),
])

patch('lib/features/read/presentation/reader/reader_page.dart', [
    ("""                        onShare: _actShare,
                        onColor: _addHl,
                        onDelete: _delHl,""",
     """                        onShare: _actShare,
                        onColor: _addHl,
                        onDelete: _delHl,
                        onXray: actXraySel,"""),
    ("""import '../../../../core/database/schema/xray.dart' as xs;""",
     """import '../../../../core/database/schema/xray.dart' as xs;
import '../../data/xray/xray_dao.dart' show XrayEntityRow;
import './reader_xray_learn_sheets.dart' show showXrPeekSheet;"""),
])

patch('lib/features/read/presentation/reader/reader_xray.dart', [
    ("""/// 退后台自动暂停解析（§8 一期不做后台续跑；回前台在面板头一键恢复）。""",
     """/// 选区工具条「X-Ray」（F6）：命中实体词→迷你卡（查看全部位置→面板详情）；
/// 未命中→面板「加为词条」弹层预填（名单驱动 read.brSelBar）。
void actXraySel() {
  final raw = _selTxt.trim();
  _clearSel();
  if (raw.isEmpty) return;
  final w = raw.length > 24 ? raw.substring(0, 24) : raw;
  unawaited(_xrSelLookup(w));
}

Future<void> _xrSelLookup(String w) async {
  final b = _book;
  if (b == null) return;
  final dao = ref.read(xrayDaoProvider);
  String? md5 = await dao.bookMd5(b.id);
  if (md5 == null || md5.isEmpty) {
    md5 = await ref.read(xraySchedulerProvider).ensureMd5(b);
  }
  if (!mounted) return;
  if (md5 != null && md5.isNotEmpty) {
    final hits = await dao.searchEntities(md5, w);
    if (!mounted) return;
    XrayEntityRow? hit;
    for (final e in hits) {
      if (e.name == w) {
        hit = e;
        break;
      }
    }
    hit ??= hits.where((e) => e.name.contains(w) || w.contains(e.name)).firstOrNull;
    if (hit != null) {
      final name = hit.name;
      showXrPeekSheet(
        context,
        ent: hit,
        onViewAll: () {
          ref.read(readerXrFocusWordProvider.notifier).state = name;
          openXrTab();
        },
      );
      return;
    }
  }
  ref.read(readerXrAddWordProvider.notifier).state = w;
  openXrTab();
}

/// 退后台自动暂停解析（§8 一期不做后台续跑；回前台在面板头一键恢复）。"""),
])
print('sel wiring ok')
