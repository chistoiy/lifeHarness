/* 批1a-2：kits_page 的 _Hero 升级为原型完整版（两枚胶囊钮 + 四功能入口 + 状态行 + 两段式清空），
 * 并新增 _RecentStrip（最近使用横条）。
 * 做法：整段替换「/// hero 控制盘卡」到「/// 搜索行」之前的类定义；命中数必须为 1。 */
const fs = require('fs');
const F = 'lib/features/kits/presentation/kits_page.dart';
const raw = fs.readFileSync(F, 'utf8');
const NL = raw.includes('\r\n') ? '\r\n' : '\n';
const L = raw.split(/\r\n|\n/);
const i1 = L.findIndex(l => l.startsWith('/// hero 控制盘卡'));
const i2 = L.findIndex(l => l.startsWith('/// 搜索行'));
if (i1 < 0 || i2 < 0 || i2 <= i1) { console.error(`!! 锚点异常 i1=$ {i1} i2=${i2}`); process.exit(1); }
if (L.filter(l => l.startsWith('/// hero 控制盘卡')).length !== 1) { console.error('!! 锚点不唯一'); process.exit(1); }

const NEW = `/// hero 控制盘卡（原型 \`.grad\` 卡：数据位 ⇄ / 设置 两枚胶囊钮 + 四枚数据位
/// + 收藏/最近/插件/统计四入口 + 状态行与两段式清空足迹）。
class _Hero extends StatelessWidget {
  const _Hero({
    required this.data,
    required this.now,
    required this.onCfg,
    required this.onSettings,
    required this.onFav,
    required this.onRecent,
    required this.onPlugins,
    required this.onStats,
    required this.onClearFootprint,
  });

  final KitHomeData data;
  final DateTime now;
  final VoidCallback onCfg;
  final VoidCallback onSettings;
  final VoidCallback onFav;
  final VoidCallback onRecent;
  final VoidCallback onPlugins;
  final VoidCallback onStats;
  final VoidCallback onClearFootprint;

  int _value(KitMetric m) => kitMetricValue(
        m,
        log: data.log,
        now: now,
        fav: data.fav,
        plugCount: data.plugins.length,
        plugOnCount: data.plugins.where((p) => p.enabled).length,
        plugSizeKb: data.plugins.fold<int>(0, (a, p) => a + p.size),
      );

  /// 右上胶囊钮（原型 \`.text-[10px] bg-white/20 rounded-full\`）。
  Widget _pill(String key, String label, VoidCallback onTap) => TextButton(
        key: ValueKey('kit-hero-$key'),
        onPressed: onTap,
        style: TextButton.styleFrom(
          backgroundColor: Colors.white24,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: const StadiumBorder(),
        ),
        child: Text(label, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700)),
      );

  /// 四功能入口方格（原型 \`.grid-cols-4 .h-[52px] .bg-white/15\`）。
  Widget _func(String key, IconData icon, String label, VoidCallback onTap) => Expanded(
        child: InkWell(
          key: ValueKey('kit-func-$key'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 19, color: Colors.white),
                const SizedBox(height: 3),
                Text(label, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final today = kitMetricValue(KitMetric.today, log: data.log, now: now, fav: data.fav);
    final week = kitMetricValue(KitMetric.week, log: data.log, now: now, fav: data.fav);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: tokens.gradient,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('小工具合集',
                        style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
                    SizedBox(height: 2),
                    Text('本地计算 · 离线可用 · 无广告',
                        style: TextStyle(color: Colors.white70, fontSize: 10.5)),
                  ],
                ),
              ),
              _pill('cfg', '数据位 ⇄', onCfg),
              const SizedBox(width: 6),
              _pill('set', '设置', onSettings),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final m in data.hero)
                Expanded(
                  child: Column(
                    key: ValueKey('kit-hero-slot-' + m.name),
                    children: [
                      Text(_value(m).toString(),
                          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(m.label, style: const TextStyle(color: Colors.white70, fontSize: 10)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _func('fav', Icons.star_border, '收藏', onFav),
              const SizedBox(width: 8),
              _func('recent', Icons.schedule, '最近', onRecent),
              const SizedBox(width: 8),
              _func('plug', Icons.extension_outlined, '插件', onPlugins),
              const SizedBox(width: 8),
              _func('stats', Icons.bar_chart, '统计', onStats),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text('今日 $today 次 · 近 7 天 $week 次 · 收藏 \${data.fav.length} 个',
                  style: const TextStyle(color: Colors.white, fontSize: 10)),
                ),
                KitTwoStageButton(
                  label: '清空足迹',
                  confirmLabel: '再点一次确认',
                  compact: true,
                  onConfirm: onClearFootprint,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 最近使用横条（原型 \`#kitRecentStrip\`：无记录整条隐藏）。
class _RecentStrip extends StatelessWidget {
  const _RecentStrip({required this.keys, required this.onOpen});

  final List<String> keys;
  final ValueChanged<KitTool> onOpen;

  @override
  Widget build(BuildContext context) {
    final tools = [for (final k in keys) if (kitToolOf(k) != null) kitToolOf(k)!];
    if (tools.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('最近使用',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.grey)),
          const SizedBox(height: 6),
          SizedBox(
            height: 86,
            child: ListView(
              key: const ValueKey('kit-recent-strip'),
              scrollDirection: Axis.horizontal,
              children: [
                for (final t in tools)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InkWell(
                      key: ValueKey('kit-recent-tile-' + t.key),
                      onTap: () => onOpen(t),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        width: 74,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: context.cardDecoration,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(t.icon, size: 19),
                            const SizedBox(height: 4),
                            Text(t.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700)),
                          ],
                        ),
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
}
`.split('\n').join(NL);

L.splice(i1, i2 - i1, ...NEW.split(NL));
const out = L.join(NL);
if (!out.includes('class _RecentStrip') || !out.includes('_pill(\'set\', \'设置\', onSettings)')) {
  console.error('!! 替换后校验失败'); process.exit(2);
}
fs.writeFileSync(F, out);
console.log(`PASS _Hero 重写 + _RecentStrip 新增（${out.length - raw.length >= 0 ? '+' : ''}${out.length - raw.length} 字符）`);
