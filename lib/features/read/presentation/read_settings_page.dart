import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/notifications/notification_service.dart';
import '../../../core/providers.dart' show sharedPreferencesProvider;
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/confirm_dialog.dart' show lhConfirm;
import '../data/isbn_enrich.dart' show DoubanCookie;
import './reader/reader_sel_layer.dart' show kBrSelDefaultTools;
import 'read_providers.dart';
import 'read_sheets.dart';
import './shelf/shelf_page.dart' show kLpAll, kLpDefault;

/// 阅读设置（原型 p-readset / RS_SEC · 计划 §6）：五组横向 tab，
/// 一次只显示一组；所有键走 settings 表 read.*，写完 readTick 广播即时生效。
/// 例外：dbCookie（豆瓣登录态凭据）只存 SharedPreferences，不进 settings 表
/// ——书架备份导出（buildBackupJson 捞 read.* 全量）不会带走它。
enum _T { chips, bool, ops, nav, go, go2, info, login, cache }

class _Row {
  const _Row(this.key, this.name, this.t, {
    this.opts = const [],
    this.pairs = const [],
    this.desc = '',
    this.route = '',
  });
  final String key;
  final String name;
  final _T t;
  final List<String> opts;

  /// 显示名 ↔ 存储值二元组（原型 chips 的 `[[显示, 存储], …]` 形式；
  /// `d == s` 者与 [opts] 等价）。用于「存储英文枚举 / 显示中文」的键
  /// （tlRange）与「存储数字 / 显示 0.75x」（brRate）。
  final List<(String, String)> pairs;
  final String desc;
  final String route;

  /// 归一后的候选（显示名, 存储值）列表：优先 [pairs]，否则 [opts] 自映射。
  List<(String, String)> get choices =>
      pairs.isNotEmpty ? pairs : [for (final o in opts) (o, o)];
}

class _Sec {
  const _Sec(this.title, this.rows);
  final String title;
  final List<_Row> rows;
}

const _secs = [
  _Sec('外观与启动', [
    _Row('openTab', '默认打开', _T.chips, opts: ['想读', '在读', '已读', '弃读']),
    _Row('wallCols', '封面墙列数', _T.chips, opts: ['3', '4', '5']),
    // R14-4 三档回落（原型 RS_SEC）：A 正文首图（默认）/ B 书脊色块 / C 纯文字卡。
    _Row('covFallback', '无封面书卡', _T.chips,
        opts: ['A 正文首图', 'B 书脊色块', 'C 纯文字卡'],
        desc: 'EPUB 无内嵌封面时的回落档 · 默认 A · 可在书架同屏预览对比'),
    _Row('imgCols', '图片墙列数', _T.chips, opts: ['3', '4', '5']),
    _Row('qtLines', '书摘文本行数', _T.chips, opts: ['2', '3', '4']),
    _Row('simple', '简洁浏览书摘', _T.bool, desc: '隐藏时间、位置等辅助信息'),
    _Row('fullCh', '完整显示章节名', _T.bool, desc: '过长章节名换行显示'),
  ]),
  _Sec('内容显示与排序', [
    _Row('newPos', '新增书籍位置', _T.chips, opts: ['开头', '末尾']),
    _Row('yearSort', '今年读完排序', _T.chips, opts: ['升序', '降序']),
    // F1-5：tlRange 统一英文枚举口径（原型 RS_SEC 存 month/half/year）——
    // 存储值走 pairs 第二元，显示仍中文，与 shelf_spine_time 读取端同源。
    _Row('tlRange', '时间线范围', _T.chips,
        pairs: [('本月', 'month'), ('近半年', 'half'), ('全年', 'year')]),
    _Row('tlDays', '时间线显示天数', _T.chips, opts: ['7', '14', '30']),
    _Row('longPress', '长按书籍菜单', _T.ops, desc: '勾选并调整顺序'),
  ]),
  _Sec('书摘创建', [
    _Row('ocr', '识图取文', _T.bool, desc: '从相册或截图识别原文'),
    _Row('rateFmt', '默认带页码与章节', _T.bool, desc: '新建摘录时自动填当前进度'),
    _Row('clipAuto', '剪贴板自动识别来源', _T.bool, desc: '复制后弹出导入提示'),
  ]),
  _Sec('阅读计时', [
    _Row('timerUI', '计时显示', _T.chips,
        opts: ['全屏', '顶部胶囊'],
        desc: '全屏＝整页沉浸（隐藏顶栏与底栏）；顶部胶囊＝不跳页，只在 app 顶部留一行胶囊计时'),
    _Row('floatBar', '悬浮计时条', _T.bool, desc: '切到别的 App 也继续计时'),
    _Row('speedFold', '有声按倍速折算', _T.bool, desc: '1.5 倍速只记 40 分钟'),
    _Row('autoAsk', '结束计时后问进度', _T.bool, desc: '停止即弹「记进度」'),
    _Row('dailyQ', '每天提醒补记', _T.bool, desc: '晚间未计时时提醒'),
  ]),
  _Sec('数据与存储', [
    _Row('feeTxn', '购书费用记入账本', _T.bool,
        desc: '新增或修改费用时同步生成/更新一笔「阅读-购书」支出'),
    _Row('isbnFill', 'ISBN 补全', _T.chips,
        opts: ['仅填 ISBN', '抓豆瓣数据'],
        desc: '扫码 / 输入 ISBN 命中后，是否抓取豆瓣书目自动填充书名、作者、出版社、页数、封面与评分'),
    _Row('dbCookie', '豆瓣登录 Cookie', _T.login,
        desc: '在应用内登录豆瓣，登录完成后自动取得 Cookie · 仅存本机 · 频繁抓取可能导致自己的账号受限'),
    _Row('dbCache', '豆瓣数据缓存', _T.cache,
        desc: '抓到的书目按 ISBN 缓存本机，二次命中先问用缓存还是联网重查'),
    _Row('import', '导入其他平台读书笔记', _T.go,
        route: '/read/import',
        desc: '微信读书 / Kindle / Notion / Markdown · 授权 / 文件 / 剪贴板 / API'),
    _Row('bkmgr', '书架资料', _T.nav,
        route: '/read/mgr', desc: '来源 / 分组 / 作者 / 出版社 / 标签'),
    _Row('stat', '阅读统计', _T.nav,
        route: '/read/stat', desc: '时长 · 热力图 · 目标'),
    // V1.59 批3 拍板③：xrBak 行改道 X-Ray 中心第三段（弹层唯一挂载点，入口不双挂）。
    _Row('xrBak', 'X-Ray 索引备份', _T.nav,
        route: '/read/xray-words?seg=idx',
        desc: '在 X-Ray 中心「索引与备份」段 · 导出 .xraybak / 从备份导入 · MD5 校验'),
    _Row('exportMd', '导出全部书摘', _T.go2, desc: 'Markdown · 按书分组'),
    _Row('exportJson', '导出书架备份', _T.go2, desc: 'JSON · 可换机导入'),
    _Row('store', '存储位置', _T.info, desc: '应用私有目录 · 本地优先'),
    _Row('sync', '服务集成', _T.info, desc: 'WebDAV / 局域网备份'),
  ]),
  // V1.50 批4（原型「本地阅读器」组 · 朗读音色随 TTS 能力延后未列）。
  _Sec('本地阅读器', [
    _Row('epub', '导入本地 EPUB', _T.nav,
        route: '/read/import-epub',
        desc: '添加图书流程内同样有入口 · Android 13+ SAF 单次读取'),
    // V1.54.1 批2 → V1.59 批3：升级 X-Ray 中心（三段同页），不带书入口（拍板①）。
    _Row('xrwords', 'X-Ray 中心', _T.nav,
        route: '/read/xray-words',
        desc: '词条 / AI 精化 / 索引与备份 三段同页 · 增删改查 · 启用开关'),
    _Row('brSync', '划线自动存为书摘', _T.bool,
        desc: '阅读器高亮=按所选分类生成一条划线书摘 · 删除高亮同步移除'),
    _Row('brLink', '书籍内外部链接', _T.chips,
        opts: ['禁止', '询问', '允许'],
        desc: '章节内跳转不受限制 · 外链默认询问'),
    // F1-5：brRate 有声书倍速（原型 RS_SEC brLink 与 brBright 之间）——
    // 存储数字（0.75~2.0），显示 0.75x；与「有声按倍速折算」开关配合，
    // 在 startSession 落库时按此倍速写入 speed（有声书才折算）。
    _Row('brRate', '有声书倍速', _T.chips,
        pairs: [
          ('0.75x', '0.75'),
          ('1.0x', '1'),
          ('1.25x', '1.25'),
          ('1.5x', '1.5'),
          ('2.0x', '2'),
        ],
        desc: '仅用于有声书：按此倍速把播放时长折算成阅读时长（配合「有声按倍速折算」开关）'),
    _Row('brBright', '阅读时屏幕常亮', _T.bool,
        desc: '进入阅读器自动生效 · 退出恢复系统策略'),
    // V1.53.2 轮5.2②：退出阅读器时结算，未达门槛不记时长也不记会话。
    _Row('brMinSecs', '短于该时长的阅读不计入', _T.chips,
        opts: ['5', '10', '15', '30', '60', '120', '300'],
        desc: '秒 · 默认 30 · 退出阅读器时结算，未达门槛不记时长也不记会话'),
    // V1.53.4④⑤（原型 RS_SEC 新两行）：长按粒度 + 选区工具条管理。
    _Row('brSelGran', '长按选择粒度', _T.chips,
        opts: ['选字', '选句'],
        desc: '默认 选字 · 长按命中单字，拖手柄扩选；选句 长按命中整句'),
    _Row('brSelBar', '选区工具条工具', _T.ops,
        desc: '勾选并调整顺序 · 移除＝不上工具条'),
  ]),
];

/// bool 键关闭/开启时的 toast 文案（原型 rsFlip 映射）。
const _boolLabel = {
  'floatBar': '悬浮计时条',
  'speedFold': '倍速折算',
  'autoAsk': '结束后问进度',
  'dailyQ': '每日补记提醒',
  'ocr': '识图取文',
  'rateFmt': '默认带页码',
  'clipAuto': '剪贴板识别',
  'simple': '简洁浏览',
  'fullCh': '完整章节名',
  'feeTxn': '购书费用入账',
  'brSync': '划线自动存书摘',
  'brBright': '阅读常亮',
};

class ReadSettingsPage extends ConsumerStatefulWidget {
  const ReadSettingsPage({super.key, this.initialSec = 0});

  /// 初始定位组（?sec= 入口：书架长按菜单「调整长按菜单」→ 1＝内容显示与排序）。
  final int initialSec;

  @override
  ConsumerState<ReadSettingsPage> createState() => _ReadSettingsPageState();
}

class _ReadSettingsPageState extends ConsumerState<ReadSettingsPage> {
  late int _sec = widget.initialSec.clamp(0, _secs.length - 1);

  bool get _dbCookieOn =>
      (ref.read(sharedPreferencesProvider).getString('read.dbCookie') ?? '')
          .isNotEmpty;

  /// Cookie 写入超 30 天＝可能已过期（豆瓣登录态约按月失效，V1.46）。
  bool get _dbCookieStale {
    final at = ref.read(sharedPreferencesProvider).getInt('read.dbCookieAt');
    if (at == null) return false; // 旧版粘贴无时间戳：不武断判过期
    return DateTime.now().millisecondsSinceEpoch - at >
        30 * 24 * 3600 * 1000;
  }

  /// 应用内登录豆瓣（V1.45 改口：替代手动粘贴）。登录页点「完成」提取并
  /// 写入 prefs 后 pop(true)，这里只刷新「已配置」状态。
  Future<void> _openDoubanLogin() async {
    final ok = await context.push<bool>('/read/douban-login');
    if (ok == true && mounted) setState(() {});
  }

  Future<void> _set(String key, String value) async {
    final repo = ref.read(readRepositoryProvider);
    await repo.setKv('read.$key', value);
    if (key == 'dailyQ') {
      await NotificationService.syncReadDaily(on: value == 'true');
    }
    ref.read(readTickProvider.notifier).state++;
    if (mounted) {
      readToast(
        context,
        _boolLabel.containsKey(key)
            ? '${value == 'true' ? '已开启 · ' : '已关闭 · '}${_boolLabel[key]}'
            : '已设置 ${_chipLabel(key, value)}',
      );
    }
  }

  /// chips 行的存储值 → 显示名（原型 rsChip toast 用显示名；
  /// pairs 行的存储值是英文枚举/数字，直接塞进 toast 会露内部口径）。
  String _chipLabel(String key, String value) {
    for (final r in _secs.expand((s) => s.rows)) {
      if (r.key != key) continue;
      for (final (label, store) in r.choices) {
        if (store == value) return label;
      }
    }
    return value;
  }

  String _val(String key, String def) =>
      ref.watch(readKvProvider(('read.$key', def))).valueOrNull ?? def;

  Future<void> _export(String key) async {
    // V1.59 批3 拍板③：xrBak 不再在本页挂弹层——行已改道 X-Ray 中心第三段。
    // 轮5：真机「点了没反应」——点击即回反馈，异常也要说出来。
    readToast(context, '导出中…');
    try {
      final repo = ref.read(readRepositoryProvider);
      final md = key == 'exportMd';
      final txt = md ? await repo.buildQuotesMd() : await repo.buildBackupJson();
      final dir = await getApplicationDocumentsDirectory();
      final name = md ? '全部书摘.md' : '书架备份.json';
      final f = File(p.join(dir.path, 'share', name));
      await f.parent.create(recursive: true);
      await f.writeAsString(txt);
      if (mounted) {
        readToast(context, '已导出 $name · ${(txt.length / 1024).toStringAsFixed(1)} KB · ${f.path}');
      }
    } catch (e) {
      if (mounted) readToast(context, '导出失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = context.tokens;
    final sec = _secs[_sec];
    return Scaffold(
      appBar: AppBar(title: const Text('阅读设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          SizedBox(
            height: 32,
            child: ListView(
              key: const ValueKey('rs-tabs'),
              scrollDirection: Axis.horizontal,
              children: [
                for (final (i, s) in _secs.indexed)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      key: ValueKey('set-tab-$i'),
                      onTap: () => setState(() => _sec = i),
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: _sec == i
                              ? tokens.accent
                              : cs.surfaceContainerHighest
                                    .withValues(alpha: .5),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          s.title,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color:
                                _sec == i ? Colors.white : cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            key: ValueKey('set-card-${sec.title}'),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: .5),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        sec.title,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                    Text(
                      '${sec.rows.length} 项',
                      key: const ValueKey('set-sec-count'),
                      style: TextStyle(
                        fontSize: 10,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                for (final r in sec.rows) _row(cs, tokens, r),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(ColorScheme cs, ThemeTokens tokens, _Row r) {
    final desc = r.desc.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              r.desc,
              style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
            ),
          );
    final head = Row(
      children: [
        Expanded(
          child: Column(
            key: ValueKey('set-${r.key}'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                r.name,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              desc,
            ],
          ),
        ),
        ..._trailing(cs, tokens, r),
      ],
    );
    final chips = r.t == _T.chips
        ? Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (label, store) in r.choices)
                  GestureDetector(
                    key: ValueKey('set-${r.key}-$store'),
                    onTap: () => _set(r.key, store),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: _val(r.key, _def(r)) == store
                            ? tokens.accent.withValues(alpha: .12)
                            : cs.surfaceContainerHighest
                                  .withValues(alpha: .4),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: _val(r.key, _def(r)) == store
                              ? tokens.accent
                              : Colors.transparent,
                        ),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: _val(r.key, _def(r)) == store
                              ? tokens.accent
                              : cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          )
        : const SizedBox.shrink();
    final opsInline = r.t == _T.ops
        ? _lpInline(r)
        : const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: .35)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [head, chips, opsInline],
      ),
    );
  }

  /// ops 行的候选池（V1.53.4⑤：池随键走；长按菜单=书架池，工具条=选区 8 项）。
  List<String> _opAll(String key) =>
      key == 'brSelBar' ? kBrSelDefaultTools : kLpAll;

  /// 长按菜单/工具条等 ops 行就地内嵌编辑（原型 5054-5056 rsRow ops：设置页内直接渲染列表，
  /// 无「调整」按钮、无弹层、无保存钮，每次操作立即落库 `read.<key>`）。
  Widget _lpInline(_Row r) {
    final cs = Theme.of(context).colorScheme;
    final all = _opAll(r.key);
    final items = _val(r.key, _def(r)).split(',').where(all.contains).toList();
    final rest = all.where((n) => !items.contains(n)).toList();
    Future<void> mutate(List<String> next) async {
      final repo = ref.read(readRepositoryProvider);
      await repo.setKv('read.${r.key}', next.join(','));
      ref.read(readTickProvider.notifier).state++;
    }

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, n) in items.indexed)
            Row(
              key: ValueKey('lpset-row-$n'),
              children: [
                IconButton(
                  key: ValueKey('lpset-up-$n'),
                  icon: Icon(
                    Icons.arrow_upward,
                    size: 16,
                    semanticLabel: '上移 $n', // R14-10
                  ),
                  onPressed: i == 0
                      ? null
                      : () {
                          final t = [...items];
                          t.insert(i - 1, t.removeAt(i));
                          mutate(t);
                        },
                ),
                IconButton(
                  key: ValueKey('lpset-dn-$n'),
                  icon: Icon(
                    Icons.arrow_downward,
                    size: 16,
                    semanticLabel: '下移 $n', // R14-10
                  ),
                  onPressed: i == items.length - 1
                      ? null
                      : () {
                          final t = [...items];
                          t.insert(i + 1, t.removeAt(i));
                          mutate(t);
                        },
                ),
                Expanded(
                  child: Text(
                    n,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton(
                  key: ValueKey('lpset-rm-$n'),
                  onPressed: () =>
                      mutate(items.where((x) => x != n).toList()),
                  child: const Text(
                    '移除',
                    style: TextStyle(fontSize: 11, color: Colors.red),
                  ),
                ),
              ],
            ),
          if (rest.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final x in rest)
                    GestureDetector(
                      key: ValueKey('lpset-add-$x'),
                      onTap: () => mutate([...items, x]),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest
                              .withValues(alpha: .4),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '＋ $x',
                          style: const TextStyle(fontSize: 10.5),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _def(_Row r) => switch (r.key) {
    'openTab' => '在读',
    'wallCols' => '3',
    // R14-4：无封面书卡回落档默认 A 正文首图。
    'covFallback' => 'A 正文首图',
    'imgCols' => '5',
    'qtLines' => '3',
    'newPos' => '开头',
    'yearSort' => '升序',
    // F1-5：tlRange 默认近半年＝英文枚举 'half'（原型 BS_SET 默认 half）。
    'tlRange' => 'half',
    'tlDays' => '14',
    'timerUI' => '全屏',
    'isbnFill' => '仅填 ISBN',
    'longPress' => kLpDefault,
    // 原型 BS_SET 默认关的两键（其余 bool 键默认开）。
    'simple' => 'false',
    'fullCh' => 'false',
    // 批4 本地阅读器：外链默认询问、常亮默认关（原型 BR_DEF.bright=false）。
    'brLink' => '询问',
    'brBright' => 'false',
    // 轮5.2②：短会话门槛默认 30 秒（chip 值以字符串存）。
    'brMinSecs' => '30',
    // F1-5：有声书倍速默认 1.0x（原型 BS_SET.brRate 默认 1）。
    'brRate' => '1',
    // V1.53.4④⑤：长按粒度默认选字；工具条名单默认 8 项全开（逗号串）。
    'brSelGran' => '选字',
    'brSelBar' => kBrSelDefaultTools.join(','),
    _ => 'true',
  };

  List<Widget> _trailing(ColorScheme cs, ThemeTokens tokens, _Row r) {
    switch (r.t) {
      case _T.bool:
        final on = _val(r.key, _def(r)) == 'true';
        return [
          Switch(
            key: ValueKey('set-${r.key}-t'),
            value: on,
            activeThumbColor: tokens.accent,
            onChanged: (v) => _set(r.key, v ? 'true' : 'false'),
          ),
        ];
      case _T.nav:
        return [
          TextButton(
            key: ValueKey('set-open-${r.key}'),
            onPressed: () => context.push(r.route),
            child: const Text('打开', style: TextStyle(fontSize: 11.5)),
          ),
        ];
      case _T.go:
        return [
          TextButton(
            key: ValueKey('set-open-${r.key}'),
            onPressed: () => context.push(r.route),
            child: const Text('配置', style: TextStyle(fontSize: 11.5)),
          ),
        ];
      case _T.go2:
        return [
          TextButton(
            key: ValueKey('set-${r.key}'),
            onPressed: () => _export(r.key),
            child: const Text('导出', style: TextStyle(fontSize: 11.5)),
          ),
        ];
      case _T.info:
        return [
          Text(
            r.key == 'store' ? '内部存储 · 只读' : '未配置',
            style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
          ),
        ];
      case _T.ops:
        return [
          Text(
            '${_val(r.key, _def(r)).split(',').where(_opAll(r.key).contains).length} 项',
            style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
          ),
        ];
      case _T.chips:
        return const [];
      case _T.login:
        // 原型 rsRow login：未配置→「登录豆瓣」进应用内登录页；
        // 已配置→「已配置」+清除+重新登录。Cookie 值永不回显、只存 prefs。
        if (!_dbCookieOn) {
          return [
            TextButton(
              key: const ValueKey('set-dbCookie-login'),
              onPressed: _openDoubanLogin,
              child: const Text('登录豆瓣', style: TextStyle(fontSize: 11.5)),
            ),
          ];
        }
        return [
          Text(
            // V1.46 过期提醒：豆瓣登录态约按月失效，超 30 天提示重登。
            _dbCookieStale ? '已配置 · 可能已过期' : '已配置',
            key: const ValueKey('set-dbCookie-on'),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: _dbCookieStale
                  ? const Color(0xFFF59E0B)
                  : const Color(0xFF059669),
            ),
          ),
          TextButton(
            key: const ValueKey('set-dbCookie-clear'),
            onPressed: () async {
              // F2-11（LH-S31）：清除登录态＝破坏性动作，先过统一二次确认
              // （取消左 · 玫红右），人话句说清后果。
              final ok = await lhConfirm(
                context,
                '清除豆瓣登录 Cookie？\n清除后需要重新登录才能抓取书目；已抓到的书目缓存不受影响。',
                okLabel: '清除',
              );
              if (!ok || !mounted) return;
              final prefs = ref.read(sharedPreferencesProvider);
              await prefs.remove('read.dbCookie');
              await prefs.remove('read.dbCookieAt');
              DoubanCookie.set(null);
              if (!mounted) return;
              setState(() {});
              readToast(context, '豆瓣 Cookie 已清除');
            },
            child: const Text('清除', style: TextStyle(fontSize: 11.5)),
          ),
          TextButton(
            key: const ValueKey('set-dbCookie-relogin'),
            onPressed: _openDoubanLogin,
            child: const Text('重新登录', style: TextStyle(fontSize: 11.5)),
          ),
        ];
      case _T.cache:
        // 原型 rsRow cache：按钮即「清除 N 条」，无缓存置灰「无缓存」。
        final n = ref.watch(doubanCacheCountProvider).valueOrNull ?? 0;
        return [
          // F2-14（LH-K36）：禁用第三态＝常开＋置灰＋点不动＋固定小标。
          // 按钮文案随有无缓存而变，另给一枚常驻小标把本机缓存状态说明白
          // （对齐书目源 chip 的「· 未接入」小标），不把状态只压在按钮文案上。
          Text(
            n == 0 ? '本机暂无缓存' : '本机 $n 条',
            key: const ValueKey('set-dbCache-state'),
            style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
          ),
          const SizedBox(width: 8),
          TextButton(
            key: const ValueKey('set-dbCache-clear'),
            onPressed: n == 0
                ? null
                : () async {
                    // F2-11（LH-S31）：清缓存＝破坏性动作，先过统一二次确认。
                    final ok = await lhConfirm(
                      context,
                      '清除 $n 条豆瓣书目缓存？\n清除后下次抓书目将重新联网查询。',
                      okLabel: '清除',
                    );
                    if (!ok || !mounted) return;
                    final repo = ref.read(readRepositoryProvider);
                    await repo.doubanCacheClear();
                    ref.read(readTickProvider.notifier).state++;
                    if (mounted) readToast(context, '已清除 $n 条豆瓣缓存');
                  },
            child: Text(
              n == 0 ? '无缓存' : '清除 $n 条',
              style: const TextStyle(fontSize: 11.5),
            ),
          ),
        ];
    }
  }
}
