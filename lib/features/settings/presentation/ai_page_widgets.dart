part of 'ai_page.dart';

// 治理G7d⑤：AI 页公共小件群自 ai_page 整块外提（行为零改动）。
// _ProviderRow 服务商行 + _MiniBtn 行内小按钮 + _Card 圆角壳 + _fmtTime 时间格式化。

/// 服务商行（原型 `#aiProvList` 的单行）：名称/预置徽 · Base URL ·
/// 模型+协议+Key 状态 · 选用（非当前）/编辑/删（当前端点不给删）。
class _ProviderRow extends StatelessWidget {
  const _ProviderRow({
    required this.provider,
    required this.isCurrent,
    required this.keyState,
    required this.onUse,
    required this.onEdit,
    required this.onDelete,
  });

  final AiProvider provider;
  final bool isCurrent;
  final String keyState;
  final VoidCallback onUse;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final p = provider;
    return Container(
      key: ValueKey('ai-prov-row-${p.id}'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: isCurrent ? 0.22 : 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Row(
                  children: [
                    Flexible(
                        child: Text(p.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700))),
                    if (p.builtin) ...[
                      const SizedBox(width: 5),
                      const Text('预置',
                          style: TextStyle(fontSize: 9, color: Colors.grey)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 2),
              if (isCurrent)
                Text('● 当前',
                    key: ValueKey('ai-prov-cur-${p.id}'),
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF10B981)))
              else
                _MiniBtn('选用', 'ai-prov-use-${p.id}', onUse),
              _MiniBtn('编辑', 'ai-prov-edit-${p.id}', onEdit),
              if (!isCurrent)
                _MiniBtn('删', 'ai-prov-del-${p.id}', onDelete,
                    color: const Color(0xFFEF4444)),
            ],
          ),
          Text(p.baseUrl,
              key: ValueKey('ai-prov-url-${p.id}'),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 10.5, fontFamily: 'monospace', color: Colors.grey)),
          Row(
            children: [
              Flexible(
                  child: Text(
                      '${p.model} · ${aiProtocolLabel(p.protocol)} · Key $keyState',
                      key: ValueKey('ai-prov-meta-${p.id}'),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 9.5, color: Colors.grey))),
              if (p.isPlainHttp)
                Text('· http 明文（局域网）',
                    key: ValueKey('ai-prov-http-${p.id}'),
                    style: const TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFF59E0B))),
            ],
          ),
        ],
      ),
    );
  }
}

/// 行内小按钮（原型 `.mini-btn`）。
class _MiniBtn extends StatelessWidget {
  const _MiniBtn(this.label, this.testKey, this.onTap, {this.color});

  final String label;
  final String testKey;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) => TextButton(
        key: ValueKey(testKey),
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: color,
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(label, style: const TextStyle(fontSize: 11)),
      );
}
class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: context.cardDecoration,
      child: child,
    );
  }
}

String _fmtTime(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}
