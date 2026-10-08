import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/load_error_state.dart';
import '../../../shared/widgets/ui_kit.dart';
import '../data/media_repo_goal.dart';
import '../data/media_repo_session.dart';
import 'media_providers.dart';

/// 影音游设置屏（原型 `m-set` · 路由 `/media/settings` · 词典 LH-C23 · 批8a）。
///
/// - 横向六组 tab（架面/排序/笔记/计时/更新提醒/数据），行态与计划 §七 键一一对名；
/// - 一律走 settings 表 KV `media.*`（铁口径④，不散落 SharedPreferences）；
/// - 逐行当场生效（铁口径①）：写 KV＋mediaTick 层层重取，speedFold 与统计 chip 双向同源；
/// - 能力未开放＝灰态点不动、零说明文案（铁口径②：识图/更新提醒三行/导出两枚）；
/// - 死键四条不铺（deskTexture/cardLiftPx/spineCols/longPress＝工单 §0.5）。
class MediaSetPage extends ConsumerStatefulWidget {
  const MediaSetPage({super.key});

  @override
  ConsumerState<MediaSetPage> createState() => _MediaSetPageState();
}

/// 一行的定义（kind＝seg|bool|gray|entry）。
typedef MdsSetRowDef = ({
  String kind,
  String key,
  String label,
  List<(String, String)> opts,
});

MdsSetRowDef _seg(String k, String label, List<(String, String)> o) =>
    (kind: 'seg', key: k, label: label, opts: o);
MdsSetRowDef _bool(String k, String label) =>
    (kind: 'bool', key: k, label: label, opts: const []);
MdsSetRowDef _gray(String k, String label) =>
    (kind: 'gray', key: k, label: label, opts: const []);
MdsSetRowDef _entry(String k, String label) =>
    (kind: 'entry', key: k, label: label, opts: const []);

/// 六组行序（逐字对齐原型 MSET_GROUPS；OCR 不在 preset 内）。
final List<({String id, String label, List<MdsSetRowDef> rows})> kMdsSetGroups = [
  (
    id: 'shelf',
    label: '架面',
    rows: [
      _seg(
          'media.defaultView', '默认视图', [('desk', '桌面'), ('spine', '脊'), ('list', '列表')]),
      _seg('media.wallCols', '桌面列数', [('2', '2 列'), ('3', '3 列')]),
    ],
  ),
  (
    id: 'sort',
    label: '排序',
    rows: [
      _seg('media.sortDefault', '默认排序', [
        ('recent', '最近活动'),
        ('rating', '评分'),
        ('added', '加入时间'),
        ('year', '发行年'),
        ('title', '标题'),
        ('progress', '进度'),
      ]),
      _seg('media.newPos', '新增插入', [('head', '置顶'), ('tail', '置底')]),
    ],
  ),
  (
    id: 'note',
    label: '笔记',
    rows: [
      _gray('media.ocr', '识图取文'),
      _bool('media.autoPos', '默认带时间点'),
      _bool('media.clipAuto', '剪贴板识别'),
    ],
  ),
  (
    id: 'timer',
    label: '计时',
    rows: [
      _seg('media.timerUI', '计时形态', [('capsule', '胶囊'), ('full', '全屏')]),
      _bool('media.floatBar', '悬浮计时条'),
      _bool('media.speedFold', '倍速折算'),
      _bool('media.autoAsk', '结束即弹记进度'),
      _bool('media.dailyQ', '晚间补记提醒'),
    ],
  ),
  (
    id: 'notify',
    label: '更新提醒',
    rows: [
      _gray('media.notifyNewEpisode', '新集上线'),
      _gray('media.notifyNewAlbum', '新专上线'),
      _gray('media.notifySequel', '续作与 DLC'),
    ],
  ),
  (
    id: 'data',
    label: '数据',
    rows: [
      _entry('goImport', '导入向导'),
      _gray('expMd', '导出 MD'),
      _gray('expJson', '导出 JSON'),
    ],
  ),
];

/// KV 默认值（与 providers 侧读侧回落同源；wallCols/排序/位置存原文串）。
const Map<String, String> kMdsPreset = {
  'media.defaultView': 'desk',
  'media.wallCols': '2',
  'media.sortDefault': 'recent',
  'media.newPos': 'head',
  'media.timerUI': 'capsule',
  'media.floatBar': 'true',
  'media.speedFold': 'false',
  'media.autoAsk': 'true',
  'media.dailyQ': 'true',
  'media.autoPos': 'true',
  'media.clipAuto': 'true',
};

/// 设置屏的 settings 表整读（media.* 前缀；一次取回，行态从这份读）。
final mediaSetKvProvider = FutureProvider<Map<String, String>>((ref) async {
  ref.watch(mediaTickProvider);
  return ref.watch(mediaRepositoryProvider).kvAllMedia();
});

class _MediaSetPageState extends ConsumerState<MediaSetPage> {
  String _tab = 'shelf';

  void _bump() {
    final t = ref.read(mediaTickProvider.notifier);
    t.state = t.state + 1;
  }

  Future<void> _write(String key, String value) async {
    if (!mounted) return;
    await ref.read(mediaRepositoryProvider).setKv(key, value);
    _bump();
  }

  String _val(Map<String, String> kv, MdsSetRowDef r) =>
      kv[r.key] ?? kMdsPreset[r.key] ?? 'false';

  @override
  Widget build(BuildContext context) {
    final kv = ref.watch(mediaSetKvProvider);
    final group = kMdsSetGroups.firstWhere((g) => g.id == _tab);
    return Scaffold(
      appBar: AppBar(title: const Text('影音设置')),
      body: kv.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => LoadErrorBanner(
          title: '设置没加载出来',
          error: e,
          onRetry: () => ref.invalidate(mediaSetKvProvider),
        ),
        data: (m) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            SizedBox(
              height: 34,
              child: ListView(
                key: const ValueKey('mds-set-tabs'),
                scrollDirection: Axis.horizontal,
                children: [
                  for (final g in kMdsSetGroups)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: PillChip(
                        key: ValueKey('mds-set-tab-${g.id}'),
                        label: g.label,
                        selected: _tab == g.id,
                        onTap: () => setState(() => _tab = g.id),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            for (final r in group.rows) _rowWidget(context, m, r),
          ],
        ),
      ),
    );
  }

  Widget _rowWidget(BuildContext context, Map<String, String> kv, MdsSetRowDef r) {
    final scheme = Theme.of(context).colorScheme;
    final v = _val(kv, r);
    return Container(
      key: ValueKey('mds-set-row-${r.key}'),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
      decoration: BoxDecoration(
        border:
            Border(bottom: BorderSide(color: scheme.outlineVariant, width: .6)),
      ),
      child: r.kind == 'seg'
          // 六档 seg（默认排序）窄屏放不下横排一行＝标题在上、chip 道在下
          //（原型 m-set 行内横排同语义，只在这类长档名行落次行）。
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5)),
                const SizedBox(height: 6),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Wrap(
                    spacing: 5,
                    runSpacing: 4,
                    children: [
                      for (final o in r.opts)
                        PillChip(
                          key: ValueKey('mds-set-${r.key}-${o.$1}'),
                          label: o.$2,
                          selected: v == o.$1,
                          onTap: () => _write(r.key, o.$1),
                        ),
                    ],
                  ),
                ),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: Text(r.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5)),
                ),
                if (r.kind == 'bool')
                  Switch(
                    key: ValueKey('mds-set-${r.key}'),
                    value: v == 'true',
                    onChanged: (on) => _write(r.key, on ? 'true' : 'false'),
                  )
                else if (r.kind == 'gray')
                  // 铁口径②：能力未开放＝灰态点不动、零说明文案（onChanged=null 即不可点）。
                  Opacity(
                    opacity: .45,
                    child: Switch(
                      key: ValueKey('mds-set-gray-${r.key}'),
                      value: false,
                      onChanged: null,
                    ),
                  )
                else
                  InkWell(
                    key: ValueKey('mds-set-go-${r.key}'),
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => AppToast.show(context, '影音导入还没上线'),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Row(
                        children: [
                          Text('直达', style: TextStyle(fontSize: 11.5)),
                          Icon(Icons.chevron_right, size: 16),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
