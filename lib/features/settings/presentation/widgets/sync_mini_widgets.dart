part of 'sync_sheets.dart';

// 治理G7d②：公共小件群自 sync_sheets 整块外提（行为零改动）。
// 字节/时间/服务名格式化 + 徽标·锁点·目录标签·分段钮·区头 + 单列滚轮 NumberWheel（T6 同源）。
// ============================ 公共小件 ============================

/// 字节数人类口径：`272.2 MB` / `1.2 GB` / `3 GB`（整数值去 `.0`）。
String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB'];
  var v = bytes.toDouble();
  var u = 0;
  while (v >= 1024 && u < units.length - 1) {
    v /= 1024;
    u++;
  }
  final s = u == 0
      ? '$bytes'
      : v.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '');
  return '$s ${units[u]}';
}

/// epoch 毫秒 → `今天 08:31` / `昨天 21:02` / `09-22 20:15`。
String formatHistoryTime(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  final now = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  final hm = '${two(d.hour)}:${two(d.minute)}';
  final sameDay = d.year == now.year && d.month == now.month && d.day == now.day;
  final yesterday = DateTime(now.year, now.month, now.day)
      .subtract(const Duration(days: 1));
  final isYesterday =
      d.year == yesterday.year && d.month == yesterday.month && d.day == yesterday.day;
  if (sameDay) return '今天 $hm';
  if (isYesterday) return '昨天 $hm';
  return '${two(d.month)}-${two(d.day)} $hm';
}

/// 服务展示名（ServiceConfig 无独立显示名字段，按端点派生——与原型
/// 「坚果云 · WebDAV / 缤纷云 · S3 / 自定义 · …」口径一致）。
String serviceDisplayName(ServiceConfig c) {
  final host = Uri.tryParse(c.apiUrl)?.host ?? '';
  if (c.isS3) {
    if (host.contains('bitiful')) return '缤纷云 · S3';
    return host.isEmpty ? '自定义 · S3' : '$host · S3';
  }
  if (host.contains('jianguoyun')) return '坚果云 · WebDAV';
  return host.isEmpty ? '未配置 · WebDAV' : '$host · WebDAV';
}

/// 差异徽标（原型 .badge-webdav / .badge-s3：协议徽标一律文字，无图标）。
class _ProtoBadge extends StatelessWidget {
  const _ProtoBadge({required this.isS3});

  final bool isS3;

  @override
  Widget build(BuildContext context) {
    final color = isS3 ? const Color(0xFF059669) : const Color(0xFF0284C7);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isS3 ? 'S3' : 'WebDAV',
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: color,
            letterSpacing: .4),
      ),
    );
  }
}

/// 保险箱状态点（原型 .lock-dot）。
class _LockDot extends StatelessWidget {
  const _LockDot();

  @override
  Widget build(BuildContext context) => Container(
        width: 7,
        height: 7,
        decoration:
            const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle),
      );
}

/// 方向徽标（S3/S4 行首上/下载箭头，原型 .dir-tag）。
class _DirTag extends StatelessWidget {
  const _DirTag({required this.up});

  final bool up;

  @override
  Widget build(BuildContext context) {
    final color = up ? Theme.of(context).colorScheme.primary : const Color(0xFF047857);
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
          size: 12, color: color),
    );
  }
}

/// 分段单选钮（原型 .seg-btn，S5 同源形态）。
class _SegBtn extends StatelessWidget {
  const _SegBtn({
    super.key,
    required this.label,
    required this.on,
    required this.onTap,
  });

  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: on ? tokens.accent.withValues(alpha: .10) : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
              color: on ? tokens.accent : tokens.cardBorder, width: on ? 1.5 : 1),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: on ? tokens.accent : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// 弹层小标题（原型 .sectitle）。
class _SecTitle extends StatelessWidget {
  const _SecTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 14, 2, 6),
        child: Text(text,
            style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF94A3B8))),
      );
}

/// 单列滚轮（T6 日志页 `_RetentionWheel` 同源实现：StatefulWidget 自持
/// FixedExtentScrollController + didUpdateWidget 等值守卫，防自激重建回环）。
class NumberWheel extends StatefulWidget {
  const NumberWheel({
    super.key,
    required this.labels,
    required this.index,
    required this.onSel,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onSel;

  @override
  State<NumberWheel> createState() => _NumberWheelState();
}

class _NumberWheelState extends State<NumberWheel> {
  static const double _itemExtent = 34;

  late final FixedExtentScrollController _ctl = FixedExtentScrollController(
      initialItem: widget.index.clamp(0, widget.labels.length - 1));

  @override
  void didUpdateWidget(NumberWheel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index &&
        _ctl.hasClients &&
        _ctl.selectedItem != widget.index) {
      _ctl.jumpTo(widget.index.clamp(0, widget.labels.length - 1) * _itemExtent);
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return SizedBox(
      height: _itemExtent * 3,
      child: CupertinoPicker(
        scrollController: _ctl,
        itemExtent: _itemExtent,
        diameterRatio: 1.5,
        backgroundColor: Colors.transparent,
        onSelectedItemChanged: widget.onSel,
        children: [
          for (var i = 0; i < widget.labels.length; i++)
            Center(
              child: Text(
                widget.labels[i],
                style: TextStyle(
                  fontSize: i == widget.index ? 19 : 12,
                  fontWeight: i == widget.index ? FontWeight.w800 : FontWeight.w600,
                  color: i == widget.index
                      ? tokens.accent
                      : const Color(0xFF94A3B8),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
