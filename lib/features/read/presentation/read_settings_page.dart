import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/notifications/notification_service.dart';
import '../../../core/theme/app_theme.dart';
import 'read_providers.dart';
import 'read_sheets.dart';
import 'shelf_page.dart' show kLpAll, kLpDefault;

/// 阅读设置（原型 p-readset / RS_SEC · 计划 §6）：五组横向 tab，
/// 一次只显示一组；所有键走 settings 表 read.*，写完 readTick 广播即时生效。
enum _T { chips, bool, ops, nav, go, go2, info }

class _Row {
  const _Row(this.key, this.name, this.t, {
    this.opts = const [],
    this.desc = '',
    this.route = '',
  });
  final String key;
  final String name;
  final _T t;
  final List<String> opts;
  final String desc;
  final String route;
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
    _Row('imgCols', '图片墙列数', _T.chips, opts: ['3', '4', '5']),
    _Row('qtLines', '书摘文本行数', _T.chips, opts: ['2', '3', '4']),
    _Row('simple', '简洁浏览书摘', _T.bool, desc: '隐藏时间、位置等辅助信息'),
    _Row('fullCh', '完整显示章节名', _T.bool, desc: '过长章节名换行显示'),
  ]),
  _Sec('内容显示与排序', [
    _Row('newPos', '新增书籍位置', _T.chips, opts: ['开头', '末尾']),
    _Row('yearSort', '今年读完排序', _T.chips, opts: ['升序', '降序']),
    _Row('tlRange', '时间线范围', _T.chips, opts: ['本月', '近半年', '全年']),
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
    _Row('import', '导入其他平台读书笔记', _T.go,
        route: '/read/import',
        desc: '微信读书 / Kindle / Notion / Markdown · 授权 / 文件 / 剪贴板 / API'),
    _Row('bkmgr', '书架资料', _T.nav,
        route: '/read/mgr', desc: '来源 / 分组 / 作者 / 出版社 / 标签'),
    _Row('stat', '阅读统计', _T.nav,
        route: '/read/stat', desc: '时长 · 热力图 · 目标'),
    _Row('exportMd', '导出全部书摘', _T.go2, desc: 'Markdown · 按书分组'),
    _Row('exportJson', '导出书架备份', _T.go2, desc: 'JSON · 可换机导入'),
    _Row('store', '存储位置', _T.info, desc: '应用私有目录 · 本地优先'),
    _Row('sync', '服务集成', _T.info, desc: 'WebDAV / 局域网备份'),
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
            : '已设置 $value',
      );
    }
  }

  String _val(String key, String def) =>
      ref.watch(readKvProvider(('read.$key', def))).valueOrNull ?? def;

  Future<void> _export(String key) async {
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
      appBar: AppBar(centerTitle: true, title: const Text('阅读设置')),
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
                for (final o in r.opts)
                  GestureDetector(
                    key: ValueKey('set-${r.key}-$o'),
                    onTap: () => _set(r.key, o),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: _val(r.key, _def(r)) == o
                            ? tokens.accent.withValues(alpha: .12)
                            : cs.surfaceContainerHighest
                                  .withValues(alpha: .4),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: _val(r.key, _def(r)) == o
                              ? tokens.accent
                              : Colors.transparent,
                        ),
                      ),
                      child: Text(
                        o,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: _val(r.key, _def(r)) == o
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
        ? _lpInline(r.key)
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

  /// 长按菜单就地内嵌编辑（原型 5054-5056 rsRow ops：设置页内直接渲染列表，
  /// 无「调整」按钮、无弹层、无保存钮，每次操作立即落库 read.longPress）。
  Widget _lpInline(String key) {
    final cs = Theme.of(context).colorScheme;
    final items = _val(key, kLpDefault).split(',').where(kLpAll.contains).toList();
    final rest = kLpAll.where((n) => !items.contains(n)).toList();
    Future<void> mutate(List<String> next) async {
      final repo = ref.read(readRepositoryProvider);
      await repo.setKv('read.$key', next.join(','));
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
                  icon: const Icon(Icons.arrow_upward, size: 16),
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
                  icon: const Icon(Icons.arrow_downward, size: 16),
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
    'imgCols' => '5',
    'qtLines' => '3',
    'newPos' => '开头',
    'yearSort' => '升序',
    'tlRange' => '近半年',
    'tlDays' => '14',
    'timerUI' => '全屏',
    'isbnFill' => '仅填 ISBN',
    'longPress' => kLpDefault,
    // 原型 BS_SET 默认关的两键（其余 bool 键默认开）。
    'simple' => 'false',
    'fullCh' => 'false',
    _ => 'true',
  };

  List<Widget> _trailing(ColorScheme cs, ThemeTokens tokens, _Row r) {
    switch (r.t) {
      case _T.bool:
        final on = _val(r.key, 'true') == 'true';
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
            '${_val(r.key, kLpDefault).split(',').where(kLpAll.contains).length} 项',
            style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
          ),
        ];
      case _T.chips:
        return const [];
    }
  }
}
