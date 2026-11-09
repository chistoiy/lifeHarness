import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart' show Database;

import '../../../shared/linkage/mindmap_mounts.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../data/mindmap_dao.dart';
import '../domain/mindmap_menu_rank.dart';
import '../domain/mindmap_models.dart';
import 'mindmap_node_sheet.dart';

/// 思维导图弹层族（批1 · 原型 `sheetMm-*` 对应物）。
///
/// 复用规则（冻结方案 §5.5）：删除确认走 [lhConfirm]（不新造）、弹层用
/// 系统底部上滑骨架（120~180ms 框架自带）、线性图标、文案不教学。
/// 空标题拦截（B8）与节点上限提示（B9）在弹层内给一行人话，不静默。
///
/// **批5**：节点弹层已抽去同目录 `mindmap_node_sheet.dart`（要加标签/任务/图片
/// 三段且返回值换成 `MmNodeDraft`，留在本件会顶破 `size_budget` 预算线）；
/// 本件只剩挂载笔记 / 行内菜单 / md 解析预览 / 删除确认 / 文件夹五族。

/// 挂载笔记弹层（原型 sheetMm-bindNote）：搜索＋列表；已挂载行高亮。
/// 返回值：null＝取消；`-1`＝解绑；其余＝新挂载笔记 id。
Future<int?> showMmBindSheet(BuildContext context, {int? currentNoteId}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (bc) => _NotePickSheet(currentNoteId: currentNoteId),
  );
}

class _NotePickSheet extends StatefulWidget {
  const _NotePickSheet({this.currentNoteId});

  final int? currentNoteId;

  @override
  State<_NotePickSheet> createState() => _NotePickSheetState();
}

class _NotePickSheetState extends State<_NotePickSheet> {
  List<MmNoteRef> _all = const [];
  String _q = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    mmMountableNotes().then((v) {
      if (!mounted) return;
      setState(() {
        _all = v;
        _loading = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hits = _q.isEmpty
        ? _all
        : _all.where((n) => n.title.contains(_q)).toList();
    return SafeArea(
      child: SizedBox(
        key: const ValueKey('mm-bind-sheet'),
        height: MediaQuery.sizeOf(context).height * 0.62,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
              child: Text('挂载笔记',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                key: const ValueKey('mm-bind-search'),
                onChanged: (v) => setState(() => _q = v),
                decoration: const InputDecoration(
                    hintText: '搜笔记', isDense: true, prefixIcon: Icon(Icons.search)),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator(strokeWidth: 2)))
                  : hits.isEmpty
                      ? Center(
                          child: Text('没有匹配的笔记',
                              style: TextStyle(
                                  color: cs.onSurfaceVariant, fontSize: 13)))
                      : ListView.builder(
                          itemCount: hits.length,
                          itemBuilder: (bc, i) {
                            final n = hits[i];
                            final cur = n.id == widget.currentNoteId;
                            return ListTile(
                              key: ValueKey('mm-bind-item-${n.id}'),
                              dense: true,
                              leading: Icon(
                                Icons.notes_outlined,
                                size: 20,
                                color: cur
                                    ? cs.primary
                                    : cs.onSurfaceVariant,
                              ),
                              title: Text(n.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: cur
                                          ? FontWeight.w700
                                          : FontWeight.w400)),
                              trailing: cur
                                  ? Text('当前挂载',
                                      style: TextStyle(
                                          fontSize: 11, color: cs.primary))
                                  : null,
                              onTap: () => Navigator.pop(bc, n.id),
                            );
                          },
                        ),
            ),
            if (widget.currentNoteId != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
                child: OutlinedButton(
                  key: const ValueKey('mm-bind-unbind'),
                  onPressed: () => Navigator.pop(context, -1),
                  child: const Text('解绑当前笔记'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 通用行内菜单（长按节点菜单 / 图行更多 / 画布更多共用一份骨架）。
/// 返回选中项的 key；点遮罩＝null。
///
/// 批P：[row]＝尾部**并排一行**（原型 `.nm-row`：收起整枝／展开全部）。
/// 节点菜单到 12 项后，这两枚同属「视图态」且互斥，并排既省一行高度也让
/// 「一个收一个放」这层对照看得见。
///
/// **高度口径**：节点菜单 12 项＋一行，原生弹层 9/16 上限在矮视口（横屏/
/// 测试 600 高）放不下末几项，走内部滚动——与原型 `#mmNodeMenu` 的
/// `max-height + overflow-y:auto` 同款，**不是缺陷**。用例侧点末项前请
/// `ensureVisible`（把意图变成「滚到那儿」，而不是改产品去迁就测试）。
Future<String?> showMmMenu(
  BuildContext context,
  List<({String key, IconData icon, String label, bool enabled})> items, {
  List<({String key, IconData icon, String label, bool enabled})> row = const [],
}) {
  return showModalBottomSheet<String>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (bc) {
      final cs = Theme.of(bc).colorScheme;
      return SafeArea(
        // 菜单项数不定：包滚动，短视口（横屏/测试 600 高）不溢出（9/16 上限内自滚）。
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
                for (final it in items)
                  ListTile(
                    key: ValueKey('mm-menu-${it.key}'),
                    dense: true,
                    enabled: it.enabled,
                    leading: Icon(it.icon,
                        size: 20,
                        color: it.enabled
                            ? cs.onSurface
                            : cs.onSurfaceVariant.withValues(alpha: .4)),
                    title: Text(it.label,
                        style: TextStyle(
                            fontSize: 14,
                            color: it.enabled
                                ? null
                                : cs.onSurfaceVariant.withValues(alpha: .4))),
                    onTap: it.enabled ? () => Navigator.pop(bc, it.key) : null,
                  ),
                if (row.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 2, 10, 2),
                    child: Row(
                      children: [
                        for (var i = 0; i < row.length; i++) ...[
                          if (i > 0) const SizedBox(width: 6),
                          Expanded(
                            child: OutlinedButton.icon(
                              key: ValueKey('mm-menu-${row[i].key}'),
                              onPressed: row[i].enabled
                                  ? () => Navigator.pop(bc, row[i].key)
                                  : null,
                              icon: Icon(row[i].icon, size: 17),
                              label: Text(row[i].label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700)),
                              style: OutlinedButton.styleFrom(
                                // 命中区 ≥44 口径，与列表项一致。
                                minimumSize: const Size(0, 44),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 6),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
    },
  );
}


/// 组内**按频次前移**（批P7）：组数、组序、每组的并排结构一律不动，
/// 只把组内**非并排**项按点击次数重排一次。
///
/// 为什么不用「全局按频次重排整份菜单」：那份菜单的组是有语义的——
/// 「增 / 连 / 改 / 换 / 剪 / 删」，「删除」跳到第一组顶上会出事，
/// 「上移/下移」拆开会丢掉「一个上一个下」的对照。所以只做**组内轻排**。
///
/// 细节：并排项（`inline`）**当作一个原子**——它自己和它的前驱都留在原位，
/// 否则「编辑」被前移时会把紧跟的「粘贴两枚」挤散。代价是这些项学不到频次，
/// 但它们本来就在 [mmSortPinned] 里（不记账）。
///
/// [ranks] 为 null → 原样返回（不复制，零分配）。
List<List<MmMenuItem>> mmRankMenuGroups(
    List<List<MmMenuItem>> groups, Map<String, int>? ranks) {
  if (ranks == null) return groups;
  // 空表也要过一遍判闸（`mmRankKeys` 的语义是「样本不足 ⇒ 回基线序」），
  // 不在这里短路：短路的收益只是一次遍历，代价是两种来源被混成一条路径。
  final out = <List<MmMenuItem>>[];
  for (final g in groups) {
    // 可排位＝非并排、且后面没跟着并排项（跟着的那个是并排组的头，原子保留）
    final movable = <int>[];
    for (var i = 0; i < g.length; i++) {
      if (g[i].inline) continue;
      if (i + 1 < g.length && g[i + 1].inline) continue;
      movable.add(i);
    }
    if (movable.length < 2) {
      out.add(g);
      continue;
    }
    // 候选键取**可排位**的键（`mmRankKeys` 只对自己收到的键求和判门槛）；
    // 并排项与置顶项在那一层被剔掉，不进候选。
    final keys = [for (final i in movable) g[i].key];
    final ordered = mmRankKeys(keys, ranks);
    final next = List<MmMenuItem>.of(g);
    // 按**位置**回填（不是按 key 找位）：重排只挪这几格，其余槽位原样不动。
    for (var k = 0; k < movable.length; k++) {
      next[movable[k]] = g.firstWhere((x) => x.key == ordered[k]);
    }
    out.add(next);
  }
  return out;
}

/// 节点菜单项（贴点浮层用）。
///
/// `inline`＝与**紧随其后的**同族项并排成一行（原型 `.nm-row`：成对或互斥的
/// 短动作并排，既省高度也让「一个上一个下」「一个收一个放」这层对照看得见）。
/// 连续 inline 项聚成一行；非 inline 项各自独占一行。
typedef MmMenuItem = ({
  String key,
  IconData icon,
  String label,
  bool enabled,
  bool inline,
});

/// 节点菜单 · **贴节点浮层**（原型 `openNodeMenuAt`）。
///
/// 为什么不沿用底部弹层：节点菜单是全模块最长的一份（原型 17 项），从底部
/// 升起时菜单头与节点隔着一整屏，人得先在「我点的是哪个节点」和「菜单第一项」
/// 之间来回找；贴点浮层把菜单直接落在节点下沿，上下文不丢，也不压住底部工具条。
///
/// [anchor]＝**屏幕坐标**（节点盒底边中点）。定位口径与原型一致：默认向下展开，
/// 下沿放不下就上翻；左右夹在 10dp 边距内。高度上限＝屏高减 20，超出内部滚动
/// （原型 `max-height + overflow-y:auto` 同款，不是缺陷）。
///
/// [groups]＝**组序列**：组间画分隔线（原型 `.nm-div`），组内按 [MmMenuItem.inline]
/// 聚行。用「组的列表」而不是「平铺项＋尾部一行」，是因为原型的分隔线穿插在
/// 中间（增/改/剪贴/删四段），尾部一行表达不了这个次序。
///
/// [ranks]＝**点击次数表**（批P7）：给了就按它把组内**非并排**项前移——
/// 组数、组序、组内并排行一律不动，见 [mmRankMenuGroups]。不给＝完全按传入序
/// （预览、导出等旁路将来复用时不必记账）。
Future<String?> showMmMenuAt(
  BuildContext context,
  Offset anchor, {
  required List<List<MmMenuItem>> groups,
  String? headline,
  Map<String, int>? ranks,
}) {
  // 批P4：落位要让开状态栏——`showGeneralDialog` 的页面铺满整屏（含状态栏），
  // 只按 10dp 夹取会把菜单顶边塞到时钟底下（6201 真机抓到：标题行被时间遮）。
  final topInset = MediaQuery.paddingOf(context).top;
  return showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭菜单',
    // 遮罩全透明：原型 `openNodeMenuAt` 没有遮罩（菜单旁边那枝还得看得清），
    // 层级感交给面板自身的 elevation。透明 barrier 仍吃掉外部点击＝点哪都关。
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 140),
    pageBuilder: (ctx, _, _) => CustomSingleChildLayout(
      delegate: _MmMenuPosition(anchor, topInset: topInset),
      child: _MmMenuPanel(
          groups: mmRankMenuGroups(groups, ranks), headline: headline),
    ),
    transitionBuilder: (ctx, anim, _, child) =>
        FadeTransition(opacity: anim, child: child),
  );
}

/// 浮层定位：拿到**实际**子高度再落位（估算高度会在窄屏上忽高忽低）。
class _MmMenuPosition extends SingleChildLayoutDelegate {
  const _MmMenuPosition(this.anchor, {this.topInset = 0});

  final Offset anchor;

  /// 状态栏高度（`showGeneralDialog` 铺满整屏 ⇒ 顶边下限得从它下面算）。
  final double topInset;

  static double _clamp(double v, double lo, double hi) =>
      v < lo ? lo : (v > hi ? hi : v);

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints c) => BoxConstraints(
        maxWidth: 236,
        // 顶部让开状态栏＋8dp，底部留 10dp；高度不够时面板内部滚动。
        maxHeight: c.maxHeight - topInset - 8 - 10,
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final left = _clamp(anchor.dx - childSize.width / 2, 10,
        _clamp(size.width - childSize.width - 10, 10, double.infinity));
    final minTop = topInset + 8;
    var top = anchor.dy + 14;
    if (top + childSize.height > size.height - 10) {
      top = anchor.dy - childSize.height - 14; // 下沿放不下 ⇒ 上翻
    }
    return Offset(
      left,
      _clamp(top, minTop,
          _clamp(size.height - childSize.height - 10, minTop, double.infinity)),
    );
  }

  @override
  bool shouldRelayout(covariant _MmMenuPosition old) =>
      old.anchor != anchor || old.topInset != topInset;
}

class _MmMenuPanel extends StatelessWidget {
  const _MmMenuPanel({required this.groups, this.headline});

  final List<List<MmMenuItem>> groups;
  final String? headline;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      key: const ValueKey('mm-node-menu'),
      color: cs.surfaceContainerHigh,
      elevation: 10,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (headline != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 3, 8, 4),
                child: Text(
                  headline!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .4,
                      color: cs.onSurfaceVariant.withValues(alpha: .7)),
                ),
              ),
            for (var g = 0; g < groups.length; g++) ...[
              if (g > 0)
                Divider(
                  height: 9,
                  thickness: 1,
                  color: cs.outlineVariant.withValues(alpha: .55),
                ),
              ..._rowsOf(context, groups[g]),
            ],
          ],
        ),
      ),
    );
  }

  /// 一组内按 inline 聚行：连续 inline 项并排，其余各占一行。
  List<Widget> _rowsOf(BuildContext context, List<MmMenuItem> items) {
    final out = <Widget>[];
    var i = 0;
    while (i < items.length) {
      if (!items[i].inline) {
        out.add(_tile(context, items[i]));
        i++;
        continue;
      }
      final run = <MmMenuItem>[];
      while (i < items.length && items[i].inline) {
        run.add(items[i]);
        i++;
      }
      out.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          children: [
            for (var k = 0; k < run.length; k++) ...[
              if (k > 0) const SizedBox(width: 6),
              Expanded(child: _pairBtn(context, run[k])),
            ],
          ],
        ),
      ));
    }
    return out;
  }

  Widget _tile(BuildContext context, MmMenuItem it) {
    final cs = Theme.of(context).colorScheme;
    final fg = it.enabled ? cs.onSurface : cs.onSurfaceVariant.withValues(alpha: .4);
    return ListTile(
      key: ValueKey('mm-menu-${it.key}'),
      dense: true,
      enabled: it.enabled,
      minLeadingWidth: 0,
      horizontalTitleGap: 9,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      visualDensity: const VisualDensity(vertical: -2),
      leading: Icon(it.icon, size: 18, color: fg),
      title: Text(it.label, style: TextStyle(fontSize: 13.5, color: fg)),
      onTap: it.enabled ? () => Navigator.pop(context, it.key) : null,
    );
  }

  Widget _pairBtn(BuildContext context, MmMenuItem it) {
    return OutlinedButton.icon(
      key: ValueKey('mm-menu-${it.key}'),
      onPressed: it.enabled ? () => Navigator.pop(context, it.key) : null,
      icon: Icon(it.icon, size: 16),
      label: Text(it.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

/// 搜索挂载节点弹层（原型 sheetMm-search · F4-3）：跨图搜节点标题与所挂笔记标题，
/// 点结果跳对应画布并定位。出口在 `shared/linkage/mindmap_mounts`（本模块不直连 DAO）。
/// 返回命中的那一行；null＝取消。
Future<MmSearchHit?> showMmSearchSheet(BuildContext context, {Database? db}) {
  return showModalBottomSheet<MmSearchHit>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (bc) => _MmSearchSheet(db: db),
  );
}

class _MmSearchSheet extends StatefulWidget {
  const _MmSearchSheet({this.db});

  /// 测试注入缝（生产 null＝走 AppDatabase 单例）。
  final Database? db;

  @override
  State<_MmSearchSheet> createState() => _MmSearchSheetState();
}

class _MmSearchSheetState extends State<_MmSearchSheet> {
  List<MmSearchHit> _hits = const [];
  String _q = '';
  bool _busy = false;

  /// 序号兜住「后发先至」：打字快时旧查询可能比新的晚回来，认序号不认先后。
  int _seq = 0;

  Future<void> _run(String q) async {
    final my = ++_seq;
    setState(() {
      _q = q;
      _busy = q.trim().isNotEmpty;
    });
    if (q.trim().isEmpty) {
      setState(() => _hits = const []);
      return;
    }
    final hits = await mmSearchMountedNodes(q, widget.db);
    if (!mounted || my != _seq) return;
    setState(() {
      _hits = hits;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: SizedBox(
        key: const ValueKey('mm-search-sheet'),
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 14, 20, 8),
              child: Text('搜索挂载节点',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                key: const ValueKey('mm-search-input'),
                autofocus: true,
                onChanged: _run,
                decoration: const InputDecoration(
                    hintText: '搜节点标题或所挂笔记标题',
                    isDense: true,
                    prefixIcon: Icon(Icons.search)),
              ),
            ),
            Expanded(
              child: _busy
                  ? const Center(
                      child: Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator(strokeWidth: 2)))
                  : _hits.isEmpty
                      ? Center(
                          child: Text(
                              _q.trim().isEmpty ? '' : '没有匹配的挂载节点',
                              style: TextStyle(
                                  fontSize: 13, color: cs.onSurfaceVariant)))
                      : ListView.builder(
                          itemCount: _hits.length,
                          itemBuilder: (bc, i) {
                            final h = _hits[i];
                            return ListTile(
                              key: ValueKey('mm-search-hit-${h.nodeId}'),
                              dense: true,
                              leading: Icon(Icons.search,
                                  size: 20, color: cs.onSurfaceVariant),
                              title: Text(h.nodeTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13.5)),
                              subtitle: Text(
                                  h.noteTitle == null
                                      ? h.mapTitle
                                      : '挂载：${h.noteTitle} · ${h.mapTitle}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: cs.onSurfaceVariant)),
                              trailing: Icon(Icons.chevron_right,
                                  size: 18, color: cs.onSurfaceVariant),
                              onTap: () => Navigator.pop(bc, h),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 解析预览弹层（原型 sheetMm-fromMd）：层级树缩进预览＋截断提示＋确认。
///
/// 批P P2：**单层标题**（多为全 H1）的处置二选一。判定位在解析层
/// （`MmMdParseResult.singleLevel`），这里只消费结论、不重判。
/// 默认「并入中心主题」——并列清单进脑子本来就是一层一项，N 个孤立根
/// 才是用户报障的「md 生成的导图节点全孤立」；想保留并列的仍可改选。
///
/// 返回：`null`＝取消；`'center'`＝并入中心主题；`'multi'`＝保留多根。
Future<String?> showMmFromMdPreview(
  BuildContext context,
  List<(String, int)> flat, {
  required bool truncated,
  bool singleLevel = false,
}) async {
  final r = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (bc) => _MmMdPreviewSheet(
      flat: flat,
      truncated: truncated,
      singleLevel: singleLevel,
    ),
  );
  return r;
}

class _MmMdPreviewSheet extends StatefulWidget {
  const _MmMdPreviewSheet({
    required this.flat,
    required this.truncated,
    required this.singleLevel,
  });

  final List<(String, int)> flat;
  final bool truncated;
  final bool singleLevel;

  @override
  State<_MmMdPreviewSheet> createState() => _MmMdPreviewSheetState();
}

class _MmMdPreviewSheetState extends State<_MmMdPreviewSheet> {
  /// 结构口径（仅单层标题时可改；默认并入中心主题）。
  bool _joinCenter = true;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final single = widget.singleLevel;
    // 并根预览＝顶部补一行「中心主题」，原扁平项整体缩进一层。
    final rows = <(String, int)>[
      if (single && _joinCenter) ('中心主题', 0),
      for (final (title, depth) in widget.flat)
        (title, single && _joinCenter ? depth + 1 : depth),
    ];
    return SafeArea(
      child: SizedBox(
        key: const ValueKey('mm-frommd-sheet'),
        height: MediaQuery.sizeOf(context).height * 0.66,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: Text('解析预览',
                  style:
                      TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            ),
            if (widget.truncated)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Text(
                  key: const ValueKey('mm-md-truncated'),
                  '已截断，超出部分未导入',
                  style: TextStyle(fontSize: 12, color: cs.error),
                ),
              ),
            if (single) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Text(
                  key: const ValueKey('mm-md-hint'),
                  _joinCenter
                      ? '已按单层标题并入中心主题（${widget.flat.length} 项）'
                      : '保留为 ${widget.flat.length} 个并列根，可在画布手动挂接',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700, color: cs.primary),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Text('结构',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: cs.onSurfaceVariant)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: _mmMdStructBtn(
                        context,
                        key: 'mm-md-struct-center',
                        label: '并入中心主题',
                        on: _joinCenter,
                        onTap: () => setState(() => _joinCenter = true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _mmMdStructBtn(
                        context,
                        key: 'mm-md-struct-multi',
                        label: '保留为多根',
                        on: !_joinCenter,
                        onTap: () => setState(() => _joinCenter = false),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: rows.length,
                itemBuilder: (bc, i) {
                  final (title, depth) = rows[i];
                  return Padding(
                    padding: EdgeInsets.only(left: depth * 18.0, top: 4),
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight:
                              depth == 0 ? FontWeight.w700 : FontWeight.w400),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    key: const ValueKey('mm-frommd-cancel'),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const ValueKey('mm-frommd-ok'),
                    onPressed: () => Navigator.pop(
                        context, (!single || _joinCenter) ? 'center' : 'multi'),
                    child: const Text('生成导图'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mmMdStructBtn(
    BuildContext context, {
    required String key,
    required String label,
    required bool on,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return OutlinedButton(
      key: ValueKey(key),
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 42),
        backgroundColor:
            on ? cs.primary.withValues(alpha: .12) : Colors.transparent,
        foregroundColor: on ? cs.primary : cs.onSurfaceVariant,
        side: BorderSide(
            color: on ? cs.primary : cs.outlineVariant.withValues(alpha: .6)),
      ),
      child: Text(label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
    );
  }
}

/// 删除二次确认（F1-11：确认文案列明连带子级数；C1：文案不出现「可撤销」——
/// 撤销栈排批 2，节点删除不进回收站，进回收站的是「删图」第九类）。
Future<bool> mmConfirmDeleteNode(BuildContext context, int total, int children) {
  return lhConfirm(context, '将删除 $total 个节点（含 $children 个子节点）\n此操作不可恢复');
}

/// 文件夹管理弹层（批2 F4-4 · 原型 sheetMm-folders）：文件夹列表＋新建＋
/// 行内改名/删除。删文件夹＝**只置空引用不删图**（DAO 侧已钉；本弹层给
/// 人话确认）。操作即时生效，关弹层后由调用侧刷新列表。
Future<void> showMmFolderSheet(BuildContext context, MindmapDao dao) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (bc) => _MmFolderSheet(dao: dao),
  );
}

class _MmFolderSheet extends StatefulWidget {
  const _MmFolderSheet({required this.dao});

  final MindmapDao dao;

  @override
  State<_MmFolderSheet> createState() => _MmFolderSheetState();
}

class _MmFolderSheetState extends State<_MmFolderSheet> {
  List<MindmapFolder> _folders = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final v = await widget.dao.listFolders();
    if (!mounted) return;
    setState(() {
      _folders = v;
      _loading = false;
    });
  }

  Future<void> _create() async {
    final r = await showMmNodeSheet(context, headline: '新建文件夹');
    if (r == null) return;
    await widget.dao.createFolder(r.draft.title);
    await _reload();
  }

  Future<void> _rename(MindmapFolder f) async {
    final r = await showMmNodeSheet(context,
        headline: '重命名文件夹', initialTitle: f.title);
    if (r == null) return;
    await widget.dao.renameFolder(f.id!, r.draft.title);
    await _reload();
  }

  Future<void> _delete(MindmapFolder f) async {
    final ok = await lhConfirm(
        context, '删除文件夹「${f.title}」？\n文件夹里的导图会回到「全部」，不会删除');
    if (!ok) return;
    await widget.dao.deleteFolder(f.id!);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: SizedBox(
        key: const ValueKey('mm-folder-sheet'),
        height: MediaQuery.sizeOf(context).height * 0.58,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: Text('文件夹',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator(strokeWidth: 2)))
                  : _folders.isEmpty
                      ? Center(
                          child: Text('还没有文件夹，新建一个归类导图',
                              style: TextStyle(
                                  fontSize: 13, color: cs.onSurfaceVariant)))
                      : ListView.builder(
                          itemCount: _folders.length,
                          itemBuilder: (bc, i) {
                            final f = _folders[i];
                            return ListTile(
                              key: ValueKey('mm-folder-row-${f.id}'),
                              dense: true,
                              leading: const Icon(Icons.folder_outlined,
                                  size: 20),
                              title: Text(f.title,
                                  style: const TextStyle(fontSize: 13.5)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    key: ValueKey(
                                        'mm-folder-rename-${f.id}'),
                                    icon: const Icon(Icons.edit_outlined,
                                        size: 18),
                                    onPressed: () => _rename(f),
                                  ),
                                  IconButton(
                                    key: ValueKey('mm-folder-del-${f.id}'),
                                    icon: const Icon(Icons.delete_outlined,
                                        size: 18),
                                    onPressed: () => _delete(f),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
              child: OutlinedButton(
                key: const ValueKey('mm-folder-create'),
                onPressed: _create,
                child: const Text('新建文件夹'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
