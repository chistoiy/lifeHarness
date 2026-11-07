import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as q;
import 'package:sqflite/sqflite.dart' show Database;

import '../../../../core/logging/app_log.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/linkage/mindmap_mounts.dart';
import 'note_sheet_lang.dart';

/// 连接点② **导图卡片实体**（冻结方案 §4.9 · 思维导图批2 面5）。
///
/// 规格五项（逐条落地，勿自造）：
///  · 形态＝左侧线性图标（account_tree）＋ 图名 ＋ 副文案「N 个根节点」
///    ＋ 根节点集合预览（每根一行，**最多 5 行**，超出显「…」）；
///  · 数据**只存 `map_id` 引用不存快照**——预览每次经 linkage 现取，
///    图改了卡片跟着更新；
///  · 点击卡片 → 经 [mmOpenCanvas] 进该图画布；
///  · 图被删除（含回收站/彻底删）→ 显示「（导图已删除）」占位、
///    **点击置灰无响应**（不使卡片失效、不跳空路由）。
///
/// 落库形态＝Quill BlockEmbed 自定义类型 [mmCardEmbedType]，data 为
/// `{"map_id":12}` 短 JSON 串（**禁存快照**：存了图改名就不跟随）。
/// Quill 对未注册 embed type 会抛 `UnimplementedError`
/// （`editor.dart` `_getEmbedBuilder`），故编辑器的 `embedBuilders`
/// 必须同时挂 [NoteImageEmbedBuilder] 与本 builder。
class MmCardEmbedBuilder extends q.EmbedBuilder {
  const MmCardEmbedBuilder();

  @override
  String get key => mmCardEmbedType;

  @override
  String toPlainText(q.Embed node) => '导图卡片';

  @override
  Widget build(BuildContext context, q.EmbedContext embedContext) {
    return MmCardBlock(mapId: mmCardMapIdOf(embedContext.node.value.data));
  }
}

/// embed 类型键（与 [MmCardEmbedBuilder.key] 同源，禁各写一份）。
const String mmCardEmbedType = 'mindmap-card';

/// 构造卡片 embed（编辑器插入用）。[mapId] 落库为短 JSON。
q.BlockEmbed mmCardEmbed(int mapId) =>
    q.BlockEmbed(mmCardEmbedType, jsonEncode({'map_id': mapId}));

/// 解析卡片 embed 的 `map_id`；data 非法/缺失 → null（渲染侧按占位处理，
/// 不抛——正文是历史存量，格式漂移不许炸编辑页）。
int? mmCardMapIdOf(Object? data) {
  if (data is int) return data;
  if (data is! String || data.isEmpty) return null;
  try {
    final v = jsonDecode(data);
    if (v is Map && v['map_id'] is int) return v['map_id'] as int;
  } catch (err) {
    // 存量脏数据按无图处理（下方 MmCardBlock 显占位）——留痕，不静默吞。
    AppLog.add('导图卡片 embed data 解析失败，按占位渲染：$err',
        level: LhLevel.warn);
  }
  return null;
}

/// 正文里的导图卡片（编辑态渲染 + 摘要外的唯一可视面）。
/// [db] 仅供测试注入内存库；生产走 linkage 出口的默认句柄。
class MmCardBlock extends StatefulWidget {
  const MmCardBlock({super.key, required this.mapId, this.db});

  final int? mapId;
  final Database? db;

  @override
  State<MmCardBlock> createState() => _MmCardBlockState();
}

class _MmCardBlockState extends State<MmCardBlock> {
  Future<({String title, List<String> roots, int rootCount})?>? _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(MmCardBlock old) {
    super.didUpdateWidget(old);
    if (old.mapId != widget.mapId) _load();
  }

  void _load() {
    final id = widget.mapId;
    // mapId 缺失/导图已删都落 null＝占位态，不重试。
    if (id == null) {
      _future = Future.value(null);
      return;
    }
    // 根数单列一查：预览只取前 5 根，拿 roots.length 当根数会谎报。
    // Future.wait 会把记录类型擦成 List<Object?>（元组 getter 全丢），故先取
    // 预览、null 即短路，不并行。
    _future = () async {
      final prev = await mmCardPreview(id, widget.db);
      if (prev == null) return null;
      final rootCount = await mmRootCountOf(id, widget.db);
      return (title: prev.$1, roots: prev.$2, rootCount: rootCount);
    }();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      key: const ValueKey('mm-card-block'),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: FutureBuilder<({String title, List<String> roots, int rootCount})?>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return Container(
              height: 62,
              alignment: Alignment.center,
              decoration: _box(context),
              child: const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          final r = snap.data;
          // 图已删/解析不出图 id：占位置灰，点击无响应（§4.9）。
          if (r == null) return _dead(context, scheme);
          final roots = r.roots;
          return GestureDetector(
            key: const ValueKey('mm-card-live'),
            onTap: () => mmOpenCanvas(context, widget.mapId!),
            child: Container(
              decoration: _box(context),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.account_tree_outlined,
                          size: 20, color: scheme.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800)),
                            Text('思维导图 · ${r.rootCount} 个根节点',
                                style: TextStyle(
                                    fontSize: 10.5,
                                    color: scheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      Text('点击进画布',
                          style: TextStyle(
                              fontSize: 10.5, color: scheme.primary)),
                    ],
                  ),
                  if (roots.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    // 预览＝根节点集合，每根一行，最多 5 行（§4.9 硬上限）。
                    for (final t in roots.take(5))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            Icon(Icons.subdirectory_arrow_right,
                                size: 12, color: scheme.onSurfaceVariant),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(t,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      height: 1.5,
                                      color: scheme.onSurfaceVariant)),
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  BoxDecoration _box(BuildContext context) {
    final tokens = context.tokens;
    return BoxDecoration(
      color: tokens.card,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: tokens.cardBorder),
    );
  }

  /// 失效占位：整块置灰、无 InkWell ⇒ 点击不响应（不做 toast、不跳空路由）。
  Widget _dead(BuildContext context, ColorScheme scheme) {
    return Opacity(
      key: const ValueKey('mm-card-dead'),
      opacity: .5,
      child: Container(
        decoration: _box(context),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Row(
          children: [
            Icon(Icons.account_tree_outlined,
                size: 20, color: scheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Text('（导图已删除）',
                  style: TextStyle(
                      fontSize: 12.5, color: scheme.onSurfaceVariant)),
            ),
          ],
        ),
      ),
    );
  }
}

/// 挑图弹层（原型 `sheetMm-card` 的作用面）：列在册导图，选中返回 `map_id`。
/// 数据经 linkage 出口 [mmSelectableMaps] 取（journal 零直连 mindmap）。
/// [db] 仅供测试注入内存库。
Future<int?> showMmCardPickSheet(BuildContext context, {Database? db}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (bc) => _MmCardPickSheet(db: db),
  );
}

class _MmCardPickSheet extends StatefulWidget {
  const _MmCardPickSheet({this.db});

  final Database? db;

  @override
  State<_MmCardPickSheet> createState() => _MmCardPickSheetState();
}

class _MmCardPickSheetState extends State<_MmCardPickSheet> {
  List<MmMapBrief> _all = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    mmSelectableMaps(widget.db).then((v) {
      if (!mounted) return;
      setState(() {
        _all = v;
        _loading = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: SizedBox(
        key: const ValueKey('mm-card-pick-sheet'),
        height: MediaQuery.sizeOf(context).height * 0.58,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
              child: NoteSheetHeader(
                  title: '插入导图卡片',
                  sub: '卡片只存图引用 · 点卡片进该图画布'),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator(strokeWidth: 2)))
                  : _all.isEmpty
                      ? Center(
                          child: Text('还没有导图',
                              style: TextStyle(
                                  color: scheme.onSurfaceVariant, fontSize: 13)))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                          itemCount: _all.length,
                          itemBuilder: (c, i) {
                            final m = _all[i];
                            return NoteSheetRow(
                              key: ValueKey('mm-card-pick-${m.id}'),
                              icon: Icons.account_tree_outlined,
                              label: m.title,
                              trailing: Text('${m.nodeCount} 个节点',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: scheme.onSurfaceVariant)),
                              onTap: () => Navigator.pop(c, m.id),
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